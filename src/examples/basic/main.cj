package mcp.examples.basic

import jsonvalue.*
import mcp.*
import mcp.transport.*
import std.collection.HashMap

main() {
    let transport = StdioServerTransport()
    let server = McpServer("hello-world-server", "1.0.0", transport)
    server.instructions = "A simple MCP server with a hello tool"

    let schema = ToolInputSchema("object", HashMap<String, JsonValue>(), [])
    schema.addField("name", "string", "Name of the person to greet", required: true)

    let tool = Tool("hello_world", "Say hello to someone", schema)
    server.addTool(tool, { params =>
        let name = match (params.arguments.get("name")) {
            case Some(JsonValue.String(n)) => n
            case _ => "World"
        }
        CallToolResult.text("Hello, ${name}!")
    })

    server.serve()
}
