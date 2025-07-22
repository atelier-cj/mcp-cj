package calculator

import mcp.{server.*, types.*}

main() {
    let s = McpServer("计算器", "1.0.0", WithLogging())
    
    // 基础计算器工具
    let calculator = Tool(
        "calculate",
        withDescription("执行基本算术运算"),
        withString("operation", 
            descriptionProperty("要执行的操作"), 
            enumProperty(["add", "subtract", "multiply", "divide"])
        ),
        withNumber("x", descriptionProperty("第一个数字")),
        withNumber("y", descriptionProperty("第二个数字"))
    )
    
    s.addTool(
        calculator,
        {
            req =>
            let operation = (req.params.arguments.get("operation")?.asString()).flatten() ?? "add"
            let x = (req.params.arguments.get("x")?.asNumber()).flatten() ?? 0.0
            let y = (req.params.arguments.get("y")?.asNumber()).flatten() ?? 0.0
            
            let result = match (operation) {
                case "add" => x + y
                case "subtract" => x - y
                case "multiply" => x * y
                case "divide" => if (y == 0.0) {
                    return CallToolResult.error("除零错误")
                } else {
                    x / y
                }
                case _ => 0.0
            }
            
            return CallToolResult.text("计算结果: ${result}")
        }
    )
    
    ServeStdio(s)
}