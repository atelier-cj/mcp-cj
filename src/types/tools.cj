package mcp.types

import jsonvalue.*
import stdx.encoding.json.stream.*
import std.collection.{HashMap, ArrayList}

public class Tool <: JsonSerializable & JsonDeserializable<Tool> {
    public var name: String = ""
    public var description: String = ""
    public var inputSchema = ToolInputSchema()
    public var annotations: ?ToolAnnotations = None
    public init() {}
    public init(name: String, description: String, inputSchema: ToolInputSchema) {
        this.name = name
        this.description = description
        this.inputSchema = inputSchema
    }
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("name").writeValue(this.name)
        w.writeName("description").writeValue(this.description)
        w.writeName("inputSchema").writeValue(this.inputSchema)
        if (let Some(v) <- this.annotations) { w.writeName("annotations").writeValue(v) }
        w.endObject()
    }
    public static func fromJson(r: JsonReader): Tool {
        let res = Tool()
        fromJsonObject(r,
            ("name", {=> res.name = r.readValue<String>()}),
            ("description", {=> res.description = r.readValue<String>()}),
            ("inputSchema", {=> res.inputSchema = r.readValue<ToolInputSchema>()}),
            ("annotations", {=> res.annotations = r.readValue<Option<ToolAnnotations>>()})
        )
        res
    }
}

public class ToolAnnotations <: JsonSerializable & JsonDeserializable<ToolAnnotations> {
    public var title: ?String = None
    public var destructiveHint: ?Bool = None
    public var idempotentHint: ?Bool = None
    public var openWorldHint: ?Bool = None
    public var readOnlyHint: ?Bool = None
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.title) { w.writeName("title").writeValue(v) }
        if (let Some(v) <- this.destructiveHint) { w.writeName("destructiveHint").writeValue(v) }
        if (let Some(v) <- this.idempotentHint) { w.writeName("idempotentHint").writeValue(v) }
        if (let Some(v) <- this.openWorldHint) { w.writeName("openWorldHint").writeValue(v) }
        if (let Some(v) <- this.readOnlyHint) { w.writeName("readOnlyHint").writeValue(v) }
        w.endObject()
    }
    public static func fromJson(r: JsonReader): ToolAnnotations {
        let res = ToolAnnotations()
        fromJsonObject(r,
            ("title", {=> res.title = r.readValue<Option<String>>()}),
            ("destructiveHint", {=> res.destructiveHint = r.readValue<Option<Bool>>()}),
            ("idempotentHint", {=> res.idempotentHint = r.readValue<Option<Bool>>()}),
            ("openWorldHint", {=> res.openWorldHint = r.readValue<Option<Bool>>()}),
            ("readOnlyHint", {=> res.readOnlyHint = r.readValue<Option<Bool>>()})
        )
        res
    }
}

public class ToolInputSchema <: JsonSerializable & JsonDeserializable<ToolInputSchema> {
    public var typ: String = "object"
    public var properties = HashMap<String, JsonValue>()
    public var required = ArrayList<String>()
    public init() {}
    public init(typ: String, properties: HashMap<String, JsonValue>, required: Array<String>) {
        this.typ = typ
        this.properties = properties
        this.required = ArrayList<String>(required)
    }
    public func addField(name: String, typ: String, description: String, required!: Bool = false) {
        if (required) { this.required.add(name) }
        let field = HashMap<String, JsonValue>()
        field.add("type", JsonValue.String(typ))
        field.add("description", JsonValue.String(description))
        this.properties.add(name, JsonValue.Map(field))
    }
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("type").writeValue(this.typ)
        w.writeName("properties").writeValue(this.properties)
        w.writeName("required").writeValue(this.required)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): ToolInputSchema {
        let res = ToolInputSchema()
        fromJsonObject(r,
            ("type", {=> res.typ = r.readValue<String>()}),
            ("properties", {=> res.properties = r.readValue<HashMap<String, JsonValue>>()}),
            ("required", {=> res.required = r.readValue<ArrayList<String>>()})
        )
        res
    }
}

public class CallToolResult <: JsonSerializable & JsonDeserializable<CallToolResult> {
    public var content = ArrayList<ContentBlock>()
    public var isError: Bool = false
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("content").writeValue(this.content)
        w.writeName("isError").writeValue(this.isError)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): CallToolResult {
        let res = CallToolResult()
        fromJsonObject(r,
            ("content", {=> res.content = r.readValue<ArrayList<ContentBlock>>()}),
            ("isError", {=> res.isError = r.readValue<Bool>()})
        )
        res
    }
    public static func text(text: String): CallToolResult {
        CallToolResult(
            ArrayList<ContentBlock>([ContentBlock.Text(TextContent(text))]),
            false
        )
    }
}

public class CallToolRequest <: JsonSerializable & JsonDeserializable<CallToolRequest> {
    public var method: String = "tools/call"
    public var params = ToolRequestParams()
    public init() {}
    public init(method: String, params: ToolRequestParams) {
        this.method = method
        this.params = params
    }
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("method").writeValue(this.method)
        w.writeName("params").writeValue(this.params)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): CallToolRequest {
        let res = CallToolRequest()
        fromJsonObject(r,
            ("method", {=> res.method = r.readValue<String>()}),
            ("params", {=> res.params = r.readValue<ToolRequestParams>()})
        )
        res
    }
}

public class ToolRequestParams <: JsonSerializable & JsonDeserializable<ToolRequestParams> {
    public var name: String = ""
    public var arguments = HashMap<String, JsonValue>()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("name").writeValue(this.name)
        w.writeName("arguments").writeValue(this.arguments)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): ToolRequestParams {
        let res = ToolRequestParams()
        fromJsonObject(r,
            ("name", {=> res.name = r.readValue<String>()}),
            ("arguments", {=> res.arguments = r.readValue<HashMap<String, JsonValue>>()})
        )
        res
    }
}

public class ListToolsRequest <: JsonSerializable & JsonDeserializable<ListToolsRequest> {
    public var method: String = "tools/list"
    public var params: ?PaginatedRequest = None
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("method").writeValue(this.method)
        if (let Some(v) <- this.params) { w.writeName("params").writeValue(v) }
        w.endObject()
    }
    public static func fromJson(r: JsonReader): ListToolsRequest {
        let res = ListToolsRequest()
        fromJsonObject(r,
            ("method", {=> res.method = r.readValue<String>()}),
            ("params", {=> res.params = r.readValue<Option<PaginatedRequest>>()})
        )
        res
    }
}

public class PaginatedRequest <: JsonSerializable & JsonDeserializable<PaginatedRequest> {
    public var cursor: ?Cursor = None
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.cursor) { w.writeName("cursor").writeValue(v) }
        w.endObject()
    }
    public static func fromJson(r: JsonReader): PaginatedRequest {
        let res = PaginatedRequest()
        fromJsonObject(r,
            ("cursor", {=> res.cursor = r.readValue<Option<Cursor>>()})
        )
        res
    }
}

public class PaginatedResult <: JsonSerializable & JsonDeserializable<PaginatedResult> {
    var nextCursor: ?Cursor = None
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.nextCursor) { w.writeName("nextCursor").writeValue(v) }
        w.endObject()
    }
    public static func fromJson(r: JsonReader): PaginatedResult {
        let res = PaginatedResult()
        fromJsonObject(r,
            ("nextCursor", {=> res.nextCursor = r.readValue<Option<Cursor>>()})
        )
        res
    }
}

public class ListToolsResult <: PaginatedResult {
    public var tools = ArrayList<Tool>()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("tools").writeValue(this.tools)
        if (let Some(v) <- this.nextCursor) { w.writeName("nextCursor").writeValue(v) }
        w.endObject()
    }
    public static func fromJson(r: JsonReader): ListToolsResult {
        let res = ListToolsResult()
        fromJsonObject(r,
            ("tools", {=> res.tools = r.readValue<ArrayList<Tool>>()}),
            ("nextCursor", {=> res.nextCursor = r.readValue<Option<Cursor>>()})
        )
        res
    }
}

public struct Cursor <: JsonSerializable & JsonDeserializable<Cursor> {
    public Cursor(let value: String) {}
    public func toJson(w: JsonWriter): Unit { this.value.toJson(w) }
    public static func fromJson(r: JsonReader): Cursor { Cursor(String.fromJson(r)) }
}
