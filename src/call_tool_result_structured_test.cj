package mcp

// CallToolResult 的可选结构化返回字段。
//
// MCP 2025-06-18 起为 tools/call 结果引入 `structuredContent`：给程序读的
// 机器可读部分，与 `content`（给人读的文本块）并列。此前本库只序列化
// content / isError，调用方拿不到任何结构化数据——只能让服务端把 JSON 塞进
// 文本块里，客户端再自己 parse，语义模糊且易错。
//
// 关键约束：该字段**可选**。不设置时序列化结果里不能出现 "structuredContent"，
// 否则会把老客户端/严格校验方从"没有这个字段"变成"有这个字段但内容为空"。

import jsonvalue.*
import stdx.encoding.json.stream.*
import std.io.ByteBuffer
import std.collection.{ArrayList, HashMap}

private func jsonOf(result: CallToolResult): String {
    let buf = ByteBuffer()
    let w = JsonWriter(buf)
    result.toJson(w)
    // 不 flush 就取 bytes() 会得到空串：JsonWriter 有内部缓冲，
    // 序列化结果要到 flush 才落到 ByteBuffer。
    w.flush()
    String.fromUtf8(buf.bytes())
}

@Test
func callToolResultOmitsStructuredContentWhenAbsent() {
    let text = jsonOf(CallToolResult.text("hi"))
    @Expect(text.contains("structuredContent"), false)
    @Expect(text.contains("\"content\""), true)
    @Expect(text.contains("\"isError\""), true)
    @Expect(text.contains("\"hi\""), true)
}

@Test
func callToolResultSerializesStructuredContent() {
    let r = CallToolResult.text("共 3 条")
    let obj = HashMap<String, JsonValue>()
    obj["total"] = JsonValue.Number(3.0)
    obj["page"] = JsonValue.Number(1.0)
    r.structuredContent = Some(JsonValue.Map(obj))
    let text = jsonOf(r)
    @Expect(text.contains("\"structuredContent\""), true)
    @Expect(text.contains("\"total\""), true)
    @Expect(text.contains("\"page\""), true)
    // content 与 isError 仍在，结构化字段是**追加**而非替换。
    @Expect(text.contains("\"content\""), true)
    @Expect(text.contains("\"isError\""), true)
}

@Test
func callToolResultRoundTripsStructuredContent() {
    let r = CallToolResult.text("t")
    let obj = HashMap<String, JsonValue>()
    obj["totalPages"] = JsonValue.Number(7.0)
    r.structuredContent = Some(JsonValue.Map(obj))
    let text = jsonOf(r)
    let back = parseCallToolResult(text)
    match (back.structuredContent) {
        case Some(v) => @Expect(v.toString().contains("totalPages"), true)
        case None => @Fail("structuredContent 未往返")
    }
}

@Test
func callToolResultParsesLegacyWithoutStructuredContent() {
    // 老服务端的响应（无该字段）必须照旧可解析。
    let back = parseCallToolResult("{\"content\":[{\"type\":\"text\",\"text\":\"ok\"}],\"isError\":false}")
    @Expect(back.isError, false)
    match (back.structuredContent) {
        case Some(_) => @Fail("缺省时应为 None")
        case None => ()
    }
}

private func parseCallToolResult(text: String): CallToolResult {
    CallToolResult.fromJson(JsonReader(ByteBuffer(text.toArray())))
}
