package mcp.transport

import ystyle::jsonrpc.*
import std.env.{getStdIn, getStdOut}
import std.sync.AtomicBool
import std.convert.*

public class StdioServerTransport <: Transport {
    private var running = AtomicBool(true)
    private let stdin = getStdIn()

    public func send(data: Array<Byte>): Unit {
        let headerEnd = this.findHeaderEnd(data)
        if (headerEnd >= 0) {
            let headerStr = String.fromUtf8(data[0..headerEnd])
            let length = this.parseLen(headerStr)
            if (length >= 0) {
                let bodyStart = headerEnd + 4
                if (data.size >= bodyStart + length) {
                    let body = data[bodyStart..(bodyStart + length)]
                    getStdOut().write(body)
                    getStdOut().write([10])
                    getStdOut().flush()
                    return
                }
            }
        }
        getStdOut().write(data)
        getStdOut().write([10])
        getStdOut().flush()
    }

    public func receive(): ?Array<Byte> {
        if (let Some(line) <- this.stdin.readln()) {
            let bytes = line.toArray()
            let lineSize = bytes.size
            let headerStr = "Content-Length: ${lineSize}"
            let headerBytes = headerStr.toArray()
            let framedLen = headerBytes.size + 4 + lineSize
            let framed = Array<Byte>(framedLen, repeat: 0)
            for (i in 0..headerBytes.size) { framed[i] = headerBytes[i] }
            framed[headerBytes.size] = 13
            framed[headerBytes.size + 1] = 10
            framed[headerBytes.size + 2] = 13
            framed[headerBytes.size + 3] = 10
            for (i in 0..lineSize) { framed[headerBytes.size + 4 + i] = bytes[i] }
            Some(framed)
        } else {
            None
        }
    }

    private func findHeaderEnd(data: Array<Byte>): Int64 {
        if (data.size < 4) { return -1 }
        let end = data.size - 4
        var i: Int64 = 0
        while (i <= end) {
            if (data[i] == 13 && data[i + 1] == 10 && data[i + 2] == 13 && data[i + 3] == 10) {
                return i
            }
            i++
        }
        -1
    }

    private func parseLen(header: String): Int64 {
        let lines = header.split('\n')
        for (line in lines) {
            let t = line.trimAscii()
            if (t.startsWith("Content-Length:")) {
                let parts = t.split(":")
                if (parts.size >= 2) {
                    match (Int64.tryParse(parts[1].trimAscii())) {
                        case Some(v) => return v
                        case _ => return -1
                    }
                }
            }
        }
        -1
    }

    public func isClosed(): Bool { !this.running.load() }
    public func close(): Unit { this.running.store(false) }
}
