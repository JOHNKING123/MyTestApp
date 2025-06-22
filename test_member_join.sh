#!/bin/bash

echo "=== 成员加入测试 ==="

echo "1. 检查P2P服务器状态..."
lsof -i:36324
if [ $? -eq 0 ]; then
    echo "✅ P2P服务器正在监听36324端口"
else
    echo "❌ P2P服务器未监听36324端口"
fi

echo ""
echo "2. 检查端口转发状态..."
/Users/zhengchuqiang/Library/Android/sdk/platform-tools/adb -s emulator-5554 forward --list | grep 36324

echo ""
echo "3. 检查Flutter进程..."
/Users/zhengchuqiang/Library/Android/sdk/platform-tools/adb -s emulator-5554 shell ps | grep mytestapp

echo ""
echo "4. 测试WebSocket连接..."
echo "尝试连接到 ws://127.0.0.1:8080"
npx wscat -c ws://127.0.0.1:8080 &
WSCAT_PID=$!
sleep 3
kill $WSCAT_PID 2>/dev/null

echo ""
echo "=== 测试说明 ==="
echo "如果WebSocket连接成功，说明P2P服务器工作正常。"
echo "成员加入问题可能在于："
echo "1. UI更新回调没有正确设置"
echo "2. 群组数据没有正确保存"
echo "3. 成员ID生成有问题"
echo ""
echo "请检查模拟器A和B的日志，确认："
echo "- 成员加入消息是否被正确接收"
echo "- 群组成员列表是否被更新"
echo "- UI是否收到更新通知" 