package basic

import mcp.{server.*, types.*}

main() {
    let s = McpServer("基础示例", "1.0.0", WithLogging())
    let tool = Tool(
        "hello_world",
        withDescription("简单的问候工具"),
        withString("name", descriptionProperty("要问候的人名"))
    )
    
    s.addTool(
        tool,
        {
            req =>
            let name = (req.params.arguments.get("name")?.asString()).flatten() ?? "世界"
            return CallToolResult.text("你好，${name}！欢迎使用仓颉MCP服务器！")
        }
    )
    
    ServeStdio(s)
}