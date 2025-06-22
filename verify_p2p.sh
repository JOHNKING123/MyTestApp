#!/bin/bash

echo "=== P2P服务器验证脚本 ==="

# 设置adb路径
ADB_PATH="/Users/zhengchuqiang/Library/Android/sdk/platform-tools/adb"

echo "1. 检查端口转发..."
$ADB_PATH -s emulator-5554 forward --list | grep 36324
$ADB_PATH -s emulator-5556 forward --list | grep 36324

echo ""
echo "2. 测试端口连通性..."
echo "测试群组创建者端口 (8080):"
nc -zv 127.0.0.1 8080 2>&1

echo ""
echo "测试群组成员端口 (8081):"
nc -zv 127.0.0.1 8081 2>&1

echo ""
echo "3. 检查模拟器内部端口..."
echo "模拟器A (群组创建者):"
$ADB_PATH -s emulator-5554 shell ss -tlnp | grep 36324 2>/dev/null || echo "端口36324未监听"

echo ""
echo "模拟器B (群组成员):"
$ADB_PATH -s emulator-5556 shell ss -tlnp | grep 36324 2>/dev/null || echo "端口36324未监听"

echo ""
echo "=== 验证完成 ==="
echo ""
echo "如果模拟器A的36324端口未监听，请："
echo "1. 重新启动模拟器A上的应用"
echo "2. 创建群组"
echo "3. 确认P2P服务器启动" 