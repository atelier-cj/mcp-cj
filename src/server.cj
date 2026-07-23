package mcp

import jsonvalue.*
import ystyle::jsonrpc.*
import stdx.encoding.json.stream.*
import std.collection.*
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
        this.rpcServer.register("initialize", { ctx => this.handleInitialize(ctx) })
        this.rpcServer.register("ping", { ctx => HandlerResult.ok(JsonValue.fromObject(EmptyResult())) })
        this.rpcServer.register("tools/list", { ctx => this.handleListTools(ctx) })
        this.rpcServer.register("tools/call", { ctx => this.handleCallTool(ctx) })
    }

    public func addTool(tool: Tool, handler: ToolHandlerFunc) {
        if (this.capabilities.tools.isNone()) {
            this.capabilities.tools = ToolsCapabilities(true)
        }
        this.toolDefs[tool.name] = tool
        this.tools[tool.name] = handler
    }

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

public class EmptyResult <: JsonSerializable & JsonDeserializable<EmptyResult> {
    public func toJson(w: JsonWriter): Unit { w.startObject(); w.endObject() }
    public static func fromJson(r: JsonReader): EmptyResult { EmptyResult() }
}
