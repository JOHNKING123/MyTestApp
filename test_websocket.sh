#!/bin/bash

echo "=== WebSocket连接测试 ==="

echo "1. 测试端口转发连通性..."
echo "测试端口8080 (群组创建者):"
nc -zv 127.0.0.1 8080 2>&1

echo ""
echo "2. 测试WebSocket连接..."
echo "尝试连接到 ws://127.0.0.1:8080"

# 使用curl测试WebSocket连接
curl -i -N -H "Connection: Upgrade" -H "Upgrade: websocket" -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: x3JJHMbDL1EzLkh9GBhXDw==" http://127.0.0.1:8080 2>&1 | head -10

echo ""
echo "3. 检查端口转发状态..."
/Users/zhengchuqiang/Library/Android/sdk/platform-tools/adb -s emulator-5554 forward --list | grep 36324

echo ""
echo "=== 测试完成 ==="
echo ""
echo "如果端口8080可以连接但WebSocket连接失败，"
echo "说明P2P服务器可能没有正确处理WebSocket升级请求。" 