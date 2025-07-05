package mcp.types

import encoding.json.stream.*
import std.collection.HashMap
import std.deriving.*
import std.io.ByteBuffer

@Derive[ToString]
public enum Value <: JsonDeserializable<Value> & JsonSerializable {
    Null | 
    Boolean(Bool) |
    Number(Float64) |
    String (String) | 
    Array(Array<Value>) |
    Map(HashMap<String, Value>)

    public static func from<T>(val:T):Value where T <: JsonDeserializable<T> & JsonSerializable  {
        match (val) {
            case v:UInt8 => Value.Number(Float64(v))
            case v:UInt16 => Value.Number(Float64(v))
            case v:UInt32 => Value.Number(Float64(v))
            case v:UInt64 => Value.Number(Float64(v))
            case v:Int8 => Value.Number(Float64(v))
            case v:Int16 => Value.Number(Float64(v))
            case v:Int32 => Value.Number(Float64(v))
            case v:Int64 => Value.Number(Float64(v))
            case v:Float16 => Value.Number(Float64(v))
            case v:Float32 => Value.Number(Float64(v))
            case v:Float64 => Value.Number(v)
            case v:Bool => Value.Boolean(v)
            case v:String => Value.String(v)
            case v:Collection<T> => 
                var arr = Array<Value>(v.size, repeat: Value.Null)
                var i = 0
                for (vv in v) {
                    arr[i] =Value.from(vv)
                    i++
                }
                Value.Array(arr)
            case v:HashMap<String, T> => 
                var m = HashMap<String, Value>(v.size)
                for ((k, vv) in v) {
                    m[k] = Value.from(vv)
                }
                Value.Map(m)
            case _ => 
                let buf = ByteBuffer()
                let w = JsonWriter(buf)
                val.toJson(w)
                let r = JsonReader(buf)
                Value.fromJson(r)
        }
    }

    public func to<T>():T where T <: JsonDeserializable<T> & JsonSerializable {
        let buf = ByteBuffer()
        let w = JsonWriter(buf)
        this.toJson(w)
        let r = JsonReader(buf)
        T.fromJson(r)
    }

    public func toJson(w: JsonWriter): Unit {
        match (this) {
            case Value.Null =>  w.writeNullValue()
            case Value.Boolean(v) =>  v.toJson(w)
            case Value.Number(v) =>  v.toJson(w)
            case Value.String(v) =>  v.toJson(w)
            case Value.Array(v) =>  v.toJson(w)
            case Value.Map(v) =>  v.toJson(w)
        }
    }

    public static func fromJson(r: JsonReader): Value {
        while (let Some(v) <- r.peek()) {
            match(v) {
                case JsonNull =>  
                    r.skip() 
                    return Value.Null
                case JsonBool => 
                  let b = r.readValue<Bool>()
                  return Boolean(b)
                case JsonNumber => 
                    let f = r.readValue<Float64>()
                    return Value.Number(f)
                case BeginArray => 
                    let arr = r.readValue<Array<Value>>()
                    return Value.Array(arr)
                case JsonString => 
                    let str = r.readValue<String>()
                    return Value.String(str)
                case BeginObject =>
                    let m =  r.readValue<HashMap<String, Value>>()
                    return Value.Map(m)
                case _ => throw Exception()
            }
        }
        return Value.Null
    }
}


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
