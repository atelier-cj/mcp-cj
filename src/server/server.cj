package mcp.server

import std.collection.{HashMap, ArrayList}
import encoding.json.stream.*
import mcp.types.*
import mcp.types.Error as McpError
import std.sync.{ReentrantReadWriteMutex, AtomicBool}

public type ServerOption = (McpServer) -> Unit

public func WithResourceCapabilities(subscribe: Bool, listChanged: Bool): ServerOption {
    return {
        server => server.capabilities.resources = ResourceCapabilities(subscribe, listChanged)
    }
}

public func WithPromptCapabilities(listChanged: Bool): ServerOption {
    return {
        server => server.capabilities.prompts = PromptCapabilities(listChanged)
    }
}

public func WithLogging(): ServerOption {
    return {
        server => server.capabilities.logging = true
    }
}



public class NotificationContext {
    public NotificationContext(let clientId: String, let sessionId: String) {}
}

public class ServerNotification {
    public ServerNotification(let context: NotificationContext, let notification: JsonRpcNotification) {}
}

type ToolHandlerFunc = (CallToolRequest) -> CallToolResult

public class ServerTool {
    public ServerTool(let tool: Tool, let handler: ToolHandlerFunc) {}
}

type NotificationHandlerFunc = (String, JsonReader) -> Unit

public class McpServer {
    let name: String
    let version: String
    var instructions:?String = None
    let tools = HashMap<String, ServerTool>()
    var notificationCallback: Option<(ServerNotification) -> Unit> = None
    let notificationHandlers = HashMap<String, NotificationHandlerFunc>()
    let capabilities = ServerCapabilities()
    var currentClient: ?NotificationContext = None
    var mu = ReentrantReadWriteMutex()
    let initialized = AtomicBool(false)
    public init(name: String, version: String, opts: Array<ServerOption>) {
        this.name = name
        this.version = version
        for (opt in opts) {
            opt(this)
        }
    }
    public func handleMessage(rawmsg: JsonReader): JsonRpcMessage {
        var basemsgopt: ?BaseMessage = None
        try {
            basemsgopt = BaseMessage.fromJson(rawmsg)
        } catch (e: Exception) {
            return createErrorResponse(RequestId.Int(0), PARSE_ERROR, "Failed to parse message")
        }
        let basemsg = basemsgopt.getOrThrow()
        if (basemsg.jsonrpc != "2.0") {
            return createErrorResponse(basemsg.id, INVALID_REQUEST, "Invalid JSON-RPC version")
        }
        if (let None <- basemsg.id) {
            this.handleNotification(basemsg.method, rawmsg)
            return NoOpMessage()
        }
        match (basemsg.method) {
            case "initialize" => 
                let request = InitializeRequest.fromJson(rawmsg)
                return  this.handleInitialize(basemsg.id.getOrThrow(), request)
            case "ping" => 
                let request = PingRequest.fromJson(rawmsg)
                return this.handlePing(basemsg.id.getOrThrow(), request)
            case "tools/list" => 
                if (this.capabilities.tools.isNone()) {
                    return createErrorResponse(basemsg.id, METHOD_NOT_FOUND, "Tools not supported")
                }
                let request = ListToolsRequest.fromJson(rawmsg)
                return this.handleListListTools(basemsg.id.getOrThrow(), request)
            case "tools/call" => 
                let request = PingRequest.fromJson(rawmsg)
                return this.handlePing(basemsg.id.getOrThrow(), request)
            case _ => createErrorResponse(basemsg.id, METHOD_NOT_FOUND, "Method ${basemsg.method} not found")
        }
        return NoOpMessage()
    }
    public func sendNotificationToClient(msg: JsonRpcNotification): Unit {
        if (let None <- this.notificationCallback) {
            throw Exception("notification channel not initialized")
        }
        this.notificationCallback?(ServerNotification(this.currentClient.getOrThrow(), msg))
    }
    public func addTool(tool: Tool, handler: ToolHandlerFunc): Unit {
        this.addTools([ServerTool(tool, handler)])
    }

    public func addTools(tools: Array<ServerTool>): Unit {
        if (this.capabilities.tools.isNone()) {
            this.capabilities.tools = ToolsCapabilities(true)
        }
        for (item in tools) {
            this.tools[item.tool.name] = item
        }
        if (this.initialized.load()) {
            this.sendNotificationToClient(ToolListChangedNotification())
        }
    }
    func handleNotification(method:String, rawmsg: JsonReader):Unit {
        var handler :?NotificationHandlerFunc = None
        synchronized(this.mu.readMutex) {
            if (this.notificationHandlers.contains(method)) {
                handler = this.notificationHandlers[method]
            }
        }
        handler?(method, rawmsg)
    }
    func handleInitialize(id:RequestId, request:InitializeRequest):JsonRpcMessage {
        let capabilities = ServerCapabilities()
        if (let Some(v) <-  this.capabilities.resources) {
            capabilities.resources = v
        }
        if (let Some(v) <-  this.capabilities.prompts) {
            capabilities.prompts = v
        }
        if (let Some(v) <-  this.capabilities.tools) {
            capabilities.tools = v
        }
        if (this.capabilities.logging) {
            capabilities.logging = true
        }

        let result = InitializeResult()
        result.serverInfo = Implementation(this.name, this.version)
        result.capabilities = capabilities
        result.instructions = this.instructions
        this.initialized.store(true)
        return JsonRpcResponse(id, result)
    }
    func handlePing(id:RequestId, request:PingRequest):JsonRpcMessage {
        return JsonRpcResponse(id, EmptyResult())
    }
    func handleListListTools(id:RequestId, request:ListToolsRequest):JsonRpcMessage {
        let result = ListToolsResult()
        var tools = ArrayList<Tool>()
        for ((_, tool) in this.tools) {
            tools.add(tool.tool)
        }
        result.tools = tools
        if (let Some(v) <- request.params) {
            if (let Some(c) <- v.cursor) {
                result.nextCursor = None
            }
        }
        return result
    }
}


func createErrorResponse(id: ?RequestId, code: Int64, message: String): JsonRpcMessage {
    return JsonRpcError(id, McpError(code, message, None))
}
