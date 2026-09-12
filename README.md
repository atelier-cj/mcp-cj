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
| `SessionHttpServerTransport` | **推荐** Streamable HTTP (2025-11-25，带 session)，支持 opencode / Cherry Studio / Inspector |
| `SessionHttpClientTransport` | Streamable HTTP 客户端 |
| `StatelessHttpServerTransport` | Streamable HTTP (2026-07-28，无 session，支持 subscriptions/listen) |
| `StatelessHttpClientTransport` | Streamable HTTP 客户端 |
| `HttpSseServerTransport` | HTTP+SSE (2024-11-05，已废弃) |
| `HttpSseClientTransport` | HTTP+SSE 客户端 |
| `Transport` 接口 | 自定义传输实现 |

> 以上名称是类型别名（`type` alias），对应的具体实现类名为 `StreamableHttpServer_2025_11_25`、`StatelessHttpServer_2026_07_28` 等。推荐使用别名，便于未来协议升级时迁移。

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
| **2026-07-28** | `StatelessHttpServerTransport` / `StatelessHttpClientTransport` | RC，最新协议 |
| **2025-11-25** | `SessionHttpServerTransport` / `SessionHttpClientTransport` | Latest，**推荐** |
| 2024-11-05 | `HttpSseServerTransport` / `HttpSseClientTransport` | 已废弃 |

兼容版本：2025-06-18, 2025-03-26, 2024-10-07

### Transport 选型指南

| Transport | 适用场景 |
|-----------|----------|
| `StdioServerTransport` | 本地子进程模式，最通用 |
| `SessionHttpServerTransport` | **推荐** Streamable HTTP (2025-11-25)，支持 opencode / Cherry Studio / Inspector |
| `StatelessHttpServerTransport` | Streamable HTTP (2026-07-28)，最新协议，无 session，支持 subscriptions/listen |
| `HttpSseServerTransport` | 已废弃的 HTTP+SSE 旧协议 (2024-11-05)，仅用于兼容老客户端 |

### 并发语义（HTTP 服务端传输）

- **支持并发请求**：响应按 JSON-RPC `id` 路由，每个在飞请求一个等待槽；同一 `id` 的多个在飞请求按到达顺序（FIFO）各自配对 —— 这同时覆盖了「多个客户端各自从 id=1 计数」的撞车场景。
- **等待有界**：单个请求等待超过 `requestTimeout`（构造参数，默认 5 分钟）即返回**带原请求 `id` 的显式 JSON-RPC 错误**（`-32001`），不会永久挂住；`close()` 会立即唤醒全部在飞请求。
- **通知**（无 `id`）会入队交给服务端处理，但按 JSON-RPC 不应答。
- 响应无法匹配到等待槽时（服务端主动通知，或 `id:null` 的错误响应），才回退到 SSE 长连接、否则丢弃。
- 运维观测：`pendingCount()` 返回当前在飞请求数。

> **背景（2026-09-12，v2.3.9）**：修复前服务端用「单个共享 `waitingForResponse` 标志 + 单个 `pendingResponse` 槽位」承载响应，而 HTTP 每连接一个 handler 协程 —— 并发请求的响应会被**静默丢弃**，且等待循环永不退出（30s 超时后只是重新 `wait`）。表现为**并发请求 100% 挂死、顺序请求约 5~7% 挂死**，且挂住的请求其实**已经执行**（客户端超时重试 → 重复写）。回归测试 `src/streamable_concurrency_test.cj` 覆盖此场景（**该测试在旧实现下必然失败**）。

## 已知问题 / 待办

| 项 | 影响面 | 状态 |
|---|---|---|
| `StatelessHttpServer_2026_07_28` 的**请求级 SSE** 路径按客户端 `id` 匹配（`requestStreams` + `respId`），跨客户端 `id` 撞车时可能误投递 | 仅"同一时刻两个客户端共用同一 `id`"的场景；顺序或正常客户端不受影响 | **待评估**（需按连接/请求命名空间化）。注：该传输的"无 SSE"同步分支对合规客户端**不可达**（`validatePreHeaders` 强制 Accept 含 `text/event-stream`），已作防御性修复 |
| 依赖库 `json-rpc` 的 `JsonRpcServer.handleOutgoingResponse` 仍用**单个** `pendingRequest`（服务端 → 客户端方向，如 sampling / elicitation） | 服务端并发向同一客户端发请求时会串响应 | **待评估**（属 json-rpc 仓库的同类模式） |
| v2.3.9 已在本地 `master`（`f30cadc`），**未推送远程、未发布中心仓** | 用 registry 版本依赖的项目拿不到本次修复 | **待定**（发布不可逆，需人工确认后执行） |

## License

MIT
