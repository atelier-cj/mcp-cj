package mcp.transport

import ystyle::jsonrpc.*
import jsonvalue.*
import stdx.net.http.*
import stdx.encoding.base64.toBase64String
import std.io.InputStream
import std.collection.{ArrayList, HashMap}
import std.sync.{Mutex, Condition}
import stdx_log.NoopLogger

public class StatelessHttpClient_2026_07_28 <: Transport {
    private let endpointUrl: String
    private let client: Client
    private let responseQueue = ArrayList<Array<Byte>>()
    private let lock = Mutex()
    private let cond: Condition
    private var closed: Bool = false
    private let toolParamHeaders = HashMap<String, HashMap<String, String>>()
    private let customHeaders = HashMap<String, String>()

    public init(endpointUrl: String) {
        this.endpointUrl = endpointUrl.trimEnd('/')
        this.client = ClientBuilder().logger(NoopLogger()).build()
        this.cond = synchronized(this.lock) { this.lock.condition() }
    }

    public func setCustomHeaders(headers: HashMap<String, String>): Unit {
        for ((k, v) in headers) { this.customHeaders.add(k, v) }
    }

    public func setToolParamHeaders(toolName: String, mappings: HashMap<String, String>): Unit {
        this.toolParamHeaders.add(toolName, mappings)
    }

    public func send(data: Array<Byte>): Unit {
        let json = String.fromUtf8(data[0..data.size - 1])
        let builder = HttpRequestBuilder()
            .url(this.endpointUrl)
            .header("content-type", "application/json")
            .header("accept", "application/json, text/event-stream")
            .header("MCP-Protocol-Version", "2026-07-28")
        for ((k, v) in this.customHeaders) { builder.header(k, v) }

        // Auto-attach Mcp-Method and Mcp-Name headers, plus x-mcp-header params
        let jv = try { Option<JsonValue>.Some(JsonValue.parse(json)) } catch (_: Exception) { Option<JsonValue>.None }
        match (jv) {
            case Some(v) =>
                let methodStr = match (v["method"]) {
                    case Some(JsonValue.String(m)) => m
                    case _ => ""
                }
                if (methodStr != "") { builder.header("Mcp-Method", methodStr) }

                match (v["params"]) {
                    case Some(JsonValue.Map(p)) =>
                        let nameVal = match (p.get("name")) {
                            case Some(JsonValue.String(n)) => n
                            case _ => match (p.get("uri")) {
                                case Some(JsonValue.String(u)) => u
                                case _ => ""
                            }
                        }
                        if (nameVal != "") { builder.header("Mcp-Name", nameVal) }

                        // x-mcp-header: map params to Mcp-Param-{Name} headers
                        if (methodStr == "tools/call" && nameVal != "") {
                            let mappings = this.toolParamHeaders.get(nameVal)
                            if (let Some(m) <- mappings) {
                                match (p.get("arguments")) {
                                    case Some(JsonValue.Map(args)) =>
                                        for ((argName, argVal) in m) {
                                            match (args.get(argName)) {
                                                case Some(v) =>
                                                    let headerVal = this.encodeParamValue(v)
                                                    builder.header("Mcp-Param-${argVal}", headerVal)
                                                case None => ()
                                            }
                                        }
                                    case _ => ()
                                }
                            }
                        }
                    case _ => ()
                }
            case None => ()
        }

        let req = builder.body(json).post().build()
        try {
            let resp = this.client.send(req)
            let contentType = resp.headers.getFirst("content-type") ?? ""

            if (resp.status == 202) { return }

            if (contentType.startsWith("text/event-stream")) {
                // SSE response — read in background
                spawn { => this.readSseStream(resp.body) }
                return
            }

            // JSON response
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

    private func encodeParamValue(v: JsonValue): String {
        let raw = match (v) {
            case JsonValue.String(s) => s
            case JsonValue.Number(n) => n.toString()
            case JsonValue.Boolean(b) => if (b) { "true" } else { "false" }
            case JsonValue.Null => "null"
            case _ => ""
        }
        if (this.needsBase64Encoding(raw)) {
            let utf8 = raw.toArray()
            let b64 = toBase64String(utf8)
            return "=?base64?${b64}?="
        }
        raw
    }

    private func needsBase64Encoding(s: String): Bool {
        // Empty or starts/ends with sentinel pattern
        if (s == "") { return false }
        if (s.startsWith("=?base64?") && s.endsWith("?=")) { return true }
        // Leading or trailing whitespace
        if (s != s.trimStart() || s != s.trimEnd()) { return true }
        // Check for non-ASCII or control characters
        for (c in s.toRuneArray()) {
            let val = UInt32(c)
            if (val < 32 || val > 126) { return true }
        }
        false
    }

    private func readSseStream(body: InputStream): Unit {
        try {
            let buf = Array<Byte>(1, repeat: 0)
            let accumulated = ArrayList<Byte>()
            while (!this.closed) {
                let n: Int64
                try {
                    n = body.read(buf)
                } catch (_: Exception) {
                    break
                }
                if (n <= 0) { break }
                accumulated.add(buf[0])
                let size = accumulated.size
                if (size >= 2 &&
                    accumulated[size - 2] == 10 &&
                    accumulated[size - 1] == 10) {
                    // Complete SSE event — parse data: lines
                    let raw = Array<Byte>(accumulated.size, repeat: 0)
                    for (i in 0..accumulated.size) { raw[i] = accumulated[i] }
                    let text = String.fromUtf8(raw)
                    let lines = text.split("\n")
                    accumulated.clear()

                    // Skip comment lines (starting with ':') and empty lines
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
                        // Comment lines (starting with ':') are keep-alive, skip
                    }
                }
            }
        } catch (e: Exception) {
            // 流为什么结束必须可见（正常 EOF / 网络错 / 解析错区分开），
            // 否则"收不到响应"无从排查
            eprintln("[mcp] stateless SSE stream closed: " + e.toString())
        } catch (e: Error) {
            eprintln("[mcp] stateless SSE stream system error: " + e.toString())
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

public type StatelessHttpClientTransport = StatelessHttpClient_2026_07_28

