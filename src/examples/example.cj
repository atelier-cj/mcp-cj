package mcp.examples
import std.collection.HashMap
import mcp.server.*
import mcp.types.*

main() {
    let s = McpServer("test", "1.0.0", WithLogging())
    let tool = Tool("hello_world", "Say hello to someone")
    tool.inputSchema.addField("name", "string", "Name of the person to greet")
    s.addTool(tool, {req =>
        let name = req.params.name
        let result = CallToolResult()
        result.content = [
            Value.from(HashMap<String, String>(
                ("type", "text"),
                ("text", "hello, ${name}"),
            ))
        ]
        return result
    })
    ServeStdio(s)
}