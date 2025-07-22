<!-- omit in toc -->
<div align="center">

# 🎯 MCP-CangJie

[![CangJie](https://img.shields.io/badge/CangJie-0.59.6-blue)](https://cangjie-lang.cn)
[![License](https://img.shields.io/badge/license-MulanPSL2-green)](LICENSE)

<strong>仓颉语言实现的Model Context Protocol (MCP)服务器，为AI应用提供安全连接本地数据源和工具的能力</strong>

<br>

**[快速开始](#快速开始) | [示例](examples/)**

<br>

</div>

```cangjie
package mcp.examples

import mcp.{server.*, types.*}

main() {
    let s = McpServer("演示服务器 🚀", "1.0.0", WithLogging())
    let tool = Tool(
        "hello_world",
        withDescription("向某人问好"),
        withString("name", descriptionProperty("要问候的人名")),
    )
    s.addTool(
        tool,
        {
            req =>
            var name = (req.params.arguments.get("name")?.asString()).flatten() ?? "世界"
            return CallToolResult.text("你好，${name}！")
        }
    )
    ServeStdio(s)
}
```

就这么简单！

MCP-CangJie处理了所有复杂的协议细节和服务器管理，让您专注于构建出色的工具。它提供高级接口，易于使用。

### 核心特性：
* **🚀 高性能**：基于仓颉原生实现，性能卓越
* **🎯 简洁**：最少的样板代码构建MCP服务器
* **📋 完整**：全面实现MCP核心规范
* **🔧 类型安全**：仓颉强类型系统，编译时检查

## 📦 安装

确保已安装仓颉编译器（版本=0.59.6）：

```toml
[dependencies]
  mcp = { git = "https://gitcode.com/ystyle/mcp-cj", branch = "master"}
```

## ⚡ 快速开始

让我们创建一个简单的计算器服务器：

```cangjie
package mcp.examples

import mcp.{server.*, types.*}

main() {
    let s = McpServer("计算器演示", "1.0.0", WithLogging())
    let calculator = Tool(
        "calculate",
        withDescription("执行基本算术运算"),
        withString("operation", 
            descriptionProperty("要执行的操作(add, subtract, multiply, divide)"), 
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
                case "divide" => y != 0.0 ? x / y : throw Exception("除零错误")
                case _ => throw Exception("未知操作")
            }
            
            return CallToolResult.text("结果: ${result}")
        }
    )
    ServeStdio(s)
}
```

## 📚 什么是MCP？

[Model Context Protocol (MCP)](https://modelcontextprotocol.io) 让您能够以安全、标准化的方式为LLM应用构建暴露数据和功能的服务器。可以将其视为专为LLM交互设计的web API。

MCP服务器可以：
- 通过**资源**暴露数据（类似于GET端点，用于将信息加载到LLM上下文中）
- 通过**工具**提供功能（类似于POST端点，用于执行代码或产生副作用）
- 通过**提示**定义交互模式（LLM交互的可重用模板）

## 🔧 核心概念

### 服务器
服务器是MCP协议的核心接口，处理连接管理、协议合规性和消息路由：

```cangjie
// 创建基本服务器
let server = McpServer(
    "我的服务器",  // 服务器名称
    "1.0.0",     // 版本
    WithLogging()  // 启用日志
)

// 使用stdio启动服务器
ServeStdio(server)
```

### 工具（完全实现）
工具让LLM通过您的服务器执行操作：

```cangjie
let tool = Tool("calculate", withDescription("执行计算"))
    .withNumber("x", descriptionProperty("第一个数字"))
    .withNumber("y", descriptionProperty("第二个数字"))

server.addTool(tool, { req =
    let x = (req.params.arguments.get("x")?.asNumber()).flatten() ?? 0.0
    let y = (req.params.arguments.get("y")?.asNumber()).flatten() ?? 0.0
    return CallToolResult.text("结果: ${x + y}")
})
```

### 资源（框架已定义，功能待实现）
资源系统已定义Capabilities框架，实际功能将在后续版本实现。

### 提示（框架已定义，功能待实现）
提示系统已定义Capabilities框架，实际功能将在后续版本实现。

## 📊 项目进度

### ✅ 已完成（基于server.cj实现）
- [x] **核心MCP服务器** - 完整的McpServer实现，支持初始化、ping、工具列表、工具调用
- [x] **JSON-RPC 2.0协议** - 完整的消息处理、错误处理、响应格式
- [x] **工具系统** - 完整的工具注册、调用、错误处理、动态通知
- [x] **类型安全** - 仓颉强类型系统，完整的Request/Response类型定义
- [x] **配置选项** - WithResourceCapabilities、WithPromptCapabilities、WithLogging等
- [x] **错误处理** - 完整的错误码、异常处理、日志记录
- [x] **线程安全** - 使用ReentrantReadWriteMutex保证并发安全
- [x] **工具动态通知** - 工具变更时的自动通知机制

### ⚠️ 部分实现
- [ ] **资源系统** - 在ServerCapabilities中定义但未实现具体功能
- [ ] **提示系统** - 在ServerCapabilities中定义但未实现具体功能
- [ ] **日志系统** - 基础日志框架，但资源/提示日志功能待完善

### 🚧 进行中
- [ ] **SSE传输层** - Server-Sent Events传输（sse.cj中部分实现，handleSSE/handleMessage未完成）
- [ ] **HTTP传输层** - 基于HTTP的传输支持
- [ ] **资源系统** - 资源列表、读取、通知功能
- [ ] **提示系统** - 提示列表、获取、参数处理功能

### 📋 待实现
- [ ] **SSE会话管理** - SSE连接的会话生命周期管理
- [ ] **资源动态通知** - 资源变更时的自动通知
- [ ] **提示动态通知** - 提示变更时的自动通知
- [ ] **完整的HTTP/SSE支持** - 目前只有stdio完全可用

## 🎯 当前状态总结

**已实现核心功能：**
- ✅ MCP服务器基础架构（100%完成）
- ✅ 工具系统（100%完成）
- ✅ JSON-RPC 2.0协议（100%完成）
- ✅ 错误处理和日志（100%完成）

**待完善功能：**
- ⚠️ 资源系统（仅定义了Capabilities，无实际实现）
- ⚠️ 提示系统（同上）
- 🚧 SSE传输层（50%完成，缺少会话管理）

**推荐当前使用：**
- ✅ **stdio传输** - 完全可用
- ✅ **工具功能** - 完全可用
- ⚠️ **资源/提示功能** - 暂不推荐使用

## 🎯 核心优势

### 性能优化
- **零拷贝序列化**：最小化内存分配
- **类型安全**：编译时类型检查
- **高性能JSON**：基于ArrayList的优化实现

### 开发体验
- **简洁API**：直观的接口设计
- **完整类型**：仓颉强类型支持
- **错误处理**：完善的异常机制

### 扩展性
- **模块化设计**：易于扩展和定制
- **泛型支持**：类型安全的泛型转换
- **插件架构**：支持自定义处理器

## 🚀 示例

查看[`examples/`](examples/)目录获取更多示例：

- [基础示例](examples/basic.cj) - 简单的"Hello World"服务器
- [计算器](examples/calculator.cj) - 完整的计算器工具
- [文件系统](examples/filesystem.cj) - 文件操作工具
- [数据库](examples/database.cj) - 数据库查询工具


## 📄 许可证

木兰宽松许可证第二版（MulanPSL2）- 详见[LICENSE](LICENSE)文件。