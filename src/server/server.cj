package mcp.server

import std.collection.{HashMap, ArrayList}
import encoding.json.stream.*
import mcp.types.*
import mcp.types.Error as McpError
import mcp.utils.JsonParserUtil
import std.sync.{ReentrantReadWriteMutex, AtomicBool}
import log.{Logger, LogLevel}
import logger.{TextLogger}
import std.fs.{File, OpenMode}
import std.io.ByteBuffer

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
    let errlogger: Logger
    public init(name: String, version: String, opts: Array<ServerOption>) {
        this.name = name
        this.version = version
        let jl = TextLogger(File("mcp.log", OpenMode.Append))
        jl.level = LogLevel.ALL
        this.errlogger = jl
        for (opt in opts) {
            opt(this)
        }
    }
    public func handleMessage(jsonBytes: Array<UInt8>): JsonRpcMessage {
        let basemsgopt: ?BaseMessage = JsonParserUtil.parseFromBytes<BaseMessage>(jsonBytes)
        if (let None <- basemsgopt) {
            this.errlogger.error("Failed to parse base message")
            return createErrorResponse(RequestId.Int(0), PARSE_ERROR, "Failed to parse message")
        }
        
        let basemsg = basemsgopt.getOrThrow()
        this.errlogger.error("parse base message:basemsg method: ${basemsg.method}")
    
        if (basemsg.jsonrpc != "2.0") {
            return createErrorResponse(basemsg.id, INVALID_REQUEST, "Invalid JSON-RPC version")
        }
        
        if (let None <- basemsg.id) {
            this.handleNotification(basemsg.method, jsonBytes)
            return NoOpMessage()
        }
        
        match (basemsg.method) {
            case "initialize" => 
                this.errlogger.info("into initialize 1")
                let requestopt: ?InitializeRequest = JsonParserUtil.parseFromBytes<InitializeRequest>(jsonBytes)
                if (let Some(request) <- requestopt) {
                    this.errlogger.info("into initialize 2, ${request.method}")
                    return this.handleInitialize(basemsg.id.getOrThrow(), request)
                } else {
                    return createErrorResponse(basemsg.id, PARSE_ERROR, "Failed to parse initialize request")
                }
            case "ping" => 
                let requestopt: ?PingRequest = JsonParserUtil.parseFromBytes<PingRequest>(jsonBytes)
                if (let Some(request) <- requestopt) {
                    return this.handlePing(basemsg.id.getOrThrow(), request)
                } else {
                    return createErrorResponse(basemsg.id, PARSE_ERROR, "Failed to parse ping request")
                }
            case "tools/list" => 
                if (this.capabilities.tools.isNone()) {
                    return createErrorResponse(basemsg.id, METHOD_NOT_FOUND, "Tools not supported")
                }
                let requestopt: ?ListToolsRequest = JsonParserUtil.parseFromBytes<ListToolsRequest>(jsonBytes)
                if (let Some(request) <- requestopt) {
                    let resp = this.handleListListTools(basemsg.id.getOrThrow(), request)
                    return JsonRpcResponse(basemsg.id ?? RequestId.Int(0), resp)
                } else {
                    return createErrorResponse(basemsg.id, PARSE_ERROR, "Failed to parse list tools request")
                }
            case "tools/call" => 
                this.errlogger.info("tools/call")
                let requestopt: ?CallToolRequest = JsonParserUtil.parseFromBytes<CallToolRequest>(jsonBytes)
                if (let Some(request) <- requestopt) {
                    if (this.capabilities.tools.isNone()) {
                        return createErrorResponse(basemsg.id, METHOD_NOT_FOUND, "Tools not supported")
                    }
                    this.errlogger.info("before/call: ${request.method}, ${request.params.name}")
                    try {
                        let result = this.handleCallTool(basemsg.id.getOrThrow(), request)
                        this.errlogger.info("after/call")
                        return JsonRpcResponse(basemsg.id ?? RequestId.Int(0), result)
                    } catch (e: Exception) {
                        this.errlogger.error("Error handling call tool: ${e.message}")
                        return createErrorResponse(basemsg.id, INTERNAL_ERROR, "Error handling call tool: ${e.message}")
                    }
                } else {
                    return createErrorResponse(basemsg.id, PARSE_ERROR, "Failed to parse call tool request")
                }
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
    func handleNotification(method:String, jsonBytes: Array<UInt8>):Unit {
        var handler :?NotificationHandlerFunc = None
        synchronized(this.mu.readMutex) {
            if (this.notificationHandlers.contains(method)) {
                handler = this.notificationHandlers[method]
            }
        }
        
        if (let Some(h) <- handler) {
            let buf = ByteBuffer(jsonBytes)
            let reader = JsonReader(buf)
            h(method, reader)
        }
    }
    func handleInitialize(id:RequestId, request:InitializeRequest):JsonRpcMessage {
        let capabilities = ServerCapabilities()
        if (let Some(v) <-  this.capabilities.resources) {
            capabilities.resources = ResourceCapabilities(v.subscribe, v.listChanged)
        } else {
            capabilities.resources = ResourceCapabilities(false, false)
        }
        if (let Some(v) <-  this.capabilities.prompts) {
            capabilities.prompts = PromptCapabilities(v.listChanged)
        }else {
            capabilities.prompts = PromptCapabilities(false)
        }
        if (let Some(v) <-  this.capabilities.tools) {
            capabilities.tools = ToolsCapabilities(v.listChanged)
        } else {
            capabilities.tools = ToolsCapabilities(false)
        }
        // if (this.capabilities.logging) {
        //     capabilities.logging = true
        // }

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
    func handleListListTools(id:RequestId, request:ListToolsRequest):Result {
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
    func handleCallTool(id:RequestId, request:CallToolRequest):Result {
        this.errlogger.info("Call tool: " + request.params.name)
        if (let Some(v) <- this.tools.get(request.params.name)) {
            this.errlogger.info("Calling tool: " + request.params.name)
            return v.handler(request)
        }
        this.errlogger.info("not Call tool: " + request.params.name)
        for ((name, tool) in this.tools) {
            this.errlogger.info("has tool: " + name)
        }
        return EmptyResult()
    }
}


func createErrorResponse(id: ?RequestId, code: Int64, message: String): JsonRpcMessage {
    return JsonRpcError(id, McpError(code, message, None))
}
