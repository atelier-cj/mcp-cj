package mcp.examples.testclient

import jsonvalue.*
import mcp.*
import mcp.transport.*
import ystyle::jsonrpc.Result
import std.collection.{HashMap, ArrayList}

main() {
    let transport = StdioClientTransport("./target/release/bin/mcp.examples.basic")
    let client = McpClient(transport)
    let info = Implementation("test-client", "1.0.0")

    println("=== Testing connect ===")
    match (client.connect(info)) {
        case Result.Ok(initResult) =>
            println("Connected! Server: ${initResult.serverInfo.name} v${initResult.serverInfo.version}")
            println("Protocol: ${initResult.protocolVersion}")
        case Result.Err(e) =>
            println("FAIL: Connect failed: ${e}")
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
    match (client.callTool("hello_world", arguments: args)) {
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
    println("\n=== All tests completed ===")
}
