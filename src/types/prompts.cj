package mcp.types

import jsonvalue.*
import stdx.encoding.json.stream.*
import std.collection.{HashMap, ArrayList}

public class Prompt <: JsonSerializable & JsonDeserializable<Prompt> {
    public var name: String = ""
    public var description: ?String = None
    public var arguments: ?ArrayList<PromptArgument> = None
    public init() {}
    public init(name: String) { this.name = name }
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("name").writeValue(this.name)
        if (let Some(v) <- this.description) { w.writeName("description").writeValue(v) }
        if (let Some(v) <- this.arguments) { w.writeName("arguments").writeValue(v) }
        w.endObject()
    }
    public static func fromJson(r: JsonReader): Prompt {
        let res = Prompt()
        fromJsonObject(r,
            ("name", {=> res.name = r.readValue<String>()}),
            ("description", {=> res.description = r.readValue<Option<String>>()}),
            ("arguments", {=> res.arguments = r.readValue<Option<ArrayList<PromptArgument>>>()})
        )
        res
    }
}

public class PromptArgument <: JsonSerializable & JsonDeserializable<PromptArgument> {
    public var name: String = ""
    public var description: ?String = None
    public var required: ?Bool = None
    public init() {}
    public init(name: String) { this.name = name }
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("name").writeValue(this.name)
        if (let Some(v) <- this.description) { w.writeName("description").writeValue(v) }
        if (let Some(v) <- this.required) { w.writeName("required").writeValue(v) }
        w.endObject()
    }
    public static func fromJson(r: JsonReader): PromptArgument {
        let res = PromptArgument()
        fromJsonObject(r,
            ("name", {=> res.name = r.readValue<String>()}),
            ("description", {=> res.description = r.readValue<Option<String>>()}),
            ("required", {=> res.required = r.readValue<Option<Bool>>()})
        )
        res
    }
}

public class PromptMessage <: JsonSerializable & JsonDeserializable<PromptMessage> {
    public var role: String = ""
    public var content = ContentBlock.Text(TextContent())
    public init() {}
    public init(role: String, content: ContentBlock) { this.role = role; this.content = content }
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("role").writeValue(this.role)
        w.writeName("content").writeValue(this.content)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): PromptMessage {
        let res = PromptMessage()
        fromJsonObject(r,
            ("role", {=> res.role = r.readValue<String>()}),
            ("content", {=> res.content = r.readValue<ContentBlock>()})
        )
        res
    }
}

public class GetPromptRequestParams <: JsonSerializable & JsonDeserializable<GetPromptRequestParams> {
    public var name: String = ""
    public var arguments: ?HashMap<String, String> = None
    public init() {}
    public init(name: String) { this.name = name }
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("name").writeValue(this.name)
        if (let Some(v) <- this.arguments) { w.writeName("arguments").writeValue(v) }
        w.endObject()
    }
    public static func fromJson(r: JsonReader): GetPromptRequestParams {
        let res = GetPromptRequestParams()
        fromJsonObject(r,
            ("name", {=> res.name = r.readValue<String>()}),
            ("arguments", {=> res.arguments = r.readValue<Option<HashMap<String, String>>>()})
        )
        res
    }
}

public class ListPromptsResult <: JsonSerializable & JsonDeserializable<ListPromptsResult> {
    public var prompts = ArrayList<Prompt>()
    public var nextCursor: ?Cursor = None
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("prompts").writeValue(this.prompts)
        if (let Some(v) <- this.nextCursor) { w.writeName("nextCursor").writeValue(v) }
        w.endObject()
    }
    public static func fromJson(r: JsonReader): ListPromptsResult {
        let res = ListPromptsResult()
        fromJsonObject(r,
            ("prompts", {=> res.prompts = r.readValue<ArrayList<Prompt>>()}),
            ("nextCursor", {=> res.nextCursor = r.readValue<Option<Cursor>>()})
        )
        res
    }
}

public class GetPromptResult <: JsonSerializable & JsonDeserializable<GetPromptResult> {
    public var description: ?String = None
    public var messages = ArrayList<PromptMessage>()
    public init() {}
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        if (let Some(v) <- this.description) { w.writeName("description").writeValue(v) }
        w.writeName("messages").writeValue(this.messages)
        w.endObject()
    }
    public static func fromJson(r: JsonReader): GetPromptResult {
        let res = GetPromptResult()
        fromJsonObject(r,
            ("description", {=> res.description = r.readValue<Option<String>>()}),
            ("messages", {=> res.messages = r.readValue<ArrayList<PromptMessage>>()})
        )
        res
    }
}
