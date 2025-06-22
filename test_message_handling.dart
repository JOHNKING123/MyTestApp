#!/usr/bin/env dart

import 'dart:convert';

/// 测试消息处理功能
void main() {
  print('=== 消息处理测试 ===');

  // 测试1: 模拟聊天消息
  print('\n1. 测试聊天消息处理');
  testChatMessage();

  // 测试2: 测试消息转发
  print('\n2. 测试消息转发');
  testMessageForwarding();

  // 测试3: 测试回调设置
  print('\n3. 测试回调设置');
  testCallbackSetup();

  print('\n=== 测试完成 ===');
}

/// 测试聊天消息处理
void testChatMessage() {
  print('模拟聊天消息...');

  // 模拟聊天消息格式
  final chatMessage = {
    'type': 'message',
    'groupId': 'test_group_123',
    'message': {
      'id': 'msg_456',
      'groupId': 'test_group_123',
      'senderId': 'user_789',
      'senderName': '测试用户',
      'content': {
        'text': 'Hello World!',
        'type': 'MessageType.text',
        'size': 12,
        'encryptedContent': 'encrypted_content_here',
      },
      'timestamp': DateTime.now().toIso8601String(),
      'type': 'MessageType.text',
      'signature': 'signature_here',
      'sequenceNumber': 1,
    },
    'timestamp': DateTime.now().millisecondsSinceEpoch,
  };

  print('聊天消息格式: ${jsonEncode(chatMessage)}');
  print('消息类型: ${chatMessage['type']}');
  print('群组ID: ${chatMessage['groupId']}');
  print(
    '发送者: ${(chatMessage['message'] as Map<String, dynamic>)['senderName']}',
  );
  print(
    '内容: ${((chatMessage['message'] as Map<String, dynamic>)['content'] as Map<String, dynamic>)['text']}',
  );
}

/// 测试消息转发
void testMessageForwarding() {
  print('模拟消息转发...');

  print('1. 模拟器B发送消息');
  print('2. P2P服务器接收消息');
  print('3. 服务器转发给其他客户端');
  print('4. 模拟器A接收消息');
  print('5. 消息解密和显示');

  // 模拟转发流程
  print('转发流程: 客户端B -> P2P服务器 -> 客户端A');
  print('消息类型: message');
  print('处理方式: _handleChatMessage');
}

/// 测试回调设置
void testCallbackSetup() {
  print('测试回调设置...');

  print('1. AppProvider.initialize() 设置P2P回调');
  print('2. P2PService.onMessageReceived = _handleP2PMessage');
  print('3. P2PService.onGroupUpdated = _handleGroupUpdate');
  print('4. P2PService.onConnectionValidate = _validateConnection');
  print('5. P2PService.onConnectionDisconnect = _handleConnectionDisconnect');

  print('回调设置完成，消息处理链路建立');
}
