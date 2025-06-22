#!/bin/bash

echo "=== 修正后的连接测试 ==="

echo "1. 测试端口转发连通性..."
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
echo "现在二维码应该包含:"
echo "  serverIP: '127.0.0.1'"
echo "  serverPort: 8080"
echo ""
echo "模拟器B应该尝试连接: 127.0.0.1:8080"
echo "这应该能正常工作，因为端口转发已经设置。" 