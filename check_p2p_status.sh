#!/bin/bash

echo "=== P2P服务器状态检查 ==="

echo "1. 检查端口36324监听状态..."
lsof -i:36324
if [ $? -eq 0 ]; then
    echo "✅ 端口36324有服务监听"
else
    echo "❌ 端口36324没有服务监听"
    echo "   说明P2P服务器没有启动"
fi

echo ""
echo "2. 检查端口8080监听状态..."
lsof -i:8080
if [ $? -eq 0 ]; then
    echo "✅ 端口8080有服务监听（端口转发）"
else
    echo "❌ 端口8080没有服务监听"
fi

echo ""
echo "3. 检查Flutter进程..."
/Users/zhengchuqiang/Library/Android/sdk/platform-tools/adb -s emulator-5554 shell ps | grep flutter
if [ $? -eq 0 ]; then
    echo "✅ Flutter进程正在运行"
else
    echo "❌ Flutter进程没有运行"
fi

echo ""
echo "4. 检查端口转发状态..."
/Users/zhengchuqiang/Library/Android/sdk/platform-tools/adb -s emulator-5554 forward --list | grep 36324

echo ""
echo "=== 诊断结果 ==="
echo "如果端口36324没有监听，说明P2P服务器没有启动。"
echo "需要在模拟器A上："
echo "1. 启动Flutter应用"
echo "2. 创建群组（这会启动P2P服务器）"
echo "3. 确保看到'P2P服务器启动成功，监听端口: 36324'的日志" 