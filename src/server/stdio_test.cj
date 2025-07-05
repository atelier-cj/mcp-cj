package mcp.server

import encoding.json.stream.*

func TestSio() {
    McpServer("MyTools", "0.1", 
        WithLogging(),
        WithPromptCapabilities(true)
    )
    McpServer("MyTools", "0.1", [
        WithLogging(),
        WithPromptCapabilities(true)
    ])
}
