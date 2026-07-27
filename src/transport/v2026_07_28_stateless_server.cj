package mcp.transport

import ystyle::jsonrpc.*
import jsonvalue.*
import stdx.net.http.*
import std.collection.{ArrayList, HashMap}
import std.sync.{Mutex, Condition, AtomicInt64}
import std.core.Duration

class SubscriptionFilter {
    var toolsListChanged: Bool = false
    var promptsListChanged: Bool = false
    var resourcesListChanged: Bool = false
    var resourceSubscriptions = ArrayList<String>()

    func accepts(method: String): Bool {
        match (method) {
            case "notifications/tools/list_changed" => this.toolsListChanged
            case "notifications/prompts/list_changed" => this.promptsListChanged
            case "notifications/resources/list_changed" => this.resourcesListChanged
            case "notifications/resources/updated" => this.resourceSubscriptions.size > 0
            case _ => false
        }
    }
}

class SubscriptionEntry {
    var writer: HttpResponseWriter
    var id: Int64
    var filter: SubscriptionFilter
    var closed: Bool = false

    public init(writer: HttpResponseWriter, id: Int64, filter: SubscriptionFilter) {
        this.writer = writer
        this.id = id
        this.filter = filter
    }
}

let nextSubId = AtomicInt64(1)

class RequestSseStream {
    var writer: HttpResponseWriter
    var requestId: String
    var progressToken: ?String
    var closed: Bool = false

    public init(writer: HttpResponseWriter, requestId: String, progressToken: ?String) {
        this.writer = writer
        this.requestId = requestId
        this.progressToken = progressToken
    }

    func matchesToken(token: String): Bool {
        match (this.progressToken) {
            case Some(t) => t == token
            case None => false
        }
    }
}

public class StatelessHttpServer_2026_07_28 <: Transport {
    private let lock = Mutex()
    private let recvCond: Condition
    private let respCond: Condition
    private let subCond: Condition
    private let messageQueue = ArrayList<Array<Byte>>()
    private var pendingResponse: ?Array<Byte> = None
    private var waitingForResponse: Bool = false
    private var closed: Bool = false
    private let subscriptions = ArrayList<SubscriptionEntry>()
    private let requestStreams = ArrayList<RequestSseStream>()

    public init() {
        this.recvCond = synchronized(this.lock) { this.lock.condition() }
        this.respCond = synchronized(this.lock) { this.lock.condition() }
        this.subCond = synchronized(this.lock) { this.lock.condition() }
    }

    public func registerRoutes(distributor: HttpRequestDistributor): Unit {
        distributor.register("/", { ctx =>
            if (ctx.request.method != "POST") {
                ctx.responseBuilder.status(405).header("content-type", "text/plain").body("Method not allowed")
                return
            }
            this.handlePost(ctx)
        })
    }

    private func handlePost(ctx: HttpContext): Unit {
        if (!this.validatePreHeaders(ctx)) { return }

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
        let jv = try { Option<JsonValue>.Some(JsonValue.parse(bodyStr)) } catch (_: Exception) { Option<JsonValue>.None }

        if (!this.validateBodyHeaders(ctx, jv)) { return }

        let method = match (jv) {
            case Some(v) => match (v["method"]) {
                case Some(JsonValue.String(m)) => Option<String>.Some(m)
                case _ => Option<String>.None
            }
            case None => Option<String>.None
        }

        if (method == Some("subscriptions/listen")) {
            this.handleSubscriptionListen(ctx, bodyStr)
            return
        }

        let hasId = match (jv) {
            case Some(v) => v["id"].isSome()
            case None => false
        }

        if (!hasId) {
            synchronized(this.lock) {
                this.messageQueue.add(total.toArray())
                this.recvCond.notifyAll()
            }
            ctx.responseBuilder.status(202).body("")
            return
        }

        // If client accepts SSE, return request-scoped SSE stream
        let accept = ctx.request.headers.getFirst("Accept") ?? ""
        if (accept.contains("text/event-stream")) {
            let rawJv = match (jv) { case Some(v) => v case None => JsonValue.Null }
            let reqId = match (rawJv["id"]) {
                case Some(JsonValue.Number(n)) => n.toString()
                case Some(JsonValue.String(s)) => s
                case _ => ""
            }
            let progressToken = match (rawJv["params"]) {
                case Some(JsonValue.Map(p)) => match (p.get("_meta")) {
                    case Some(JsonValue.Map(meta)) => match (meta.get("progressToken")) {
                        case Some(JsonValue.String(s)) => Option<String>.Some(s)
                        case Some(JsonValue.Number(n)) => Option<String>.Some(n.toString())
                        case _ => Option<String>.None
                    }
                    case _ => Option<String>.None
                }
                case _ => Option<String>.None
            }

            ctx.responseBuilder
                .status(200)
                .header("content-type", "text/event-stream")
                .header("cache-control", "no-cache")
                .header("transfer-encoding", "chunked")
                .header("x-accel-buffering", "no")

            let writer = HttpResponseWriter(ctx)
            let stream = RequestSseStream(writer, reqId, progressToken)
            synchronized(this.lock) {
                this.requestStreams.add(stream)
                this.messageQueue.add(total.toArray())
                this.recvCond.notifyAll()
            }

            // Keep SSE open until response arrives or timeout
            try {
                var keepAliveCounter = 0
                for (_ in 0..300) {
                    synchronized(this.lock) {
                        if (stream.closed) { break }
                    }
                    sleep(Duration.second)
                    keepAliveCounter++
                    if (keepAliveCounter >= 15) {
                        keepAliveCounter = 0
                        writer.write((":\r\n").toArray())
                    }
                }
            } catch (_: Exception) { }
            synchronized(this.lock) {
                stream.closed = true
                var i = 0
                while (i < this.requestStreams.size) {
                    if (this.requestStreams[i].requestId == reqId) {
                        this.requestStreams.remove(at: i)
                    } else { i++ }
                }
            }
            return
        }

        // Synchronous response (no SSE requested)
        synchronized(this.lock) {
            this.messageQueue.add(total.toArray())
            this.recvCond.notifyAll()
            this.waitingForResponse = true
            while (this.pendingResponse.isNone() && !this.closed) {
                this.respCond.wait(timeout: 30 * Duration.second)
            }
            if (let Some(response) <- this.pendingResponse) {
                this.pendingResponse = None
                this.waitingForResponse = false
                ctx.responseBuilder.status(200)
                    .header("content-type", "application/json")
                    .body(String.fromUtf8(response))
            } else {
                this.waitingForResponse = false
                ctx.responseBuilder.status(504).body("{\"error\":\"timeout\"}")
            }
        }
    }

    private func handleSubscriptionListen(ctx: HttpContext, bodyStr: String): Unit {
        let jv = try { JsonValue.parse(bodyStr) } catch (_: Exception) { return }
        let params = match (jv["params"]) { case Some(p) => p case _ => JsonValue.Null }
        let notifs = match (params["notifications"]) { case Some(n) => n case _ => JsonValue.Null }

        let filter = SubscriptionFilter()
        match (notifs["toolsListChanged"]) {
            case Some(JsonValue.Boolean(v)) => filter.toolsListChanged = v
            case _ => ()
        }
        match (notifs["promptsListChanged"]) {
            case Some(JsonValue.Boolean(v)) => filter.promptsListChanged = v
            case _ => ()
        }
        match (notifs["resourcesListChanged"]) {
            case Some(JsonValue.Boolean(v)) => filter.resourcesListChanged = v
            case _ => ()
        }
        match (notifs["resourceSubscriptions"]) {
            case Some(JsonValue.Array(arr)) =>
                for (item in arr) {
                    match (item) {
                        case JsonValue.String(uri) => filter.resourceSubscriptions.add(uri)
                        case _ => ()
                    }
                }
            case _ => ()
        }

                let subId = match (jv["id"]) {
            case Some(id) => id
            case _ => JsonValue.Null
        }

        ctx.responseBuilder
            .status(200)
            .header("content-type", "text/event-stream")
            .header("cache-control", "no-cache")
            .header("transfer-encoding", "chunked")
            .header("x-accel-buffering", "no")

        let writer = HttpResponseWriter(ctx)
        let entry = SubscriptionEntry(writer, nextSubId.fetchAdd(1), filter)

        synchronized(this.lock) {
            this.subscriptions.add(entry)
        }

        // Send acknowledged notification
        let ackStr = this.buildAcknowledged(subId)
        writer.write(("data: " + ackStr + "\n\n").toArray())

        // Keep SSE stream alive until closed
        try {
            while (true) {
                synchronized(this.lock) {
                    if (entry.closed || this.closed) { break }
                }
                sleep(Duration.second * 30) // 30s keep-alive
                synchronized(this.lock) {
                    if (entry.closed || this.closed) { break }
                }
                writer.write((":\r\n").toArray())
            }
        } catch (_: Exception) {
            // Client disconnected
        }
        synchronized(this.lock) {
            entry.closed = true
            var i = 0
            while (i < this.subscriptions.size) {
                if (this.subscriptions[i].id == entry.id) {
                    this.subscriptions.remove(at: i)
                } else { i++ }
            }
        }
    }

    private func buildAcknowledged(subId: JsonValue): String {
        let m = HashMap<String, JsonValue>()
        m.add("jsonrpc", JsonValue.String("2.0"))
        m.add("method", JsonValue.String("notifications/subscriptions/acknowledged"))
        let params = HashMap<String, JsonValue>()
        let meta = HashMap<String, JsonValue>()
        meta.add("io.modelcontextprotocol/subscriptionId", subId)
        params.add("_meta", JsonValue.Map(meta))
        m.add("params", JsonValue.Map(params))
        String.fromUtf8(JsonValue.Map(m).toBytes())
    }

    private func validatePreHeaders(ctx: HttpContext): Bool {
        if (let Some(origin) <- ctx.request.headers.getFirst("Origin")) {
            if ((origin.startsWith("http://") || origin.startsWith("https://")) && !this.isAllowedOrigin(origin)) {
                ctx.responseBuilder.status(403).body("{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32001,\"message\":\"Origin not allowed\"}}")
                return false
            }
        }
        if (ctx.request.headers.getFirst("MCP-Protocol-Version").isNone()) {
            ctx.responseBuilder.status(400).body("{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32002,\"message\":\"Missing MCP-Protocol-Version header\"}}")
            return false
        }
        let accept = ctx.request.headers.getFirst("Accept") ?? ""
        if (!accept.contains("application/json") || !accept.contains("text/event-stream")) {
            ctx.responseBuilder.status(400).body("{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32002,\"message\":\"Accept header must include application/json and text/event-stream\"}}")
            return false
        }
        true
    }

    private func validateBodyHeaders(ctx: HttpContext, body: ?JsonValue): Bool {
        match (body) {
            case Some(jv) =>
                let bodyMethod = match (jv["method"]) {
                    case Some(JsonValue.String(m)) => m
                    case _ => ""
                }
                if (let Some(headerMethod) <- ctx.request.headers.getFirst("Mcp-Method")) {
                    if (headerMethod != bodyMethod) {
                        ctx.responseBuilder.status(400).body("{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32020,\"message\":\"HeaderMismatch: Mcp-Method header '${headerMethod}' does not match body method '${bodyMethod}'\"}}")
                        return false
                    }
                }
                if (let Some(headerName) <- ctx.request.headers.getFirst("Mcp-Name")) {
                    let bodyName = match (jv["params"]) {
                        case Some(JsonValue.Map(p)) =>
                            match (p.get("name")) {
                                case Some(JsonValue.String(n)) => n
                                case _ => match (p.get("uri")) {
                                    case Some(JsonValue.String(u)) => u
                                    case _ => ""
                                }
                            }
                        case _ => ""
                    }
                    if (bodyName != "" && headerName != bodyName) {
                        ctx.responseBuilder.status(400).body("{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32020,\"message\":\"HeaderMismatch: Mcp-Name header '${headerName}' does not match body value '${bodyName}'\"}}")
                        return false
                    }
                }
                // MCP-Protocol-Version must match _meta.io.modelcontextprotocol/protocolVersion
                let headerVersion = ctx.request.headers.getFirst("MCP-Protocol-Version") ?? ""
                if (headerVersion != "") {
                    let bodyVersion = match (jv["params"]) {
                        case Some(JsonValue.Map(p)) => match (p.get("_meta")) {
                            case Some(JsonValue.Map(meta)) => match (meta.get("io.modelcontextprotocol/protocolVersion")) {
                                case Some(JsonValue.String(v)) => v
                                case _ => ""
                            }
                            case _ => ""
                        }
                        case _ => ""
                    }
                    if (bodyVersion != "" && headerVersion != bodyVersion) {
                        ctx.responseBuilder.status(400).body("{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32020,\"message\":\"HeaderMismatch: MCP-Protocol-Version header '${headerVersion}' does not match body version '${bodyVersion}'\"}}")
                        return false
                    }
                }
                true
            case None => true
        }
    }

    private func isAllowedOrigin(origin: String): Bool {
        origin == "http://127.0.0.1" || origin.startsWith("http://127.0.0.1:") ||
        origin == "http://localhost" || origin.startsWith("http://localhost:") ||
        origin == "https://studio.ai" || origin == "https://inspector.modelcontextprotocol.io"
    }

    public func send(data: Array<Byte>): Unit {
        let json = String.fromUtf8(data[0..data.size - 1])
        let jv = try { Option<JsonValue>.Some(JsonValue.parse(json)) } catch (_: Exception) { Option<JsonValue>.None }

        match (jv) {
            case Some(msg) =>
                let hasMethod = msg["method"].isSome()
                let hasId = msg["id"].isSome()

                if (hasMethod && !hasId) {
                    let methodStr = match (msg["method"]) {
                        case Some(JsonValue.String(m)) => m
                        case _ => ""
                    }
                    if (methodStr == "notifications/cancelled") { return }

                    // Progress notifications: route to matching request SSE stream
                    if (methodStr == "notifications/progress") {
                        let token = match (msg["params"]) {
                            case Some(JsonValue.Map(p)) => match (p.get("progressToken")) {
                                case Some(JsonValue.String(s)) => Option<String>.Some(s)
                                case Some(JsonValue.Number(n)) => Option<String>.Some(n.toString())
                                case _ => Option<String>.None
                            }
                            case _ => Option<String>.None
                        }
                        match (token) {
                            case Some(t) =>
                                let writers = synchronized(this.lock) {
                                    let list = ArrayList<HttpResponseWriter>()
                                    for (stream in this.requestStreams) {
                                        if (!stream.closed && stream.matchesToken(t)) {
                                            list.add(stream.writer)
    }
}
                                    list
                                }
                                for (w in writers) {
                                    w.write(("data: " + json + "\n\n").toArray())
                                }
                                return
                            case None => ()
                        }
                    }

                    let subWriters = ArrayList<HttpResponseWriter>()
                    let subPayloads = ArrayList<Array<Byte>>()
                    synchronized(this.lock) {
                        var i = 0
                        while (i < this.subscriptions.size) {
                            let sub = this.subscriptions[i]
                            if (sub.closed) {
                                this.subscriptions.remove(at: i)
                                continue
                            }
                            if (sub.filter.accepts(methodStr)) {
                                let bytes = this.injectSubscriptionId(msg, sub.id)
                                if (let Some(b) <- bytes) {
                                    subWriters.add(sub.writer)
                                    subPayloads.add(b)
                                }
                            }
                            i++
                        }
                    }
                    for (idx in 0..subWriters.size) {
                        subWriters[idx].write(("data: " + String.fromUtf8(subPayloads[idx]) + "\n\n").toArray())
                    }
                    return
                }

                if (hasId) {
                    let respId = match (msg["id"]) {
                        case Some(JsonValue.Number(n)) => n.toString()
                        case Some(JsonValue.String(s)) => s
                        case _ => ""
                    }
                    var found = false
                    var sseWriter: Option<HttpResponseWriter> = None
                    synchronized(this.lock) {
                        if (respId != "") {
                            var i = 0
                            while (i < this.requestStreams.size) {
                                let s = this.requestStreams[i]
                                if (s.requestId == respId && !s.closed) {
                                    sseWriter = Option.Some(s.writer)
                                    s.closed = true
                                    this.requestStreams.remove(at: i)
                                    found = true
                                    break
                                }
                                i++
    }
}

                        if (!found && this.waitingForResponse) {
                            this.pendingResponse = Some(json.toArray())
                            this.respCond.notifyAll()
                        }
                    }
                    if (let Some(w) <- sseWriter) {
                        w.write(("data: " + json + "\n\n").toArray())
                    }
                }
            case None => ()
        }
    }

    private func injectSubscriptionId(msg: JsonValue, subId: Int64): ?Array<Byte> {
        let subIdVal = JsonValue.Number(Float64(subId))
        let map = HashMap<String, JsonValue>()
        map.add("jsonrpc", JsonValue.String("2.0"))
        match (msg["method"]) {
            case Some(m) => map.add("method", m)
            case None => return None
        }
        match (msg["params"]) {
            case Some(JsonValue.Map(p)) =>
                let newParams = HashMap<String, JsonValue>(p)
                match (newParams.get("_meta")) {
                    case Some(JsonValue.Map(metaMap)) =>
                        let newMeta = HashMap<String, JsonValue>(metaMap)
                        newMeta.add("io.modelcontextprotocol/subscriptionId", subIdVal)
                        newParams.add("_meta", JsonValue.Map(newMeta))
                    case _ =>
                        let newMeta = HashMap<String, JsonValue>()
                        newMeta.add("io.modelcontextprotocol/subscriptionId", subIdVal)
                        newParams.add("_meta", JsonValue.Map(newMeta))
                }
                map.add("params", JsonValue.Map(newParams))
            case Some(v) =>
                let newParams = HashMap<String, JsonValue>()
                let newMeta = HashMap<String, JsonValue>()
                newMeta.add("io.modelcontextprotocol/subscriptionId", subIdVal)
                newParams.add("_meta", JsonValue.Map(newMeta))
                newParams.add("data", v)
                map.add("params", JsonValue.Map(newParams))
            case None =>
                let newParams = HashMap<String, JsonValue>()
                let newMeta = HashMap<String, JsonValue>()
                newMeta.add("io.modelcontextprotocol/subscriptionId", subIdVal)
                newParams.add("_meta", JsonValue.Map(newMeta))
                map.add("params", JsonValue.Map(newParams))
        }
        Some(JsonValue.Map(map).toBytes())
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

    public func close(): Unit {
        synchronized(this.lock) {
            this.closed = true
            this.recvCond.notifyAll()
            this.respCond.notifyAll()
            this.subCond.notifyAll()
        }
    }
}

type StatelessHttpServerTransport = StatelessHttpServer_2026_07_28
