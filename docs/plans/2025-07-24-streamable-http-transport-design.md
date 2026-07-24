# Streamable HTTP Transport 设计

## 背景

为 mcp-cj 添加 Streamable HTTP Transport 支持，基于 MCP 2025-11-25 协议的 Streamable HTTP 传输层。

## 架构

### 依赖关系

```
mcp-cj (transport) → json-rpc (Transport 接口 + Framing) → stdx.net.http (HTTP/SSE)
```

### 核心思路

两个 Transport 实现 `ysytle::jsonrpc.Transport` 接口，配合 `NewlineFraming`。

Transport **不管理 HTTP Server 生命周期**，只向 `HttpRequestDistributor` 注册 handler，由调用方控制 Server。

```
┌─────────────────────────────┐
│  调用方代码                    │
│  ServerBuilder.distributor() │
│       .addr().serve()        │
└────────┬────────────────────┘
         │ 注册 handler
         ▼
┌─────────────────────────────┐
│  StreamableHttpServerTransport │
│  - registerRoutes(distributor) │
│  - send() → SSE writer        │
│  - receive() ← POST queue     │
└─────────────────────────────┘
```

## 组件

### StreamableHttpServerTransport

**构造**：接收 `distributor: HttpRequestDistributor`

**路由注册**：
- `GET /sse` → `handleSSE`
- `POST /message` → `handleMessage`

**状态**：
- `sseWriter: ?HttpResponseWriter` — 当前 SSE 连接 writer
- `sessionId: String` — 当前会话 ID
- `messageQueue: ArrayList<Array<Byte>>` — POST 消息队列
- `lock: Mutex` + `cond: Condition` — 队列同步

**Transport 接口**：
- `send(data: Array<Byte>)`: `data = json\n`（NewlineFraming 已加），拆掉末尾 `\n`，包装为 `data: json\n\n`，写入 SSE writer
- `receive()`: 从 `messageQueue` 阻塞获取，追加 `\n` 返回
- `isClosed()`: 是否已关闭
- `close()`: 关闭 SSE writer

**事件流**：
1. SSE 连接 → 发送 `event: session_id\ndata: {id}\n\n`
2. POST 请求 → 读 body → 入队 → 唤醒 receive()
3. `receive()` 返回 body → JsonRpcServer 处理 → `send()` 写 SSE 事件

### StreamableHttpClientTransport

**构造**：接收 `baseUrl: String`

**Transport 接口**：
- `send(data: Array<Byte>)`: `data = json\n`，拆 `\n`，POST `json` 到 `{baseUrl}/message?session_id={id}`
- `receive()`: 从 SSE 流阻塞读下一个事件，提取 `data:` 内容，追加 `\n` 返回
- `isClosed()`: 是否已关闭
- `close()`: 关闭 SSE 连接

### SSE 事件格式

```
data: {json}\n\n
```

Session ID 事件：
```
event: session_id\ndata: {id}\n\n
```

### NewlineFraming 配合

Transport 层负责与 SSE 协议的转换，NewlineFraming 只做消息边界标记：
- `encode(bytes)` → `bytes + \n`
- `decode(data)` → `(bytes, consumed)` 按 `\n` 分割

## Server 协作方式

```cangjie
let distributor = DirectDistributor()
let transport = StreamableHttpServerTransport(distributor)
let server = McpServer("my", "1.0.0", transport)
server.start()

let httpServer = ServerBuilder()
    .addr("127.0.0.1:8080")
    .distributor(distributor)
    .build()
httpServer.serve()
```

## 错误处理

- SSE 连接断开：清空 writer，标记 closed，下一轮 receive() 返回 None
- POST body 为空：返回 400
- HTTP 方法不对：返回 405
- session_id 无效：返回 404
