package mcp.types

import jsonvalue.*
import stdx.encoding.json.stream.*
import std.collection.{HashMap, ArrayList}
import std.io.ByteBuffer

public enum ContentBlock <: JsonSerializable & JsonDeserializable<ContentBlock> {
    | Text(TextContent)
    | Image(ImageContent)
    | Audio(AudioContent)
    | Embedded(EmbeddedResource)

    public func toJson(w: JsonWriter): Unit {
        match (this) {
            case ContentBlock.Text(v) => v.toJson(w)
            case ContentBlock.Image(v) => v.toJson(w)
            case ContentBlock.Audio(v) => v.toJson(w)
            case ContentBlock.Embedded(v) => v.toJson(w)
        }
    }
    public static func fromJson(r: JsonReader): ContentBlock {
        let v = JsonValue.fromJson(r)
        let typStr = match (v["type"]) {
            case Some(JsonValue.String(t)) => t
            case _ => throw Exception("Missing 'type' field in ContentBlock")
        }
        let buf = ByteBuffer(v.toBytes())
        let nr = JsonReader(buf)
        match (typStr) {
            case "text" => ContentBlock.Text(TextContent.fromJson(nr))
            case "image" => ContentBlock.Image(ImageContent.fromJson(nr))
            case "audio" => ContentBlock.Audio(AudioContent.fromJson(nr))
            case "resource" => ContentBlock.Embedded(EmbeddedResource.fromJson(nr))
            case _ => throw Exception("Unknown content type: ${typStr}")
        }
    }
}

public class TextContent <: JsonSerializable & JsonDeserializable<TextContent> {
    public var `type`: String = "text"
    public var text: String = ""
    public var annotations: ?JsonValue = None
    public init() {}
    public init(text: String) { this.text = text }
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("type").writeValue(this.`type`)
        w.writeName("text").writeValue(this.text)
        if (let Some(v) <- this.annotations) { w.writeName("annotations"); v.toJson(w) }
        w.endObject()
    }
    public static func fromJson(r: JsonReader): TextContent {
        let res = TextContent()
        fromJsonObject(r,
            ("type", {=> res.`type` = r.readValue<String>()}),
            ("text", {=> res.text = r.readValue<String>()}),
            ("annotations", {=> res.annotations = r.readValue<Option<JsonValue>>()})
        )
        res
    }
}

public class ImageContent <: JsonSerializable & JsonDeserializable<ImageContent> {
    public var `type`: String = "image"
    public var data: String = ""
    public var mimeType: String = ""
    public var annotations: ?JsonValue = None
    public init() {}
    public init(data: String, mimeType: String) {
        this.data = data
        this.mimeType = mimeType
    }
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("type").writeValue(this.`type`)
        w.writeName("data").writeValue(this.data)
        w.writeName("mimeType").writeValue(this.mimeType)
        if (let Some(v) <- this.annotations) { w.writeName("annotations"); v.toJson(w) }
        w.endObject()
    }
    public static func fromJson(r: JsonReader): ImageContent {
        let res = ImageContent()
        fromJsonObject(r,
            ("type", {=> res.`type` = r.readValue<String>()}),
            ("data", {=> res.data = r.readValue<String>()}),
            ("mimeType", {=> res.mimeType = r.readValue<String>()}),
            ("annotations", {=> res.annotations = r.readValue<Option<JsonValue>>()})
        )
        res
    }
}

public class AudioContent <: JsonSerializable & JsonDeserializable<AudioContent> {
    public var `type`: String = "audio"
    public var data: String = ""
    public var mimeType: String = ""
    public var annotations: ?JsonValue = None
    public init() {}
    public init(data: String, mimeType: String) {
        this.data = data
        this.mimeType = mimeType
    }
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("type").writeValue(this.`type`)
        w.writeName("data").writeValue(this.data)
        w.writeName("mimeType").writeValue(this.mimeType)
        if (let Some(v) <- this.annotations) { w.writeName("annotations"); v.toJson(w) }
        w.endObject()
    }
    public static func fromJson(r: JsonReader): AudioContent {
        let res = AudioContent()
        fromJsonObject(r,
            ("type", {=> res.`type` = r.readValue<String>()}),
            ("data", {=> res.data = r.readValue<String>()}),
            ("mimeType", {=> res.mimeType = r.readValue<String>()}),
            ("annotations", {=> res.annotations = r.readValue<Option<JsonValue>>()})
        )
        res
    }
}

public class EmbeddedResource <: JsonSerializable & JsonDeserializable<EmbeddedResource> {
    public var `type`: String = "resource"
    public var resource = ResourceContents()
    public var annotations: ?JsonValue = None
    public init() {}
    public init(resource: ResourceContents) { this.resource = resource }
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("type").writeValue(this.`type`)
        w.writeName("resource").writeValue(this.resource)
        if (let Some(v) <- this.annotations) { w.writeName("annotations"); v.toJson(w) }
        w.endObject()
    }
    public static func fromJson(r: JsonReader): EmbeddedResource {
        let res = EmbeddedResource()
        fromJsonObject(r,
            ("type", {=> res.`type` = r.readValue<String>()}),
            ("resource", {=> res.resource = r.readValue<ResourceContents>()}),
            ("annotations", {=> res.annotations = r.readValue<Option<JsonValue>>()})
        )
        res
    }
}
