package mcp.types

import encoding.json.stream.*
import std.collection.{HashMap, ArrayList}
import std.io.ByteBuffer
import std.deriving.*

public type Value = JsonValue

/* 高性能Value类型 - 基于现有模式优化 */
@Derive[ToString]
public enum JsonValue <: JsonDeserializable<JsonValue> & JsonSerializable {
    Null | 
    Boolean(Bool) |
    Number(Float64) |
    String (String) | 
    Array(ArrayList<JsonValue>) |
    Map(HashMap<String, JsonValue>)

    /* 高效的JSON反序列化实现 */
    public static func fromJson(r: JsonReader): JsonValue {
        while (let Some(v) <- r.peek()) {
            match (v) {
                case JsonNull =>
                    r.skip()
                    return JsonValue.Null
                case JsonBool =>
                    let b = r.readValue<Bool>()
                    return JsonValue.Boolean(b)
                case JsonNumber =>
                    let f = r.readValue<Float64>()
                    return JsonValue.Number(f)
                case BeginArray =>
                    let arr = r.readValue<ArrayList<JsonValue>>()
                    return JsonValue.Array(arr)
                case JsonString =>
                    let str = r.readValue<String>()
                    return JsonValue.String(str)
                case BeginObject =>
                    let m = r.readValue<HashMap<String, JsonValue>>()
                    return JsonValue.Map(m)
                case _ =>
                    throw Exception("Invalid JSON token")
            }
        }
        return JsonValue.Null
    }

    /* 高效的JSON序列化实现 */
    public func toJson(w: JsonWriter): Unit {
        match (this) {
            case JsonValue.Null => w.writeNullValue()
            case JsonValue.Boolean(b) => w.writeValue(b)
            case JsonValue.Number(n) => w.writeValue(n)
            case JsonValue.String(s) => w.writeValue(s)
            case JsonValue.Array(arr) => w.writeValue(arr)
            case JsonValue.Map(map) => w.writeValue(map)
        }
    }

    /* 类型安全的访问器 */
    public func asBool(): Option<Bool> {
        match (this) {
            case JsonValue.Boolean(b) => Some(b)
            case _ => None
        }
    }

    public func asNumber(): Option<Float64> {
        match (this) {
            case JsonValue.Number(n) => Some(n)
            case _ => None
        }
    }

    public func asString(): Option<String> {
        match (this) {
            case JsonValue.String(s) => Some(s)
            case _ => None
        }
    }

    public func asArray(): Option<ArrayList<JsonValue>> {
        match (this) {
            case JsonValue.Array(arr) => Some(arr)
            case _ => None
        }
    }

    public func asMap(): Option<HashMap<String, JsonValue>> {
        match (this) {
            case JsonValue.Map(m) => Some(m)
            case _ => None
        }
    }

    /* 高性能构建器 */
    public static func builder(): JsonValueBuilder {
        JsonValueBuilder()
    }
}

/* 高性能构建器模式 */
public class JsonValueBuilder {
    private var value: Option<JsonValue> = None
    private var map: Option<HashMap<String, JsonValue>> = None
    private var array: Option<ArrayList<JsonValue>> = None

    public func setNull(): JsonValueBuilder {
        this.value = JsonValue.Null
        this
    }

    public func setBool(value: Bool): JsonValueBuilder {
        this.value = JsonValue.Boolean(value)
        this
    }

    public func setNumber(value: Float64): JsonValueBuilder {
        this.value = JsonValue.Number(value)
        this
    }

    public func setString(value: String): JsonValueBuilder {
        this.value = JsonValue.String(value)
        this
    }

    public func setArray(): JsonValueBuilder {
        this.array = ArrayList<JsonValue>()
        this
    }

    public func addArrayItem(item: JsonValue): JsonValueBuilder {
        match (this.array) {
            case None => this.array = ArrayList<JsonValue>()
            case _ => ()
        }
        match (this.array) {
            case Some(arr) => arr.add(item)
            case _ => ()
        }
        this
    }

    public func setMap(): JsonValueBuilder {
        this.map = HashMap<String, JsonValue>()
        this
    }

    public func putMapItem(key: String, value: JsonValue): JsonValueBuilder {
        match (this.map) {
            case None => this.map = HashMap<String, JsonValue>()
            case _ => ()
        }
        match (this.map) {
            case Some(m) => m[key] = value
            case _ => ()
        }
        this
    }

    public func build(): JsonValue {
        match (this.value) {
            case Some(v) => v
            case None =>
                match (this.array) {
                    case Some(arr) => JsonValue.Array(arr)
                    case None =>
                        match (this.map) {
                            case Some(m) => JsonValue.Map(m)
                            case None => JsonValue.Null
                        }
                }
        }
    }
}

/* 高性能JSON解析器 */
public class JsonValueParser {
    public static func parse(json: String): JsonValue {
        let buffer = ByteBuffer(json.toArray())
        let reader = JsonReader(buffer)
        JsonValue.fromJson(reader)
    }
    
    public static func parse(bytes: Array<UInt8>): JsonValue {
        let buffer = ByteBuffer(bytes)
        let reader = JsonReader(buffer)
        JsonValue.fromJson(reader)
    }
}

/* 高性能JSON生成器 */
public class JsonValueGenerator {
    public static func generate(value: JsonValue): String {
        let buffer = ByteBuffer()
        let writer = JsonWriter(buffer)
        value.toJson(writer)
        writer.flush()
        buffer.flush()
        String.fromUtf8(buffer.bytes())
    }
    
    public static func generateBytes(value: JsonValue): Array<UInt8> {
        let buffer = ByteBuffer()
        let writer = JsonWriter(buffer)
        value.toJson(writer)
        writer.flush()
        buffer.flush()
        buffer.bytes()
    }
}

/* 泛型类与JsonValue的互相转换 */
public class JsonValueMapper {
    /* 从T类型转换为JsonValue */
    public static func fromObject<T>(obj: T): JsonValue where T <: JsonSerializable {
        let buffer = ByteBuffer()
        let writer = JsonWriter(buffer)
        obj.toJson(writer)
        writer.flush()
        buffer.flush()
        
        // 重新解析为JsonValue
        let reader = JsonReader(buffer)
        JsonValue.fromJson(reader)
    }
    
    /* 从JsonValue转换为T类型 */
    public static func toObject<T>(jsonValue: JsonValue): T where T <: JsonDeserializable<T> {
        let buffer = ByteBuffer()
        let writer = JsonWriter(buffer)
        jsonValue.toJson(writer)
        writer.flush()
        buffer.flush()
        
        // 从JsonValue解析为T类型
        let reader = JsonReader(buffer)
        T.fromJson(reader)
    }
    
    /* 从String转换为T类型 */
    public static func parseString<T>(jsonStr: String): T where T <: JsonDeserializable<T> {
        let buffer = ByteBuffer(jsonStr.toArray())
        let reader = JsonReader(buffer)
        T.fromJson(reader)
    }
    
    /* 从T类型转换为String */
    public static func stringify<T>(obj: T): String where T <: JsonSerializable {
        let buffer = ByteBuffer()
        let writer = JsonWriter(buffer)
        obj.toJson(writer)
        writer.flush()
        buffer.flush()
        String.fromUtf8(buffer.bytes())
    }
}