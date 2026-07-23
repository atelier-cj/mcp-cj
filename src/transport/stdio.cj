package mcp.transport

import ystyle::jsonrpc.*
import std.env.{getStdIn, getStdOut}
import std.sync.AtomicBool
import std.io.ByteBuffer
import std.convert.*
import std.unicode.*

public class StdioServerTransport <: Transport {
    private var running = AtomicBool(true)
    private let stdin = getStdIn()
    private let buf = ByteBuffer()

    public func send(data: Array<Byte>): Unit {
        getStdOut().write(data)
        getStdOut().flush()
    }

    public func receive(): ?Array<Byte> {
        while (!this.isClosed()) {
            let data = this.buf.bytes()
            let headerEnd = this.findHeaderEnd(data)
            if (headerEnd >= 0) {
                let headerStr = String.fromUtf8(data[0..headerEnd])
                let length = this.parseLen(headerStr)
                if (length >= 0) {
                    let bodyStart = headerEnd + 4
                    if (data.size >= bodyStart + length) {
                        let msgLen = bodyStart + length
                        let msg = Array<Byte>(msgLen, repeat: 0)
                        for (i in 0..msgLen) { msg[i] = data[i] }
                        this.buf.clear()
                        if (data.size > msgLen) {
                            this.buf.write(data[msgLen..data.size])
                        }
                        return Some(msg)
                    }
                }
            }
            let chunk = Array<Byte>(4096, repeat: 0)
            try {
                let n = this.stdin.read(chunk)
                if (n <= 0) { return None }
                this.buf.write(chunk[0..n])
            } catch (e: Exception) {
                return None
            }
        }
        None
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
            let t = line.trim()
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
