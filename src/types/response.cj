package mcp.types

import encoding.json.stream.*

public class InitializeResult <: Result {
    public var meta:?Value = None
    public let protocolVersion:String = LastProtocolVersion
    public var capabilities = ServerCapabilities()
    public var serverInfo = Implementation()
    public var instructions:?String = None
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("_meta").writeValue(this.meta)
        w.writeName("protocolVersion").writeValue(this.protocolVersion)
        w.writeName("capabilities").writeValue(this.capabilities)
        w.writeName("serverInfo").writeValue(this.serverInfo)
        w.writeName("instructions").writeValue(this.instructions)
        w.endObject()
    }

    public static func fromJson(r: JsonReader): InitializeResult {
        let res = InitializeResult()
        fromJsonObject(
            r,
            ("_meta", {=> res.meta = r.readValue<Option<Value>>()}),
            ("capabilities", {=> res.capabilities = r.readValue<ServerCapabilities>()}),
            ("serverInfo", {=> res.serverInfo = r.readValue<Implementation>()}),
            ("instructions", {=> res.instructions = r.readValue<Option<String>>()}),
        )
        return res
    }
}