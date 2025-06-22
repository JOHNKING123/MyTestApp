#!/bin/bash

echo "=== TCP连接测试 ==="

echo "1. 测试主机到端口8080的TCP连接..."
nc -zv 127.0.0.1 8080 2>&1
if [ $? -eq 0 ]; then
    echo "✅ 主机可以连接到端口8080"
else
    echo "❌ 主机无法连接到端口8080"
fi

echo ""
echo "2. 测试主机到端口36324的TCP连接..."
nc -zv 127.0.0.1 36324 2>&1
if [ $? -eq 0 ]; then
    echo "✅ 主机可以连接到端口36324"
else
    echo "❌ 主机无法连接到端口36324"
fi

echo ""
echo "3. 从模拟器B测试TCP连接到转换后的地址..."
/Users/zhengchuqiang/Library/Android/sdk/platform-tools/adb -s emulator-5556 shell nc -z 10.0.2.2 8080
if [ $? -eq 0 ]; then
    echo "✅ 模拟器B可以TCP连接到10.0.2.2:8080"
else
    echo "❌ 模拟器B无法TCP连接到10.0.2.2:8080"
fi

echo ""
echo "4. 从模拟器B测试TCP连接到原始地址..."
/Users/zhengchuqiang/Library/Android/sdk/platform-tools/adb -s emulator-5556 shell nc -z 10.0.2.2 36324
if [ $? -eq 0 ]; then
    echo "✅ 模拟器B可以TCP连接到10.0.2.2:36324"
else
    echo "❌ 模拟器B无法TCP连接到10.0.2.2:36324"
fi

echo ""
echo "5. 检查端口转发状态..."
/Users/zhengchuqiang/Library/Android/sdk/platform-tools/adb -s emulator-5554 forward --list | grep 36324

echo ""
echo "=== 测试说明 ==="
echo "TCP连接测试可以验证："
echo "1. 端口转发是否正常工作"
echo "2. 目标端口是否有服务监听"
echo "3. 网络连通性是否正常"
echo ""
echo "如果TCP连接成功但WebSocket连接失败，"
echo "说明问题在于WebSocket协议处理。" 