package mcp

import jsonvalue.*
import ystyle::jsonrpc.{JsonRpcClient, Transport, NewlineFraming, RequestId, Result, NotificationCallback, Request, serializeRequest}
import stdx.encoding.json.stream.*
import std.collection.*
import std.sync.Mutex
import std.time.DateTime
import mcp.types.*

public class McpClient {
    private let rpcClient: JsonRpcClient
    private var serverCapabilities: ?ServerCapabilities = None
    private var serverInfo: ?Implementation = None
    private var serverProtocolVersion: String = ""
    private var initialized: Bool = false
    // 已建立的订阅（诊断用：能回答"订阅了几条、活了多久"）
    private let subscriptions = ArrayList<Subscription>()
    private let lock = Mutex()
    private var subIdSeq: Int64 = 1000

    private func nextSubId(): Int64 {
        synchronized(this.lock) {
            this.subIdSeq++
            this.subIdSeq
        }
    }

    // 保留一份 transport：订阅要自己发原始请求（不能走 call()，见 subscribe 注释）
    private let transport: Transport

    public init(transport: Transport) {
        this.transport = transport
        this.rpcClient = JsonRpcClient(transport, framing: NewlineFraming())
    }

    public func connect(clientInfo: Implementation, timeout!: Duration = 30 * Duration.second): Result<InitializeResult> {
        this.rpcClient.start()
        let params = HashMap<String, JsonValue>()
        params.add("protocolVersion", JsonValue.String("2025-11-25"))
        params.add("capabilities", JsonValue.fromObject(ClientCapabilities()))
        params.add("clientInfo", JsonValue.fromObject(clientInfo))
        let result = this.rpcClient.call<HashMap<String, JsonValue>, InitializeResult>("initialize", params: params, timeout: timeout)
        match (result) {
            case Result.Ok(initResult) =>
                this.serverCapabilities = Some(initResult.capabilities)
                this.serverInfo = Some(initResult.serverInfo)
                this.serverProtocolVersion = initResult.protocolVersion
                this.initialized = true
                this.rpcClient.notify("notifications/initialized")
                result
            case Result.Err(e) => result
        }
    }

    public func close(): Unit {
        this.rpcClient.close()
    }

    public func isConnected(): Bool { this.initialized }

    public func getServerCapabilities(): ?ServerCapabilities { this.serverCapabilities }
    public func getServerInfo(): ?Implementation { this.serverInfo }
    public func getServerProtocolVersion(): String { this.serverProtocolVersion }

    // ---- Notifications ----

    public func setNotificationCallback(cb: NotificationCallback): Unit {
        this.rpcClient.setNotificationCallback(cb)
    }

    public func cancelRequest(requestId: JsonValue, reason!: ?String = None): Unit {
        this.rpcClient.notify("notifications/cancelled", params: CancelledNotificationParams(requestId, reason: reason))
    }

    public func notifyProgress(progressToken: JsonValue, progress: Float64, total!: ?Float64 = None, message!: ?String = None): Unit {
        this.rpcClient.notify("notifications/progress", params: ProgressNotificationParams(progressToken, progress, total: total, message: message))
    }

    public func notifyRootsListChanged(): Unit {
        this.rpcClient.notify("notifications/roots/list_changed")
    }

    // ---- Tools ----

    public func listTools(timeout!: Duration = 30 * Duration.second): Result<ListToolsResult> {
        if (!this.initialized) { return Result.Err("Client not initialized") }
        this.rpcClient.call<JsonValue, ListToolsResult>("tools/list", params: None, timeout: timeout)
    }

    public func callTool(name: String, arguments!: ?HashMap<String, JsonValue> = None, timeout!: Duration = 30 * Duration.second): Result<CallToolResult> {
        if (!this.initialized) { return Result.Err("Client not initialized") }
        let params = HashMap<String, JsonValue>()
        params.add("name", JsonValue.String(name))
        if (let Some(args) <- arguments) {
            params.add("arguments", JsonValue.Map(args))
        }
        this.rpcClient.call<HashMap<String, JsonValue>, CallToolResult>("tools/call", params: params, timeout: timeout)
    }

    // ---- Resources ----

    public func listResources(timeout!: Duration = 30 * Duration.second): Result<ListResourcesResult> {
        if (!this.initialized) { return Result.Err("Client not initialized") }
        this.rpcClient.call<JsonValue, ListResourcesResult>("resources/list", params: None, timeout: timeout)
    }

    public func readResource(uri: String, timeout!: Duration = 30 * Duration.second): Result<ReadResourceResult> {
        if (!this.initialized) { return Result.Err("Client not initialized") }
        let params = HashMap<String, JsonValue>()
        params.add("uri", JsonValue.String(uri))
        this.rpcClient.call<HashMap<String, JsonValue>, ReadResourceResult>("resources/read", params: params, timeout: timeout)
    }

    public func listResourceTemplates(timeout!: Duration = 30 * Duration.second): Result<ListResourceTemplatesResult> {
        if (!this.initialized) { return Result.Err("Client not initialized") }
        this.rpcClient.call<JsonValue, ListResourceTemplatesResult>("resources/templates/list", params: None, timeout: timeout)
    }

    // ---- Prompts ----

    public func listPrompts(timeout!: Duration = 30 * Duration.second): Result<ListPromptsResult> {
        if (!this.initialized) { return Result.Err("Client not initialized") }
        this.rpcClient.call<JsonValue, ListPromptsResult>("prompts/list", params: None, timeout: timeout)
    }

    public func getPrompt(name: String, arguments!: ?HashMap<String, String> = None, timeout!: Duration = 30 * Duration.second): Result<GetPromptResult> {
        if (!this.initialized) { return Result.Err("Client not initialized") }
        let params = HashMap<String, JsonValue>()
        params.add("name", JsonValue.String(name))
        if (let Some(args) <- arguments) {
            let argMap = HashMap<String, JsonValue>()
            for ((k, v) in args) { argMap.add(k, JsonValue.String(v)) }
            params.add("arguments", JsonValue.Map(argMap))
        }
        this.rpcClient.call<HashMap<String, JsonValue>, GetPromptResult>("prompts/get", params: params, timeout: timeout)
    }

    // ---- 订阅（服务端主动推送通知） ----

    /**
     * 建立通知订阅：之后服务端会在这条 SSE 流上主动推 `notifications/...` 系列。
     *
     * **不等 ack**：订阅响应分两阶段（一次 ack + 之后的无期限通知流），
     * 用 `call()` 等 ack 之后就没人在读那条流了。所以这里只把请求发出去，
     * 读流与分发交给 transport 的后台循环——它本来就会把 SSE 事件
     * 灌进 responseQueue，通知经 jsonrpc 回调分发给用户。
     *
     * 这意味着：**返回 Ok 只代表"请求发出去了"**，不代表服务端已接受。
     * 服务端接受后会推一条 `notifications/subscriptions/acknowledged`；
     * 想确认订阅真的建立，就在通知回调里等它（见 `isSubscriptionAck`）。
     *
     * 在调用前必须先 `connect()`（需要 initialized）并装好通知回调。
     */
    public func subscribe(filter: SubscriptionRequest): Result<Subscription> {
        if (!this.initialized) { return Result.Err("Client not initialized") }
        let id = RequestId.Int(this.nextSubId())
        let sub = Subscription(id, filter, nowMsMs())
        let params = HashMap<String, JsonValue>()
        params.add("notifications", JsonValue.fromObject(filter))
        let req = Request(id, "subscriptions/listen", params: Some(JsonValue.Map(params)))
        try {
            // 自己编码 + 直接发：call() 会绑一个待响应槽等 ack，
            // 而订阅是"一次 ack + 之后的长流"，用 call() 会把流留给没人读的槽位
            this.transport.send(NewlineFraming().encode(serializeRequest(req)))
        } catch (e: Exception) {
            // 送不出去必须如实报错：否则调用方以为订阅成功了
            return Result.Err("subscribe failed: " + e.toString())
        }
        synchronized(this.lock) { this.subscriptions.add(sub) }
        Result.Ok(sub)
    }

    /** 已发出的订阅数（诊断用）。 */
    public func subscriptionCount(): Int64 {
        synchronized(this.lock) { this.subscriptions.size }
    }

    /** 已发出的订阅（副本）。 */
    public func activeSubscriptions(): ArrayList<Subscription> {
        synchronized(this.lock) { ArrayList<Subscription>(this.subscriptions) }
    }
}

func nowMsMs(): Int64 {
    DateTime.now().toUnixTimeStamp().toMilliseconds()
}
