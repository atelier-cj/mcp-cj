package mcp.transport

import std.collection.ArrayList

/**
 * HTTP 层的失败与「JSON-RPC 错误响应」的分界。
 *
 * 非 2xx 有两种，混在一起处理就会把原因弄丢：
 *
 * - **JSON-RPC 错误响应**（规范允许 4xx/5xx 携带）：它是协议消息，调用方要拿得到
 *   `code`/`message`，必须照常投递；
 * - **HTTP 层自己的失败**：网关/框架给的 `text/plain` 或 HTML（如 Go 的
 *   `Invalid session ID`、`404 page not found`）。把它当协议消息喂给解析器，只会
 *   得到一句 `Parse error`——服务端真正说的话被丢掉，在途调用还要干等满 timeout。
 */
/** 错误体摘要的字节上限（超出即截断）。 */
const HTTP_ERROR_SNIPPET_BYTES: Int64 = 200

/** 响应体是否长得像一条 JSON-RPC 消息（首个非空白字节为 `{` 或 `[`）。 */
func looksLikeJsonMessage(body: Array<Byte>): Bool {
    for (b in body) {
        if (b == 32 || b == 9 || b == 10 || b == 13) {
            continue
        }
        return b == 123 || b == 91
    }
    false
}

/** HTTP 失败的异常文本：状态码 + 端点 + 服务端原文（截断后）。 */
func httpFailureText(status: UInt16, url: String, body: Array<Byte>): String {
    let detail = bodySnippet(body)
    if (detail == "") {
        return "HTTP ${status} from ${url}"
    }
    "HTTP ${status} from ${url}: ${detail}"
}

/** 错误体摘要：折叠控制字符、按上限截断（不切断多字节字符）。 */
func bodySnippet(body: Array<Byte>): String {
    if (body.size == 0) {
        return ""
    }
    let flat = ArrayList<Byte>()
    for (b in body) {
        if (b < 32 || b == 127) {
            flat.add(32)          // 换行/制表/其它控制字符折叠成空格
        } else {
            flat.add(b)
        }
    }
    var cut = flat.size
    if (cut > HTTP_ERROR_SNIPPET_BYTES) {
        cut = HTTP_ERROR_SNIPPET_BYTES
        // UTF-8 续字节形如 10xxxxxx（0x80..0xBF）：回退到字符边界，别切出半个字
        while (cut > 0 && flat[cut] >= 128 && flat[cut] < 192) {
            cut--
        }
    }
    let raw = Array<Byte>(cut, repeat: 0)
    for (i in 0..cut) {
        raw[i] = flat[i]
    }
    String.fromUtf8(raw).trimAscii()
}
