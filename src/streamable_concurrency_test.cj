package mcp

// streamable HTTP 传输层的并发回归测试。
//
// 背景（2026-09-12 生产事故）：旧实现用「单个共享 waitingForResponse 标志 + 单个
// pendingResponse 槽位」承载响应，而 HTTP 每连接一个 handler 协程。并发请求全部在
// 入队后被消费线程处理完并 send()，此时还没有任何 handler 置位 → 响应被静默丢弃 →
// 每个 handler 进入永不退出的等待（30s 超时后只是重新 wait）→ 请求永久挂住。
// 实测：忆时塔并发请求 100% 挂住、顺序请求约 5~7% 挂住。
//
// 本测试就是当年缺的那条用例：并发请求必须**各自拿回自己的响应**（id 与载荷都对得上），
// 且多客户端 id 撞车时也不能丢请求或串台。

import jsonvalue.*
import mcp.transport.*
import stdx.net.http.*
import std.collection.{ArrayList, HashMap}
import std.sync.*
import std.unittest.*
import std.unittest.testmacro.*

class ConnTestPortHolder {
    var value: UInt16 = 0
}

// 起一个真实 HTTP 服务（含 MCP 层与一个 echo 工具），供并发用例共用。
class ConnTestServer {
    let server: Server
    let transport: StreamableHttpServer_2025_11_25
    let baseUrl: String

    init() {
        let portLock = Mutex()
        let portCond = synchronized(portLock) { portLock.condition() }
        let holder = ConnTestPortHolder()
        let server = ServerBuilder().addr("127.0.0.1").port(0).build()
        let transport = StreamableHttpServer_2025_11_25()
        transport.registerRoutes(server.distributor)

        let mcpServer = McpServer("conn-test-server", "1.0.0", transport)
        let schema = ToolInputSchema("object", HashMap<String, JsonValue>(), [])
        schema.addField("tag", "string", "回显标签", required: true)
        mcpServer.addTool(Tool("echo", "回显 tag", schema), { params =>
            let tag = match (params.arguments.get("tag")) {
                case Some(JsonValue.String(t)) => t
                case _ => "?"
            }
            // 制造真实的重叠窗口：并发请求必须在「有别的请求正在处理」时各自拿到响应
            sleep(Duration.millisecond * 30)
            CallToolResult.text(tag)
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
func rawPost(baseUrl: String, body: String): String {
    let client = ClientBuilder().build()
    try {
        let req = HttpRequestBuilder()
            .url(baseUrl + "/")
            .header("content-type", "application/json")
            .header("accept", "application/json, text/event-stream")
            .header("MCP-Protocol-Version", "2025-11-25")
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
            } catch (_: Exception) { break }
            if (n <= 0) { break }
            total.add(all: buf[0..n])
        }
        String.fromUtf8(total.toArray())
    } finally {
        client.close()
    }
}

func echoBody(id: Int64, tag: String): String {
    "{\"jsonrpc\":\"2.0\",\"id\":${id},\"method\":\"tools/call\"," +
        "\"params\":{\"name\":\"echo\",\"arguments\":{\"tag\":\"${tag}\"}}}"
}

// 从响应里取 (id, 工具返回文本)；取不到时 id = -1。
func parseEchoResponse(resp: String): (Int64, String) {
    let jv = try {
        JsonValue.parse(resp)
    } catch (_: Exception) {
        JsonValue.Null
    }
    let id = match (jv["id"]) {
        case Some(JsonValue.Number(n)) => Int64(n)
        case _ => Int64(-1)
    }
    var text = ""
    match (jv["result"]) {
        case Some(r) =>
            match (r["content"]) {
                case Some(JsonValue.Array(items)) =>
                    if (items.size > 0) {
                        match (items[0]["text"]) {
                            case Some(JsonValue.String(t)) => text = t
                            case _ => ()
                        }
                    }
                case _ => ()
            }
        case None => ()
    }
    (id, text)
}

@Test
public class StreamableHttpConcurrencyTest {
    // 并发且 id 各不相同时：每个请求必须拿回「自己那次」的 id 与载荷。
    // 旧实现下这条会全部挂住（客户端超时）。
    @TestCase
    public func testConcurrentRequestsEachGetOwnResponse(): Unit {
        let s = ConnTestServer()
        try {
            let n: Int64 = 8
            let pairs = ArrayList<(Int64, String)>()
            let mutex = Mutex()
            let tasks = ArrayList<Future<Unit>>()
            for (i in 0..n) {
                let f = spawn {
                    let tag = "t${i}"
                    let resp = rawPost(s.baseUrl, echoBody(i + 1, tag))
                    let parsed = parseEchoResponse(resp)
                    synchronized(mutex) {
                        pairs.add(parsed)
                    }
                }
                tasks.add(f)
            }
            for (t in tasks) {
                let _ = t.get()
            }
            @Expect(pairs.size, n)
            // id 与 tag 必须成对：第 i 个请求 = id(i+1) + tag t{i}
            var matched: Int64 = 0
            for (p in pairs) {
                let (id, tag) = p
                if (id >= 1 && id <= n && tag == "t${id - 1}") {
                    matched += 1
                }
            }
            @Expect(matched, n) // 全部逐条对上；错配 = 响应串台
        } finally {
            s.close()
        }
    }

    // 多客户端 id 撞车（都从 id=1 起）：不能丢请求，也不能串台。
    @TestCase
    public func testConcurrentRequestsWithSameIdAllAnswered(): Unit {
        let s = ConnTestServer()
        try {
            let n: Int64 = 8
            let tags = ArrayList<String>()
            let mutex = Mutex()
            let tasks = ArrayList<Future<Unit>>()
            for (i in 0..n) {
                let f = spawn {
                    let tag = "same${i}"
                    let resp = rawPost(s.baseUrl, echoBody(1, tag))
                    let (id, text) = parseEchoResponse(resp)
                    synchronized(mutex) {
                        if (id == 1) {
                            tags.add(text)
                        }
                    }
                }
                tasks.add(f)
            }
            for (t in tasks) {
                let _ = t.get()
            }
            // 8 个请求都应答且各自唯一 —— 丢失会出现缺失、串台会出现重复
            @Expect(tags.size, n)
            var distinct = 0
            for (i in 0..n) {
                let want = "same${i}"
                var hit = false
                for (t in tags) {
                    if (t == want) { hit = true }
                }
                if (hit) { distinct += 1 }
            }
            @Expect(distinct, n)
        } finally {
            s.close()
        }
    }

    // 顺序请求不受影响（回归保护）。
    @TestCase
    public func testSequentialRequestsStillWork(): Unit {
        let s = ConnTestServer()
        try {
            for (i in 0..5) {
                let resp = rawPost(s.baseUrl, echoBody(100 + i, "seq${i}"))
                let (id, text) = parseEchoResponse(resp)
                @Expect(id, 100 + i)
                @Expect(text, "seq${i}")
            }
        } finally {
            s.close()
        }
    }
}
