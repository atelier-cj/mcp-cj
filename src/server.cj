package mcp

import jsonvalue.*
import ystyle::jsonrpc.{JsonRpcServer, Transport, HandlerContext, HandlerResult, NewlineFraming}
import stdx.encoding.json.stream.*
import std.collection.*
import mcp.types.*

public type ToolHandlerFunc = (ToolRequestParams) -> CallToolResult
public type ResourceHandlerFunc = (ReadResourceRequestParams) -> ReadResourceResult
public type PromptHandlerFunc = (GetPromptRequestParams) -> GetPromptResult

// Notification callback types
public type CancelledCallback = (CancelledNotificationParams) -> Unit
public type ProgressCallback = (ProgressNotificationParams) -> Unit
public type RootsListChangedCallback = () -> Unit
public type InitializedCallback = () -> Unit

public class McpServer {
    private let rpcServer: JsonRpcServer
    private let tools = HashMap<String, ToolHandlerFunc>()
    private let toolDefs = HashMap<String, Tool>()
    private let resources = HashMap<String, ResourceHandlerFunc>()
    private let resourceDefs = HashMap<String, McpResource>()
    private let resourceTemplates = HashMap<String, McpResourceTemplate>()
    private let prompts = HashMap<String, PromptHandlerFunc>()
    private let promptDefs = HashMap<String, Prompt>()
    public var capabilities = ServerCapabilities()
    public var instructions: ?String = None
    public let name: String
    public let version: String

    private var cancelledCb: ?CancelledCallback = None
    private var progressCb: ?ProgressCallback = None
    private var rootsListChangedCb: ?RootsListChangedCallback = None
    private var initializedCb: ?InitializedCallback = None

    public init(name: String, version: String, transport: Transport) {
        this.name = name
        this.version = version
        this.rpcServer = JsonRpcServer(transport, framing: NewlineFraming())
        this.registerHandlers()
    }

    private func registerHandlers() {
        this.rpcServer.register("initialize", { ctx => this.handleInitialize(ctx) })
        this.rpcServer.register("ping", { ctx => HandlerResult.ok(JsonValue.fromObject(EmptyResult())) })
        this.rpcServer.register("tools/list", { ctx => this.handleListTools(ctx) })
        this.rpcServer.register("tools/call", { ctx => this.handleCallTool(ctx) })
        this.rpcServer.register("resources/list", { ctx => this.handleListResources(ctx) })
        this.rpcServer.register("resources/read", { ctx => this.handleReadMcpResource(ctx) })
        this.rpcServer.register("resources/templates/list", { ctx => this.handleListMcpResourceTemplates(ctx) })
        this.rpcServer.register("prompts/list", { ctx => this.handleListPrompts(ctx) })
        this.rpcServer.register("prompts/get", { ctx => this.handleGetPrompt(ctx) })
        this.rpcServer.register("notifications/initialized", { ctx => this.handleInitialized(ctx) })
        this.rpcServer.register("notifications/cancelled", { ctx => this.handleCancelled(ctx) })
        this.rpcServer.register("notifications/progress", { ctx => this.handleProgress(ctx) })
        this.rpcServer.register("notifications/roots/list_changed", { ctx => this.handleRootsListChanged(ctx) })
    }

    public func addTool(tool: Tool, handler: ToolHandlerFunc) {
        if (this.capabilities.tools.isNone()) {
            this.capabilities.tools = ToolsCapabilities(true)
        }
        this.toolDefs[tool.name] = tool
        this.tools[tool.name] = handler
    }

    public func addMcpResource(resource: McpResource, handler: ResourceHandlerFunc) {
        if (this.capabilities.resources.isNone()) {
            this.capabilities.resources = ResourceCapabilities(false, false)
        }
        this.resourceDefs[resource.uri] = resource
        this.resources[resource.uri] = handler
    }

    public func addMcpResourceTemplate(template: McpResourceTemplate) {
        if (this.capabilities.resources.isNone()) {
            this.capabilities.resources = ResourceCapabilities(false, false)
        }
        this.resourceTemplates[template.name] = template
    }

    public func addPrompt(prompt: Prompt, handler: PromptHandlerFunc) {
        if (this.capabilities.prompts.isNone()) {
            this.capabilities.prompts = PromptCapabilities(true)
        }
        this.promptDefs[prompt.name] = prompt
        this.prompts[prompt.name] = handler
    }

    public func setOnCancelled(cb: CancelledCallback): Unit { this.cancelledCb = cb }
    public func setOnProgress(cb: ProgressCallback): Unit { this.progressCb = cb }
    public func setOnRootsListChanged(cb: RootsListChangedCallback): Unit { this.rootsListChangedCb = cb }
    public func setOnInitialized(cb: InitializedCallback): Unit { this.initializedCb = cb }

    public func start() {
        this.rpcServer.start()
    }

    public func serve() {
        this.rpcServer.serve()
    }

    public func close() {
        this.rpcServer.close()
    }

    private func handleInitialize(ctx: HandlerContext): HandlerResult {
        let result = InitializeResult()
        result.serverInfo = Implementation(this.name, this.version)
        result.capabilities = this.capabilities
        result.instructions = this.instructions
        HandlerResult.ok(JsonValue.fromObject(result))
    }

    // ---- Tools ----

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

    // ---- Resources ----

    private func handleListResources(ctx: HandlerContext): HandlerResult {
        let result = ListResourcesResult()
        result.resources = ArrayList<McpResource>(this.resourceDefs.values())
        HandlerResult.ok(JsonValue.fromObject(result))
    }

    private func handleReadMcpResource(ctx: HandlerContext): HandlerResult {
        let params = ctx.getParams<ReadResourceRequestParams>()
        let uri = params?.uri ?? ""
        if (let Some(handler) <- this.resources.get(uri)) {
            try {
                let result = handler(params ?? ReadResourceRequestParams())
                return HandlerResult.ok(JsonValue.fromObject(result))
            } catch (e: Exception) {
                return HandlerResult.err(INTERNAL_ERROR, "Resource read failed: ${e.message}")
            }
        }
        HandlerResult.err(METHOD_NOT_FOUND, "Resource not found: ${uri}")
    }

    private func handleListMcpResourceTemplates(ctx: HandlerContext): HandlerResult {
        let result = ListResourceTemplatesResult()
        result.resourceTemplates = ArrayList<McpResourceTemplate>(this.resourceTemplates.values())
        HandlerResult.ok(JsonValue.fromObject(result))
    }

    // ---- Prompts ----

    private func handleListPrompts(ctx: HandlerContext): HandlerResult {
        let result = ListPromptsResult()
        result.prompts = ArrayList<Prompt>(this.promptDefs.values())
        HandlerResult.ok(JsonValue.fromObject(result))
    }

    private func handleGetPrompt(ctx: HandlerContext): HandlerResult {
        let params = ctx.getParams<GetPromptRequestParams>()
        let name = params?.name ?? ""
        if (let Some(handler) <- this.prompts.get(name)) {
            try {
                let result = handler(params ?? GetPromptRequestParams())
                return HandlerResult.ok(JsonValue.fromObject(result))
            } catch (e: Exception) {
                return HandlerResult.err(INTERNAL_ERROR, "Prompt get failed: ${e.message}")
            }
        }
        HandlerResult.err(METHOD_NOT_FOUND, "Prompt not found: ${name}")
    }

    // ---- Notification Handlers (Client → Server) ----

    private func handleInitialized(ctx: HandlerContext): HandlerResult {
        if (let Some(cb) <- this.initializedCb) { cb() }
        HandlerResult.ok(JsonValue.Null)
    }

    private func handleCancelled(ctx: HandlerContext): HandlerResult {
        if (let Some(cb) <- this.cancelledCb) {
            if (let Some(params) <- ctx.getParams<CancelledNotificationParams>()) {
                cb(params)
            }
        }
        HandlerResult.ok(JsonValue.Null)
    }

    private func handleProgress(ctx: HandlerContext): HandlerResult {
        if (let Some(cb) <- this.progressCb) {
            if (let Some(params) <- ctx.getParams<ProgressNotificationParams>()) {
                cb(params)
            }
        }
        HandlerResult.ok(JsonValue.Null)
    }

    private func handleRootsListChanged(ctx: HandlerContext): HandlerResult {
        if (let Some(cb) <- this.rootsListChangedCb) { cb() }
        HandlerResult.ok(JsonValue.Null)
    }

    // ---- Notification Emit (Server → Client) ----

    public func notifyResourceListChanged(): Unit {
        this.rpcServer.notify("notifications/resources/list_changed")
    }

    public func notifyResourceUpdated(uri: String): Unit {
        this.rpcServer.notify("notifications/resources/updated", params: ResourceUpdatedNotificationParams(uri))
    }

    public func notifyPromptListChanged(): Unit {
        this.rpcServer.notify("notifications/prompts/list_changed")
    }

    public func notifyToolListChanged(): Unit {
        this.rpcServer.notify("notifications/tools/list_changed")
    }

    public func notifyLogMessage(level: LoggingLevel, data: JsonValue, logger!: ?String = None): Unit {
        this.rpcServer.notify("notifications/message", params: LoggingMessageNotificationParams(level, data, logger: logger))
    }

    public func notifyCancelled(requestId: JsonValue, reason!: ?String = None): Unit {
        this.rpcServer.notify("notifications/cancelled", params: CancelledNotificationParams(requestId, reason: reason))
    }

    public func notifyProgress(progressToken: JsonValue, progress: Float64, total!: ?Float64 = None, message!: ?String = None): Unit {
        this.rpcServer.notify("notifications/progress", params: ProgressNotificationParams(progressToken, progress, total: total, message: message))
    }
}

public class EmptyResult <: JsonSerializable & JsonDeserializable<EmptyResult> {
    public func toJson(w: JsonWriter): Unit { w.startObject(); w.endObject() }
    public static func fromJson(r: JsonReader): EmptyResult { EmptyResult() }
}
