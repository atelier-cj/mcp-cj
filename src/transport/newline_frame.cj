package mcp.transport

/**
 * 把一条消息规整成「恰好以一个换行结尾」的记录。
 *
 * 传输层用换行分帧（客户端侧 `NewlineFraming`），所以每条消息必须**恰好**带一个
 * 结尾换行。服务端可能自带换行（Go 的 mcp-go 在 JSON 后就带一个），此时再补一个
 * 就多出一个空行：空行会被分帧解成一条**空消息**，于是一次成功的请求附赠一句
 *
 *     [jsonrpc] client handleMessage error: Exception: Parse error
 *
 * 而调用本身是成功的——线索因此指向解析器而不是分帧，极难从现象倒推回来。
 */
func frameLine(body: Array<Byte>): Array<Byte> {
    // 先剪掉尾部所有 CR/LF，再加正好一个
    var end = body.size
    while (end > 0 && (body[end - 1] == 10 || body[end - 1] == 13)) {
        end--
    }
    let result = Array<Byte>(end + 1, repeat: 0)
    for (i in 0..end) {
        result[i] = body[i]
    }
    result[end] = 10
    result
}
