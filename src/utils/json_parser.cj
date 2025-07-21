package mcp.utils

import encoding.json.stream.*
import std.io.{ByteBuffer, StringReader}

public class JsonParserUtil {
    
    public static func parseFromBytes<T>(jsonBytes: Array<UInt8>): ?T where T <: JsonDeserializable<T> {
        let buf = ByteBuffer(jsonBytes)
        let reader = JsonReader(buf)
        try {
            return T.fromJson(reader)
        } catch (e: Exception) {
            return None
        }
    }
    
    public static func parseFromString<T>(jsonStr: String): ?T where T <: JsonDeserializable<T> {
        let buf = ByteBuffer(jsonStr.toArray())
        let reader = JsonReader(buf)
        try {
            return T.fromJson(reader)
        } catch (e: Exception) {
            return None
        }
    }
    
    public static func serializeToBytes<T>(obj: T): Array<UInt8> where T <: JsonSerializable {
        let buf = ByteBuffer()
        let writer = JsonWriter(buf)
        obj.toJson(writer)
        writer.flush()
        buf.flush()
        return buf.bytes()
    }
    
    public static func serializeToString<T>(obj: T): String where T <: JsonSerializable {
        let bytes = serializeToBytes(obj)
        return String.fromUtf8(bytes)
    }
}