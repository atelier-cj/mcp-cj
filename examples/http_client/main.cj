package http_client

import mcp.{server.*, types.*}
import net.http.{ClientBuilder, HttpRequestBuilder}
import std.io.{ByteBuffer}

main() {
    let s = McpServer("HTTP客户端", "1.0.0", WithLogging())
    
    // HTTP GET请求工具
    let httpGet = Tool(
        "http_get",
        withDescription("发送HTTP GET请求"),
        withString("url", descriptionProperty("请求URL"), requiredProperty())
    )
    
    s.addTool(
        httpGet,
        {
            req =>
            let url = (req.params.arguments.get("url")?.asString()).flatten() ?? ""
            if (url.isEmpty()) {
                return CallToolResult.error("URL不能为空")
            }
            
            try {
                let client = ClientBuilder().build()
                let response = client.get(url)
                
                let result = StringBuilder()
                result.append("状态码: ${response.statusCode}\n")
                result.append("响应头:\n")
                for ((key, value) in response.headers) {
                    result.append("${key}: ${value}\n")
                }
                
                let body = response.body.readToEnd()
                if (body.size() > 200) {
                    result.append("响应体(前200字符): ${String.fromUtf8(body.slice(0, 200))}...")
                } else {
                    result.append("响应体: ${String.fromUtf8(body)}")
                }
                
                client.close()
                return CallToolResult.text(result.toString())
            } catch (e: Exception) {
                return CallToolResult.error("HTTP请求失败: ${e.message}")
            }
        }
    )
    
    // HTTP POST请求工具
    let httpPost = Tool(
        "http_post",
        withDescription("发送HTTP POST请求"),
        withString("url", descriptionProperty("请求URL"), requiredProperty()),
        withString("data", descriptionProperty("POST数据")),
        withString("content_type", descriptionProperty("内容类型"), defaultValueProperty("application/json"))
    )
    
    s.addTool(
        httpPost,
        {
            req =>
            let url = (req.params.arguments.get("url")?.asString()).flatten() ?? ""
            let data = (req.params.arguments.get("data")?.asString()).flatten() ?? ""
            let contentType = (req.params.arguments.get("content_type")?.asString()).flatten() ?? "application/json"
            
            if (url.isEmpty()) {
                return CallToolResult.error("URL不能为空")
            }
            
            try {
                let client = ClientBuilder().build()
                let request = HttpRequestBuilder()
                    .method("POST")
                    .url(url)
                    .header("Content-Type", contentType)
                    .body(data)
                    .build()
                
                let response = client.send(request)
                let body = response.body.readToEnd()
                
                let result = JsonValue.Map(HashMap([
                    ("status", JsonValue.Number(response.statusCode.toFloat64())),
                    ("body", JsonValue.String(String.fromUtf8(body)))
                ]))
                
                client.close()
                return CallToolResult.json(result)
            } catch (e: Exception) {
                return CallToolResult.error("HTTP POST请求失败: ${e.message}")
            }
        }
    )
    
    ServeStdio(s)
}