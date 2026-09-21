package mcp

// HTTP 层的失败不能被当作协议消息投给解析器。
//
// 现场：服务端会话失效后，POST 收到 `400 Bad Request` + `text/plain` 的
// "Invalid session ID"。客户端把这个纯文本体原样塞进接收队列，于是：
//   ① 解析必然失败，日志只留下一句
//      `[jsonrpc] client handleMessage error: Exception: Parse error`；
//   ② 服务端真正说的话（会话失效）被丢掉，在途调用还要干等满 timeout。
//
// 期望：非 2xx **且不是 JSON-RPC 消息**的响应，在传输层就变成异常，
// 消息里带上状态码与服务端原文；而规范允许的「4xx/5xx + JSON-RPC 错误体」
// 照旧投递（调用方要拿得到 code/message）。

import jsonvalue.*
import ystyle::jsonrpc.{Transport, Result}
import mcp.transport.*
import stdx.net.http.*
import std.collection.{ArrayList, HashMap}
import std.sync.*
import std.time.MonoTime
import std.unittest.*
import std.unittest.testmacro.*

class ErrorServerPortHolder {
    var value: UInt16 = 0
}

/** 固定回一个 HTTP 错误 + 给定响应体的假服务端。 */
class ErrorServer {
    let server: Server
    let baseUrl: String

    init(status: UInt16, contentType: String, respond: (String) -> String) {
        let portLock = Mutex()
        let portCond = synchronized(portLock) { portLock.condition() }
        let holder = ErrorServerPortHolder()
        let server = ServerBuilder().addr("127.0.0.1").port(0).build()
        server.distributor.register("/mcp", { ctx =>
            let buf = Array<Byte>(4096, repeat: 0)
            let total = ArrayList<Byte>()
            while (true) {
                let len = ctx.request.body.read(buf)
                if (len <= 0) { break }
                total.add(all: buf[0..len])
            }
            let text = respond(String.fromUtf8(total.toArray()))
            ctx.responseBuilder.status(status)
                .header("content-type", contentType)
                .body(text)
        })
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
        this.baseUrl = "http://127.0.0.1:${holder.value}/mcp"
    }

    func close(): Unit {
        this.server.close()
    }
}

/** 原样回一个纯文本错误体（模拟 Go 侧 `Invalid session ID`）。 */
func plainErrorBody(status: UInt16, text: String): ErrorServer {
    ErrorServer(status, "text/plain; charset=utf-8", { _ => text })
}

/** 回一个 JSON-RPC 错误响应，id 照抄请求里的 id。 */
func jsonErrorBody(status: UInt16, code: Int64, message: String): ErrorServer {
    ErrorServer(status, "application/json", { body =>
        let id = match (JsonValue.parse(body)["id"]) {
            case Some(JsonValue.Number(n)) => Int64(n).toString()
            case Some(JsonValue.String(v)) => v
            case _ => "1"
        }
        "{\"jsonrpc\":\"2.0\",\"id\":${id},\"error\":{\"code\":${code},\"message\":\"${message}\"}}"
    })
}

func connectOutcome(transport: Transport): (Bool, String, Int64) {
    let client = McpClient(transport)
    let start = MonoTime.now()
    var threw = false
    var message = ""
    try {
        match (client.connect(Implementation("probe", "1.0.0"), timeout: Duration.second * 5)) {
            case Result.Ok(_) => ()
            case Result.Err(reason) => message = reason
        }
    } catch (e: Exception) {
        threw = true
        message = e.message
    }
    let elapsed = (MonoTime.now() - start).toMilliseconds()
    client.close()
    (threw, message, elapsed)
}

// ── 会话式传输（2025-11-25 streamable-http）────────────────────

@Test
func sessionTransport_plainTextHttpErrorIsSurfaced() {
    let server = plainErrorBody(UInt16(400), "Invalid session ID")
    let transport = StreamableHttpClient_2025_11_25(server.baseUrl)
    let (threw, message, elapsed) = connectOutcome(transport)
    transport.close()
    server.close()

    if (!threw) {
        @Fail("HTTP failure must surface as an error, got: ${message}")
    }
    if (!message.contains("HTTP 400")) {
        @Fail("message should carry the status code, got: ${message}")
    }
    if (!message.contains("Invalid session ID")) {
        @Fail("message should carry the server's own words, got: ${message}")
    }
    // 立刻失败，而不是干等满 timeout（5s）后才报「请求超时」
    if (elapsed >= 3000) {
        @Fail("the failure must come back at once, waited ${elapsed}ms")
    }
}

@Test
func sessionTransport_jsonRpcErrorStillReachesTheCaller() {
    // 规范允许 4xx/5xx 携带 JSON-RPC 错误体：那是协议消息，不该变成传输异常
    let server = jsonErrorBody(UInt16(400), -32000, "session expired")
    let transport = StreamableHttpClient_2025_11_25(server.baseUrl)
    let (threw, message, elapsed) = connectOutcome(transport)
    transport.close()
    server.close()

    if (threw) {
        @Fail("a JSON-RPC error body is a protocol message, not a transport failure: ${message}")
    }
    if (!message.contains("session expired")) {
        @Fail("caller should see the server's error message, got: ${message}")
    }
    if (elapsed >= 3000) {
        @Fail("the error response should be delivered at once, waited ${elapsed}ms")
    }
}

// ── 无状态传输（2026-07-28 stateless）─────────────────────────

@Test
func statelessTransport_plainTextHttpErrorIsSurfaced() {
    let server = plainErrorBody(UInt16(401), "invalid token")
    let transport = StatelessHttpClient_2026_07_28(server.baseUrl)
    let (threw, message, elapsed) = connectOutcome(transport)
    transport.close()
    server.close()

    if (!threw) {
        @Fail("HTTP failure must surface as an error, got: ${message}")
    }
    if (!message.contains("HTTP 401")) {
        @Fail("message should carry the status code, got: ${message}")
    }
    if (!message.contains("invalid token")) {
        @Fail("message should carry the server's own words, got: ${message}")
    }
    if (elapsed >= 3000) {
        @Fail("the failure must come back at once, waited ${elapsed}ms")
    }
}

@Test
func statelessTransport_htmlErrorBodyIsSurfaced() {
    // 反向代理/网关的 HTML 错误页同理：不是 JSON 就不是协议消息
    let server = ErrorServer(UInt16(502), "text/html", { _ => "<html><body>Bad Gateway</body></html>" })
    let transport = StatelessHttpClient_2026_07_28(server.baseUrl)
    let (threw, message, _) = connectOutcome(transport)
    transport.close()
    server.close()

    if (!threw) {
        @Fail("HTML error page must surface as a transport failure, got: ${message}")
    }
    if (!message.contains("HTTP 502")) {
        @Fail("message should carry the status code, got: ${message}")
    }
}
