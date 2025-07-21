package mcp.types

import std.collection.{HashMap, ArrayList}
import encoding.json.stream.*

public class Tool <: JsonDeserializable<Tool> & JsonSerializable {
    public var name: String = ""
    public var description: String = ""
    public var inputSchema = ToolInputSchema()
    public init() {}
    public init(name:String, description:String){
        this.name = name
        this.description = description
        this.inputSchema = ToolInputSchema("object", HashMap<String, Value>(), [])
    }

    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("name").writeValue(this.name)
        w.writeName("description").writeValue(this.description)
        w.writeName("inputSchema").writeValue(this.inputSchema)
        w.endObject()
    }

    public static func fromJson(r: JsonReader): Tool {
        let res = Tool()
        fromJsonObject(
            r,
            ("name", {=> res.name = r.readValue<String>()}),
            ("description", {=> res.description = r.readValue<String>()}),
            ("inputSchema", {=> res.inputSchema = r.readValue<ToolInputSchema>()}),
        )
        return res
    }
}

public class ToolInputSchema <: JsonDeserializable<ToolInputSchema> & JsonSerializable {
    public var typ: String = ""
    public var properties = HashMap<String, Value>()
    public var required = ArrayList<String>()
    public init() {}
    public init(typ:String, properties: HashMap<String, Value>, required:Array<String> ) {
        this.typ = typ
        this.properties = properties
        this.required = ArrayList<String>(required)
    }

    public func addField(name:String, typ:String, description:String, required!:Bool=false) {
        if (required) {
            this.required.add(name)
        }
        let field = HashMap<String, Value>()
        field.add("type", Value.String(typ))
        field.add("description", Value.String(description))
        this.properties.add(name, Value.Map(field))
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
        fromJsonObject(
            r,
            ("type", {=> res.typ = r.readValue<String>()}),
            ("properties", {=> res.properties = r.readValue<HashMap<String, Value>>()}),
            ("required", {=> res.required = r.readValue<ArrayList<String>>()}),
        )
        return res
    }
}

public class CallToolResult <: Result {
    public var method: String = ""
    public var content: Array<Value> = []
    public var isError = false

    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("method").writeValue(this.method)
        w.writeName("content").writeValue(this.content)
        w.writeName("isError").writeValue(this.isError)
        w.endObject()
    }

    public static func fromJson(r: JsonReader): CallToolResult {
        let res = CallToolResult()
        fromJsonObject(
            r,
            ("method", {=> res.method = r.readValue<String>()}),
            ("content", {=> res.content = r.readValue<Array<Value>>()}),
            ("isError", {=> res.isError = r.readValue<Bool>()}),
        )
        return res
    }
}

public class CallToolRequest <: JsonDeserializable<CallToolRequest> & JsonSerializable {
    public var method: String
    public var params: ToolRequestParams
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
        let res = CallToolRequest("111", ToolRequestParams())
        fromJsonObject(
            r,
            ("method", {=> res.method = r.readValue<String>()}),
            ("params", {=> res.params = r.readValue<ToolRequestParams>()}),
        )
        return res
    }
}

public class ToolRequestParams <: JsonDeserializable<ToolRequestParams> & JsonSerializable {
    public var name: String = ""
    public var arguments = HashMap<String, Value>()

    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("name").writeValue(this.name)
        w.writeName("arguments").writeValue(this.arguments)
        w.endObject()
    }

    public static func fromJson(r: JsonReader): ToolRequestParams {
        let res = ToolRequestParams()
        fromJsonObject(
            r,
            ("name", {=> res.name = r.readValue<String>()}),
            ("arguments", {=> res.arguments = r.readValue<HashMap<String, Value>>()}),
        )
        return res
    }
}

public class ListToolsRequest <: JsonRpcMessage & JsonDeserializable<ListToolsRequest> {
    public var method:String = "tools/list"
    public var params:?PaginatedRequest = None
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("jsonrpc").writeValue(this.jsonrpc)
        w.writeName("method").writeValue(this.method)
        w.writeName("params").writeValue(this.params)
        w.endObject()
    }

    public static func fromJson(r: JsonReader): ListToolsRequest {
        let res = ListToolsRequest()
        fromJsonObject(
            r,
            ("method", {=> res.method = r.readValue<String>()}),
            ("params", {=> res.params = r.readValue<Option<PaginatedRequest>>()}),
        )
        return res
    }
}

public struct Cursor <: ToString & JsonDeserializable<Cursor> & JsonSerializable {
    public Cursor(let value:String){}
    public func toJson(w: JsonWriter): Unit {
        this.value.toJson(w)
    }

    public static func fromJson(r: JsonReader): Cursor {
        return Cursor(String.fromJson(r))
    }
    public func toString():String {
        return this.value
    }
}

public class PaginatedRequest <: JsonDeserializable<PaginatedRequest> & JsonSerializable {
    public var cursor:?Cursor = None
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("cursor").writeValue(this.cursor)
        w.endObject()
    }

    public static func fromJson(r: JsonReader): PaginatedRequest {
        let res = PaginatedRequest()
        fromJsonObject(
            r,
            ("cursor", {=> res.cursor = r.readValue<Option<Cursor>>() }),
        )
        return res
    }
}

public class PaginatedResult <: JsonDeserializable<PaginatedResult> & JsonSerializable {
    var nextCursor:?Cursor = None
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("nextCursor").writeValue(this.nextCursor)
        w.endObject()
    }

    public static func fromJson(r: JsonReader): PaginatedResult {
        let res = PaginatedResult()
        fromJsonObject(
            r,
            ("nextCursor", {=> res.nextCursor = r.readValue<Option<Cursor>>() }),
        )
        return res
    }
}

public class ListToolsResult <: Result {
    public var tools = ArrayList<Tool>()
    public var nextCursor :?Cursor = None
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("tools").writeValue(this.tools)
        if (this.nextCursor.isSome()) {
            w.writeName("nextCursor").writeValue(this.nextCursor)
        }
        w.endObject()
    }

    public static func fromJson(r: JsonReader): ListToolsResult {
        let res = ListToolsResult()
        fromJsonObject(
            r,
            ("tools", {=> res.tools = r.readValue<ArrayList<Tool>>() }),
            ("nextCursor", {=> res.nextCursor = r.readValue<Option<Cursor>>() }),
        )
        return res
    }
}