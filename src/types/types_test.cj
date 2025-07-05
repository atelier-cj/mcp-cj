package mcp.types

import std.collection.HashMap
import encoding.json.stream.*
import std.io.*
import std.console.Console
import std.unittest.*
import std.unittest.testmacro.*

@Test
func TestValue() {
    let m = HashMap<String, Value>()
    m["a"] = Value.Null
    m["b"] = Value.from(1)
    m["d"] = Value.Boolean(true)
    m["e"] = Value.Array([Value.from(1), Value.from(2),Value.from(3),Value.from(4)])
    m["f"] = Value.Map(HashMap<String, Value>(("f1", Value.from(1))))
    let w = JsonWriter(Console.stdOut)
    m.toJson(w)
    w.flush()
    println("\n--------------")
    let o = ByteBuffer()
    o.write(#"{"a":null,"b":1,"c":3.14,"d":true,"e":[1,2,3,4],"f":{"f1":1}}"#.toArray())
    let r = JsonReader(o)
    let am = HashMap<String, Value>.fromJson(r)
    println(am)
}

func TestSio() {
    
}