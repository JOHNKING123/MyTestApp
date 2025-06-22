#!/bin/bash

echo "=== Android模拟器网络测试脚本 ==="

# 设置adb路径
ADB_PATH="/Users/zhengchuqiang/Library/Android/sdk/platform-tools/adb"

echo "1. 检查设备连接..."
$ADB_PATH devices

echo ""
echo "2. 检查端口转发状态..."
$ADB_PATH -s emulator-5554 forward --list | grep 36324
$ADB_PATH -s emulator-5556 forward --list | grep 36324

echo ""
echo "3. 测试端口转发连通性..."
echo "测试群组创建者端口 (8080):"
nc -zv 127.0.0.1 8080 2>&1

echo ""
echo "测试群组成员端口 (8081):"
nc -zv 127.0.0.1 8081 2>&1

echo ""
echo "4. 测试模拟器网络连通性..."
echo "测试模拟器A到主机的连通性:"
$ADB_PATH -s emulator-5554 shell ping -c 2 10.0.2.2

echo ""
echo "测试模拟器B到主机的连通性:"
$ADB_PATH -s emulator-5556 shell ping -c 2 10.0.2.2

echo ""
echo "=== 测试完成 ==="
echo ""
echo "如果所有测试都通过，说明网络配置正确。"
echo "现在可以在模拟器上测试P2P群聊功能了。" 