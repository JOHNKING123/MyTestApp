#!/bin/bash

echo "=== P2P服务器状态检查 ==="

# 设置adb路径
ADB_PATH="/Users/zhengchuqiang/Library/Android/sdk/platform-tools/adb"

echo "1. 检查端口转发状态..."
$ADB_PATH -s emulator-5554 forward --list | grep 36324
$ADB_PATH -s emulator-5556 forward --list | grep 36324

echo ""
echo "2. 检查本地端口监听状态..."
echo "检查端口 8080 (群组创建者转发):"
nc -zv 127.0.0.1 8080 2>&1

echo ""
echo "检查端口 8081 (群组成员转发):"
nc -zv 127.0.0.1 8081 2>&1

echo ""
echo "3. 检查模拟器内部端口状态..."
echo "检查模拟器A的36324端口:"
$ADB_PATH -s emulator-5554 shell netstat -tlnp | grep 36324 2>/dev/null || echo "端口36324未监听"

echo ""
echo "检查模拟器B的36324端口:"
$ADB_PATH -s emulator-5556 shell netstat -tlnp | grep 36324 2>/dev/null || echo "端口36324未监听"

echo ""
echo "4. 检查模拟器进程..."
echo "模拟器A的Flutter进程:"
$ADB_PATH -s emulator-5554 shell ps | grep flutter 2>/dev/null || echo "未找到Flutter进程"

echo ""
echo "模拟器B的Flutter进程:"
$ADB_PATH -s emulator-5556 shell ps | grep flutter 2>/dev/null || echo "未找到Flutter进程"

echo ""
echo "=== 检查完成 ==="
echo ""
echo "如果端口转发正常但36324端口未监听，说明P2P服务器未启动。"
echo "请检查群组创建者的应用日志。" 