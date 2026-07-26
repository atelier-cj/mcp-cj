package mcp.examples.v2025_11_25_streamable_test

import jsonvalue.*
import mcp.*
import mcp.transport.*
import ystyle::jsonrpc.Result
import std.collection.{HashMap, ArrayList}
import stdx.net.http.*
import std.sync.{Mutex, Condition}

class PortHolder {
    var value: UInt16 = 0
}

main() {
    let portLock = Mutex()
    let portCond = synchronized(portLock) { portLock.condition() }
    let portHolder = PortHolder()

    let server = ServerBuilder()
        .addr("127.0.0.1")
        .port(0)
        .build()
    server.afterBind({ =>
        synchronized(portLock) {
            portHolder.value = server.port
            portCond.notifyAll()
        }
    })

    let transport = StreamableHttpServer_2025_11_25()
    transport.registerRoutes(server.distributor)

    let mcpServer = McpServer("http-test-server", "1.0.0", transport)
    mcpServer.instructions = "HTTP e2e test server"

    // ======== Tool ========
    let toolschema = ToolInputSchema("object", HashMap<String, JsonValue>(), [])
    toolschema.addField("name", "string", "Name to greet", required: true)

    let tool = Tool("hello", "Say hello", toolschema)
    mcpServer.addTool(tool, { params =>
        let name = match (params.arguments.get("name")) {
            case Some(JsonValue.String(n)) => n
            case _ => "World"
        }
        CallToolResult.text("Hello, ${name}!")
    })

    // ======== Resource ========
    let resource = McpResource("greeting://World", "Greeting Resource")
    resource.description = "A sample static resource"
    mcpServer.addMcpResource(resource, { params =>
        let name = params.uri.split("://").get(1) ?? "World"
        let result = ReadResourceResult()
        let rc = ResourceContents(params.uri)
        rc.mimeType = Some("text/plain")
        rc.text = Some("Hello, ${name}! This is a resource.")
        result.contents = ArrayList<ResourceContents>([rc])
        result
    })

    let template = McpResourceTemplate("docs://{path}", "Documentation Resource")
    template.description = "A template resource for documentation"
    mcpServer.addMcpResourceTemplate(template)

    // ======== Prompt ========
    let prompt = Prompt("greet")
    prompt.description = "Generate a personalized greeting"
    prompt.arguments = ArrayList<PromptArgument>([
        PromptArgument("name"),
        PromptArgument("language"),
    ])
    prompt.arguments.getOrThrow()[0].description = "Name to greet"
    prompt.arguments.getOrThrow()[1].description = "Language (zh/en)"
    prompt.arguments.getOrThrow()[1].required = Some(false)

    mcpServer.addPrompt(prompt, { params =>
        let name = params.arguments?.get("name")
        let lang = params.arguments?.get("language")
        let nameStr = match (name) { case Some(Some(n)) => n case _ => "World" }
        let langStr = match (lang) { case Some(Some(l)) => l case _ => "en" }
        let text = if (langStr == "zh") {
            "你好，${nameStr}！"
        } else {
            "Hello, ${nameStr}!"
        }
        let result = GetPromptResult()
        result.description = Some("Greeting for ${nameStr}")
        result.messages = ArrayList<PromptMessage>([
            PromptMessage("user", ContentBlock.Text(TextContent(text)))
        ])
        result
    })

    mcpServer.start()

    spawn {
        => server.serve()
    }

    synchronized(portLock) {
        while (portHolder.value == 0) {
            portCond.wait(timeout: 5 * Duration.second)
        }
    }

    let baseUrl = "http://127.0.0.1:${portHolder.value}"
    println("Server started at ${baseUrl}")

    let client = McpClient(StreamableHttpClient_2025_11_25(baseUrl))
    let info = Implementation("http-test-client", "1.0.0")

    println("=== Testing connect ===")
    match (client.connect(info)) {
        case Result.Ok(initResult) =>
            println("Connected! Server: ${initResult.serverInfo.name} v${initResult.serverInfo.version}")
            println("Protocol: ${initResult.protocolVersion}")
        case Result.Err(e) =>
            println("FAIL: Connect failed: ${e}")
            transport.close()
            server.close()
            return
    }

    println("\n=== Testing listTools ===")
    match (client.listTools()) {
        case Result.Ok(result) =>
            for (tool in result.tools) {
                println("  Tool: ${tool.name} - ${tool.description}")
            }
        case Result.Err(e) =>
            println("FAIL: listTools failed: ${e}")
    }

    println("\n=== Testing callTool ===")
    let args = HashMap<String, JsonValue>()
    args.add("name", JsonValue.String("Test"))
    match (client.callTool("hello", arguments: args)) {
        case Result.Ok(result) =>
            for (content in result.content) {
                match (content) {
                    case ContentBlock.Text(tc) => println("  Result: ${tc.text}")
                    case _ => println("  Unexpected content type")
                }
            }
        case Result.Err(e) =>
            println("FAIL: callTool failed: ${e}")
    }

    println("\n=== Testing listResources ===")
    match (client.listResources()) {
        case Result.Ok(result) =>
            for (res in result.resources) {
                println("  Resource: ${res.uri} - ${res.name}")
            }
        case Result.Err(e) =>
            println("FAIL: listResources failed: ${e}")
    }

    println("\n=== Testing readResource ===")
    match (client.readResource("greeting://World")) {
        case Result.Ok(result) =>
            for (content in result.contents) {
                if (let Some(text) <- content.text) {
                    println("  Content: ${text}")
                }
            }
        case Result.Err(e) =>
            println("FAIL: readResource failed: ${e}")
    }

    println("\n=== Testing listResourceTemplates ===")
    match (client.listResourceTemplates()) {
        case Result.Ok(result) =>
            for (t in result.resourceTemplates) {
                println("  Template: ${t.name} - ${t.uriTemplate}")
            }
        case Result.Err(e) =>
            println("FAIL: listResourceTemplates failed: ${e}")
    }

    println("\n=== Testing listPrompts ===")
    match (client.listPrompts()) {
        case Result.Ok(result) =>
            for (prompt in result.prompts) {
                println("  Prompt: ${prompt.name} - ${prompt.description}")
            }
        case Result.Err(e) =>
            println("FAIL: listPrompts failed: ${e}")
    }

    println("\n=== Testing getPrompt ===")
    let promptArgs = HashMap<String, String>()
    promptArgs.add("name", "Alice")
    match (client.getPrompt("greet", arguments: promptArgs)) {
        case Result.Ok(result) =>
            for (msg in result.messages) {
                match (msg.content) {
                    case ContentBlock.Text(tc) => println("  Message: ${tc.text}")
                    case _ => println("  Unexpected content type")
                }
            }
        case Result.Err(e) =>
            println("FAIL: getPrompt failed: ${e}")
    }

    client.close()
    transport.close()
    server.close()
    println("\n=== All HTTP e2e tests completed ===")
}
