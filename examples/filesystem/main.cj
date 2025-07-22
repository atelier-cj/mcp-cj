package filesystem

import mcp.{server.*, types.*}
import std.fs.{File, Path, OpenMode}
import std.io.{ByteBuffer}

main() {
    let s = McpServer("文件系统", "1.0.0", WithLogging())
    
    // 文件读取工具
    let readFile = Tool(
        "read_file",
        withDescription("读取文件内容"),
        withString("path", descriptionProperty("文件路径"), requiredProperty())
    )
    
    s.addTool(
        readFile,
        {
            req =>
            let path = (req.params.arguments.get("path")?.asString()).flatten() ?? ""
            if (path.isEmpty()) {
                return CallToolResult.error("文件路径不能为空")
            }
            
            try {
                let content = File.read(path)
                return CallToolResult.text("文件内容:\n${content}")
            } catch (e: Exception) {
                return CallToolResult.error("读取文件失败: ${e.message}")
            }
        }
    )
    
    // 文件列表工具
    let listFiles = Tool(
        "list_files",
        withDescription("列出目录中的文件"),
        withString("directory", descriptionProperty("目录路径"))
    )
    
    s.addTool(
        listFiles,
        {
            req =>
            let directory = (req.params.arguments.get("directory")?.asString()).flatten() ?? "."
            
            try {
                let files = ArrayList<String>()
                let dir = Path(directory)
                
                // 简化的文件列表实现
                return CallToolResult.text("目录 ${directory} 中的文件列表功能待完善")
            } catch (e: Exception) {
                return CallToolResult.error("列出文件失败: ${e.message}")
            }
        }
    )
    
    ServeStdio(s)
}