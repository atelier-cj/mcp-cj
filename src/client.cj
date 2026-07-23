package mcp

import jsonvalue.*
import ystyle::jsonrpc.{JsonRpcClient, Transport, RequestId, Result}
import stdx.encoding.json.stream.*
import std.collection.*
import mcp.types.*

public class McpClient {
    private let rpcClient: JsonRpcClient
    private var serverCapabilities: ?ServerCapabilities = None
    private var serverInfo: ?Implementation = None
    private var serverProtocolVersion: String = ""
    private var initialized: Bool = false

    public init(transport: Transport) {
        this.rpcClient = JsonRpcClient(transport)
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
}
