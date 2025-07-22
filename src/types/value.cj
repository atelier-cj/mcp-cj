package mcp.types

import encoding.json.stream.*
import std.collection.HashMap
import std.deriving.*
import std.io.ByteBuffer

@Derive[ToString]
public enum RequestId <: JsonDeserializable<RequestId> & JsonSerializable {
   String(String) | Int(Int64)

    public func toJson(w: JsonWriter): Unit {
         match (this) {
            case RequestId.String(v) =>  v.toJson(w)
            case RequestId.Int(v) =>  v.toJson(w)
         }
         return
    }

    public static func fromJson(r: JsonReader): RequestId {
        while (let Some(v) <- r.peek()) {
            match(v) {
                case JsonString =>  
                    let str = r.readValue<String>()
                    return RequestId.String(str)
                case JsonNumber=>  
                    let f = r.readValue<Float64>()
                    return RequestId.Int(Int64(f))
                case _ => ()
            }
        }
        return RequestId.Int(0)
    }
}
