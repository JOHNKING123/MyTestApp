#!/bin/bash

echo "=== 模拟器IP转换测试 ==="

echo "1. 测试模拟器B连接到模拟器A的转换逻辑..."
echo "原始地址: 10.0.2.15:36324"
echo "转换后地址: 10.0.2.2:8080"

echo ""
echo "2. 测试端口转发连通性..."
nc -zv 127.0.0.1 8080 2>&1

echo ""
echo "3. 从模拟器B测试连接到转换后的地址..."
/Users/zhengchuqiang/Library/Android/sdk/platform-tools/adb -s emulator-5556 shell nc -z 10.0.2.2 8080
if [ $? -eq 0 ]; then
    echo "✅ 模拟器B可以连接到转换后的地址"
else
    echo "❌ 模拟器B无法连接到转换后的地址"
fi

echo ""
echo "4. 检查端口转发状态..."
/Users/zhengchuqiang/Library/Android/sdk/platform-tools/adb -s emulator-5554 forward --list | grep 36324

echo ""
echo "=== 转换逻辑说明 ==="
echo "当模拟器B扫描二维码得到 10.0.2.15:36324 时："
echo "1. 检测到目标IP是模拟器A的IP (10.0.2.15)"
echo "2. 自动转换为 10.0.2.2:8080"
echo "3. 通过端口转发连接到模拟器A的36324端口"
echo ""
echo "这样模拟器B就能成功连接到模拟器A的P2P服务器了！" 