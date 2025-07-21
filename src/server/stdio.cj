package mcp.server

import log.{Logger, LogLevel}
import logger.{TextLogger}
import std.env.{getStdIn, getStdOut, getStdErr, ConsoleReader, ConsoleWriter}
import std.io.{OutputStream, InputStream, StringReader, StringWriter, ByteBuffer, BufferedInputStream}
import std.fs.{File, OpenMode}
import encoding.json.stream.{JsonReader, JsonWriter}
import mcp.types.*
import std.sync.ReentrantMutex

public class StdioServer {
    let server: McpServer
    var errlogger: Logger
    let mu = ReentrantMutex()
    public init(server: McpServer) {
        this.server = server
        let jl = TextLogger(File("mcp.log", OpenMode.Append))
        jl.level = LogLevel.ALL
        this.errlogger = jl
        this.errlogger.info("Starting stdio server")
    }
    public func setErrorLogger(errlogger: Logger) {
        this.errlogger = errlogger
    }
    public func listen(stdin: ConsoleReader, stdout: ConsoleWriter) {
        this.server.currentClient = NotificationContext("stdio", "stdio")
        this.server.notificationCallback = {
            smsg => if (smsg.context.clientId == "stdio") {
                try {
                    this.writeResponse(smsg.notification, stdout)
                } catch (e: Exception) {
                    this.errlogger.error("Error writing notification: ${e}")
                }
            }
        }
        this.errlogger.info("listening for messages from stdin")
        while (true) {
            try {
                if (let Some(v) <- stdin.readln()) {
                    try {
                        this.errlogger.info("read line from stdin: ", ("msg", v))
                        this.processMessage(v, stdout)
                    } catch (e: Exception) {
                        this.errlogger.error("Error handling message: ${e}")
                    }
                }
            } catch (e: Exception) {
                this.errlogger.error("Error reading input: ${e}")
            }
        }
    }
    func processMessage(line: String, writer: ConsoleWriter) {
        let jsonBytes = line.toArray()
        this.errlogger.info("Received message: ${line}")
        try {
            let response = this.server.handleMessage(jsonBytes)
            if (let _: NoOpMessage <- response) {
                this.errlogger.error("Received message, NoOpMessage")
                return
            }
            this.writeResponse(response, writer)
        } catch (e: Exception) {
            throw Exception("failed to write response: ${e}")
        }
    }

    func writeResponse(response: JsonRpcMessage, stdout: ConsoleWriter) {
        this.errlogger.info("Writing response")
        synchronized(this.mu) {
            var buff = ByteBuffer()
            let jw = JsonWriter(buff)
            response.toJson(jw)
            jw.flush()
            buff.flush()
            let bs = buff.bytes()
            this.errlogger.info("Writing: ${String.fromUtf8(bs)}")
            stdout.writeln(bs)
            stdout.flush()
        }
    }
}

public func ServeStdio(server: McpServer) {
    let s = StdioServer(server)
    s.listen(getStdIn(), getStdOut())
}
