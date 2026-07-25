package mcp.transport

import ystyle::jsonrpc.*
import jsonvalue.*
import stdx.net.http.*
import std.collection.ArrayList
import std.sync.{Mutex, Condition}

public class StatelessHttpServerTransport <: Transport {
    private let messageQueue = ArrayList<Array<Byte>>()
    private let lock = Mutex()
    private let recvCond: Condition
    private let respCond: Condition
    private var pendingResponse: ?Array<Byte> = None
    private var waitingForResponse: Bool = false
    private var closed: Bool = false

    public init() {
        this.recvCond = synchronized(this.lock) { this.lock.condition() }
        this.respCond = synchronized(this.lock) { this.lock.condition() }
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
        if (!this.validateRequest(ctx)) { return }

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
        let hasId = try {
            let jv = JsonValue.parse(bodyStr)
            jv["id"].isSome()
        } catch (_: Exception) { false }

        if (!hasId) {
            synchronized(this.lock) {
                this.messageQueue.add(total.toArray())
                this.recvCond.notifyAll()
            }
            ctx.responseBuilder.status(202).body("")
            return
        }

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
                let respStr = String.fromUtf8(response)
                ctx.responseBuilder.status(200)
                    .header("content-type", "application/json")
                    .body(respStr)
            } else {
                this.waitingForResponse = false
                ctx.responseBuilder.status(504).body("{\"error\":\"timeout\"}")
            }
        }
    }

    private func validateRequest(ctx: HttpContext): Bool {
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

        true
    }

    private func isAllowedOrigin(origin: String): Bool {
        origin == "http://127.0.0.1" || origin.startsWith("http://127.0.0.1:") ||
        origin == "http://localhost" || origin.startsWith("http://localhost:") ||
        origin == "https://studio.ai" || origin == "https://inspector.modelcontextprotocol.io"
    }

    public func send(data: Array<Byte>): Unit {
        let json = String.fromUtf8(data[0..data.size - 1])
        synchronized(this.lock) {
            if (this.waitingForResponse) {
                this.pendingResponse = Some(json.toArray())
                this.respCond.notifyAll()
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

    public func close(): Unit {
        synchronized(this.lock) {
            this.closed = true
            this.recvCond.notifyAll()
            this.respCond.notifyAll()
        }
    }
}
