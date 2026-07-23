#!/bin/bash
# 端到端测试： basic 服务器 ←→ testclient
set -e

FIFO_S2C=$(mktemp -u)  # server→client
FIFO_C2S=$(mktemp -u)  # client→server

cleanup() {
    rm -f "$FIFO_S2C" "$FIFO_C2S"
    kill $SERVER_PID 2>/dev/null
    kill $CLIENT_PID 2>/dev/null
    wait 2>/dev/null
}
trap cleanup EXIT

mkfifo "$FIFO_S2C" "$FIFO_C2S"

SERVER=./target/release/bin/mcp.examples.basic
CLIENT=./target/release/bin/mcp.examples.testclient

eval "$(cjvs stdx-env zsh)"
eval "$(cjvs env zsh)"

# 启动服务器：读 client→server，写 server→client
$SERVER < "$FIFO_C2S" > "$FIFO_S2C" 2>/dev/null &
SERVER_PID=$!

sleep 0.5

# 启动客户端：读 server→client，写 client→server
$CLIENT < "$FIFO_S2C" > "$FIFO_C2S" 2>/dev/null &
CLIENT_PID=$!

wait $CLIENT_PID 2>/dev/null
echo "exit: $?"
