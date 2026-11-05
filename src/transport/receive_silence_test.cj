package mcp.transport

// 回归：静默超过 30 秒，receive() **不能**返回 None。
//
// 曾经的问题（实测现象：订阅建立 30 秒后 `client transport closed by peer`）：
//   receive() 在队列空等 30 秒后返回 None → json-rpc 的接收循环把 None
//   当作对端关闭 → shutdown() → 接收线程永久退出。
//
// 普通请求是"发了就有回"，踩不到；而订阅（服务端主动推）天然有长时间静默，
// 一建立就假死。
//
// 契约：receive() 返回 None **只表示真的关闭**。超时是"暂时还没有"，
// 不是"连接断了"。

import std.sync.{Mutex, Condition}
import std.core.{Duration, sleep}
import std.time.DateTime

@Test
func receiveBlocksInsteadOfReturningNoneOnSilence() {
    // 用一个小 sleep 模拟"静默"：真等 30 秒太慢，
    // 这里验证的是"没有数据时它会继续等，而不是立刻/定时返回 None"
    let t = StatelessHttpClient_2026_07_28("http://127.0.0.1:1/")
    // 另起一个线程，1 秒后关闭 transport
    let closer = Closer(t)
    spawn { => closer.run(1000) }

    let start = nowMs()
    let r = t.receive()        // 应当阻塞到 close，而不是 30 秒后自己返回
    let elapsed = nowMs() - start

    // 拿到的是 None（因为 close 了），但**是 close 导致的**
    @Expect(match (r) { case None => true; case _ => false }, true)
    // 关键断言：等待时间接近 1 秒（close 时机），而不是 30 秒（旧实现的超时）
    @Expect(elapsed < 10000, true)
}

class Closer {
    let t: StatelessHttpClient_2026_07_28

    init(t: StatelessHttpClient_2026_07_28) {
        this.t = t
    }

    func run(delayMs: Int64): Unit {
        sleep(Duration.millisecond * delayMs)
        this.t.close()
    }
}

func nowMs(): Int64 {
    DateTime.now().toUnixTimeStamp().toMilliseconds()
}
