package mcp.transport

import ystyle::jsonrpc.*
import std.process.{launch, ProcessRedirect, SubProcess}
import std.io.{OutputStream, InputStream}

public class StdioClientTransport <: Transport {
    private let process: SubProcess
    private let stdin: OutputStream
    private let stdout: InputStream

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
        this.stdin.write(data)
        this.stdin.flush()
    }

    public func receive(): ?Array<Byte> {
        let chunk = Array<Byte>(4096, repeat: 0)
        let n = this.stdout.read(chunk)
        if (n <= 0) { return None }
        Some(chunk[0..n])
    }

    public func isClosed(): Bool { false }
    public func close(): Unit {
        this.process.terminate(force: true)
        this.process.wait()
    }
}
