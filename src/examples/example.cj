package mcp.examples

import std.collection.HashMap
import mcp.server.*
import mcp.types.*
import encoding.json.stream.*
import std.env.{ConsoleWriter, getStdOut}

main() {
    let s = McpServer("test", "1.0.0", WithLogging())
    let tool = Tool("hello_world", "Say hello to someone")
    tool.inputSchema.addField("name", "string", "Name of the person to greet")
    s.addTool(
        tool,
        {
            req =>
            let name = req.params.arguments.get("name")
            let result = CallToolResult()
            result.content = [
                Value.Map(
                    HashMap<String, Value>(
                        ("tpye", Value.String("text")),
                        ("text", Value.String("hello, ${name}")),
                    )
                )
            ]
            return result
        }
    )
    ServeStdio(s)
}
