package mcp.transport

import ystyle::jsonrpc.*
import jsonvalue.*
import stdx.net.http.*
import std.collection.ArrayList
import std.sync.{Mutex, Condition}
import std.random.Random
import sonyflake.*

let sf = Sonyflake(Setting(Random().nextUInt16()))

public class SessionHttpServerTransport <: Transport {
    private let messageQueue = ArrayList<Array<Byte>>()
    private let lock = Mutex()
    private let recvCond: Condition
    private let sseCond: Condition
    private let respCond: Condition
    private var sseWriter: ?HttpResponseWriter = None
    private var pendingResponse: ?Array<Byte> = None
    private var waitingForResponse: Bool = false
    private var closed: Bool = false

    public init() {
        this.recvCond = synchronized(this.lock) { this.lock.condition() }
        this.sseCond = synchronized(this.lock) { this.lock.condition() }
        this.respCond = synchronized(this.lock) { this.lock.condition() }
    }

    public func registerRoutes(distributor: HttpRequestDistributor): Unit {
        distributor.register("/", { ctx =>
            if (ctx.request.method == "GET") {
                this.handleSSE(ctx)
            } else if (ctx.request.method == "POST") {
                this.handlePost(ctx)
            } else {
                ctx.responseBuilder.status(405).header("content-type", "text/plain").body("Method not allowed")
            }
        })
    }

    private func handleSSE(ctx: HttpContext): Unit {
        ctx.responseBuilder
            .status(200)
            .header("content-type", "text/event-stream")
            .header("cache-control", "no-cache")
            .header("connection", "keep-alive")
            .header("transfer-encoding", "chunked")

        let writer = HttpResponseWriter(ctx)
        let sid = sf.NextID().toString()

        synchronized(this.lock) {
            this.sseWriter = Some(writer)
        }

        writer.write(("event: session_id\ndata: " + sid + "\n\n").toArray())

        synchronized(this.lock) {
            while (!this.closed) {
                this.sseCond.wait()
            }
        }
    }

    private func handlePost(ctx: HttpContext): Unit {
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
        let jv = JsonValue.parse(bodyStr)
        let isNotification = match (jv["id"]) { case None => true case _ => false }

        let useSSE = match (ctx.request.url.query) {
            case Some(q) => q.contains("session_id")
            case None => false
        }

        if (useSSE) {
            synchronized(this.lock) {
                this.messageQueue.add(total.toArray())
                this.recvCond.notifyAll()
            }
            ctx.responseBuilder.status(200).header("content-type", "application/json").body("{\"ok\":true}")
        } else {
            synchronized(this.lock) {
                this.messageQueue.add(total.toArray())
                this.recvCond.notifyAll()
                if (!isNotification) {
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
            if (isNotification) {
                ctx.responseBuilder.status(202).body("")
            }
        }
    }

    public func send(data: Array<Byte>): Unit {
        let json = String.fromUtf8(data[0..data.size - 1])
        synchronized(this.lock) {
            if (this.waitingForResponse) {
                this.pendingResponse = Some(json.toArray())
                this.respCond.notifyAll()
            } else if (let Some(writer) <- this.sseWriter) {
                let event = "data: " + json + "\n\n"
                writer.write(event.toArray())
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
            this.sseCond.notifyAll()
            this.respCond.notifyAll()
        }
    }
}
