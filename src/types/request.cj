package mcp.types

import std.collection.HashMap
import encoding.json.stream.*

public interface ClientRequest {}

public class InitializeRequest <: ClientRequest & JsonRpcRequest & JsonDeserializable<InitializeRequest> {
    var params = InitializeRequestParams()
    public prop method: String {
        get() {
            "initialize"
        }
    }
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("jsonrpc").writeValue(this.jsonrpc)
        w.writeName("method").writeValue(this.method)
        w.writeName("params").writeValue(this.params)
        w.endObject()
    }

    public static func fromJson(r: JsonReader): InitializeRequest {
        let res = InitializeRequest()
        fromJsonObject(r, 
            ("params", {=> res.params = r.readValue<InitializeRequestParams>() })
        )
        return res
    }
}

public class InitializeRequestParams <: JsonDeserializable<InitializeRequestParams> & JsonSerializable {
    var protocolVersion: String = ""
    var capabilities =  ClientCapabilities()
    var clienfInfo = Implementation()
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("protocolVersion").writeValue(this.protocolVersion)
        w.endObject()
    }

    public static func fromJson(r: JsonReader): InitializeRequestParams {
        let res = InitializeRequestParams()
        fromJsonObject(
            r,
        )
        return res
    }
}

public class ClientCapabilities <: JsonDeserializable<ClientCapabilities> & JsonSerializable {
    var experimental: Option<HashMap<String, Value>> = None
    var roots: Option<ClientCapabilityRoot> = None
    var simpling: Option<Value> = None
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("experimental").writeValue(this.experimental)
        w.writeName("roots").writeValue(this.roots)
        w.writeName("simpling").writeValue(this.simpling)
        w.endObject()
    }

    public static func fromJson(r: JsonReader): ClientCapabilities {
        let res = ClientCapabilities()
        fromJsonObject(
            r,
            ("experimental", {=> res.experimental = r.readValue<Option<HashMap<String, Value>>>()}),
            ("roots", {=> res.roots = r.readValue<Option<ClientCapabilityRoot>>()}),
            ("simpling", {=> res.simpling = r.readValue<Option<Value>>()}),
        )
        return res
    }
}

public class ClientCapabilityRoot <: JsonDeserializable<ClientCapabilityRoot> & JsonSerializable {
    var listChanged: Option<Bool> = None
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("listChanged").writeValue(this.listChanged)
        w.endObject()
    }

    public static func fromJson(r: JsonReader): ClientCapabilityRoot {
        let res = ClientCapabilityRoot()
        fromJsonObject(
            r,
            ("listChanged", {=> res.listChanged = r.readValue<Option<Bool>>()})
        )
        return res
    }
}

public class PingRequest <: JsonRpcRequest & JsonDeserializable<PingRequest>{
    public prop method:String {
        get() {
            "ping"
        }
    }
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("jsonrpc").writeValue(this.jsonrpc)
        w.writeName("method").writeValue(this.method)
        w.endObject()
    }

    public static func fromJson(r: JsonReader): PingRequest {
        let res = PingRequest()
        return res
    }
}
