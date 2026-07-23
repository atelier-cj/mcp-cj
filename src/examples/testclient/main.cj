package mcp.examples.testclient

import jsonvalue.*
import mcp.*
import mcp.transport.*
import ystyle::jsonrpc.{Transport, Result}
import std.io.ByteBuffer
import std.collection.{HashMap, ArrayList}

public class PipeTransport <: Transport {
    private var peer: ?PipeTransport = None
    private let buf = ByteBuffer()
    private var peerBuf: ?ByteBuffer = None

    public init() {}

    public func link(other: PipeTransport): Unit {
        this.peer = other
        this.peerBuf = other.buf
        other.peer = this
        other.peerBuf = this.buf
    }

    public func send(data: Array<Byte>): Unit {
        if (let Some(buf) <- this.peerBuf) {
            buf.write(data)
        }
    }

    public func receive(): ?Array<Byte> {
        var result: ?Array<Byte> = None
        while (result.isNone()) {
            let data = this.buf.bytes()
            if (data.size > 0) {
                this.buf.clear()
                result = Some(data)
            } else {
                sleep(Duration.millisecond * 10)
            }
        }
        result
    }

    public func isClosed(): Bool { false }
    public func close(): Unit {}
}

main() {
    let t1 = PipeTransport()
    let t2 = PipeTransport()
    t1.link(t2)

    let server = McpServer("test-server", "1.0.0", t1)
    spawn { server.serve() }
    sleep(Duration.millisecond * 100)

    let client = McpClient(t2)
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
