package mcp.types

import encoding.json.stream.*
import std.collection.HashMap

func fromJsonObject(r: JsonReader, list: Array<(String, () -> Unit)>) {
    let refs = HashMap<String, () -> Unit>(list)
    while (let Some(v) <- r.peek()) {
        match (v) {
            case BeginObject =>
                r.startObject()
                while (r.peek() != EndObject) {
                    let n = r.readName()
                    if (refs.contains(n)) {
                        refs[n]()
                    } else {
                        r.skip()
                    }
                }
                r.endObject()
                break
            case _ => throw Exception()
        }
    }
}

