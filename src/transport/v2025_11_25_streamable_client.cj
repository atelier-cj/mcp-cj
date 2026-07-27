package mcp.transport

import ystyle::jsonrpc.*
import stdx.net.http.*
import std.io.InputStream
import std.collection.{ArrayList, HashMap}
import std.sync.{Mutex, Condition}

public class StreamableHttpClient_2025_11_25 <: Transport {
    private let endpointUrl: String
    private let client: Client
    private let responseQueue = ArrayList<Array<Byte>>()
    private let lock = Mutex()
    private let cond: Condition
    private var sessionId: String = ""
    private var closed: Bool = false
    private let customHeaders = HashMap<String, String>()

    public init(endpointUrl: String, headers: HashMap<String, String>) {
        this.endpointUrl = endpointUrl.trimEnd('/')
        this.client = ClientBuilder().build()
        this.cond = synchronized(this.lock) { this.lock.condition() }
        for ((k, v) in headers) { this.customHeaders.add(k, v) }
        this.startNotifStream()
    }

    public init(endpointUrl: String) {
        this.endpointUrl = endpointUrl.trimEnd('/')
        this.client = ClientBuilder().build()
        this.cond = synchronized(this.lock) { this.lock.condition() }
        this.startNotifStream()
    }

    private func startNotifStream(): Unit {
        try {
            let builder = HttpRequestBuilder()
                .url(this.endpointUrl)
                .header("Accept", "text/event-stream")
            for ((k, v) in this.customHeaders) { builder.header(k, v) }
            let req = builder.get().build()
            let resp = this.client.send(req)
            spawn { => this.readNotifStream(resp.body) }
        } catch (_: Exception) { }
    }

    private func readNotifStream(body: InputStream): Unit {
        try {
            let buf = Array<Byte>(1, repeat: 0)
            let accumulated = ArrayList<Byte>()
            while (!this.closed) {
                let n: Int64
                try {
                    n = body.read(buf)
                } catch (_: Exception) { break }
                if (n <= 0) { break }
                accumulated.add(buf[0])
                let size = accumulated.size
                if (size >= 2 &&
                    accumulated[size - 2] == 10 &&
                    accumulated[size - 1] == 10) {
                    let raw = Array<Byte>(accumulated.size, repeat: 0)
                    for (i in 0..accumulated.size) { raw[i] = accumulated[i] }
                    let text = String.fromUtf8(raw)
                    let lines = text.split("\n")
                    accumulated.clear()
                    for (line in lines) {
                        if (line.startsWith("data: ")) {
                            let content = line[6..]
                            if (!content.startsWith("{") && !content.startsWith("[")) { continue }
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
            }
        } catch (_: Exception) { }
    }

    public func setCustomHeaders(headers: HashMap<String, String>): Unit {
        for ((k, v) in headers) { this.customHeaders.add(k, v) }
    }

    public func send(data: Array<Byte>): Unit {
        let json = String.fromUtf8(data[0..data.size - 1])
        let builder = HttpRequestBuilder()
            .url(this.endpointUrl)
            .header("content-type", "application/json")
            .header("accept", "application/json, text/event-stream")
            .header("MCP-Protocol-Version", "2025-11-25")
        for ((k, v) in this.customHeaders) { builder.header(k, v) }
        if (this.sessionId != "") {
            builder.header("Mcp-Session-Id", this.sessionId)
        }

        let req = builder.body(json).post().build()
        try {
            let resp = this.client.send(req)
            let contentType = resp.headers.getFirst("content-type") ?? ""

            if (let Some(sid) <- resp.headers.getFirst("Mcp-Session-Id")) {
                this.sessionId = sid
            }

            if (resp.status == 202) { return }

            if (contentType.startsWith("text/event-stream")) {
                spawn { => this.readSseStream(resp.body) }
                return
            }

            let body = this.readBody(resp.body)
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

    private func readSseStream(body: InputStream): Unit {
        try {
            let buf = Array<Byte>(1, repeat: 0)
            let accumulated = ArrayList<Byte>()
            while (!this.closed) {
                let n: Int64
                try {
                    n = body.read(buf)
                } catch (_: Exception) { break }
                if (n <= 0) { break }
                accumulated.add(buf[0])
                let size = accumulated.size
                if (size >= 2 &&
                    accumulated[size - 2] == 10 &&
                    accumulated[size - 1] == 10) {
                    let raw = Array<Byte>(accumulated.size, repeat: 0)
                    for (i in 0..accumulated.size) { raw[i] = accumulated[i] }
                    let text = String.fromUtf8(raw)
                    let lines = text.split("\n")
                    accumulated.clear()
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
            }
        } catch (_: Exception) { }
    }

    private func readBody(body: InputStream): Array<Byte> {
        let buf = Array<Byte>(4096, repeat: 0)
        let total = ArrayList<Byte>()
        while (true) {
            let n: Int64
            try {
                n = body.read(buf)
            } catch (_: Exception) { break }
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

type SessionHttpClientTransport = StreamableHttpClient_2025_11_25

