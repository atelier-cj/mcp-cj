package mcp.examples.v2025_11_25_streamable_server

import jsonvalue.*
import mcp.*
import mcp.transport.*
import std.collection.{HashMap, ArrayList}
import stdx.net.http.*

main() {
    let server = ServerBuilder()
        .addr("127.0.0.1")
        .port(8080)
        .build()

    let transport = StreamableHttpServer_2025_11_25()
    transport.registerRoutes(server.distributor)

    let mcpServer = McpServer("http-hello-server", "1.0.0", transport)
    mcpServer.instructions = "An MCP server using Streamable HTTP transport"

    let toolschema = ToolInputSchema("object", HashMap<String, JsonValue>(), [])
    toolschema.addField("name", "string", "Name of the person to greet", required: true)

    let tool = Tool("hello", "Say hello", toolschema)
    mcpServer.addTool(tool, { params =>
        let name = match (params.arguments.get("name")) {
            case Some(JsonValue.String(n)) => n
            case _ => "World"
        }
        CallToolResult.text("Hello, ${name}!")
    })

    mcpServer.start()

    println("MCP HTTP server listening on http://127.0.0.1:8080")

    server.serve()
}
