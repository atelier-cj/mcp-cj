package mcp.types

import encoding.json.stream.*

public interface JsonRpcMessage <: JsonDeserializable<JsonRpcMessage> & JsonSerializable {
    prop jsonrpc: String {
        get() {
            JSONRPCVersion
        }
    }
}

public interface JsonRpcRequest <: JsonRpcMessage {
    prop method: String
    // mut prop id:RequestId
    // prop params: Params
}

public class JsonRpcResponse <: JsonRpcMessage {
    let id:RequestId
    let result: Result
    public init(id:RequestId, result: Result) {
        this.id = id
        this.result = result
    }
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("id").writeValue(this.id)
        w.writeName("result").writeValue(this.result)
        w.endObject()
    }

    public static func fromJson(r: JsonReader): JsonRpcResponse {
        return JsonRpcResponse(RequestId.Int(0), EmptyResult())
    }
}

public interface Result <: JsonDeserializable<Result> & JsonSerializable {}

public class EmptyResult <: Result {
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.endObject()
    }

    public static func fromJson(r: JsonReader): EmptyResult {
        return EmptyResult()
    }
}

public interface JsonRpcNotification <: JsonRpcMessage {
    prop method: String
    prop params: Option<Params>
}

public interface Params <: JsonDeserializable<Params> & JsonSerializable {}

public class EmptyParams <: Params {
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.endObject()
    }

    public static func fromJson(r: JsonReader): EmptyParams {
        return EmptyParams()
    }
}

protected class BaseMessage {
    public var jsonrpc: String = ""
    public var method: String = ""
    public var id: ?RequestId = None
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("jsonrpc").writeValue(this.jsonrpc)
        w.writeName("method").writeValue(this.method)
        w.writeName("id").writeValue(this.id)
        w.endObject()
    }

    public static func fromJson(r: JsonReader): BaseMessage {
        let res = BaseMessage()
        fromJsonObject(
            r,
            ("jsonrpc", {=> res.jsonrpc = r.readValue<String>()}),
            ("method", {=> res.method = r.readValue<String>()}),
            ("id", {=> res.id = r.readValue<Option<RequestId>>()}),
        )
        return res
    }
}

public class NoOpMessage <: JsonRpcMessage {
    public func toJson(w: JsonWriter): Unit {
        w.writeNullValue()
    }

    public static func fromJson(r: JsonReader): NoOpMessage {
        return NoOpMessage()
    }
}

public class JsonRpcError <: JsonRpcMessage {
    public var id: ?RequestId
    public var error: Error
    public init(id: ?RequestId, error: Error) {
        this.id = id
        this.error = error
    }
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("jsonrpc").writeValue(this.jsonrpc)
        w.writeName("id").writeValue(this.id)
        w.writeName("error").writeValue(this.error)
        w.endObject()
    }

    public static func fromJson(r: JsonReader): JsonRpcError {
        let res = JsonRpcError(RequestId.Int(0), Error(0, "unkonw", None))
        fromJsonObject(
            r,
            ("id", {=> res.id = r.readValue<Option<RequestId>>()}),
            ("error", {=> res.error = r.readValue<Error>()})
        )
        return res
    }
}

public class Error <: JsonDeserializable<Error> & JsonSerializable {
    public var code: Int64
    public var mseesge: String
    public var data: ?Value
    public init(code: Int64, message: String, data: ?Value) {
        this.code = code
        this.mseesge = message
        this.data = data
    }
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("code").writeValue(this.code)
        w.writeName("mseesge").writeValue(this.mseesge)
        w.writeName("data").writeValue(this.data)
        w.endObject()
    }

    public static func fromJson(r: JsonReader): Error {
        let res = Error(0, "", None)
        fromJsonObject(
            r,
            ("code", {=> res.code = r.readValue<Int64>()}),
            ("mseesge", {=> res.mseesge = r.readValue<String>()}),
            ("data", {=> res.data = r.readValue<Option<Value>>()}),
        )
        return res
    }
}
