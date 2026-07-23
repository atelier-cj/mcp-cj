package mcp.transport

import ystyle::jsonrpc.*
import std.process.{launch, ProcessRedirect, SubProcess}
import std.io.{OutputStream, InputStream, ByteBuffer}
import std.convert.*
import std.unicode.*

public class StdioClientTransport <: Transport {
    private let process: SubProcess
    private let stdin: OutputStream
    private let stdout: InputStream
    private let buf = ByteBuffer()

    public init(command: String) {
        let proc = launch(command,
            stdIn: ProcessRedirect.Pipe,
            stdOut: ProcessRedirect.Pipe,
            stdErr: ProcessRedirect.Inherit)
        this.process = proc
        this.stdin = proc.stdInPipe
        this.stdout = proc.stdOutPipe
    }

    public func send(data: Array<Byte>): Unit {
        let headerEnd = this.findHeaderEnd(data)
        if (headerEnd >= 0) {
            let headerStr = String.fromUtf8(data[0..headerEnd])
            let length = this.parseLen(headerStr)
            if (length >= 0) {
                let bodyStart = headerEnd + 4
                if (data.size >= bodyStart + length) {
                    let body = data[bodyStart..(bodyStart + length)]
                    this.stdin.write(body)
                    this.stdin.write([10])
                    this.stdin.flush()
                    return
                }
            }
        }
        this.stdin.write(data)
        this.stdin.write([10])
        this.stdin.flush()
    }

    public func receive(): ?Array<Byte> {
        var result: ?Array<Byte> = None
        while (result.isNone()) {
            let data = this.buf.bytes()
            for (i in 0..data.size) {
                if (data[i] == 10) {
                    let lineSize = if (i > 0 && data[i - 1] == 13) { i - 1 } else { i }
                    let line = Array<Byte>(lineSize, repeat: 0)
                    for (j in 0..lineSize) { line[j] = data[j] }
                    let remaining = data.size - i - 1
                    if (remaining > 0) {
                        this.buf.clear()
                        this.buf.write(data[(i + 1)..data.size])
                    } else {
                        this.buf.clear()
                    }
                    let headerStr = "Content-Length: ${lineSize}"
                    let headerBytes = headerStr.toArray()
                    let framedLen = headerBytes.size + 4 + lineSize
                    let framed = Array<Byte>(framedLen, repeat: 0)
                    for (j in 0..headerBytes.size) { framed[j] = headerBytes[j] }
                    framed[headerBytes.size] = 13
                    framed[headerBytes.size + 1] = 10
                    framed[headerBytes.size + 2] = 13
                    framed[headerBytes.size + 3] = 10
                    for (j in 0..lineSize) { framed[headerBytes.size + 4 + j] = line[j] }
                    result = Some(framed)
                    break
                }
            }
            if (result.isNone()) {
                let chunk = Array<Byte>(4096, repeat: 0)
                let n = this.stdout.read(chunk)
                if (n <= 0) { return None }
                this.buf.write(chunk[0..n])
            }
        }
        result
    }

    public func isClosed(): Bool { false }
    public func close(): Unit {
        this.process.terminate(force: true)
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
}
