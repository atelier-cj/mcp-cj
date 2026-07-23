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
  mcp = { git = "https://github.com/ystyle/mcp-cj", branch = "master"}
```

```bash
export CANGJIE_STDX_PATH=/path/to/stdx
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
| `StdioServerTransport` | 标准输入输出传输 |
| `Transport` 接口 | 自定义传输实现 |

### 协议支持

| 方法 | 状态 |
|------|------|
| `initialize` / `ping` | ✅ |
| `tools/list` / `tools/call` | ✅ |
| `resources/list` / `resources/read` | ✅ |
| `resources/templates/list` | ✅ |
| `prompts/list` / `prompts/get` | ✅ |
| `notifications/*` | 部分支持 |
| `logging/setLevel` | 待实现 |
| `completions/complete` | 待实现 |

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

支持 MCP 协议版本：**2025-11-25**（Latest）

兼容版本：2025-06-18, 2025-03-26, 2024-11-05, 2024-10-07

## License

MIT
