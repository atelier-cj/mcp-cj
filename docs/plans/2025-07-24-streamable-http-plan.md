# Streamable HTTP Transport 实施计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为 mcp-cj 添加 Streamable HTTP Transport（Server + Client）

**架构:** 两个 `Transport` 实现（Server/Client）通过 `HttpRequestDistributor` 注册路由，使用 `stdx.net.http` 做 HTTP/SSE 通信，`sonyflake` 做 session ID，配合 `NewlineFraming`。

**Tech Stack:** Cangjie 1.1, stdx.net.http, jsonvalue, ystyle::jsonrpc (NewlineFraming), sonyflake

---

### Task 1: StreamableHttpServerTransport

**Files:**
- Create: `src/transport/streamable_http_server.cj`
- Test: `src/examples/testclient/main.cj`（后续集成测试）

**Step 1: Write the file**

```cangjie
package mcp.transport

import ystyle::jsonrpc.*
import stdx.net.http.*
import std.collection.*
import std.sync.*
import std.random.Random
import sonyflake.*

let sonyflake = Sonyflake(Setting(Random().nextUInt16()))

public class StreamableHttpServerTransport <: Transport {
    private let messageQueue = ArrayList<Array<Byte>>()
    private let lock = Mutex()
    private let cond: Condition
    private var sseWriter: ?HttpResponseWriter = None
    private var sessionId: String = ""
    private var closed: Bool = false

    public init() {
        this.cond = synchronized(this.lock) { this.lock.condition() }
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

        let writer = HttpResponseWriter(ctx)
        this.sessionId = sonyflake.NextID().toString()

        synchronized(this.lock) {
            this.sseWriter = Some(writer)
        }

        writer.write(("event: session_id\ndata: " + this.sessionId + "\n\n").toArray())

        while (true) {
            sleep(1 * Duration.second)
            if (this.closed) { break }
        }
    }

    private func handleMessage(ctx: HttpContext): Unit {
        if (ctx.request.method != "POST") {
            ctx.responseBuilder.status(405).header("content-type", "text/plain").body("Method not allowed")
            return
        }

        let url = ctx.request.url
        let clientSessionId = url.queryForm.get("session_id")

        let buf = Array<Byte>(4096, repeat: 0)
        let total = ArrayList<Byte>()
        while (let len = ctx.request.body.read(buf)) {
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
            this.cond.notifyAll()
        }

        ctx.responseBuilder.status(200)
            .header("content-type", "application/json")
            .body("{\"ok\":true}")
    }

    public func send(data: Array<Byte>): Unit {
        let jsonStr = String.fromUtf8(data[0..data.size - 1])
        let event = "data: " + jsonStr + "\n\n"
        synchronized(this.lock) {
            if (let Some(writer) <- this.sseWriter) {
                writer.write(event.toArray())
            }
        }
    }

    public func receive(): ?Array<Byte> {
        synchronized(this.lock) {
            while (this.messageQueue.size == 0 && !this.closed) {
                this.cond.wait(timeout: 30 * Duration.second)
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
            this.cond.notifyAll()
        }
    }
}
```

**Step 2: Build and verify compilation**

Run: `cjpm build`
Expected: COMPILE SUCCESS

**Step 3: Commit**

```bash
git add src/transport/streamable_http_server.cj
git commit -m "feat(transport): add StreamableHttpServerTransport"
```

---

### Task 2: StreamableHttpClientTransport

**Files:**
- Create: `src/transport/streamable_http_client.cj`

**Step 1: Write the file**

```cangjie
package mcp.transport

import ystyle::jsonrpc.*
import stdx.net.http.*
import std.sync.*

public class StreamableHttpClientTransport <: Transport {
    private let baseUrl: String
    private let client: Client
    private var sessionId: String = ""
    private let sseBody: InputStream
    private var closed: Bool = false
    private var sseClosed: Bool = false

    public init(baseUrl: String) {
        this.baseUrl = baseUrl.trimEnd('/')
        this.client = ClientBuilder().build()

        let sseResp = this.client.get(this.baseUrl + "/sse")
        this.sseBody = sseResp.body

        let id = this.readSessionId()
        if (let Some(sid) <- id) {
            this.sessionId = sid
        }
    }

    private func readSessionId(): ?String {
        let buf = Array<Byte>(32768, repeat: 0)
        let accumulated = StringBuilder()
        while (true) {
            let n = this.sseBody.read(buf)
            if (n <= 0) { return None }
            let chunk = String.fromUtf8(buf[0..n])
            accumulated.append(chunk)
            let text = accumulated.toString()
            if (let Some(idx) <- text.indexOf("event: session_id")) {
                let afterEvent = text[idx..]
                if (let Some(dl) <- afterEvent.indexOf("\ndata: ")) {
                    let dataStart = dl + 7
                    if (let Some(nl) <- afterEvent.indexOf("\n\n", dataStart)) {
                        return Some(afterEvent[dataStart..nl])
                    }
                }
            }
        }
    }

    public func send(data: Array<Byte>): Unit {
        let jsonStr = String.fromUtf8(data[0..data.size - 1])
        let url = this.baseUrl + "/message?session_id=" + this.sessionId
        let req = HttpRequestBuilder()
            .url(url)
            .header("content-type", "application/json")
            .body(jsonStr)
            .post()
            .build()
        let resp = this.client.send(req)
        if (resp.status != 200) {
            throw Exception("POST failed: " + resp.status.toString())
        }
    }

    public func receive(): ?Array<Byte> {
        let buf = Array<Byte>(1, repeat: 0)
        let accumulated = StringBuilder()
        while (!this.closed && !this.sseClosed) {
            let n = this.sseBody.read(buf)
            if (n <= 0) {
                this.sseClosed = true
                return None
            }
            accumulated.append(Rune(buf[0]))
            let text = accumulated.toString()
            if (text.endsWith("\n\n")) {
                let lines = text.split("\n")
                for (line in lines) {
                    if (line.startsWith("data: ")) {
                        let jsonStr = line[6..]
                        let bytes = jsonStr.toArray()
                        let result = Array<Byte>(bytes.size + 1, repeat: 0)
                        for (i in 0..bytes.size) { result[i] = bytes[i] }
                        result[bytes.size] = 10
                        return Some(result)
                    }
                }
                accumulated.clear()
            }
        }
        None
    }

    public func isClosed(): Bool {
        this.closed || this.sseClosed
    }

    public func close(): Unit {
        this.closed = true
        this.client.close()
    }
}
```

**Step 2: Build and verify compilation**

Run: `cjpm build`
Expected: COMPILE SUCCESS

**Step 3: Commit**

```bash
git add src/transport/streamable_http_client.cj
git commit -m "feat(transport): add StreamableHttpClientTransport"
```

---

### Task 3: Integration test

**Files:**
- Create: `src/examples/http_server/main.cj`

**Step 1: Write the server example**

```cangjie
package mcp.examples.http_server

import jsonvalue.*
import mcp.*
import mcp.transport.*
import std.collection.{HashMap, ArrayList}
import stdx.net.http.*

main() {
    let distributor = DirectDistributor()

    let transport = StreamableHttpServerTransport()
    transport.registerRoutes(distributor)

    let server = McpServer("streamable-http-server", "1.0.0", transport)

    let toolschema = ToolInputSchema("object", HashMap<String, JsonValue>(), [])
    toolschema.addField("name", "string", "Name of the person to greet", required: true)

    let tool = Tool("hello", "Say hello", toolschema)
    server.addTool(tool, { params =>
        let name = match (params.arguments.get("name")) {
            case Some(JsonValue.String(n)) => n
            case _ => "World"
        }
        CallToolResult.text("Hello, ${name}!")
    })

    server.start()

    let httpServer = ServerBuilder()
        .addr("127.0.0.1:8080")
        .distributor(distributor)
        .build()
    println("Server listening on http://127.0.0.1:8080")
    httpServer.serve()
}
```

**Step 2: Add package config to cjpm.toml**

```
[package.package-configuration."mcp.examples.http_server"]
output-type = "executable"
compile-option = "--static"
```

**Step 3: Build**

Run: `cjpm build`
Expected: COMPILE SUCCESS

**Step 4: Commit**

```bash
git add src/examples/http_server/main.cj cjpm.toml
git commit -m "feat(examples): add Streamable HTTP server example"
```

---

### Task 4: Update root.cj

**Files:**
- Modify: `src/root.cj`

**Step 1: Add public import**

Add `public import mcp.transport.streamable_http_server.*` and `public import mcp.transport.streamable_http_client.*`

**Step 2: Commit**

```bash
git add src/root.cj
git commit -m "fix: add Streamable HTTP transports to public exports"
```
