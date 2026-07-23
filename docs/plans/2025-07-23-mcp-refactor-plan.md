# mcp-cj 重构实施计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将 mcp-cj 重构为基于 jsonvalue + json-rpc 库的分层架构，并更新 MCP 协议至 2025-11-25

**架构:**
- mcp 核心层（MCP 协议类型 + McpServer）依赖 ystyle::jsonrpc（JSON-RPC 2.0 框架）
- ystyle::jsonrpc 依赖 jsonvalue（通用 JSON Value 类型）
- jsonvalue 依赖 stdx.encoding.json.stream

**Tech Stack:** Cangjie 1.1.0+, stdx, jsonvalue, ystyle::jsonrpc

---

### Task 1: 更新 cjpm.toml 依赖配置

**Files:**
- Modify: `cjpm.toml`

**Step 1: 修改 cjpm.toml**

更新 cjc-version 和添加依赖：

```toml
[dependencies]
  jsonvalue = { path = "../jsonvalue" }
  jsonrpc = { path = "../json-rpc/jsonrpc" }
  sonyflake = { git = "https://github.com/ystyle/cj-sonyflake", branch = "master"}

[package]
  cjc-version = "1.1.0"
  compile-option = "-Woff unused"
  description = "MCP (Model Context Protocol) 服务端框架"
  link-option = ""
  name = "mcp"
  output-type = "static"
  override-compile-option = ""
  src-dir = ""
  target-dir = ""
  version = "2.0.0"

# [package.package-configuration."mcp.examples"]
# output-type = "executable"

[target.x86_64-unknown-linux-gnu.bin-dependencies]
path-option = [ "${CANGJIE_STDX_PATH}" ]

[target.x86_64-w64-mingw32.bin-dependencies]
path-option = [ "${CANGJIE_STDX_PATH}" ]

[target.aarch64-linux-ohos.bin-dependencies]
  path-option = ["${CANGJIE_STDX_PATH}"]
[target.x86_64-linux-ohos.bin-dependencies]
  path-option = ["${CANGJIE_STDX_PATH}"]
```

**Step 2: 运行 cjpm build 验证依赖解析**

Run: `cd /home/ystyle/Projects/Cangjie/mcp-cj && export CANGJIE_STDX_PATH=/home/ystyle/.config/cjvs/stdx/1.1.0-alpha.60306/linux_x86_64_cjnative/static/stdx && cjpm build`
Expected: 编译成功或至少依赖解析成功

**Step 3: Commit**

```bash
git add cjpm.toml
git commit -m "build: update dependencies to use jsonvalue and json-rpc"
```

---

### Task 2: 删除废弃文件

**Files:**
- Delete: `src/types/fast_value.cj`
- Delete: `src/types/jsonrpc_message.cj`
- Delete: `src/types/request.cj`
- Delete: `src/types/response.cj`
- Delete: `src/types/value.cj`
- Delete: `src/types/utils.cj`
- Delete: `src/types/notification.cj`
- Delete: `src/utils/json_parser.cj`

**Step 1: 删除文件**

Run: 
```bash
git rm src/types/fast_value.cj src/types/jsonrpc_message.cj src/types/request.cj
git rm src/types/response.cj src/types/value.cj src/types/utils.cj
git rm src/types/notification.cj src/utils/json_parser.cj
```

**Step 2: 清理 server 中对废弃文件的引用**

删除 `src/server/server.cj` 中：
- `import mcp.types.Error as McpError` — 改为用 json-rpc 的 JsonRpcError
- `import mcp.utils.JsonParserUtil` — 改用 jsonvalue

**Step 3: Commit**

```bash
git commit -m "refactor: remove deprecated files replaced by jsonvalue and json-rpc"
```

---

### Task 3: 重写 types/types.cj — MCP 协议核心类型

**Files:**
- Rewrite: `src/types/types.cj`

**Step 1: 编写新的 types.cj**

核心类型：

```cangjie
package mcp.types

import jsonvalue.*
import stdx.encoding.json.stream.*

// 协议版本
public const LastProtocolVersion = "2025-11-25"

// 错误码
public const PARSE_ERROR = -32700
public const INVALID_REQUEST = -32600
public const METHOD_NOT_FOUND = -32601
public const INVALID_PARAMS = -32602
public const INTERNAL_ERROR = -32603

// Implementation — 不变
public class Implementation <: JsonSerializable & JsonDeserializable<Implementation> {
    var name: String = ""
    var version: String = ""
    public init(name: String, version: String) { ... }
    ...
}

// ServerCapabilities — 扩展新字段
public class ServerCapabilities <: JsonSerializable & JsonDeserializable<ServerCapabilities> {
    public var resources: Option<ResourceCapabilities> = None
    public var prompts: Option<PromptCapabilities> = None
    public var tools: Option<ToolsCapabilities> = None
    public var logging: ?JsonValue = None
    public var tasks: ?JsonValue = None
    public var experimental: ?JsonValue = None
    ...
}

// ResourceCapabilities — 简化，直接序列化字段
public class ResourceCapabilities <: JsonSerializable & JsonDeserializable<ResourceCapabilities> {
    public var subscribe: Bool = false
    public var listChanged: Bool = false
    ...
}

// PromptCapabilities / ToolsCapabilities — 同上
// InitializeResult — 新增 _meta 和 protocolVersion
public class InitializeResult {
    public let protocolVersion: String = LastProtocolVersion
    public var capabilities = ServerCapabilities()
    public var serverInfo = Implementation()
    public var instructions: ?String = None
    ...
}
```

**Step 2: 编译验证**

Run: `cjpm build`
Expected: 编译成功

**Step 3: Commit**

```bash
git add src/types/types.cj
git commit -m "refactor(types): rewrite core types for 2025-11-25 protocol"
```

---

### Task 4: 重写 types/tools.cj — 工具相关类型

**Files:**
- Rewrite: `src/types/tools.cj`

**Step 1: 编写新的 tools.cj**

保留 Tool 核心功能，删除冗余的工具构造 DSL（withString/withNumber 等）：

```cangjie
package mcp.types

import jsonvalue.*
import std.collection.{HashMap, ArrayList}
import stdx.encoding.json.stream.*

// Tool — 新增 ToolAnnotations 字段
public class Tool <: JsonSerializable & JsonDeserializable<Tool> {
    public var name: String = ""
    public var description: String = ""
    public var inputSchema = ToolInputSchema()
    public var annotations: ?ToolAnnotations = None
    ...
}

// ToolInputSchema
public class ToolInputSchema <: JsonSerializable & JsonDeserializable<ToolInputSchema> {
    public var typ: String = "object"
    public var properties = HashMap<String, JsonValue>()
    public var required = ArrayList<String>()
    ...
}

// ToolAnnotations — 新增 2025-11-25
public class ToolAnnotations <: JsonSerializable & JsonDeserializable<ToolAnnotations> {
    public var title: ?String = None
    public var destructiveHint: ?Bool = None
    public var idempotentHint: ?Bool = None
    public var openWorldHint: ?Bool = None
    public var readOnlyHint: ?Bool = None
    ...
}

// CallToolResult — content 改为 ContentBlock 数组
public class CallToolResult <: JsonSerializable & JsonDeserializable<CallToolResult> {
    public var content = ArrayList<ContentBlock>()
    public var isError: Bool = false
    ...
}

// CallToolRequestParams
public class ToolRequestParams <: JsonSerializable & JsonDeserializable<ToolRequestParams> {
    public var name: String = ""
    public var arguments = HashMap<String, JsonValue>()
    ...
}
```

**Step 2: 编译验证**

Run: `cjpm build`
Expected: 编译成功

**Step 3: Commit**

```bash
git add src/types/tools.cj
git commit -m "refactor(tools): add ToolAnnotations, use ContentBlock, simplify API"
```

---

### Task 5: 创建 types/content.cj — 统一内容类型

**Files:**
- Create: `src/types/content.cj`

**Step 1: 创建 content.cj**

```cangjie
package mcp.types

import jsonvalue.*
import std.collection.HashMap
import stdx.encoding.json.stream.*

// ContentBlock — 统一内容类型
public enum ContentBlock <: JsonSerializable & JsonDeserializable<ContentBlock> {
    | Text(TextContent)
    | Image(ImageContent)
    | Audio(AudioContent)
    | Embedded(EmbeddedResource)

    public func toJson(w: JsonWriter): Unit { ... }
    public static func fromJson(r: JsonReader): ContentBlock { ... }
}

public class TextContent <: JsonSerializable & JsonDeserializable<TextContent> {
    public var text: String = ""
    public var annotations: ?JsonValue = None
    ...
}

public class ImageContent <: JsonSerializable & JsonDeserializable<ImageContent> {
    public var data: String = ""
    public var mimeType: String = ""
    public var annotations: ?JsonValue = None
    ...
}

public class AudioContent <: JsonSerializable & JsonDeserializable<AudioContent> {
    public var data: String = ""
    public var mimeType: String = ""
    ...
}

public class EmbeddedResource <: JsonSerializable & JsonDeserializable<EmbeddedResource> {
    public var resource: ResourceContents
    ...
}
```

**Step 2: 编译验证**

Run: `cjpm build`
Expected: 编译成功

**Step 3: Commit**

```bash
git add src/types/content.cj
git commit -m "feat(types): add ContentBlock types for 2025-11-25 protocol"
```

---

### Task 6: 重写 src/server.cj — McpServer

**Files:**
- Rewrite: `src/server/server.cj` → `src/server.cj`（移到根目录）

**Step 1: 创建新的 server.cj**

基于 ystyle::jsonrpc 的 JsonRpcServer：

```cangjie
package mcp

import jsonvalue.*
import ystyle::jsonrpc.*
import std.collection.*
import std.sync.*
import mcp.types.*

public type ToolHandlerFunc = (ToolRequestParams) -> CallToolResult

public class McpServer {
    private let rpcServer: JsonRpcServer
    private let tools = HashMap<String, ToolHandlerFunc>()
    private let toolDefs = HashMap<String, Tool>()
    public var capabilities = ServerCapabilities()
    public var instructions: ?String = None
    public let name: String
    public let version: String
    
    public init(name: String, version: String, transport: Transport) {
        this.name = name
        this.version = version
        this.rpcServer = JsonRpcServer(transport)
        this.registerHandlers()
    }
    
    private func registerHandlers() {
        rpcServer.register("initialize", { ctx => this.handleInitialize(ctx) })
        rpcServer.register("ping", { ctx => HandlerResult.ok(EmptyResult()) })
        rpcServer.register("tools/list", { ctx => this.handleListTools(ctx) })
        rpcServer.register("tools/call", { ctx => this.handleCallTool(ctx) })
    }
    
    public func addTool(tool: Tool, handler: ToolHandlerFunc) {
        if (this.capabilities.tools.isNone()) {
            this.capabilities.tools = ToolsCapabilities(true)
        }
        this.toolDefs[tool.name] = tool
        this.tools[tool.name] = handler
    }
    
    public func start() { this.rpcServer.start() }
    public func close() { this.rpcServer.close() }
    
    private func handleInitialize(ctx: HandlerContext): HandlerResult {
        let result = InitializeResult()
        result.serverInfo = Implementation(this.name, this.version)
        result.capabilities = this.capabilities
        result.instructions = this.instructions
        HandlerResult.ok(JsonValue.fromObject(result))
    }
    
    private func handleListTools(ctx: HandlerContext): HandlerResult {
        let result = ListToolsResult()
        result.tools = ArrayList<Tool>(this.toolDefs.values())
        HandlerResult.ok(JsonValue.fromObject(result))
    }
    
    private func handleCallTool(ctx: HandlerContext): HandlerResult {
        let params = ctx.getParams<ToolRequestParams>()
        let name = params?.name ?? ""
        if (let Some(handler) <- this.tools.get(name)) {
            try {
                let result = handler(params ?? ToolRequestParams())
                return HandlerResult.ok(JsonValue.fromObject(result))
            } catch (e: Exception) {
                return HandlerResult.err(INTERNAL_ERROR, "Tool call failed: ${e.message}")
            }
        }
        HandlerResult.err(METHOD_NOT_FOUND, "Tool not found: ${name}")
    }
}
```

**Step 2: 编译验证**

Run: `cjpm build`
Expected: 编译成功

**Step 3: Commit**

```bash
git add src/server.cj
git rm src/server/server.cj src/server/stdio.cj src/server/stdio_test.cj
git commit -m "refactor(server): rewrite McpServer based on json-rpc JsonRpcServer"
```

---

### Task 7: 创建 transport/stdio.cj — Stdio 传输层

**Files:**
- Create: `src/transport/stdio.cj`

**Step 1: 创建 StdioServerTransport**

实现 ystyle::jsonrpc 的 Transport 接口：

```cangjie
package mcp.transport

import ystyle::jsonrpc.*
import jsonvalue.*
import std.env.{getStdIn, getStdOut}
import std.io.ByteBuffer
import stdx.encoding.json.stream.*

public class StdioServerTransport <: Transport {
    private var running = AtomicBool(false)
    
    public func send(data: Array<Byte>): Unit {
        let stdout = getStdOut()
        // 写入长度前缀 + JSON 数据
        stdout.writeln(String.fromUtf8(data))
        stdout.flush()
    }
    
    public func receive(): ?Array<Byte> {
        let stdin = getStdIn()
        if (let Some(line) <- stdin.readln()) {
            Some(line.toArray())
        } else {
            None
        }
    }
    
    public func isClosed(): Bool { !this.running.load() }
    public func close(): Unit { this.running.store(false) }
}

// 便捷函数
public func ServeStdio(server: McpServer) {
    server.start()
}
```

**Step 2: 编译验证**

Run: `cjpm build`
Expected: 编译成功

**Step 3: Commit**

```bash
git add src/transport/stdio.cj
git commit -m "feat(transport): add StdioServerTransport implementing json-rpc Transport"
```

---

### Task 8: 创建 root.cj — 包入口

**Files:**
- Modify: `src/root.cj`

**Step 1: 更新 root.cj**

```cangjie
package mcp

public import mcp.types.*
public import mcp.transport.*
```

**Step 2: 编译验证**

Run: `cjpm build`
Expected: 编译成功

**Step 3: Commit**

```bash
git add src/root.cj
git commit -m "refactor: update root package entry with re-exports"
```

---

### Task 9: 更新 examples

**Files:**
- Modify: `src/examples/example.cj`

**Step 1: 更新 example.cj**

```cangjie
package mcp.examples

import mcp.*
import mcp.transport.*

main() {
    // 使用 StdioServerTransport
    let transport = StdioServerTransport()
    
    let server = McpServer("MyTools", "1.0.0", transport)
    server.instructions = "This is an example MCP server"
    
    let tool = Tool(
        "hello_world",
        "Say hello to someone",
        ToolInputSchema("object", HashMap<String, JsonValue>(), [])
    )
    tool.inputSchema.addField("name", "string", "Name of the person to greet", required: true)
    
    server.addTool(tool, { params =>
        let name = params.arguments.get("name") ?? JsonValue.String("World")
        CallToolResult.text("Hello, ${name}")
    })
    
    println("MCP server started")
    transport.receiveLoop(server)
}
```

**Step 2: 编译验证**

Run: `cjpm build`
Expected: 编译成功

**Step 3: Commit**

```bash
git add src/examples/example.cj
git commit -m "docs(examples): update example to use new API"
```
