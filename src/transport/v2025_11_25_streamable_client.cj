package mcp.transport

import ystyle::jsonrpc.*
import stdx.net.http.*
import std.io.InputStream
import std.collection.{ArrayList, HashMap}
import std.sync.{Mutex, Condition}
import stdx.log.NoopLogger

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
        this.client = ClientBuilder().logger(NoopLogger()).build()
        this.cond = synchronized(this.lock) { this.lock.condition() }
        for ((k, v) in headers) { this.customHeaders.add(k, v) }
        this.startNotifStream()
    }

    public init(endpointUrl: String) {
        this.endpointUrl = endpointUrl.trimEnd('/')
        this.client = ClientBuilder().logger(NoopLogger()).build()
        this.cond = synchronized(this.lock) { this.lock.condition() }
        this.startNotifStream()
    }

    private func startNotifStream(): Unit {
        try {
            let builder = HttpRequestBuilder()
                .url(this.endpointUrl)
                .header("Accept", "text/event-stream")
            // 通知流是 SSE 长连接：读超时必须不限。
            // 默认 15s 会让流在静默期被悄悄切断（服务端还在推、客户端收不到，
            // 且没有报错）。详见 stateless client 同名位置的注释。
            builder.readTimeout(Duration.Max)
            for ((k, v) in this.customHeaders) { builder.header(k, v) }
            let req = builder.get().build()
            let resp = this.client.send(req)
            spawn { => this.readNotifStream(resp.body) }
        } catch (e: Exception) {
            // 通知流启动失败不能静默：此后服务端通知全部收不到，
            // 而调用方只看到"通知一直不来"
            eprintln("[mcp] start notification stream failed: " + e.toString())
        } catch (e: Error) {
            eprintln("[mcp] start notification stream system error: " + e.toString())
        }
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
                            let result = frameLine(bytes)
                            synchronized(this.lock) {
                                this.responseQueue.add(result)
                                this.cond.notifyAll()
                            }
                        }
                    }
                }
            }
        } catch (e: Exception) {
            // 流为什么结束必须可见（正常 EOF / 网络错 / 解析错）
            eprintln("[mcp] notification stream closed: " + e.toString())
        } catch (e: Error) {
            eprintln("[mcp] notification stream system error: " + e.toString())
        }
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
            if (resp.status < 200 || resp.status >= 300) {
                if (!looksLikeJsonMessage(body)) {
                    // HTTP 层的失败原样投递只会变成一句 "Parse error"，把服务端
                    // 真正说的话（会话失效 / 鉴权失败 / 路径写错）盖掉
                    throw Exception(httpFailureText(resp.status, this.endpointUrl, body))
                }
            } else if (body.size == 0) {
                // 2xx 却是空体：规范里只该出现在 202（上面已返回）。喂给解析器同样
                // 只会得到 "Parse error"，原因（对端没按规范回）反而看不见
                eprintln("[mcp] empty body from ${this.endpointUrl} (status ${resp.status})")
                return
            }

            let result = frameLine(body)
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
                            // 只有 JSON 对象/数组才是协议消息（保活/空 data 行跳过）
                            if (!looksLikeJsonMessage(bytes)) { continue }
                            let result = frameLine(bytes)
                            synchronized(this.lock) {
                                this.responseQueue.add(result)
                                this.cond.notifyAll()
                            }
                        }
                    }
                }
            }
        } catch (e: Exception) {
            // SSE 主响应流为什么结束必须可见
            eprintln("[mcp] SSE stream closed: " + e.toString())
        } catch (e: Error) {
            eprintln("[mcp] SSE stream system error: " + e.toString())
        }
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

    // **返回值只有两种含义**：Some(数据) / None(真的关闭了)。超时不返回 None。
    //
    // 为什么必须严格：json-rpc 的接收循环把 None 当作对端关闭并 `shutdown()`，
    // 让接收线程永久退出。此前这里空等 30 秒后返回 None，于是**只要 30 秒
    // 没有消息就判定连接断掉**——普通请求踩不到（往返很快），但订阅场景
    // 天然有长时间静默，一建立就假死。详细分析见 stateless client 的同名方法。
    public func receive(): ?Array<Byte> {
        synchronized(this.lock) {
            while (this.responseQueue.size == 0 && !this.closed) {
                this.cond.wait()
            }
            if (this.responseQueue.size > 0) {
                Option<Array<Byte>>.Some(this.responseQueue.remove(at: 0))
            } else {
                Option<Array<Byte>>.None
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

public type SessionHttpClientTransport = StreamableHttpClient_2025_11_25

