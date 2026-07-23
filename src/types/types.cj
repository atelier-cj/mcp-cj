package mcp.types

import jsonvalue.*
import stdx.encoding.json.stream.*
import std.collection.HashMap

public const LastProtocolVersion = "2025-11-25"

public const PARSE_ERROR = -32700
public const INVALID_REQUEST = -32600
public const METHOD_NOT_FOUND = -32601
public const INVALID_PARAMS = -32602
public const INTERNAL_ERROR = -32603

public class Implementation <: JsonSerializable & JsonDeserializable<Implementation> {
    var name: String = ""
    var version: String = ""
    public init() {}
    public init(name: String, version: String) {
        this.name = name
        this.version = version
    }
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("name").writeValue(this.name)
        w.writeName("version").writeValue(this.version)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): Implementation {
        let res = Implementation()
        fromJsonObject(r,
            ("name", {=> res.name = r.readValue<String>()}),
            ("version", {=> res.version = r.readValue<String>()})
        )
        res
    }
}

public class ServerCapabilities <: JsonSerializable & JsonDeserializable<ServerCapabilities> {
    public var resources: Option<ResourceCapabilities> = None
    public var prompts: Option<PromptCapabilities> = None
    public var tools: Option<ToolsCapabilities> = None
    public var logging: ?Bool = None
    public var tasks: ?JsonValue = None
    public var experimental: ?JsonValue = None
    public var completions: ?JsonValue = None
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.resources) { w.writeName("resources").writeValue(v) }
        if (let Some(v) <- this.prompts) { w.writeName("prompts").writeValue(v) }
        if (let Some(v) <- this.tools) { w.writeName("tools").writeValue(v) }
        if (let Some(v) <- this.logging) { w.writeName("logging").writeValue(v) }
        if (let Some(v) <- this.tasks) { w.writeName("tasks"); v.toJson(w) }
        if (let Some(v) <- this.experimental) { w.writeName("experimental"); v.toJson(w) }
        if (let Some(v) <- this.completions) { w.writeName("completions"); v.toJson(w) }
        w.endObject()
    }
    public static func fromJson(r: JsonReader): ServerCapabilities {
        let res = ServerCapabilities()
        fromJsonObject(r,
            ("resources", {=> res.resources = r.readValue<Option<ResourceCapabilities>>()}),
            ("prompts", {=> res.prompts = r.readValue<Option<PromptCapabilities>>()}),
            ("tools", {=> res.tools = r.readValue<Option<ToolsCapabilities>>()}),
            ("logging", {=> res.logging = r.readValue<Option<Bool>>()})
        )
        res
    }
}

public class ClientCapabilities <: JsonSerializable & JsonDeserializable<ClientCapabilities> {
    public var experimental: ?JsonValue = None
    public var roots: ?JsonValue = None
    public var sampling: ?JsonValue = None
    public var tasks: ?JsonValue = None
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.experimental) { w.writeName("experimental"); v.toJson(w) }
        if (let Some(v) <- this.roots) { w.writeName("roots"); v.toJson(w) }
        if (let Some(v) <- this.sampling) { w.writeName("sampling"); v.toJson(w) }
        if (let Some(v) <- this.tasks) { w.writeName("tasks"); v.toJson(w) }
        w.endObject()
    }
    public static func fromJson(r: JsonReader): ClientCapabilities {
        let res = ClientCapabilities()
        fromJsonObject(r,
            ("experimental", {=> res.experimental = r.readValue<Option<JsonValue>>()}),
            ("roots", {=> res.roots = r.readValue<Option<JsonValue>>()}),
            ("sampling", {=> res.sampling = r.readValue<Option<JsonValue>>()}),
            ("tasks", {=> res.tasks = r.readValue<Option<JsonValue>>()})
        )
        res
    }
}

public class ResourceCapabilities <: JsonSerializable & JsonDeserializable<ResourceCapabilities> {
    public var subscribe: Bool = false
    public var listChanged: Bool = false
    public init() {}
    public init(subscribe: Bool, listChanged: Bool) {
        this.subscribe = subscribe
        this.listChanged = listChanged
    }
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("subscribe").writeValue(this.subscribe)
        w.writeName("listChanged").writeValue(this.listChanged)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): ResourceCapabilities {
        let res = ResourceCapabilities()
        fromJsonObject(r,
            ("subscribe", {=> res.subscribe = r.readValue<Bool>()}),
            ("listChanged", {=> res.listChanged = r.readValue<Bool>()})
        )
        res
    }
}

public class PromptCapabilities <: JsonSerializable & JsonDeserializable<PromptCapabilities> {
    public var listChanged: Bool = false
    public init() {}
    public init(listChanged: Bool) { this.listChanged = listChanged }
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("listChanged").writeValue(this.listChanged)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): PromptCapabilities {
        let res = PromptCapabilities()
        fromJsonObject(r,
            ("listChanged", {=> res.listChanged = r.readValue<Bool>()})
        )
        res
    }
}

public class ToolsCapabilities <: JsonSerializable & JsonDeserializable<ToolsCapabilities> {
    public var listChanged: Bool = false
    public init() {}
    public init(listChanged: Bool) { this.listChanged = listChanged }
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("listChanged").writeValue(this.listChanged)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): ToolsCapabilities {
        let res = ToolsCapabilities()
        fromJsonObject(r,
            ("listChanged", {=> res.listChanged = r.readValue<Bool>()})
        )
        res
    }
}

public class InitializeResult <: JsonSerializable & JsonDeserializable<InitializeResult> {
    public let protocolVersion: String = LastProtocolVersion
    public var capabilities = ServerCapabilities()
    public var serverInfo = Implementation()
    public var instructions: ?String = None
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("protocolVersion").writeValue(this.protocolVersion)
        w.writeName("capabilities").writeValue(this.capabilities)
        w.writeName("serverInfo").writeValue(this.serverInfo)
        if (let Some(v) <- this.instructions) { w.writeName("instructions").writeValue(v) }
        w.endObject()
    }
    public static func fromJson(r: JsonReader): InitializeResult {
        let res = InitializeResult()
        fromJsonObject(r,
            ("capabilities", {=> res.capabilities = r.readValue<ServerCapabilities>()}),
            ("serverInfo", {=> res.serverInfo = r.readValue<Implementation>()}),
            ("instructions", {=> res.instructions = r.readValue<Option<String>>()})
        )
        res
    }
}

func fromJsonObject(r: JsonReader, list: Array<(String, () -> Unit)>) {
    let refs = HashMap<String, () -> Unit>(list)
    while (let Some(v) <- r.peek()) {
        match (v) {
            case BeginObject =>
                r.startObject()
                while (r.peek() != EndObject) {
                    let n = r.readName()
                    if (refs.contains(n)) { refs[n]() }
                    else { r.skip() }
                }
                r.endObject()
                break
            case _ => throw Exception()
        }
    }
}
