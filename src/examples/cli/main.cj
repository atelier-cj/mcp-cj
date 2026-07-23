package mcp.examples.cli

import jsonvalue.*
import mcp.*
import mcp.transport.*
import ystyle::jsonrpc.Result
import std.collection.HashMap
import std.env.getCommandLine

main() {
    if (let Some(cmd) <- getCommand()) {
        let transport = StdioServerTransport()
        let client = McpClient(transport)
        let info = Implementation("mcp-cli", "1.0.0")
        match (client.connect(info)) {
            case Result.Ok(_) => ()
            case Result.Err(e) =>
                println("Failed to connect: ${e}")
                return
        }

        match (cmd) {
            case "tools/list" =>
                match (client.listTools()) {
                    case Result.Ok(result) => println(JsonValue.fromObject(result).stringify())
                    case Result.Err(e) => println("Error: ${e}")
                }
            case "resources/list" =>
                match (client.listResources()) {
                    case Result.Ok(result) => println(JsonValue.fromObject(result).stringify())
                    case Result.Err(e) => println("Error: ${e}")
                }
            case "prompts/list" =>
                match (client.listPrompts()) {
                    case Result.Ok(result) => println(JsonValue.fromObject(result).stringify())
                    case Result.Err(e) => println("Error: ${e}")
                }
            case _ =>
                println("Unknown command: ${cmd}")
        }
        client.close()
    }
}

func getCommand(): ?String {
    let args = getCommandLine()
    if (args.size > 1) { Some(args[1]) }
    else { None }
}
