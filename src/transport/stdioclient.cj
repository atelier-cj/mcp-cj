package mcp.transport

import ystyle::jsonrpc.*
import std.process.{launch, ProcessRedirect, SubProcess}
import std.io.{OutputStream, InputStream}
import std.collection.*

public class StdioClientTransport <: Transport {
    private let process: SubProcess
    private let stdin: OutputStream
    private let stdout: InputStream

    // env：传给子进程的完整环境（std launch environment=Some 为整体替换语义，
    // 调用方需自行并入 PATH/LD_LIBRARY_PATH 等关键变量）；None = 继承父进程环境（默认）。
    // 提供 env 时命令按空白拆分后走全参 launch（保留单参 launch 对带参命令的支持语义）。
    public init(command: String, env!: ?HashMap<String, String> = None) {
        let proc = match (env) {
            case Some(e) =>
                let parts = command.split(' ')
                let cmd = parts[0]
                var rest = ArrayList<String>()
                for (i in 1..parts.size) { rest.add(parts[Int64(i)]) }
                let argv = Array<String>(rest.size, repeat: "")
                for (i in 0..rest.size) { argv[i] = rest[Int64(i)] }
                launch(cmd, argv, environment: Some(e),
                    stdIn: ProcessRedirect.Pipe, stdOut: ProcessRedirect.Pipe, stdErr: ProcessRedirect.Inherit)
            case None =>
                launch(command,
                    stdIn: ProcessRedirect.Pipe, stdOut: ProcessRedirect.Pipe, stdErr: ProcessRedirect.Inherit)
        }
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
