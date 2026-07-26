package mcp.transport

import ystyle::jsonrpc.*
import stdx.net.http.*
import std.io.InputStream
import std.collection.{ArrayList, HashMap}

public class SessionHttpClientTransport <: Transport {
    private let baseUrl: String
    private let client: Client
    private var sessionId: String = ""
    private let sseBody: InputStream
    private var closed: Bool = false
    private let customHeaders = HashMap<String, String>()

    public init(baseUrl: String, headers: HashMap<String, String>) {
        this.baseUrl = baseUrl.trimEnd('/')
        this.client = ClientBuilder().build()
        for ((k, v) in headers) { this.customHeaders.add(k, v) }
        let builder = HttpRequestBuilder()
            .url(this.baseUrl)
            .header("Accept", "text/event-stream")
        for ((k, v) in this.customHeaders) { builder.header(k, v) }
        let req = builder.get().build()
        let resp = this.client.send(req)
        this.sseBody = resp.body
        let id = this.readSessionId()
        if (let Some(sid) <- id) {
            this.sessionId = sid
        }
    }

    public init(baseUrl: String) {
        this.baseUrl = baseUrl.trimEnd('/')
        this.client = ClientBuilder().build()
        let sseResp = this.client.get(this.baseUrl)
        this.sseBody = sseResp.body
        let id = this.readSessionId()
        if (let Some(sid) <- id) {
            this.sessionId = sid
        }
    }

    public func setCustomHeaders(headers: HashMap<String, String>): Unit {
        for ((k, v) in headers) { this.customHeaders.add(k, v) }
    }

    private func readSessionId(): ?String {
        let buf = Array<Byte>(1, repeat: 0)
        let accumulated = ArrayList<Byte>()
        while (!this.closed) {
            let n: Int64
            try {
                n = this.sseBody.read(buf)
            } catch (_: Exception) {
                return None
            }
            if (n <= 0) { return None }
            accumulated.add(buf[0])
            if (accumulated.size >= 2 &&
                accumulated[accumulated.size - 2] == 10 &&
                accumulated[accumulated.size - 1] == 10) {
                break
            }
        }
        let raw = Array<Byte>(accumulated.size, repeat: 0)
        for (i in 0..accumulated.size) { raw[i] = accumulated[i] }
        let text = String.fromUtf8(raw)
        let lines = text.split("\n")
        for (line in lines) {
            if (line.startsWith("data: ")) {
                return Some(line[6..])
            }
            if (line.startsWith("event: session_id")) {
                continue
            }
        }
        None
    }

    public func send(data: Array<Byte>): Unit {
        let json = String.fromUtf8(data[0..data.size - 1])
        let url = this.baseUrl + "?session_id=" + this.sessionId
        let builder = HttpRequestBuilder()
            .url(url)
            .header("content-type", "application/json")
            .body(json)
            .post()
        for ((k, v) in this.customHeaders) { builder.header(k, v) }
        let req = builder.build()
        try {
            let resp = this.client.send(req)
            if (resp.status != 200) {
                throw Exception("POST failed: " + resp.status.toString())
            }
        } catch (e: Exception) {
            if (!this.closed) { throw e }
        }
    }

    public func receive(): ?Array<Byte> {
        let buf = Array<Byte>(1, repeat: 0)
        let accumulated = ArrayList<Byte>()
        while (!this.closed) {
            let n: Int64
            try {
                n = this.sseBody.read(buf)
            } catch (_: Exception) {
                return None
            }
            if (n <= 0) { return None }
            accumulated.add(buf[0])
            let size = accumulated.size
            if (size >= 2 &&
                accumulated[size - 2] == 10 &&
                accumulated[size - 1] == 10) {
                break
            }
        }
        let raw = Array<Byte>(accumulated.size, repeat: 0)
        for (i in 0..accumulated.size) { raw[i] = accumulated[i] }
        let text = String.fromUtf8(raw)
        let lines = text.split("\n")
        for (line in lines) {
            if (line.startsWith("data: ")) {
                let content = line[6..]
                let bytes = content.toArray()
                let result = Array<Byte>(bytes.size + 1, repeat: 0)
                for (i in 0..bytes.size) { result[i] = bytes[i] }
                result[bytes.size] = 10
                return Some(result)
            }
        }
        None
    }

    public func isClosed(): Bool {
        this.closed
    }

    public func close(): Unit {
        this.closed = true
        this.client.close()
    }
}
