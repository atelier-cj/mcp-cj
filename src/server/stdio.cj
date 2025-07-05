package mcp.server

import log.Logger
import logger.JsonLogger
import std.env.{getStdIn, getStdOut, getStdErr}
import std.io.{OutputStream, InputStream, StringReader, StringWriter, ByteBuffer, BufferedInputStream}
import encoding.json.stream.{JsonReader, JsonWriter}
import mcp.types.*
import std.sync.ReentrantMutex

public class StdioServer {
    let server:McpServer
    var errlogger: Logger
    let mu = ReentrantMutex()
    public init(server:McpServer) {
        this.server = server
        this.errlogger = JsonLogger(getStdErr())
    }
    public func setErrorLogger(errlogger: Logger) {
        this.errlogger = errlogger
    }
    public func listen(stdin:InputStream, stdout:OutputStream) {
        this.server.currentClient = NotificationContext("stdio", "stdio")
        this.server.notificationCallback = {smsg =>
            if (smsg.context.clientId == "stdio") {
                try {
                    this.writeResponse(smsg.notification, stdout)
                } catch (e:Exception) {
                    this.errlogger.error("Error writing notification: ${e}")
                }
            }
        }
        let reader = StringReader(stdin)
        while (true) {
            try {
                let line = reader.readln()
                if (let Some(v) <- line) {
                    try {
                        this.processMessage(v, stdout)
                    } catch (e:Exception) {
                        this.errlogger.error("Error handling message: ${e}")
                    }
                }
            } catch (e:Exception) {
                this.errlogger.error("Error reading input: ${e}")
            }
        }
        
    }
    func processMessage(line:String,writer:OutputStream) {
        let buf = ByteBuffer(line.toArray())
        let jr = JsonReader(buf)
        try {
            let response = this.server.handleMessage(jr)
            if (let _:NoOpMessage <- response) {
                return
            }
            this.writeResponse(response, writer)
        } catch (e:Exception) {
            throw Exception("failed to write response: ${e}")
        }
    }

    func writeResponse(response:JsonRpcMessage, stdout:OutputStream) {
        synchronized(this.mu) {
            response.toJson(JsonWriter(stdout))
        }
    }
}

public func ServeStdio(server:McpServer) {
    let s = StdioServer(server)
    s.listen(getStdIn(), getStdOut())
}