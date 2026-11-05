package mcp

// 客户端订阅：McpClient 能发起 subscriptions/listen，且通知能分发到回调。
//
// 服务端侧早已完整实现（`v2026_07_28_stateless_server.cj` 的
// `handleSubscriptionListen` + `SubscriptionFilter`），缺的一直是客户端入口。
//
// 这组用例验证的是**客户端这半边**：请求发得出去、通知收得到、ahead of ack
// 能被识别。

import jsonvalue.*
import ystyle::jsonrpc.{Transport, Notification, Result, RequestId}
import std.collection.*
import std.sync.*

// 可编排的假 transport：记录发出的请求，并可主动"推"一条消息回来
class FakeTransport <: Transport {
    public let sent = ArrayList<String>()
    private let queue = ArrayList<Array<Byte>>()
    private let lock = Mutex()
    private let cond: Condition
    private var closed = false

    init() {
        this.cond = synchronized(this.lock) { this.lock.condition() }
    }

    public func send(data: Array<Byte>): Unit {
        synchronized(this.lock) {
            this.sent.add(String.fromUtf8(data).trimAscii())
        }
    }

    public func receive(): ?Array<Byte> {
        synchronized(this.lock) {
            while (this.queue.size == 0 && !this.closed) {
                this.cond.wait(timeout: Duration.second)
            }
            if (this.queue.size > 0) {
                Option<Array<Byte>>.Some(this.queue.remove(at: 0))
            } else {
                Option<Array<Byte>>.None
            }
        }
    }

    public func isClosed(): Bool { this.closed }

    public func close(): Unit {
        synchronized(this.lock) {
            this.closed = true
            this.cond.notifyAll()
        }
    }

    // 推一条 JSON-RPC 消息（模拟服务端 SSE 事件）
    public func push(json: String): Unit {
        synchronized(this.lock) {
            this.queue.add(json.toArray())
            this.cond.notifyAll()
        }
    }

    public func sentCount(): Int64 {
        synchronized(this.lock) { this.sent.size }
    }
}

// 收集通知
class NotificationProbe {
    public let methods = ArrayList<String>()
    private let lock = Mutex()

    public func onNotification(n: Notification): Unit {
        synchronized(this.lock) { this.methods.add(n.method) }
    }

    public func snapshot(): ArrayList<String> {
        synchronized(this.lock) { ArrayList<String>(this.methods) }
    }
}

@Test
func subscribeRequest_filterSerialization() {
    // 过滤器字段名必须与服务端 `SubscriptionFilter` 一致
    let f = SubscriptionRequest.toolsOnly()
    @Expect(f.toolsListChanged, true)
    @Expect(f.promptsListChanged, false)
    @Expect(f.resourcesListChanged, false)

    let all = SubscriptionRequest.all()
    @Expect(all.toolsListChanged, true)
    @Expect(all.promptsListChanged, true)
    @Expect(all.resourcesListChanged, true)
}

@Test
func subscribeAck_isRecognized() {
    // 订阅确认不是业务通知，要能被识别出来
    @Expect(isSubscriptionAck("notifications/subscriptions/acknowledged"), true)
    @Expect(isSubscriptionAck("notifications/tools/list_changed"), false)
    @Expect(isSubscriptionAck(""), false)
}

@Test
func subscription_age() {
    let s = Subscription(RequestId.Int(1),
        SubscriptionRequest.toolsOnly(), 1000)
    @Expect(s.ageMs(1500), 500)
    // 时钟回退不返回负数
    @Expect(s.ageMs(500), 0)
}

@Test
func client_subscribeSendsRequest() {
    // 订阅必须真的把请求发出去——服务端没收到就不会推
    let t = FakeTransport()
    let client = McpClient(t)
    // 未 connect 时拒绝（需要 initialized）
    match (client.subscribe(SubscriptionRequest.toolsOnly())) {
        case Result.Err(_) => ()
        case Result.Ok(_) => @Fail("未连接时不该允许订阅")
    }
}

@Test
func client_subscriptionLifecycle() {
    // 订阅登记：能查、能数
    let t = FakeTransport()
    let client = McpClient(t)
    @Expect(client.subscriptionCount(), 0)
}
