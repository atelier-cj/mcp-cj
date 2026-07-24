package mcp.examples.http_testclient

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

    let transport = StreamableHttpServerTransport()
    transport.registerRoutes(server.distributor)

    let mcpServer = McpServer("http-test-server", "1.0.0", transport)

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

    let client = McpClient(StreamableHttpClientTransport(baseUrl))
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

    client.close()
    transport.close()
    server.close()
    println("\n=== All HTTP e2e tests completed ===")
}
