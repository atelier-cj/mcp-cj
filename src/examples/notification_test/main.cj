package mcp.examples.notification_test

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

class NotifState {
    var receivedInitialized: Bool = false
    var receivedToolListChanged: Bool = false
    var receivedResourceListChanged: Bool = false
    var receivedResourceUpdated: Bool = false
    var receivedPromptListChanged: Bool = false
    var receivedLogMessage: Bool = false
    var receivedProgress: Bool = false
    var receivedCancelled: Bool = false
    var receivedRootsListChanged: Bool = false
    var lastLogLevel: ?LoggingLevel = None
    var lastProgress: Float64 = 0.0
    var lastCancelledReason: ?String = None
}

main() {
    let portLock = Mutex()
    let portCond = synchronized(portLock) { portLock.condition() }
    let portHolder = PortHolder()

    let notifLock = Mutex()
    let notifCond = synchronized(notifLock) { notifLock.condition() }
    let serverNotif = NotifState()

    let clientLock = Mutex()
    let clientCond = synchronized(clientLock) { clientLock.condition() }
    let clientNotif = NotifState()

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

    let transport = SessionHttpServerTransport()
    transport.registerRoutes(server.distributor)

    let mcpServer = McpServer("notif-test-server", "1.0.0", transport)
    mcpServer.instructions = "Notification e2e test server"

    let tool = Tool("hello", "Say hello", ToolInputSchema("object", HashMap<String, JsonValue>(), []))
    mcpServer.addTool(tool, { params => CallToolResult.text("Hello!") })

    // Register server-side notification callbacks (receiving Client→Server notifications)
    mcpServer.setOnInitialized({ =>
        synchronized(notifLock) {
            serverNotif.receivedInitialized = true
            notifCond.notifyAll()
        }
    })

    mcpServer.setOnCancelled({ params =>
        synchronized(notifLock) {
            serverNotif.receivedCancelled = true
            serverNotif.lastCancelledReason = params.reason
            notifCond.notifyAll()
        }
    })

    mcpServer.setOnProgress({ params =>
        synchronized(notifLock) {
            serverNotif.receivedProgress = true
            serverNotif.lastProgress = params.progress
            notifCond.notifyAll()
        }
    })

    mcpServer.setOnRootsListChanged({ =>
        synchronized(notifLock) {
            serverNotif.receivedRootsListChanged = true
            notifCond.notifyAll()
        }
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

    let client = McpClient(SessionHttpClientTransport(baseUrl))
    let info = Implementation("notif-test-client", "1.0.0")

    // Register client-side notification callback (receiving Server→Client notifications)
    client.setNotificationCallback({ notif =>
        synchronized(clientLock) {
            match (notif.method) {
                case "notifications/tools/list_changed" =>
                    clientNotif.receivedToolListChanged = true
                    clientCond.notifyAll()
                case "notifications/resources/list_changed" =>
                    clientNotif.receivedResourceListChanged = true
                    clientCond.notifyAll()
                case "notifications/resources/updated" =>
                    clientNotif.receivedResourceUpdated = true
                    clientCond.notifyAll()
                case "notifications/prompts/list_changed" =>
                    clientNotif.receivedPromptListChanged = true
                    clientCond.notifyAll()
                case "notifications/message" =>
                    clientNotif.receivedLogMessage = true
                    clientCond.notifyAll()
                case "notifications/progress" =>
                    clientNotif.receivedProgress = true
                    clientCond.notifyAll()
                case "notifications/cancelled" =>
                    clientNotif.receivedCancelled = true
                    clientCond.notifyAll()
                case _ => ()
            }
        }
    })

    // Connect
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

    func waitForClientCond(state: NotifState): Bool {
        synchronized(clientLock) {
            for (_ in 0..50) {
                if (state.receivedToolListChanged ||
                    state.receivedResourceListChanged ||
                    state.receivedResourceUpdated ||
                    state.receivedPromptListChanged ||
                    state.receivedLogMessage ||
                    state.receivedProgress ||
                    state.receivedCancelled) {
                    return true
                }
                clientCond.wait(timeout: 100 * Duration.millisecond)
            }
            false
        }
    }

    func waitForServerCond(state: NotifState): Bool {
        synchronized(notifLock) {
            for (_ in 0..50) {
                if (state.receivedCancelled ||
                    state.receivedProgress ||
                    state.receivedRootsListChanged) {
                    return true
                }
                notifCond.wait(timeout: 100 * Duration.millisecond)
            }
            false
        }
    }

    // ===== Test 1: Server emits notifyToolListChanged → Client receives =====
    println("\n=== Test 1: Server→Client notifyToolListChanged ===")
    mcpServer.notifyToolListChanged()
    if (waitForClientCond(clientNotif)) {
        println("  PASS: Client received notifications/tools/list_changed")
    } else {
        println("  FAIL: Client did not receive notifications/tools/list_changed")
    }

    // ===== Test 2: Server emits notifyResourceListChanged → Client receives =====
    println("\n=== Test 2: Server→Client notifyResourceListChanged ===")
    mcpServer.notifyResourceListChanged()
    if (waitForClientCond(clientNotif)) {
        println("  PASS: Client received notifications/resources/list_changed")
    } else {
        println("  FAIL: Client did not receive notifications/resources/list_changed")
    }

    // ===== Test 3: Server emits notifyResourceUpdated → Client receives =====
    println("\n=== Test 3: Server→Client notifyResourceUpdated ===")
    mcpServer.notifyResourceUpdated("file:///test.txt")
    if (waitForClientCond(clientNotif)) {
        println("  PASS: Client received notifications/resources/updated")
    } else {
        println("  FAIL: Client did not receive notifications/resources/updated")
    }

    // ===== Test 4: Server emits notifyPromptListChanged → Client receives =====
    println("\n=== Test 4: Server→Client notifyPromptListChanged ===")
    mcpServer.notifyPromptListChanged()
    if (waitForClientCond(clientNotif)) {
        println("  PASS: Client received notifications/prompts/list_changed")
    } else {
        println("  FAIL: Client did not receive notifications/prompts/list_changed")
    }

    // ===== Test 5: Server emits notifyLogMessage → Client receives =====
    println("\n=== Test 5: Server→Client notifyLogMessage ===")
    mcpServer.notifyLogMessage(LoggingLevel.Info, JsonValue.String("Server started"), logger: "test")
    if (waitForClientCond(clientNotif)) {
        println("  PASS: Client received notifications/message")
    } else {
        println("  FAIL: Client did not receive notifications/message")
    }

    // ===== Test 6: Server emits notifyProgress → Client receives =====
    println("\n=== Test 6: Server→Client notifyProgress ===")
    clientNotif.receivedProgress = false
    mcpServer.notifyProgress(JsonValue.String("token-1"), 50.0, total: 100.0, message: "Processing")
    if (waitForClientCond(clientNotif)) {
        println("  PASS: Client received notifications/progress")
    } else {
        println("  FAIL: Client did not receive notifications/progress")
    }

    // ===== Test 7: Server emits notifyCancelled → Client receives =====
    println("\n=== Test 7: Server→Client notifyCancelled ===")
    clientNotif.receivedCancelled = false
    mcpServer.notifyCancelled(JsonValue.Number(42.0), reason: "Server shutdown")
    if (waitForClientCond(clientNotif)) {
        println("  PASS: Client received notifications/cancelled")
    } else {
        println("  FAIL: Client did not receive notifications/cancelled")
    }

    // ===== Test 8: Client→Server cancelRequest =====
    println("\n=== Test 8: Client→Server notifyCancelled ===")
    serverNotif.receivedCancelled = false
    client.cancelRequest(JsonValue.Number(1.0), reason: "Test cancellation")
    if (waitForServerCond(serverNotif)) {
        println("  PASS: Server received notifications/cancelled with reason: ${serverNotif.lastCancelledReason}")
    } else {
        println("  FAIL: Server did not receive notifications/cancelled")
    }

    // ===== Test 9: Client→Server notifyProgress =====
    println("\n=== Test 9: Client→Server notifyProgress ===")
    serverNotif.receivedProgress = false
    client.notifyProgress(JsonValue.String("ct-1"), 75.0, total: 100.0, message: "Client processing")
    if (waitForServerCond(serverNotif)) {
        println("  PASS: Server received notifications/progress: ${serverNotif.lastProgress}")
    } else {
        println("  FAIL: Server did not receive notifications/progress")
    }

    // ===== Test 10: Client→Server notifyRootsListChanged =====
    println("\n=== Test 10: Client→Server notifyRootsListChanged ===")
    serverNotif.receivedRootsListChanged = false
    client.notifyRootsListChanged()
    if (waitForServerCond(serverNotif)) {
        println("  PASS: Server received notifications/roots/list_changed")
    } else {
        println("  FAIL: Server did not receive notifications/roots/list_changed")
    }

    // Cleanup
    client.close()
    transport.close()
    server.close()

    println("\n=== Notification e2e tests completed ===")
}
