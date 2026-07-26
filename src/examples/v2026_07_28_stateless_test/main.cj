package mcp.examples.v2026_07_28_stateless_test

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

    let transport = StatelessHttpServer_2026_07_28()
    transport.registerRoutes(server.distributor)

    let mcpServer = McpServer("stateless-test-server", "1.0.0", transport)

    let tool = Tool("hello", "Say hello", ToolInputSchema("object", HashMap<String, JsonValue>(), []))
    mcpServer.addTool(tool, { params => CallToolResult.text("Hello!") })

    // Register notification callback — verify server→client notifications work
    mcpServer.start()
    spawn { => server.serve() }

    synchronized(portLock) {
        while (portHolder.value == 0) {
            portCond.wait(timeout: 5 * Duration.second)
        }
    }

    let baseUrl = "http://127.0.0.1:${portHolder.value}"
    println("Server started at ${baseUrl}")

    let client = McpClient(StatelessHttpClient_2026_07_28(baseUrl))
    let info = Implementation("stateless-test-client", "1.0.0")

    println("=== Testing connect ===")
    match (client.connect(info)) {
        case Result.Ok(initResult) =>
            println("Connected! Server: ${initResult.serverInfo.name} v${initResult.serverInfo.version}")
        case Result.Err(e) =>
            println("FAIL: Connect failed: ${e}")
            transport.close()
            server.close()
            return
    }

    println("\n=== Testing tools/list ===")
    match (client.listTools()) {
        case Result.Ok(result) =>
            for (tool in result.tools) {
                println("  Tool: ${tool.name} - ${tool.description}")
            }
        case Result.Err(e) =>
            println("FAIL: listTools failed: ${e}")
    }

    // Test header validation — missing Mcp-Method header should still work (optional for some methods)
    println("\n=== Testing header validation ===")
    let rawClient2 = ClientBuilder().build()
    let badReq = HttpRequestBuilder()
        .url(baseUrl + "/")
        .header("content-type", "application/json")
        .header("accept", "application/json, text/event-stream")
        .body("{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\",\"params\":{}}")
        .post()
        .build()
    let badResp = rawClient2.send(badReq)
    // Should fail due to missing MCP-Protocol-Version
    if (badResp.status == 400) {
        println("  PASS: Missing MCP-Protocol-Version header rejected with 400")
    } else {
        println("  FAIL: Expected 400, got ${badResp.status}")
    }

    // Test Mcp-Method header validation
    let rawClient3 = ClientBuilder().build()
    let mismatchReq = HttpRequestBuilder()
        .url(baseUrl + "/")
        .header("content-type", "application/json")
        .header("accept", "application/json, text/event-stream")
        .header("MCP-Protocol-Version", "2026-07-28")
        .header("Mcp-Method", "tools/call")
        .body("{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/list\",\"params\":{}}")
        .post()
        .build()
    let mismatchResp = rawClient3.send(mismatchReq)
    if (mismatchResp.status == 400) {
        println("  PASS: Mcp-Method mismatch rejected with 400")
    } else {
        println("  FAIL: Expected 400, got ${mismatchResp.status}")
    }

    rawClient2.close()
    rawClient3.close()

    // Test subscription/listen — via raw POST to verify SSE stream works
    println("\n=== Testing subscriptions/listen ===")
    let rawClient = ClientBuilder().build()
    let listenReq = HttpRequestBuilder()
        .url(baseUrl + "/")
        .header("content-type", "application/json")
        .header("accept", "application/json, text/event-stream")
        .header("MCP-Protocol-Version", "2026-07-28")
        .header("Mcp-Method", "subscriptions/listen")
        .body("{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"subscriptions/listen\",\"params\":{\"notifications\":{\"toolsListChanged\":true}}}")
        .post()
        .build()
    let listenResp = rawClient.send(listenReq)
    let contentType = listenResp.headers.getFirst("content-type") ?? ""

    if (contentType.startsWith("text/event-stream")) {
        // Read the first SSE event (acknowledged)
        let buf = Array<Byte>(1, repeat: 0)
        let accumulated = ArrayList<Byte>()
        var foundAck = false
        for (_ in 0..10000) {
            let n: Int64
            try {
                n = listenResp.body.read(buf)
            } catch (_: Exception) {
                break
            }
            if (n <= 0) { break }
            accumulated.add(buf[0])
            let size = accumulated.size
            if (size >= 2 && accumulated[size - 2] == 10 && accumulated[size - 1] == 10) {
                let raw = Array<Byte>(accumulated.size, repeat: 0)
                for (i in 0..accumulated.size) { raw[i] = accumulated[i] }
                let text = String.fromUtf8(raw)
                for (line in text.split("\n")) {
                    if (line.startsWith("data: ")) {
                        let data = line[6..]
                        if (data.contains("notifications/subscriptions/acknowledged")) {
                            foundAck = true
                            println("  PASS: Received acknowledged notification")
                        }
                    }
                }
                accumulated.clear()
                break // Got first event
            }
        }
        if (!foundAck) {
            println("  FAIL: Did not receive acknowledged notification")
        }

        // Now test that notifyToolListChanged is sent via SSE
        println("\n=== Testing notifyToolListChanged via subscription ===")
        mcpServer.notifyToolListChanged()
        var foundNotif = false
        for (_ in 0..10000) {
            let n: Int64
            try {
                n = listenResp.body.read(buf)
            } catch (_: Exception) {
                break
            }
            if (n <= 0) { break }
            accumulated.add(buf[0])
            let size = accumulated.size
            if (size >= 2 && accumulated[size - 2] == 10 && accumulated[size - 1] == 10) {
                let raw = Array<Byte>(accumulated.size, repeat: 0)
                for (i in 0..accumulated.size) { raw[i] = accumulated[i] }
                let text = String.fromUtf8(raw)
                for (line in text.split("\n")) {
                    if (line.startsWith("data: ")) {
                        let data = line[6..]
                        if (data.contains("notifications/tools/list_changed")) {
                            foundNotif = true
                            let hasSubId = data.contains("io.modelcontextprotocol/subscriptionId")
                            if (hasSubId) {
                                println("  PASS: Received tools/list_changed with subscriptionId")
                            } else {
                                println("  FAIL: tools/list_changed missing subscriptionId")
                            }
                        }
                    }
                }
                accumulated.clear()
                break
            }
        }
        if (!foundNotif) {
            println("  FAIL: Did not receive tools/list_changed via subscription")
        }
    } else {
        println("  FAIL: Expected SSE response, got ${contentType}")
    }

    rawClient.close()
    client.close()
    transport.close()
    server.close()

    println("\n=== Stateless HTTP tests completed ===")
}
