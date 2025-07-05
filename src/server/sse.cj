package mcp.server

import net.http.{HttpContext, Server as HttpServer, ServerBuilder, HttpStatusCode, HttpResponsePusher}
import std.net.IPSocketAddress
import std.io.ByteBuffer
import std.random.Random
import sonyflake.*

let sonyflake = Sonyflake(Setting(Random().nextUInt16()))

type SSEContextFunc = (HttpContext) -> Unit
type SSEOption = (SSEServer) -> Unit

public func WithBaseURL(baseurl:String):SSEOption {
    {s => s.baseurl = baseurl}
}

public func WithBasePath(basepath:String):SSEOption {
    {s => 
        s.basePath = if (!basepath.startsWith("/")) {
            "/" + basepath
        } else {
            basepath
        }
        if (let Some(v) <- s.basePath) {
            s.basePath = v.trimEnd('/')
        }
        s.basePath = s.basePath
        s.baseurl = "${s.baseurl}${s.basePath}"
    }
}

public func WithMessageEndpoint(endpoint:String):SSEOption {
    {s => s.messageEndpoint = endpoint}
}

public func WithSSEEndpoint(endpoint:String):SSEOption {
    {s => s.sseEndpoint = endpoint}
}

public func WithHttpServer(ser:HttpServer):SSEOption {
    {s => s.srv = ser}
}

public func WithSSEContextFunc(fn:SSEContextFunc):SSEOption {
    {s => s.contextFunc = fn}
}

class SSESession {
    
}

public class SSEServer {
    let server:McpServer
    var baseurl:?String = None
    var basePath:?String = None
    var messageEndpoint = "/message"
    var sseEndpoint = "/sse"
    var srv:?HttpServer = None
    var contextFunc:?SSEContextFunc = None
    public init(server:McpServer, opts:Array<SSEOption>) {
        this.server = server
        for (opt in opts) {
            opt(this)
        }
    }
    public func start(addr:String):Unit {
        if (this.srv.isNone()) {
            this.srv = ServerBuilder().addr(addr).build()
        }
        this.srv?.distributor.register("${this.basePath}${this.sseEndpoint}", this.handleSSE)
        this.srv?.distributor.register("${this.basePath}${this.messageEndpoint}", this.handleMessage)
        this.srv?.serve()
    }
    public func handleSSE(ctx:HttpContext):Unit {
        if (ctx.request.method != "GET") {
            ctx.responseBuilder.status(HttpStatusCode.STATUS_METHOD_NOT_ALLOWED).body('Method not allowed')
            return
        }
        ctx.responseBuilder
            .header("Content-Type", "text/event-stream")
            .header("Cache-Control", "no-cache")
            .header("Connection", "keep-alive")
            .header("Access-Control-Allow-Origin", "*")
        let pusheropt = HttpResponsePusher.getPusher(ctx)
        if (pusheropt.isNone()) {
            ctx.responseBuilder.status(HttpStatusCode.STATUS_INTERNAL_SERVER_ERROR).body('Streaming unsupported')
            return
        }
        let pusher = pusheropt.getOrThrow()
        let sessionId = sonyflake.NextID().toString()
    }
    public func handleMessage(ctx:HttpContext):Unit {
        if (ctx.request.method != "POST") {
            ctx.responseBuilder.status(HttpStatusCode.STATUS_METHOD_NOT_ALLOWED).body('Method not allowed')
            return
        }




        let writer = ByteBuffer()
        ctx.responseBuilder.body(writer)


    }
}