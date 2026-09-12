package mcp.transport

import ystyle::jsonrpc.*
import jsonvalue.*
import stdx.net.http.*
import std.collection.{ArrayList, HashMap}
import std.sync.{Mutex, Condition, AtomicInt64}
import std.random.Random
import sonyflake.*

let sf = Sonyflake(Setting(Random().nextUInt16()))
let nextSessionId = AtomicInt64(1)
// 等待槽的进程内唯一序号：用于在队列里按值定位并摘除自己（Cangjie 无引用相等运算符）。
let nextCallToken = AtomicInt64(1)

// 一个在飞请求的等待槽。
//
// 关键不变量：**注册等待槽与入队请求必须在同一个临界区内完成**。旧实现先入队并唤醒
// 消费线程、之后才置"我在等响应"，消费线程可以抢在这个窗口内把响应发完 —— 而响应投递
// 只认那一个全局标志，于是响应被静默丢弃，调用方进入永不退出（30s×N 循环）的等待。
// 这是生产上"忆时塔偶发请求永久挂住"的根因。
class PendingCall {
    let token: Int64
    let cond: Condition
    var response: ?Array<Byte> = None

    init(lock: Mutex) {
        this.token = nextCallToken.fetchAdd(1)
        this.cond = lock.condition()
    }
}

// 从 JSON-RPC 消息里取 id 的字符串化形式。
//
// 形状前缀（n:/s:）用来区分数字 id 与字符串 id，避免 1 与 "1" 互相干扰。
// 无 id（通知）或结构不可用时返回 None —— 这类消息不应答。
func jsonRpcIdKey(jv: JsonValue): ?String {
    match (jv["id"]) {
        case Some(JsonValue.Number(n)) => Some("n:" + n.toString())
        case Some(JsonValue.String(s)) => Some("s:" + s)
        case _ => None
    }
}

// 单个请求的等待上限：到点返回显式 JSON-RPC 错误，绝不无限等待。
// 默认 5 分钟——足够覆盖忆时塔里最慢的 summarize 类调用，同时保证任何异常都不会变成永久挂住。
let DEFAULT_REQUEST_TIMEOUT = Duration.minute * 5

public class StreamableHttpServer_2025_11_25 <: Transport {
    private let messageQueue = ArrayList<Array<Byte>>()
    private let lock = Mutex()
    private let recvCond: Condition
    private let sseCond: Condition
    private var sseWriter: ?HttpResponseWriter = None
    private var closed: Bool = false
    // 在飞请求：JSON-RPC id → 等待队列（FIFO）。
    //
    // 用队列而不是单值，是为了同时解决两件事：
    //   ① 并发：多个请求可以同时在飞，各自拿到自己的响应；
    //   ② id 撞车：不同客户端各自从 id=1 起计数，同一 id 的两个在飞请求按到达顺序配对
    //      （jsonrpc 的 receiveLoop 严格串行处理，所以同一 id 的响应也必然按序返回）。
    private let pending = HashMap<String, ArrayList<PendingCall>>()
    // SSE 长连接心跳间隔：周期写 SSE 注释行探测对端活性。客户端断开后写失败 →
    // 清理陈旧 writer 并退出 handleSSE，http 层随即回收连接（否则 SSE 连接永不
    // 退出 = CLOSE_WAIT/fd 泄漏 → 内存持续增长 → 生产写路径 OOM 诱因）。
    private let heartbeatInterval: Duration
    private let requestTimeout: Duration

    public init(heartbeatInterval!: Duration = Duration.second * 30,
        requestTimeout!: Duration = DEFAULT_REQUEST_TIMEOUT) {
        this.heartbeatInterval = heartbeatInterval
        this.requestTimeout = requestTimeout
        this.recvCond = synchronized(this.lock) { this.lock.condition() }
        this.sseCond = synchronized(this.lock) { this.lock.condition() }
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
        var parsed: ?JsonValue = None
        try {
            parsed = Some(JsonValue.parse(bodyStr))
        } catch (_: Exception) {
            parsed = None
        }
        let jv = match (parsed) {
            case Some(v) => v
            case None => JsonValue.Null
        }

        // Create session for initialize without MCP-Session-Id
        let hasSessionHeader = ctx.request.headers.getFirst("MCP-Session-Id").isSome()
        let methodName = match (jv["method"]) {
            case Some(JsonValue.String(m)) => m
            case _ => ""
        }
        let shouldCreateSession = !hasSessionHeader && methodName == "initialize"

        match (jsonRpcIdKey(jv)) {
            case None =>
                // 通知（无 id）：交给服务端处理，但按 JSON-RPC 不应答。
                // 旧实现在这里直接 202 返回、**根本不入队** —— 于是 notifications/initialized
                // 之类的通知永远到不了服务端。现在入队，只是不注册等待槽。
                synchronized(this.lock) {
                    this.messageQueue.add(total.toArray())
                    this.recvCond.notifyAll()
                }
                ctx.responseBuilder.status(202).body("")
            case Some(key) =>
                this.awaitResponse(ctx, key, jv, total.toArray(), shouldCreateSession)
        }
    }

    // 请求路径：注册等待槽 + 入队（同一临界区）→ 有界等待 → 写回响应。
    private func awaitResponse(ctx: HttpContext, key: String, jv: JsonValue, body: Array<Byte>,
        shouldCreateSession: Bool): Unit {
        var call: ?PendingCall = None
        synchronized(this.lock) {
            if (this.closed) {
                ctx.responseBuilder.status(503).header("content-type", "text/plain").body("Server closed")
                return
            }
            let slot = PendingCall(this.lock)
            // 顺序不可颠倒：先把等待槽挂上，再入队并唤醒消费线程。
            match (this.pending.get(key)) {
                case Some(queue) => queue.add(slot)
                case None =>
                    let queue = ArrayList<PendingCall>()
                    queue.add(slot)
                    this.pending[key] = queue
            }
            this.messageQueue.add(body)
            this.recvCond.notifyAll()
            call = Some(slot)
        }

        let pendingCall = match (call) {
            case Some(c) => c
            case None => return
        }
        var respBytes: ?Array<Byte> = None
        var timedOut = false
        synchronized(this.lock) {
            while (pendingCall.response.isNone() && !this.closed) {
                // wait 返回 false 表示超时：直接退出，返回显式错误。
                // 旧实现超时后只是重新 wait，于是一次响应丢失 = 永久挂住。
                if (!pendingCall.cond.wait(timeout: this.requestTimeout)) {
                    timedOut = true
                    break
                }
            }
            respBytes = pendingCall.response
            // 摘掉自己：正常投递，或超时/关闭时离开队列（避免为已放弃的请求长期占位）。
            // 按 token 值定位，而不是引用相等（Cangjie 无 ===）。
            match (this.pending.get(key)) {
                case Some(queue) =>
                    var idx: Int64 = -1
                    for (i in 0..queue.size) {
                        if (queue[i].token == pendingCall.token) {
                            idx = i
                            break
                        }
                    }
                    if (idx >= 0) {
                        queue.remove(at: idx)
                    }
                    if (queue.size == 0) {
                        this.pending.remove(key)
                    }
                case None => ()
            }
        }

        let builder = ctx.responseBuilder.status(200).header("content-type", "application/json")
        if (shouldCreateSession) {
            let sid = nextSessionId.fetchAdd(1).toString()
            builder.header("MCP-Session-Id", sid)
        }
        match (respBytes) {
            case Some(b) => builder.body(String.fromUtf8(b))
            case None =>
                let reason = if (timedOut) { "request timeout" } else { "server closed" }
                builder.body(timeoutBody(jv, reason))
        }
    }

    private func handleDelete(ctx: HttpContext): Unit {
        ctx.responseBuilder.status(405).header("content-type", "text/plain").body("Method not allowed")
    }

    public func send(data: Array<Byte>): Unit {
        if (data.size == 0) { return }
        let json = String.fromUtf8(data[0..data.size - 1])
        var key: ?String = None
        try {
            key = jsonRpcIdKey(JsonValue.parse(json))
        } catch (_: Exception) {
            key = None
        }
        var delivered = false
        synchronized(this.lock) {
            match (key) {
                case Some(k) =>
                    match (this.pending.get(k)) {
                        case Some(queue) =>
                            if (queue.size > 0) {
                                let slot = queue[0]
                                if (slot.response.isNone()) {
                                    slot.response = Some(json.toArray())
                                    slot.cond.notifyAll()
                                    delivered = true
                                }
                                // 该槽已被超时放弃 / 已投递：消费掉响应并出队，保持 FIFO 对齐
                                queue.remove(at: 0)
                                if (queue.size == 0) { this.pending.remove(k) }
                            }
                        case None => ()
                    }
                case None => ()
            }
            if (!delivered) {
                // 无等待槽可投递（服务端主动通知、或 id:null 的错误响应）：
                // 有 SSE 长连接就走 SSE，否则丢弃。
                match (this.sseWriter) {
                    case Some(writer) =>
                        let event = "data: " + json + "\n\n"
                        // 陈旧 SSE 连接写失败（客户端已断开）：清理该 writer，绝不把异常抛给调用方。
                        // 否则单次断连会经 handleMessage → close() 杀死整个服务器的接收循环，
                        // 表现为后续所有请求瞬时 {"error":"timeout"}（需要重启才恢复）。
                        try {
                            writer.write(event.toArray())
                        } catch (_: Exception) {
                            this.sseWriter = None
                        }
                    case None => ()
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

    // 当前在飞请求数（运维监控/测试用）
    public func pendingCount(): Int64 {
        synchronized(this.lock) {
            var n: Int64 = 0
            for ((_, queue) in this.pending) { n += queue.size }
            n
        }
    }

    public func close(): Unit {
        synchronized(this.lock) {
            this.closed = true
            this.recvCond.notifyAll()
            this.sseCond.notifyAll()
            // 唤醒全部在飞请求，让它们的等待循环立刻退出（否则要等到各自超时）
            for ((_, queue) in this.pending) {
                for (slot in queue) { slot.cond.notifyAll() }
            }
            this.pending.clear()
        }
    }
}

// 超时/关闭时的显式应答：带上原请求的 id，客户端可据此判定失败而不是无限等待。
func timeoutBody(jv: JsonValue, reason: String): String {
    let idText = match (jv["id"]) {
        case Some(v) => v.stringify()
        case None => "null"
    }
    "{\"jsonrpc\":\"2.0\",\"id\":" + idText +
        ",\"error\":{\"code\":-32001,\"message\":\"" + reason + "\"}}"
}

public type SessionHttpServerTransport = StreamableHttpServer_2025_11_25
