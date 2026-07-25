package mcp.transport

import ystyle::jsonrpc.*
import stdx.net.http.*
import std.io.InputStream
import std.collection.ArrayList
import std.sync.{Mutex, Condition}

public class StatelessHttpClientTransport <: Transport {
    private let endpointUrl: String
    private let client: Client
    private let responseQueue = ArrayList<Array<Byte>>()
    private let lock = Mutex()
    private let cond: Condition
    private var closed: Bool = false

    public init(endpointUrl: String) {
        this.endpointUrl = endpointUrl.trimEnd('/')
        this.client = ClientBuilder().build()
        this.cond = synchronized(this.lock) { this.lock.condition() }
    }

    public func send(data: Array<Byte>): Unit {
        let json = String.fromUtf8(data[0..data.size - 1])
        let req = HttpRequestBuilder()
            .url(this.endpointUrl + "/")
            .header("content-type", "application/json")
            .header("accept", "application/json, text/event-stream")
            .header("MCP-Protocol-Version", "2026-07-28")
            .body(json)
            .post()
            .build()
        try {
            let resp = this.client.send(req)
            let contentType = resp.headers.getFirst("content-type") ?? ""

            if (resp.status == 202) {
                return
            }

            let body = this.readBody(resp.body)

            if (contentType.startsWith("text/event-stream")) {
                this.handleSseResponse(body)
                return
            }

            let result = Array<Byte>(body.size + 1, repeat: 0)
            for (i in 0..body.size) { result[i] = body[i] }
            result[body.size] = 10
            synchronized(this.lock) {
                this.responseQueue.add(result)
                this.cond.notifyAll()
            }
        } catch (e: Exception) {
            if (!this.closed) { throw e }
        }
    }

    private func handleSseResponse(data: Array<Byte>): Unit {
        let text = String.fromUtf8(data)
        let lines = text.split("\n")
        for (line in lines) {
            if (line.startsWith("data: ")) {
                let content = line[6..]
                let bytes = content.toArray()
                let result = Array<Byte>(bytes.size + 1, repeat: 0)
                for (i in 0..bytes.size) { result[i] = bytes[i] }
                result[bytes.size] = 10
                synchronized(this.lock) {
                    this.responseQueue.add(result)
                    this.cond.notifyAll()
                }
            }
        }
    }

    private func readBody(body: InputStream): Array<Byte> {
        let buf = Array<Byte>(4096, repeat: 0)
        let total = ArrayList<Byte>()
        while (true) {
            let n: Int64
            try {
                n = body.read(buf)
            } catch (_: Exception) {
                break
            }
            if (n <= 0) { break }
            total.add(all: buf[0..n])
        }
        total.toArray()
    }

    public func receive(): ?Array<Byte> {
        synchronized(this.lock) {
            while (this.responseQueue.size == 0 && !this.closed) {
                this.cond.wait(timeout: 30 * Duration.second)
            }
            if (this.responseQueue.size > 0) {
                Some(this.responseQueue.remove(at: 0))
            } else {
                None
            }
        }
    }

    public func isClosed(): Bool {
        this.closed
    }

    public func close(): Unit {
        this.closed = true
        synchronized(this.lock) { this.cond.notifyAll() }
        this.client.close()
    }
}
