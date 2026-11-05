package mcp

import jsonvalue.*
import stdx.encoding.json.stream.{JsonSerializable, JsonWriter}
import ystyle::jsonrpc.RequestId
import ystyle::jsonrpc.*
import std.collection.*
import std.time.DateTime

// MCP 客户端的订阅 API：让服务端主动推送通知。
//
// ## 为什么需要
//
// 服务端侧（`v2026_07_28_stateless_server.cj`）完整实现了 `subscriptions/listen`：
// 客户端声明想听什么，服务端就在 SSE 长流上推 `notifications/*`。
//
// 但客户端侧此前只有 `setNotificationCallback`（一个裸回调）——**没有发起订阅的
// 入口**，所以服务端推不了（没有订阅登记，它就不推）。
//
// ## 机制（已实测验证）
//
// 客户端发一条 `subscriptions/listen` 请求：
//
//   POST /  {"method":"subscriptions/listen",
//            "params":{"notifications":{"toolsListChanged":true}}}
//   ← SSE: data: {"method":"notifications/subscriptions/acknowledged", ...}
//   ← SSE: data: {"method":"notifications/tools/list_changed", ...}   （之后随时）
//
// 这条流是**长期保持**的：服务端每 30 秒发一次 keep-alive 注释行。
//
// ## 为什么不用 JSON-RPC 的 call()
//
// `call()` 会绑定一个 pendingRequest 等“那一条响应”。而订阅响应是两个阶段：
// 先一个 ack、之后是无期限的通知流。用 call() 等 ack 之后就没人读了。
// 所以这里**自己发原始请求**，把流交给 transport 的后台读取（它本来就会
// 把 SSE 事件灌进 responseQueue），通知经 jsonrpc 的通知回调分发给用户。
//
// 一句话：**订阅只需要“把请求发出去”，读流与分发都是现成的。**

// 订阅过滤器：声明想听哪些通知。
//
// 字段名与服务端 `SubscriptionFilter` 一致（`notifications` 下的 key），
// 两边照同一份协议，改一处要同步改另一处。
public class SubscriptionRequest <: JsonSerializable {
    public var toolsListChanged: Bool = false
    public var promptsListChanged: Bool = false
    public var resourcesListChanged: Bool = false
    public var resourceSubscriptions: ArrayList<String> = ArrayList<String>()

    public init(toolsListChanged!: Bool = false,
        promptsListChanged!: Bool = false,
        resourcesListChanged!: Bool = false,
        resourceSubscriptions!: ArrayList<String> = ArrayList<String>()) {
        this.toolsListChanged = toolsListChanged
        this.promptsListChanged = promptsListChanged
        this.resourcesListChanged = resourcesListChanged
        this.resourceSubscriptions = resourceSubscriptions
    }

    // 全开（最常用）
    public static func all(): SubscriptionRequest {
        SubscriptionRequest(toolsListChanged: true, promptsListChanged: true,
            resourcesListChanged: true)
    }

    // 只要工具列表变更（群消息/新成员这类"数据变了"的信号通常走它）
    public static func toolsOnly(): SubscriptionRequest {
        SubscriptionRequest(toolsListChanged: true)
    }

    public func toJson(w: JsonWriter): Unit {
        w.startObject()
        w.writeName("toolsListChanged").writeValue(this.toolsListChanged)
        w.writeName("promptsListChanged").writeValue(this.promptsListChanged)
        w.writeName("resourcesListChanged").writeValue(this.resourcesListChanged)
        w.writeName("resourceSubscriptions")
        w.startArray()
        for (uri in this.resourceSubscriptions) { w.writeValue(uri) }
        w.endArray()
        w.endObject()
    }
}

// 一条已建立（或已请求）的订阅。
public class Subscription {
    public let requestId: RequestId
    public let filter: SubscriptionRequest
    // 建立时刻（毫秒）：诊断"订阅活了多久"用
    public let createdAtMs: Int64
    public var acknowledged: Bool = false

    public init(requestId: RequestId, filter: SubscriptionRequest, createdAtMs: Int64) {
        this.requestId = requestId
        this.filter = filter
        this.createdAtMs = createdAtMs
    }

    public func ageMs(nowMs: Int64): Int64 {
        if (nowMs < this.createdAtMs) { return 0 }
        nowMs - this.createdAtMs
    }
}

// 判断一条通知是不是"订阅已确认"。
//
// 服务端在建立订阅后立刻回一条 `notifications/subscriptions/acknowledged`。
// 它不是业务通知，用户回调通常不关心——但"订阅有没有真的建立"必须能看见，
// 否则订阅失败与"服务端一直没事件"完全无法区分。
public func isSubscriptionAck(method: String): Bool {
    method == "notifications/subscriptions/acknowledged"
}
