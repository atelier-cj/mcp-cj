package mcp.examples.basic

import jsonvalue.*
import mcp.*
import mcp.transport.*
import std.collection.{HashMap, ArrayList}

main() {
    let transport = StdioServerTransport()
    let server = McpServer("hello-world-server", "1.0.0", transport)
    server.instructions = "An example MCP server with tool, resource, and prompt support"

    // ======== Tool ========
    let toolschema = ToolInputSchema("object", HashMap<String, JsonValue>(), [])
    toolschema.addField("name", "string", "Name of the person to greet", required: true)

    let tool = Tool("hello_world", "Say hello to someone", toolschema)
    server.addTool(tool, { params =>
        let name = match (params.arguments.get("name")) {
            case Some(JsonValue.String(n)) => n
            case _ => "World"
        }
        CallToolResult.text("Hello, ${name}!")
    })

    // ======== Resource ========
    let resource = McpResource("greeting://World", "Greeting Resource")
    resource.description = "A sample static resource for demonstration"
    server.addMcpResource(resource, { params =>
        let name = params.uri.split("://").get(1) ?? "World"
        let result = ReadResourceResult()
        let rc = ResourceContents(params.uri)
        rc.mimeType = Some("text/plain")
        rc.text = Some("Hello, ${name}! This is a resource.")
        result.contents = ArrayList<ResourceContents>([rc])
        result
    })

    // ======== Prompt ========
    let prompt = Prompt("greet")
    prompt.description = "Generate a personalized greeting message"
    prompt.arguments = ArrayList<PromptArgument>([
        PromptArgument("name"),
        PromptArgument("language"),
    ])
    prompt.arguments.getOrThrow()[0].description = "Name of the person to greet"
    prompt.arguments.getOrThrow()[1].description = "Language (zh/en)"
    prompt.arguments.getOrThrow()[1].required = Some(false)

    server.addPrompt(prompt, { params =>
        let name = params.arguments?.get("name")
        let lang = params.arguments?.get("language")
        let nameStr = match (name) { case Some(Some(n)) => n case _ => "World" }
        let langStr = match (lang) { case Some(Some(l)) => l case _ => "en" }
        let text = if (langStr == "zh") {
            "你好，${nameStr}！欢迎使用 MCP！"
        } else {
            "Hello, ${nameStr}! Welcome to MCP!"
        }
        let result = GetPromptResult()
        result.description = Some("Greeting for ${nameStr}")
        result.messages = ArrayList<PromptMessage>([
            PromptMessage("user", ContentBlock.Text(TextContent(text)))
        ])
        result
    })

    server.serve()
}
