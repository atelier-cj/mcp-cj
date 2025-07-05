package mcp.types

import std.collection.HashMap
import encoding.json.stream.*

public class ToolListChangedNotification <: JsonRpcNotification {
    public prop method:String {
        get() {
            "notifications/tools/list_changed"
        }
    }
    public prop params:Option<Params> {
        get() {
          return EmptyParams()
        }
    }
    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("jsonrpc").writeValue(this.jsonrpc)
        w.writeName("method").writeValue(this.method)
        w.writeName("params").writeValue(this.params)
        w.endObject()
    }

    public static func fromJson(r: JsonReader): ToolListChangedNotification {
        return ToolListChangedNotification()
    }
}