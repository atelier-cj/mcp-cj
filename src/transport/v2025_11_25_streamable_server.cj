package mcp.transport

import ystyle::jsonrpc.*
import jsonvalue.*
import stdx.net.http.*
import std.collection.ArrayList
import std.sync.{Mutex, Condition, AtomicInt64}
import std.random.Random
import sonyflake.*

let sf = Sonyflake(Setting(Random().nextUInt16()))
let nextSessionId = AtomicInt64(1)

public class StreamableHttpServer_2025_11_25 <: Transport {
    private let messageQueue = ArrayList<Array<Byte>>()
    private let lock = Mutex()
    private let recvCond: Condition
    private let sseCond: Condition
    private let respCond: Condition
    private var sseWriter: ?HttpResponseWriter = None
    private var pendingResponse: ?Array<Byte> = None
    private var waitingForResponse: Bool = false
    private var closed: Bool = false
    // SSE 长连接心跳间隔：周期写 SSE 注释行探测对端活性。客户端断开后写失败 →
    // 清理陈旧 writer 并退出 handleSSE，http 层随即回收连接（否则 SSE 连接永不
    // 退出 = CLOSE_WAIT/fd 泄漏 → 内存持续增长 → 生产写路径 OOM 诱因）。
    private let heartbeatInterval: Duration

    public init(heartbeatInterval!: Duration = Duration.second * 30) {
        this.heartbeatInterval = heartbeatInterval
        this.recvCond = synchronized(this.lock) { this.lock.condition() }
        this.sseCond = synchronized(this.lock) { this.lock.condition() }
        this.respCond = synchronized(this.lock) { this.lock.condition() }
    }

    public func registerRoutes(distributor: HttpRequestDistributor): Unit {
        distributor.register("/", { ctx => this.handle(ctx) })
    }

    // 单一入口 handler（与 UI 等合并单端口时直接分发：POST/DELETE → MCP，其余交给外层）
    public func asHandler(): HttpRequestHandler {
        FuncHandler({ ctx => this.handle(ctx) })
    }

    private func handle(ctx: HttpContext): Unit {
        if (ctx.request.method == "GET") {
            this.handleSSE(ctx)
        } else if (ctx.request.method == "POST") {
            this.handlePost(ctx)
        } else if (ctx.request.method == "DELETE") {
            this.handleDelete(ctx)
        } else {
            ctx.responseBuilder.status(405).header("content-type", "text/plain").body("Method not allowed")
        }
    }

    private func handleSSE(ctx: HttpContext): Unit {
        ctx.responseBuilder
            .status(200)
            .header("content-type", "text/event-stream")
            .header("cache-control", "no-cache")
            .header("connection", "keep-alive")
            .header("transfer-encoding", "chunked")

        let writer = HttpResponseWriter(ctx)

        synchronized(this.lock) {
            this.sseWriter = Some(writer)
        }

        // 立即写一个 SSE 注释行：触发首次写入（提交 200 + SSE 响应头）。
        // 否则客户端永远收不到响应头（健康服务器下 handleSSE 阻塞在等待循环里），
        // 官方 MCP 客户端/Inspector 无法建立 SSE 通道。
        try {
            writer.write(": mcp connected\n\n".toArray())
        } catch (_: Exception) {
            // 连接刚建立即失败：忽略，后续由 send() 清理陈旧 writer
        }

        // 等待循环：close() 唤醒退出；心跳间隔超时则写一个 SSE 注释行探测对端
        // 活性——客户端断开后写失败，清理 writer 并退出，http 层回收连接
        // （修复：SSE 长连接原先无限阻塞在 sseCond.wait()，对端断开后无人 close，
        // CLOSE_WAIT/fd 累积 → 内存增长 → 生产写路径 OOM）。
        var sseAlive = true
        while (sseAlive) {
            var timedOut = false
            synchronized(this.lock) {
                if (this.closed) {
                    sseAlive = false
                } else {
                    let woke = this.sseCond.wait(timeout: this.heartbeatInterval)
                    if (this.closed) {
                        sseAlive = false
                    } else if (!woke) {
                        // 超时未唤醒：跳出做心跳探测（锁外写，避免持锁 IO）
                        timedOut = true
                    }
                }
            }
            if (!sseAlive) { break }
            if (!timedOut) { continue }
            // 锁外心跳写：写失败 = 对端已断开，清理陈旧 writer 退出
            synchronized(this.lock) {
                match (this.sseWriter) {
                    case Some(w) =>
                        try {
                            w.write(": ping\n\n".toArray())
                        } catch (_: Exception) {
                            this.sseWriter = None
                            sseAlive = false
                        }
                    case None =>
                        // writer 已被 send() 清理（写失败过）：连接已断，退出
                        sseAlive = false
                }
            }
        }
    }

    private func handlePost(ctx: HttpContext): Unit {
        // Validate MCP-Protocol-Version header
        if (ctx.request.headers.getFirst("MCP-Protocol-Version").isNone() &&
            ctx.request.headers.getFirst("Mcp-Method").isSome()) {
            ctx.responseBuilder.status(400).header("content-type", "text/plain").body("Missing MCP-Protocol-Version header")
            return
        }

        let buf = Array<Byte>(4096, repeat: 0)
        let total = ArrayList<Byte>()
        while (true) {
            let len = ctx.request.body.read(buf)
            if (len <= 0) { break }
            total.add(all: buf[0..len])
        }
        if (total.size == 0) {
            ctx.responseBuilder.status(400).header("content-type", "text/plain").body("Empty body")
            return
        }

        let bodyStr = String.fromUtf8(total.toArray())
        let jv = try { JsonValue.parse(bodyStr) } catch (_: Exception) { JsonValue.Null }

        // Determine if this is a notification (no id) or request (has id)
        let isNotification = match (jv["id"]) { case None => true case _ => false }

        // Create session for initialize without MCP-Session-Id
        let hasSessionHeader = ctx.request.headers.getFirst("MCP-Session-Id").isSome()
        let methodName = match (jv["method"]) {
            case Some(JsonValue.String(m)) => m
            case _ => ""
        }
        let shouldCreateSession = !hasSessionHeader && methodName == "initialize"

        // Notifications: accept with 202
        if (isNotification) {
            ctx.responseBuilder.status(202).body("")
            return
        }

        // Requests: queue and wait for response
        synchronized(this.lock) {
            this.messageQueue.add(total.toArray())
            this.recvCond.notifyAll()
        }

        let respBytes = synchronized(this.lock) {
            this.waitingForResponse = true
            while (this.pendingResponse.isNone() && !this.closed) {
                this.respCond.wait(timeout: 30 * Duration.second)
            }
            if (let Some(response) <- this.pendingResponse) {
                this.pendingResponse = None
                this.waitingForResponse = false
                Option<Array<Byte>>.Some(response)
            } else {
                this.waitingForResponse = false
                Option<Array<Byte>>.None
            }
        }

        let builder = ctx.responseBuilder.status(200).header("content-type", "application/json")
        if (shouldCreateSession) {
            let sid = nextSessionId.fetchAdd(1).toString()
            builder.header("MCP-Session-Id", sid)
        }
        match (respBytes) {
            case Some(b) => builder.body(String.fromUtf8(b))
            case None => builder.body("{\"error\":\"timeout\"}")
        }
    }

    private func handleDelete(ctx: HttpContext): Unit {
        ctx.responseBuilder.status(405).header("content-type", "text/plain").body("Method not allowed")
    }

    public func send(data: Array<Byte>): Unit {
        let json = String.fromUtf8(data[0..data.size - 1])
        synchronized(this.lock) {
            if (this.waitingForResponse) {
                this.pendingResponse = Some(json.toArray())
                this.respCond.notifyAll()
            } else if (let Some(writer) <- this.sseWriter) {
                let event = "data: " + json + "\n\n"
                // 陈旧 SSE 连接写失败（客户端已断开）：清理该 writer，绝不把异常抛给调用方。
                // 否则单次断连会经 handleMessage → close() 杀死整个服务器的接收循环，
                // 表现为后续所有请求瞬时 {"error":"timeout"}（需要重启才恢复）。
                try {
                    writer.write(event.toArray())
                } catch (_: Exception) {
                    this.sseWriter = None
                }
            }
        }
    }

    public func receive(): ?Array<Byte> {
        synchronized(this.lock) {
            while (this.messageQueue.size == 0 && !this.closed) {
                this.recvCond.wait(timeout: 30 * Duration.second)
            }
            if (this.messageQueue.size > 0) {
                let bytes = this.messageQueue.remove(at: 0)
                let result = Array<Byte>(bytes.size + 1, repeat: 0)
                for (i in 0..bytes.size) { result[i] = bytes[i] }
                result[bytes.size] = 10
                Some(result)
            } else {
                None
            }
        }
    }

    public func isClosed(): Bool {
        synchronized(this.lock) { this.closed }
    }

    // 当前是否有活跃 SSE 连接（运维监控/测试用：SSE 长连接泄漏排查，
    // 见 handleSSE 心跳注释——对端断开后 writer 被清理，此处转 false）
    public func hasActiveSse(): Bool {
        synchronized(this.lock) { this.sseWriter.isSome() }
    }

    public func close(): Unit {
        synchronized(this.lock) {
            this.closed = true
            this.recvCond.notifyAll()
            this.sseCond.notifyAll()
            this.respCond.notifyAll()
        }
    }
}

public type SessionHttpServerTransport = StreamableHttpServer_2025_11_25

