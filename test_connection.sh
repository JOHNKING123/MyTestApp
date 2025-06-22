#!/bin/bash

echo "=== 模拟器连接测试 ==="

# 设置adb路径
ADB_PATH="/Users/zhengchuqiang/Library/Android/sdk/platform-tools/adb"

echo "1. 检查端口转发状态..."
$ADB_PATH -s emulator-5554 forward --list | grep 36324
$ADB_PATH -s emulator-5556 forward --list | grep 36324

echo ""
echo "2. 测试端口连通性..."
echo "测试群组创建者端口 (8080):"
nc -zv 127.0.0.1 8080 2>&1

echo ""
echo "3. 从模拟器B测试连接到模拟器A..."
echo "测试模拟器B到localhost:8080的连接:"
$ADB_PATH -s emulator-5556 shell nc -zv 127.0.0.1 8080 2>&1

echo ""
echo "4. 测试WebSocket连接..."
echo "从模拟器B连接到模拟器A的WebSocket:"
$ADB_PATH -s emulator-5556 shell curl -i -N -H "Connection: Upgrade" -H "Upgrade: websocket" -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: x3JJHMbDL1EzLkh9GBhXDw==" http://127.0.0.1:8080 2>&1 | head -5

echo ""
echo "=== 测试完成 ==="
echo ""
echo "如果模拟器B无法连接到localhost:8080，"
echo "说明端口转发配置有问题。" 