package mcp

// 请求级 SSE（2026-07-28 stateless 传输）的并发回归。
//
// 缺陷（2026-09-13 定位）：请求级 SSE 流在收尾时按 **reqId** 清理 `requestStreams`：
//
//     while (i < this.requestStreams.size) {
//         if (this.requestStreams[i].requestId == reqId) { this.requestStreams.remove(at: i) }
//         else { i++ }
//     }
//
// 各客户端都从 id=1 开始计数 → 一个客户端请求收尾，会把**另一个客户端同 id 的流一并摘掉**。
// 被误杀的流再也收不到响应（`send()` 按 id 找不到流就丢弃），只能干等到 SSE 保持上限。
//
// 修法：每条流分配一个身份 token，只摘自己那一条。
//
// 用例：两个客户端同时用 **id=1** 发请求级 SSE 工具调用：
//   - 客户端 A 先注册（t=0），工具 800ms 返回；
//   - 客户端 B 后注册（t=300ms），工具 3000ms 返回。
// A 的响应先回来 → A 的 handler 在下一次 1s 轮询（约 t=1.8s）退出并收尾 —— 此时 B 仍在飞，
// 旧实现会把 B 的流一并摘掉；B 的响应（约 t=3.8s）回来时已无流可投 → B 干等到 SSE 上限。
// 两边都必须拿回自己的结果。

import jsonvalue.*
import mcp.transport.*
import stdx.net.http.*
import std.collection.{ArrayList, HashMap}
import std.sync.*
import std.unittest.*
import std.unittest.testmacro.*

class SsePortHolder {
    var value: UInt16 = 0
}

class SseToolServer {
    let server: Server
    let transport: StatelessHttpServer_2026_07_28
    let baseUrl: String

    init() {
        let portLock = Mutex()
        let portCond = synchronized(portLock) { portLock.condition() }
        let holder = SsePortHolder()
        let server = ServerBuilder().addr("127.0.0.1").port(0).build()
        // requestTimeout 同时是请求级 SSE 的保持上限（默认 5 分钟）：调小让用例快速收敛
        let transport = StatelessHttpServer_2026_07_28(requestTimeout: Duration.second * 8)
        transport.registerRoutes(server.distributor)

        let mcpServer = McpServer("sse-test-server", "1.0.0", transport)
        let schema = ToolInputSchema("object", HashMap<String, JsonValue>(), [])
        mcpServer.addTool(Tool("first", "先注册、先返回", schema), { _ =>
            sleep(Duration.millisecond * 800)
            CallToolResult.text("first-ok")
        })
        mcpServer.addTool(Tool("second", "后注册、晚返回", schema), { _ =>
            sleep(Duration.millisecond * 3000)
            CallToolResult.text("second-ok")
        })
        mcpServer.start()

        server.afterBind({ =>
            synchronized(portLock) {
                holder.value = server.port
                portCond.notifyAll()
            }
        })
        spawn {
            => server.serve()
        }
        synchronized(portLock) {
            while (holder.value == 0) {
                portCond.wait(timeout: 5 * Duration.second)
            }
        }
        this.server = server
        this.transport = transport
        this.baseUrl = "http://127.0.0.1:${holder.value}"
    }

    public func close(): Unit {
        this.transport.close()
        this.server.close()
    }
}

// 每次调用独立建 Client：模拟「多个客户端各自一条连接」的真实场景。
func sseRawPost(baseUrl: String, body: String): String {
    let client = ClientBuilder().readTimeout(Duration.second * 20).build()
    try {
        let req = HttpRequestBuilder()
            .url(baseUrl + "/")
            .header("content-type", "application/json")
            .header("accept", "application/json, text/event-stream")
            .header("MCP-Protocol-Version", "2026-07-28")
            .header("Mcp-Method", "tools/call")
            .body(body)
            .post()
            .build()
        let resp = client.send(req)
        let buf = Array<Byte>(4096, repeat: 0)
        let total = ArrayList<Byte>()
        while (true) {
            let n: Int64
            try {
                n = resp.body.read(buf)
            } catch (_: Exception) {
                break
            }
            if (n <= 0) {
                break
            }
            total.add(all: buf[0..n])
        }
        String.fromUtf8(total.toArray())
    } finally {
        client.close()
    }
}

func sseToolCallBody(id: Int64, tool: String): String {
    "{\"jsonrpc\":\"2.0\",\"id\":${id},\"method\":\"tools/call\"," +
        "\"params\":{\"name\":\"${tool}\",\"arguments\":{}}}"
}

// 跨协程收集结果（lambda 不能捕获可变局部变量，用对象字段 + 条件变量）
class SseResultBox {
    private let lock = Mutex()
    private let cond: Condition
    private var value: ?String = None

    public init() {
        this.cond = synchronized(this.lock) {
            this.lock.condition()
        }
    }

    public func set(v: String): Unit {
        synchronized(this.lock) {
            this.value = Some(v)
            this.cond.notifyAll()
        }
    }

    public func wait(timeoutMs: Int64): String {
        synchronized(this.lock) {
            var waited: Int64 = 0
            while (this.value.isNone() && waited < timeoutMs) {
                this.cond.wait(timeout: 100 * Duration.millisecond)
                waited += 100
            }
            match (this.value) {
                case Some(v) => v
                case None => "<no response>"
            }
        }
    }
}

@Test
public class StatelessRequestSseConcurrencyTest {
    // 两个客户端用同一个 JSON-RPC id 并发发请求级 SSE：各拿各的结果。
    @TestCase
    public func testTwoClientsWithSameRequestIdEachGetOwnSseResponse(): Unit {
        let s = SseToolServer()
        try {
            let firstBox = SseResultBox()
            spawn {
                firstBox.set(sseRawPost(s.baseUrl, sseToolCallBody(1, "first")))
            }
            // 让 first 的流先注册（requestStreams 里 first 在前），保证响应按注册顺序配对
            sleep(Duration.millisecond * 300)
            // second 仍在飞时，first 的收尾就是「误杀同 id 其它流」的那一步
            let secondResp = sseRawPost(s.baseUrl, sseToolCallBody(1, "second"))

            @Expect(secondResp.contains("second-ok"), true)
            @Expect(firstBox.wait(12000).contains("first-ok"), true)
        } finally {
            s.close()
        }
    }
}
