package mcp.transport

import ystyle::jsonrpc.*
import stdx.net.http.*
import std.collection.*
import std.sync.*
import std.random.Random
import sonyflake.*

let sonyflake = Sonyflake(Setting(Random().nextUInt16()))

public class HttpSseServer_2024_11_05 <: Transport {
    private let messageQueue = ArrayList<Array<Byte>>()
    private let lock = Mutex()
    private let recvCond: Condition
    private let sseCond: Condition
    private var sseWriter: ?HttpResponseWriter = None
    private var sessionId: String = ""
    private var closed: Bool = false

    public init() {
        this.recvCond = synchronized(this.lock) { this.lock.condition() }
        this.sseCond = synchronized(this.lock) { this.lock.condition() }
    }

    public func registerRoutes(distributor: HttpRequestDistributor): Unit {
        distributor.register("/sse", { ctx => this.handleSSE(ctx) })
        distributor.register("/message", { ctx => this.handleMessage(ctx) })
    }

    private func handleSSE(ctx: HttpContext): Unit {
        if (ctx.request.method != "GET") {
            ctx.responseBuilder.status(405).header("content-type", "text/plain").body("Method not allowed")
            return
        }

        ctx.responseBuilder
            .status(200)
            .header("content-type", "text/event-stream")
            .header("cache-control", "no-cache")
            .header("connection", "keep-alive")
            .header("transfer-encoding", "chunked")

        let writer = HttpResponseWriter(ctx)
        let sid = sonyflake.NextID().toString()

        synchronized(this.lock) {
            this.sessionId = sid
            this.sseWriter = Some(writer)
        }

        writer.write(("event: session_id\ndata: " + sid + "\n\n").toArray())

        synchronized(this.lock) {
            while (!this.closed) {
                this.sseCond.wait()
            }
        }
    }

    private func handleMessage(ctx: HttpContext): Unit {
        if (ctx.request.method != "POST") {
            ctx.responseBuilder.status(405).header("content-type", "text/plain").body("Method not allowed")
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
            ctx.responseBuilder.status(400).body("Empty body")
            ctx.responseBuilder.header("content-type", "text/plain")
            return
        }

        let bytes = total.toArray()

        synchronized(this.lock) {
            this.messageQueue.add(bytes)
            this.recvCond.notifyAll()
        }

        ctx.responseBuilder.status(200).header("content-type", "application/json").body("{\"ok\":true}")
    }

    public func send(data: Array<Byte>): Unit {
        let json = String.fromUtf8(data[0..data.size - 1])
        let event = "data: " + json + "\n\n"
        synchronized(this.lock) {
            if (let Some(writer) <- this.sseWriter) {
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
        }
    }
}
