package mcp.transport

// `http_failure.cj` 的判定与摘要：这两条规则决定了「什么样的响应体可以当协议
// 消息投递」，写错了要么把服务端的话丢掉（回到 Parse error），要么把正常的
// JSON-RPC 错误响应误判成传输异常。

import std.unittest.*
import std.unittest.testmacro.*

@Test
func looksLikeJsonMessage_onlyAcceptsObjectOrArray() {
    @Expect(looksLikeJsonMessage("{\"a\":1}".toArray()), true)
    @Expect(looksLikeJsonMessage("  \n\t[1,2]".toArray()), true)
    // HTTP 层自己的失败：都不是协议消息
    @Expect(looksLikeJsonMessage("Invalid session ID".toArray()), false)
    @Expect(looksLikeJsonMessage("<!DOCTYPE html>".toArray()), false)
    @Expect(looksLikeJsonMessage("404 page not found\n".toArray()), false)
    @Expect(looksLikeJsonMessage(Array<Byte>()), false)
}

@Test
func bodySnippet_foldsWhitespaceAndTruncates() {
    @Expect(bodySnippet("Invalid session ID".toArray()), "Invalid session ID")
    // 多行/带制表符的错误体折叠成一行，免得把日志冲散
    @Expect(bodySnippet("line1\nline2\t".toArray()), "line1 line2")

    let sb = StringBuilder()
    for (_ in 0..500) {
        sb.append("x")
    }
    @Expect(bodySnippet(sb.toString().toArray()).size, HTTP_ERROR_SNIPPET_BYTES)
}

@Test
func bodySnippet_doesNotSplitMultibyteCharacters() {
    let sb = StringBuilder()
    for (_ in 0..100) {
        sb.append("中")
    }
    // 上限 200 字节落在第 67 个字符中间，回退到 66 个字符（198 字节）
    @Expect(bodySnippet(sb.toString().toArray()).toArray().size, 198)
}

@Test
func httpFailureText_carriesStatusUrlAndBody() {
    @Expect(httpFailureText(UInt16(400), "http://x/mcp", "Invalid session ID".toArray()),
        "HTTP 400 from http://x/mcp: Invalid session ID")
    @Expect(httpFailureText(UInt16(500), "http://x/mcp", Array<Byte>()),
        "HTTP 500 from http://x/mcp")
}
