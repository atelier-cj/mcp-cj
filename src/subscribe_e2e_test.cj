package mcp

// 端到端：连真实服务端 → 订阅 → 收到推送。
//
// 默认跳过（需要真实服务）。设 MCP_E2E_URL 才启用：
//   MCP_E2E_URL=http://127.0.0.1:18202/ cjpm test --filter '*e2e*'
//
// 为什么要这条用例：订阅是"两阶段响应 + 长流"，用假 transport 只能验证
// 请求发出去了，验证不了"服务端真的会推、客户端真的收得到"。
// 而这两件事恰恰是这组功能存在的全部理由。

import jsonvalue.*
import mcp.transport.*
import ystyle::jsonrpc.{Result, Notification}
import std.collection.*
import std.sync.{Mutex, Condition}
import std.env.getVariable
import std.core.Duration

class E2EProbe {
    let lock = Mutex()
    let cond: Condition
    var acked: Bool = false
    var listChanged: Bool = false

    init() {
        this.cond = synchronized(this.lock) { this.lock.condition() }
    }

    func onNotification(n: Notification): Unit {
        synchronized(this.lock) {
            if (isSubscriptionAck(n.method)) { this.acked = true }
            if (n.method == "notifications/tools/list_changed") { this.listChanged = true }
            this.cond.notifyAll()
        }
    }

    func waitAck(timeoutMs: Int64): Bool {
        var waited: Int64 = 0
        synchronized(this.lock) {
            while (waited < timeoutMs) {
                if (this.acked) { return true }
                this.cond.wait(timeout: Duration.millisecond * 200)
                waited += 200
            }
            this.acked
        }
    }

    func waitListChanged(timeoutMs: Int64): Bool {
        var waited: Int64 = 0
        synchronized(this.lock) {
            while (waited < timeoutMs) {
                if (this.listChanged) { return true }
                this.cond.wait(timeout: Duration.millisecond * 200)
                waited += 200
            }
            this.listChanged
        }
    }
}

@Test
func e2e_subscribeReceivesAckFromRealServer() {
    let url = match (getVariable("MCP_E2E_URL")) {
        case Some(u) => u
        case None => return   // 未配置：跳过（不是失败）
    }
    let transport = StatelessHttpClient_2026_07_28(url)
    let client = McpClient(transport)
    let probe = E2EProbe()
    client.setNotificationCallback({ n => probe.onNotification(n) })

    match (client.connect(Implementation("e2e-test", "1.0.0"))) {
        case Result.Err(e) => @Fail("connect failed: " + e)
        case Result.Ok(_) => ()
    }
    match (client.subscribe(SubscriptionRequest.toolsOnly())) {
        case Result.Err(e) => @Fail("subscribe failed: " + e)
        case Result.Ok(_) => ()
    }
    // 服务端接受订阅后会推 ack
    @Expect(probe.waitAck(5000), true)
    @Expect(client.subscriptionCount(), 1)

    // 触发一次「群消息」→ 服务端应推 tools/list_changed。
    // 这一步才真正验证"推送能被收到"——ack 只是握手成功。
    let gid = "e2e-group-fixed"
    let created = client.callTool("create_group",
        arguments: mkArgs([("group_name", JsonValue.String("e2e")),
                           ("owner_id", JsonValue.String("e2e-bot"))]))
    match (created) {
        case Result.Err(e) => @Fail("create_group failed: " + e)
        case Result.Ok(_) => ()
    }
    // 从返回里取邀请码
    let inv = extractInviteCode(created)
    @Expect(inv != "", true)
    let sent = client.callTool("send_group_message",
        arguments: mkArgs([("invite_code", JsonValue.String(inv)),
                           ("sender_id", JsonValue.String("e2e-bot")),
                           ("content", JsonValue.String("触发通知"))]))
    match (sent) {
        case Result.Err(e) => @Fail("send_group_message failed: " + e)
        case Result.Ok(_) => ()
    }
    // 等待推送到达
    @Expect(probe.waitListChanged(10000), true)
    client.close()
}

func mkArgs(pairs: Array<(String, JsonValue)>): HashMap<String, JsonValue> {
    let m = HashMap<String, JsonValue>()
    for ((k, v) in pairs) { m.add(k, v) }
    m
}

// 从 create_group 的返回文本里抠邀请码。
//
// 返回形如 {"code":0,"data":{"invite_code":"kMSzMAA4",...}}，
// 这里只做最小解析——端到端用例关心的是"通知能不能收到"，
// 不是把 SDK 的结果解析做成通用工具。
func extractInviteCode(r: Result<CallToolResult>): String {
    let text = match (r) {
        case Result.Ok(c) =>
            var t = ""
            for (b in c.content) {
                match (b) {
                    case ContentBlock.Text(tc) => t = t + tc.text
                    case _ => ()
                }
            }
            t
        case Result.Err(_) => ""
    }
    let key = "\"invite_code\":"
    let i = text.indexOf(key)
    match (i) {
        case None => ""
        case Some(start) =>
            let from = start + key.size
            let rest = text[from..]
            let q1 = rest.indexOf("\"")
            match (q1) {
                case None => ""
                case Some(a) =>
                    let after = rest[(a + 1)..]
                    let q2 = after.indexOf("\"")
                    match (q2) {
                        case None => ""
                        case Some(b) => after[0..b]
                    }
            }
    }
}
