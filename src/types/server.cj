package mcp.types

import std.collection.HashMap
import encoding.json.stream.*

public class ServerCapabilities <: JsonDeserializable<ServerCapabilities> & JsonSerializable {
    public var resources: Option<ResourceCapabilities> = None
    public var prompts: Option<PromptCapabilities> = None
    public var tools: Option<ToolsCapabilities> = None
    public var logging:?Bool = None
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        // w.writeName("resources").writeValue(this.resources)
        w.writeName("prompts").writeValue(this.prompts)
        w.writeName("tools").writeValue(this.tools)
        w.writeName("logging").writeValue(HashMap<String,String>())
        w.endObject()
    }

    public static func fromJson(r: JsonReader): ServerCapabilities {
        let res =ServerCapabilities()
        fromJsonObject(r, 
            ("resources", {=> res.resources = r.readValue<Option<ResourceCapabilities>>()}),
            ("prompts", {=> res.prompts = r.readValue<Option<PromptCapabilities>>()}),
            ("tools", {=> res.tools = r.readValue<Option<ToolsCapabilities>>()}),
            ("logging", {=> res.logging = r.readValue<Option<Bool>>()})
        )
        return res
    }
}

public class ResourceCapabilities <: JsonDeserializable<ResourceCapabilities> & JsonSerializable {
    public var subscribe: Bool = false
    public var listChanged: Bool = false
    public init(){}
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
        let res =ResourceCapabilities()
        fromJsonObject(r, 
            ("subscribe", {=> res.subscribe = r.readValue<Bool>()}),
            ("listChanged", {=> res.listChanged = r.readValue<Bool>()})
        )
        return res
    }
}

public class PromptCapabilities <: JsonDeserializable<PromptCapabilities> & JsonSerializable {
    public var listChanged: Bool = false
    public init() {
        
    }
    public init(listChanged: Bool) {
        this.listChanged = listChanged
    }
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("listChanged").writeValue(this.listChanged)
        w.endObject()
    }

    public static func fromJson(r: JsonReader): PromptCapabilities {
        let res =PromptCapabilities()
        fromJsonObject(r, 
            ("listChanged", {=> res.listChanged = r.readValue<Bool>()})
        )
        return res
    }
}

public class ToolsCapabilities <: JsonDeserializable<ToolsCapabilities> & JsonSerializable {
    public var listChanged: Bool = false
    public init() {
        
    }
    public init(listChanged: Bool) {
        this.listChanged = listChanged
    }
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("listChanged").writeValue(this.listChanged)
        w.endObject()
    }

    public static func fromJson(r: JsonReader): ToolsCapabilities {
        let res =ToolsCapabilities()
        fromJsonObject(r, 
            ("listChanged", {=> res.listChanged = r.readValue<Bool>()})
        )
        return res
    }
}

public class Implementation <: JsonDeserializable<Implementation> & JsonSerializable {
    var name:String = ""
    var version:String = ""
    public init() {
        
    }
    public init(name:String,version:String){
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
        let res =Implementation()
        fromJsonObject(r, 
            ("name", {=> res.name = r.readValue<String>()}),
            ("version", {=> res.version = r.readValue<String>()})
        )
        return res
    }
}