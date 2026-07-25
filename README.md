# mcp-cj

仓颉语言实现的 [Model Context Protocol (MCP)](https://modelcontextprotocol.io) 框架，包含服务端和客户端。

基于 [`jsonvalue`](https://github.com/ystyle/jsonvalue) + [`json-rpc`](https://github.com/ystyle/cj-json-rpc) 分层架构，支持协议版本 **2025-11-25**。

## 架构

```
mcp ──> ystyle::jsonrpc ──> jsonvalue ──> stdx.encoding.json.stream
```

## 安装

```toml
[dependencies]
  mcp = "2.0.0"
```

```bash
eval "$(cjvs stdx-env zsh)"   # 设置 stdx 环境变量
cjpm build
```

## 快速开始

```cangjie
package mcp.examples.basic

import jsonvalue.*
import mcp.*
import mcp.transport.*
import std.collection.HashMap

main() {
    let transport = StdioServerTransport()
    let server = McpServer("my-server", "1.0.0", transport)

    let schema = ToolInputSchema("object", HashMap<String, JsonValue>(), [])
    schema.addField("name", "string", "Name to greet", required: true)

    let tool = Tool("hello", "Say hello", schema)
    server.addTool(tool, { params =>
        let name = match (params.arguments.get("name")) {
            case Some(JsonValue.String(n)) => n
            case _ => "World"
        }
        CallToolResult.text("Hello, ${name}!")
    })

    server.serve()
}
```

用 [MCP Inspector](https://github.com/modelcontextprotocol/inspector) 测试：

```bash
npx @modelcontextprotocol/inspector --cli ./target/release/bin/mcp.examples.basic --method tools/list
npx @modelcontextprotocol/inspector --cli ./target/release/bin/mcp.examples.basic --method tools/call --tool-name hello --tool-arg name=World
```

## API

### McpServer

| 方法 | 说明 |
|------|------|
| `init(name, version, transport)` | 创建服务器 |
| `addTool(tool, handler)` | 注册工具 |
| `addMcpResource(resource, handler)` | 注册资源 |
| `addPrompt(prompt, handler)` | 注册提示模板 |
| `start()` | 非阻塞启动 |
| `serve()` | 阻塞启动（推荐） |
| `close()` | 关闭服务器 |

### McpClient

| 方法 | 说明 |
|------|------|
| `init(transport)` | 创建客户端 |
| `connect(clientInfo)` | 连接并完成初始化握手 |
| `listTools()` | 列出服务端工具 |
| `callTool(name, arguments)` | 调用工具 |
| `listResources()` | 列出服务端资源 |
| `readResource(uri)` | 读取资源内容 |
| `listResourceTemplates()` | 列出资源模板 |
| `listPrompts()` | 列出服务端提示 |
| `getPrompt(name, arguments)` | 获取提示内容 |
| `close()` | 关闭连接 |

```cangjie
let transport = StdioServerTransport()
let client = McpClient(transport)

let info = Implementation("my-client", "1.0.0")
match (client.connect(info)) {
    case Result.Ok(init) =>
        println("Connected: ${init.serverInfo.name}")
    case Result.Err(e) =>
        println("Failed: ${e}")
}

// 调用工具
let args = HashMap<String, JsonValue>()
args.add("name", JsonValue.String("World"))
match (client.callTool("hello", arguments: args)) {
    case Result.Ok(r) => // handle result
    case Result.Err(e) => println("Error: ${e}")
}

client.close()
```

### Transport

| 实现 | 说明 |
|------|------|
| `StdioServerTransport` | 标准输入输出传输（服务端） |
| `StdioClientTransport` | 标准输入输出传输（客户端，subprocess） |
| `HttpSseServerTransport` | HTTP+SSE 传输（服务端，2024-11-05 旧版，已废弃） |
| `HttpSseClientTransport` | HTTP+SSE 传输（客户端） |
| `SessionHttpServerTransport` | Streamable HTTP 传输（服务端，2025-11-25，带 session） |
| `SessionHttpClientTransport` | Streamable HTTP 传输（客户端） |
| `StatelessHttpServerTransport` | Streamable HTTP 传输（服务端，2026-07-28，无 session） |
| `StatelessHttpClientTransport` | Streamable HTTP 传输（客户端） |
| `Transport` 接口 | 自定义传输实现 |

### 使用 Streamable HTTP Transport (2025-11-25 Session)

服务端（基于 `stdx.net.http`）：

```cangjie
import stdx.net.http.*

let httpServer = ServerBuilder()
    .addr("127.0.0.1").port(8080).build()

let transport = SessionHttpServerTransport()
transport.registerRoutes(httpServer.distributor)

let server = McpServer("my-server", "1.0.0", transport)
// ... 注册工具、资源等 ...
server.start()
httpServer.serve()
```

客户端（连接上述服务端）：

```cangjie
let client = McpClient(SessionHttpClientTransport("http://127.0.0.1:8080"))
```

### 协议支持

| 方法 | 状态 |
|------|------|
| `initialize` / `ping` | ✅ |
| `tools/list` / `tools/call` | ✅ |
| `resources/list` / `resources/read` | ✅ |
| `resources/templates/list` | ✅ |
| `prompts/list` / `prompts/get` | ✅ |
| `subscriptions/listen` | ✅ (StatelessHttpTransport) |
| `notifications/initialized` | ✅ |
| `notifications/cancelled` | ✅ (双向，Session/Stdio) |
| `notifications/progress` | ✅ (双向) |
| `notifications/roots/list_changed` | ✅ |
| `notifications/resources/*` | ✅ (list_changed / updated) |
| `notifications/prompts/list_changed` | ✅ |
| `notifications/tools/list_changed` | ✅ |
| `notifications/message` (日志) | ✅ |
| `logging/setLevel` | 待实现 |
| `completion/complete` | 待实现 |
| Header 校验 (`MCP-Protocol-Version` / `Mcp-Method` / `Mcp-Name`) | ✅ (StatelessHttpTransport) |
| 取消语义（关 SSE 流 = 取消） | ✅ (StatelessHttpTransport) |

### 类型

工具相关：`Tool`, `ToolInputSchema`, `CallToolResult`, `ToolAnnotations`, `PaginatedRequest`

资源相关：`McpResource`, `ResourceContents`, `ResourceTemplate`, `ReadResourceResult`

提示相关：`Prompt`, `PromptArgument`, `PromptMessage`, `GetPromptResult`

内容相关：`ContentBlock`, `TextContent`, `ImageContent`, `AudioContent`, `EmbeddedResource`

## 依赖库

| 库 | 说明 |
|------|------|
| [jsonvalue](https://github.com/ystyle/jsonvalue) | 通用 JSON Value 类型 |
| [json-rpc](https://github.com/ystyle/cj-json-rpc) | JSON-RPC 2.0 框架 |

## 协议版本

支持 MCP 协议版本：

| 版本 | Transport | 状态 |
|------|-----------|------|
| **2026-07-28** | `StatelessHttpTransport` | RC，最新协议 |
| **2025-11-25** | `SessionHttpTransport` | Latest，**推荐** |
| 2024-11-05 | `HttpSseTransport` | 已废弃 |

兼容版本：2025-06-18, 2025-03-26, 2024-10-07

### Transport 选型指南

| Transport | 适用场景 |
|-----------|----------|
| `StdioServerTransport` | 本地子进程模式，最通用 |
| `SessionHttpServerTransport` | **推荐** Streamable HTTP (2025-11-25)，支持 opencode / Cherry Studio / Inspector |
| `StatelessHttpServerTransport` | Streamable HTTP (2026-07-28)，最新协议，无 session，支持 subscriptions/listen |
| `HttpSseServerTransport` | 已废弃的 HTTP+SSE 旧协议 (2024-11-05)，仅用于兼容老客户端 |

## License

MIT
