package mcp.transport

import ystyle::jsonrpc.*
import std.env.{getStdIn, getStdOut}
import std.sync.AtomicBool

public class StdioServerTransport <: Transport {
    private var running = AtomicBool(true)

    public func send(data: Array<Byte>): Unit {
        getStdOut().write(data)
        getStdOut().flush()
    }

    public func receive(): ?Array<Byte> {
        if (let Some(line) <- getStdIn().readln()) {
            let chars = line.toArray()
            let bytes = Array<Byte>(chars.size + 1, repeat: 0)
            for (i in 0..chars.size) { bytes[i] = chars[i] }
            bytes[chars.size] = 10
            Some(bytes)
        } else {
            None
        }
    }

    public func isClosed(): Bool { !this.running.load() }
    public func close(): Unit { this.running.store(false) }
}
