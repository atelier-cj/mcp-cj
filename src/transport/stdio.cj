package mcp.transport

import ystyle::jsonrpc.*
import std.env.{getStdIn, getStdOut}
import std.sync.AtomicBool

public class StdioServerTransport <: Transport {
    private var running = AtomicBool(true)

    public func send(data: Array<Byte>): Unit {
        let stdout = getStdOut()
        stdout.writeln(data)
        stdout.flush()
    }

    public func receive(): ?Array<Byte> {
        let stdin = getStdIn()
        if (let Some(line) <- stdin.readln()) {
            Some(line.toArray())
        } else {
            None
        }
    }

    public func isClosed(): Bool {
        !this.running.load()
    }

    public func close(): Unit {
        this.running.store(false)
    }
}
