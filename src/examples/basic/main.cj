package mcp.examples.basic

import jsonvalue.*
import mcp.*
import mcp.transport.*
import std.collection.HashMap

main() {
    let transport = StdioServerTransport()
    let server = McpServer("MyTools", "1.0.0", transport)
    server.instructions = "This is an example MCP server with a simple hello tool"

    let toolSchema = ToolInputSchema("object", HashMap<String, JsonValue>(), [])
    toolSchema.addField("name", "string", "Name of the person to greet", required: true)

    let tool = Tool("hello_world", "Say hello to someone", toolSchema)
    server.addTool(tool, { params =>
        let name = match (params.arguments.get("name")) {
            case Some(JsonValue.String(n)) => n
            case _ => "World"
        }
        CallToolResult.text("Hello, ${name}!")
    })

    println("MCP server started: ${server.name} v${server.version}")
    server.start()
}
