# mcp-cj 重构设计

## 概述

将 mcp-cj 从独立实现重构为基于 `jsonvalue` + `json-rpc` 库的分层架构，并更新 MCP 协议版本至 2025-11-25。

## 架构

### 依赖关系

```
mcp ──> ystyle::jsonrpc ──> jsonvalue ──> stdx.encoding.json.stream
```

- `jsonvalue` — 通用 JSON Value 类型，替代手写的 `fast_value.cj`
- `ystyle::jsonrpc` — JSON-RPC 2.0 框架，替代手写的 JSON-RPC 消息层
- `mcp` — MCP 协议层，专注 MCP 特定类型和方法

### 目录结构

```
src/
├── mcp.cj             # 包入口，re-export
├── server.cj          # McpServer 实现
├── client.cj          # McpClient 实现（新增）
├── types/
│   ├── types.cj       # MCP 协议类型定义（InitializeResult, ServerCapabilities 等）
│   ├── tools.cj       # Tool, ToolInputSchema, CallToolResult 等
│   ├── resources.cj   # Resource, ResourceTemplate, ResourceContents 等（新增）
│   ├── prompts.cj     # Prompt, PromptMessage, PromptArgument 等（新增）
│   ├── tasks.cj       # Task, TaskMetadata, TaskStatus 等（新增）
│   └── content.cj     # ContentBlock, TextContent, ImageContent, AudioContent 等（新增）
└── transport/
    └── stdio.cj       # StdioServerTransport
```

### 删除文件

| 文件 | 原因 |
|------|------|
| `src/types/fast_value.cj` | 被 jsonvalue 库替代 |
| `src/types/jsonrpc_message.cj` | 被 json-rpc 库替代 |
| `src/types/request.cj` | 被 json-rpc 库替代 |
| `src/types/response.cj` | 被 json-rpc 库替代 |
| `src/types/value.cj` | 被 jsonvalue 库替代 |
| `src/types/utils.cj` | fromJsonObject 可内联或用 jsonvalue |
| `src/types/notification.cj` | 改用 json-rpc 的 Notification |
| `src/utils/json_parser.cj` | JsonParserUtil 被 jsonvalue 替代 |

### 保留并修改

| 文件 | 改动 |
|------|------|
| `src/types/types.cj` | 保留 ServerCapabilities/Implementation/常量，删除 JSON-RPC 相关 |
| `src/types/server.cj` | 迁移至 `src/server.cj`，用 json-rpc 的 JsonRpcServer |
| `src/types/tools.cj` | 精简 Tool/CallToolResult，删除工具构造 DSL |
| `src/server/server.cj` | McpServer 重写，基于 json-rpc JsonRpcServer |
| `src/server/stdio.cj` | StdioServer 重写，基于 json-rpc Transport |
| `src/root.cj` | 扩展为包入口，re-export 关键类型 |

## McpServer 设计

```cangjie
public class McpServer {
    // 内部使用 json-rpc 的 JsonRpcServer
    private let rpcServer: JsonRpcServer
    
    // MCP 能力声明
    public var capabilities: ServerCapabilities
    public var instructions: ?String
    
    // 注册工具
    public func addTool(tool: Tool, handler: ToolHandlerFunc)
    
    // 生命周期
    public func start()
    public func close()
}
```

McpServer 内部注册以下 MCP handler 到 JsonRpcServer：

| Method | Handler |
|--------|---------|
| `initialize` | 协议版本校验 + ServerCapabilities 返回 |
| `ping` | 空响应 |
| `tools/list` | 返回已注册工具列表 |
| `tools/call` | 调用工具 handler 并返回结果 |
| `notifications/initialized` | 标记初始化完成 |

## 新协议特性（2025-11-25）

### ContentBlock
统一内容类型体系：
- `TextContent` — 文本
- `ImageContent` — 图片（base64 data + mimeType）
- `AudioContent` — 音频（base64 data + mimeType）
- `EmbeddedResource` — 嵌套资源引用

### ToolAnnotations
工具元数据：destructiveHint, idempotentHint, openWorldHint, readOnlyHint, title

### Tasks
任务支持的请求增强：taskId, createdAt, status 等

### 通知
- ProgressNotification — 处理进度
- LoggingMessageNotification — 日志消息
- TaskStatusNotification — 任务状态变更

## 迁移步骤

1. 更新 cjpm.toml 添加 jsonvalue + json-rpc 依赖
2. 删除废弃文件
3. 创建 MCP 协议类型文件
4. 重写 McpServer（基于 JsonRpcServer）
5. 重写传输层
6. 更新 examples
7. 编译验证
