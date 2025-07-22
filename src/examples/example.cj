package mcp.examples

import mcp.{server.*, types.*}

main() {
    let s = McpServer("test", "1.0.0", WithLogging())
    let tool = Tool(
        "hello_world",
        withDescription("Say hello to someone"),
        withString("name", descriptionProperty("Name of the person to greet")),
    )
    s.addTool(
        tool,
        {
            req =>
            var name = (req.params.arguments.get("name")?.asString()).flatten() ?? "World"
            return CallToolResult.text("Hello, ${name}")
        }
    )
    ServeStdio(s)
}
