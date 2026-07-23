package mcp.types

import jsonvalue.*
import stdx.encoding.json.stream.*
import std.collection.{HashMap, ArrayList}

public class McpResource <: JsonSerializable & JsonDeserializable<McpResource> {
    public var uri: String = ""
    public var name: String = ""
    public var description: ?String = None
    public var mimeType: ?String = None
    public var size: ?Int64 = None
    public var annotations: ?JsonValue = None
    public init() {}
    public init(uri: String, name: String) { this.uri = uri; this.name = name }
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("uri").writeValue(this.uri)
        w.writeName("name").writeValue(this.name)
        if (let Some(v) <- this.description) { w.writeName("description").writeValue(v) }
        if (let Some(v) <- this.mimeType) { w.writeName("mimeType").writeValue(v) }
        if (let Some(v) <- this.size) { w.writeName("size").writeValue(v) }
        if (let Some(v) <- this.annotations) { w.writeName("annotations"); v.toJson(w) }
        w.endObject()
    }
    public static func fromJson(r: JsonReader): McpResource {
        let res = McpResource()
        fromJsonObject(r,
            ("uri", {=> res.uri = r.readValue<String>()}),
            ("name", {=> res.name = r.readValue<String>()}),
            ("description", {=> res.description = r.readValue<Option<String>>()}),
            ("mimeType", {=> res.mimeType = r.readValue<Option<String>>()}),
            ("size", {=> res.size = r.readValue<Option<Int64>>()}),
            ("annotations", {=> res.annotations = r.readValue<Option<JsonValue>>()})
        )
        res
    }
}

public class ResourceContents <: JsonSerializable & JsonDeserializable<ResourceContents> {
    public var uri: String = ""
    public var mimeType: ?String = None
    public init() {}
    public init(uri: String) { this.uri = uri }
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("uri").writeValue(this.uri)
        if (let Some(v) <- this.mimeType) { w.writeName("mimeType").writeValue(v) }
        w.endObject()
    }
    public static func fromJson(r: JsonReader): ResourceContents {
        let res = ResourceContents()
        fromJsonObject(r,
            ("uri", {=> res.uri = r.readValue<String>()}),
            ("mimeType", {=> res.mimeType = r.readValue<Option<String>>()})
        )
        res
    }
}

public class TextResourceContents <: JsonSerializable & JsonDeserializable<TextResourceContents> {
    public var uri: String = ""
    public var text: String = ""
    public var mimeType: ?String = None
    public init() {}
    public init(uri: String, text: String) { this.uri = uri; this.text = text }
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("uri").writeValue(this.uri)
        w.writeName("text").writeValue(this.text)
        if (let Some(v) <- this.mimeType) { w.writeName("mimeType").writeValue(v) }
        w.endObject()
    }
    public static func fromJson(r: JsonReader): TextResourceContents {
        let res = TextResourceContents()
        fromJsonObject(r,
            ("uri", {=> res.uri = r.readValue<String>()}),
            ("text", {=> res.text = r.readValue<String>()}),
            ("mimeType", {=> res.mimeType = r.readValue<Option<String>>()})
        )
        res
    }
}

public class BlobResourceContents <: JsonSerializable & JsonDeserializable<BlobResourceContents> {
    public var uri: String = ""
    public var blob: String = ""
    public var mimeType: ?String = None
    public init() {}
    public init(uri: String, blob: String) { this.uri = uri; this.blob = blob }
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("uri").writeValue(this.uri)
        w.writeName("blob").writeValue(this.blob)
        if (let Some(v) <- this.mimeType) { w.writeName("mimeType").writeValue(v) }
        w.endObject()
    }
    public static func fromJson(r: JsonReader): BlobResourceContents {
        let res = BlobResourceContents()
        fromJsonObject(r,
            ("uri", {=> res.uri = r.readValue<String>()}),
            ("blob", {=> res.blob = r.readValue<String>()}),
            ("mimeType", {=> res.mimeType = r.readValue<Option<String>>()})
        )
        res
    }
}

public class McpResourceTemplate <: JsonSerializable & JsonDeserializable<McpResourceTemplate> {
    public var uriTemplate: String = ""
    public var name: String = ""
    public var description: ?String = None
    public var mimeType: ?String = None
    public var annotations: ?JsonValue = None
    public init() {}
    public init(uriTemplate: String, name: String) { this.uriTemplate = uriTemplate; this.name = name }
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("uriTemplate").writeValue(this.uriTemplate)
        w.writeName("name").writeValue(this.name)
        if (let Some(v) <- this.description) { w.writeName("description").writeValue(v) }
        if (let Some(v) <- this.mimeType) { w.writeName("mimeType").writeValue(v) }
        if (let Some(v) <- this.annotations) { w.writeName("annotations"); v.toJson(w) }
        w.endObject()
    }
    public static func fromJson(r: JsonReader): McpResourceTemplate {
        let res = McpResourceTemplate()
        fromJsonObject(r,
            ("uriTemplate", {=> res.uriTemplate = r.readValue<String>()}),
            ("name", {=> res.name = r.readValue<String>()}),
            ("description", {=> res.description = r.readValue<Option<String>>()}),
            ("mimeType", {=> res.mimeType = r.readValue<Option<String>>()}),
            ("annotations", {=> res.annotations = r.readValue<Option<JsonValue>>()})
        )
        res
    }
}

public class ResourceUpdatedNotificationParams <: JsonSerializable & JsonDeserializable<ResourceUpdatedNotificationParams> {
    public var uri: String = ""
    public init() {}
    public init(uri: String) { this.uri = uri }
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("uri").writeValue(this.uri)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): ResourceUpdatedNotificationParams {
        let res = ResourceUpdatedNotificationParams()
        fromJsonObject(r, ("uri", {=> res.uri = r.readValue<String>()}))
        res
    }
}

// ---- List/Read request/result types ----

public class ListResourcesRequest <: JsonSerializable & JsonDeserializable<ListResourcesRequest> {
    public var method: String = "resources/list"
    public var params: ?PaginatedRequest = None
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("method").writeValue(this.method)
        if (let Some(v) <- this.params) { w.writeName("params").writeValue(v) }
        w.endObject()
    }
    public static func fromJson(r: JsonReader): ListResourcesRequest {
        let res = ListResourcesRequest()
        fromJsonObject(r,
            ("method", {=> res.method = r.readValue<String>()}),
            ("params", {=> res.params = r.readValue<Option<PaginatedRequest>>()})
        )
        res
    }
}

public class ListResourcesResult <: JsonSerializable & JsonDeserializable<ListResourcesResult> {
    public var resources = ArrayList<McpResource>()
    public var nextCursor: ?Cursor = None
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("resources").writeValue(this.resources)
        if (let Some(v) <- this.nextCursor) { w.writeName("nextCursor").writeValue(v) }
        w.endObject()
    }
    public static func fromJson(r: JsonReader): ListResourcesResult {
        let res = ListResourcesResult()
        fromJsonObject(r,
            ("resources", {=> res.resources = r.readValue<ArrayList<McpResource>>()}),
            ("nextCursor", {=> res.nextCursor = r.readValue<Option<Cursor>>()})
        )
        res
    }
}

public class ReadResourceRequestParams <: JsonSerializable & JsonDeserializable<ReadResourceRequestParams> {
    public var uri: String = ""
    public init() {}
    public init(uri: String) { this.uri = uri }
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("uri").writeValue(this.uri)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): ReadResourceRequestParams {
        let res = ReadResourceRequestParams()
        fromJsonObject(r, ("uri", {=> res.uri = r.readValue<String>()}))
        res
    }
}

public class ReadResourceResult <: JsonSerializable & JsonDeserializable<ReadResourceResult> {
    public var contents = ArrayList<ResourceContents>()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("contents").writeValue(this.contents)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): ReadResourceResult {
        let res = ReadResourceResult()
        fromJsonObject(r,
            ("contents", {=> res.contents = r.readValue<ArrayList<ResourceContents>>()})
        )
        res
    }
}

public class ListResourceTemplatesResult <: JsonSerializable & JsonDeserializable<ListResourceTemplatesResult> {
    public var resourceTemplates = ArrayList<McpResourceTemplate>()
    public var nextCursor: ?Cursor = None
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("resourceTemplates").writeValue(this.resourceTemplates)
        if (let Some(v) <- this.nextCursor) { w.writeName("nextCursor").writeValue(v) }
        w.endObject()
    }
    public static func fromJson(r: JsonReader): ListResourceTemplatesResult {
        let res = ListResourceTemplatesResult()
        fromJsonObject(r,
            ("resourceTemplates", {=> res.resourceTemplates = r.readValue<ArrayList<McpResourceTemplate>>()}),
            ("nextCursor", {=> res.nextCursor = r.readValue<Option<Cursor>>()})
        )
        res
    }
}
