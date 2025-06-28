import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import '../models/message.dart';
import '../models/group.dart';
import '../services/encryption_service.dart';
import '../services/storage_service.dart';
import '../utils/debug_logger.dart';
import 'p2p_service.dart';
import '../services/key_manager.dart';

/// 消息管理器
class MessageService {
  static final MessageService _instance = MessageService._internal();
  factory MessageService() => _instance;
  MessageService._internal();

  final Map<String, List<Message>> _groupMessages = {};
  final Map<String, int> _sequenceNumbers = {};

  // 消息更新回调
  Function(String groupId)? onMessageUpdated;
  Function(String groupId, Message message)? onMessageReceived;

  /// 发送消息
  Future<Message?> sendMessage(
    String groupId,
    String content,
    String senderId,
  ) async {
    try {
      DebugLogger().info('MessageService: 发送消息到群组 $groupId', tag: 'MESSAGE');

      // 获取群组信息
      final group = await StorageService.loadGroup(groupId);
      if (group == null) {
        DebugLogger().error('MessageService: 群组不存在 $groupId', tag: 'MESSAGE');
        return null;
      }

      // 生成消息ID
      final messageId = _generateMessageId(senderId, groupId);

      // 加密消息内容
      final encryptedContent = await EncryptionService.encryptMessage(
        content,
        group.sessionKey.key,
      );

      // 获取用户密钥对
      DebugLogger().info(
        'MessageService: 查找用户密钥对 senderId=$senderId',
        tag: 'MESSAGE',
      );
      final userKeyPair = await KeyManager.loadUserKeyPair(senderId);
      if (userKeyPair == null) {
        DebugLogger().error(
          'MessageService: 未找到用户密钥对 $senderId',
          tag: 'MESSAGE',
        );
        return null;
      } else {
        DebugLogger().info(
          'MessageService: 找到用户密钥对 senderId=$senderId, publicKey=${userKeyPair.publicKey.substring(0, 8)}..., privateKey=${userKeyPair.privateKey.substring(0, 8)}...',
          tag: 'MESSAGE',
        );
      }
      // 签名密文
      final signature = await Ed25519Helper.sign(
        encryptedContent,
        userKeyPair.privateKey,
        userKeyPair.publicKey,
      );

      // 创建消息内容（带密文）
      final messageContentWithEnc = MessageContent(
        text: content,
        type: MessageType.text,
        data: {},
        size: content.length,
        encryptedContent: encryptedContent,
      );

      // 创建消息
      final message = Message(
        id: messageId,
        groupId: groupId,
        senderId: senderId,
        content: messageContentWithEnc,
        type: MessageType.text,
        timestamp: DateTime.now(),
        status: MessageStatus.sending,
        signature: signature,
        metadata: {'publicKey': userKeyPair.publicKey},
        sequenceNumber: _getNextSequenceNumber(groupId),
      );

      // 创建网络消息
      final networkMessage = {
        'type': NetworkMessage.TYPE_CHAT_MESSAGE,
        'messageId': messageId,
        'groupId': groupId,
        'senderId': senderId,
        'content': encryptedContent,
        'timestamp': message.timestamp.millisecondsSinceEpoch,
        'sequenceNumber': message.sequenceNumber,
        'signature': signature,
        'publicKey': userKeyPair.publicKey,
        'metadata': {
          'messageType': messageContentWithEnc.type.toString(),
          'size': messageContentWithEnc.size,
        },
      };

      // 广播消息
      P2PService.broadcastMessage(networkMessage);

      // 保存消息到本地
      _addMessageToGroup(groupId, message);
      await StorageService.saveMessage(groupId, message);

      // 更新消息状态为已发送
      message.status = MessageStatus.sent;

      // 触发消息更新回调
      onMessageUpdated?.call(groupId);

      DebugLogger().info('MessageService: 消息发送成功 $messageId', tag: 'MESSAGE');
      return message;
    } catch (e) {
      DebugLogger().error('MessageService: 发送消息失败 $e', tag: 'MESSAGE');
      return null;
    }
  }

  /// 接收消息
  Future<Message?> receiveMessage(
    String groupId,
    Map<String, dynamic> encryptedMessage, {
    Map<String, String>? userPublicKeyMap, // 新增参数，userId->publicKey
  }) async {
    try {
      DebugLogger().info('MessageService: 接收消息', tag: 'MESSAGE');

      // 解析网络消息
      final networkMessage = NetworkMessage.fromJson(encryptedMessage);

      // 检查重放攻击
      if (_isReplayAttack(networkMessage)) {
        DebugLogger().warning('MessageService: 检测到重放攻击，忽略消息', tag: 'MESSAGE');
        return null;
      }

      // 获取群组信息
      final group = await StorageService.loadGroup(groupId);
      if (group == null) {
        DebugLogger().error('MessageService: 群组不存在 $groupId', tag: 'MESSAGE');
        return null;
      }

      // 1. 获取senderId和消息体中的publicKey
      final senderId = networkMessage.senderId;
      final msgPublicKey =
          encryptedMessage['publicKey'] ??
          (networkMessage.metadata != null
              ? networkMessage.metadata['publicKey']
              : null);
      if (msgPublicKey == null) {
        DebugLogger().error('MessageService: 消息缺少publicKey', tag: 'MESSAGE');
        return null;
      }
      // 2. 查本地公钥
      String? localPublicKey;
      final member = group.members.where((m) => m.userId == senderId).isNotEmpty
          ? group.members.firstWhere((m) => m.userId == senderId)
          : null;
      if (userPublicKeyMap != null) {
        localPublicKey = userPublicKeyMap[senderId];
      } else {
        localPublicKey = member?.publicKey;
      }
      if (localPublicKey == null) {
        DebugLogger().error(
          'MessageService: 本地未找到senderId=$senderId的公钥',
          tag: 'MESSAGE',
        );
        return null;
      }
      // 3. double确认
      if (localPublicKey != msgPublicKey) {
        DebugLogger().error(
          '安全警告：本地公钥与消息体公钥不一致！senderId=$senderId, localPublicKey=$localPublicKey, msgPublicKey=$msgPublicKey',
          tag: 'MESSAGE',
        );
        return null;
      }
      // 4. 验签
      final signature = encryptedMessage['signature'];
      final cipherText = networkMessage.content;
      DebugLogger().info(
        'MessageService: 开始验签 senderId=$senderId, signature=${signature?.toString().substring(0, 8)}..., publicKey=${localPublicKey.substring(0, 8)}...',
        tag: 'MESSAGE',
      );
      final isValid = await Ed25519Helper.verify(
        cipherText,
        signature,
        localPublicKey,
      );
      if (!isValid) {
        DebugLogger().error(
          '签名校验失败！senderId=$senderId, signature=${signature?.toString().substring(0, 8)}..., publicKey=${localPublicKey.substring(0, 8)}...',
          tag: 'MESSAGE',
        );
        return null;
      } else {
        DebugLogger().info('签名校验通过 senderId=$senderId', tag: 'MESSAGE');
      }
      // 5. 验签通过，解密
      final decryptedText = await EncryptionService.decryptMessage(
        cipherText,
        group.sessionKey.key,
      );

      // 创建消息内容
      final decryptedContent = MessageContent(
        text: decryptedText,
        type: MessageType.text,
        data: {},
        size: decryptedText.length,
        encryptedContent: cipherText,
      );

      // 创建消息对象
      final message = Message(
        id: networkMessage.messageId,
        groupId: groupId,
        senderId: senderId,
        content: decryptedContent,
        type: networkMessage.type == NetworkMessage.TYPE_CHAT_MESSAGE
            ? MessageType.text
            : MessageType.system,
        timestamp: networkMessage.timestamp,
        status: MessageStatus.delivered,
        signature: signature,
        metadata: networkMessage.metadata,
        sequenceNumber: encryptedMessage['sequenceNumber'] ?? 0,
      );

      // 添加到本地消息列表
      _addMessageToGroup(groupId, message);

      // 保存到本地存储
      await StorageService.saveMessage(groupId, message);

      // 触发消息接收回调
      onMessageReceived?.call(groupId, message);
      onMessageUpdated?.call(groupId);

      DebugLogger().info(
        'MessageService: 消息接收成功 ${message.id}',
        tag: 'MESSAGE',
      );
      return message;
    } catch (e) {
      DebugLogger().error('MessageService: 接收消息失败 $e', tag: 'MESSAGE');
      return null;
    }
  }

  /// 获取群组消息
  Future<List<Message>> getMessages(
    String groupId, {
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      // 从本地缓存获取
      final cachedMessages = _groupMessages[groupId] ?? [];

      if (cachedMessages.isNotEmpty) {
        final start = offset;
        final end = (offset + limit).clamp(0, cachedMessages.length);
        return cachedMessages.sublist(start, end);
      }

      // 从存储加载
      final storedMessages = await StorageService.loadMessages(
        groupId,
        limit: limit,
        offset: offset,
      );

      // 更新缓存
      _groupMessages[groupId] = storedMessages;

      return storedMessages;
    } catch (e) {
      DebugLogger().error('MessageService: 获取消息失败 $e', tag: 'MESSAGE');
      return [];
    }
  }

  /// 搜索消息
  Future<List<Message>> searchMessages(String groupId, String query) async {
    try {
      final messages = _groupMessages[groupId] ?? [];
      final results = <Message>[];

      for (final message in messages) {
        if (message.content.text.toLowerCase().contains(query.toLowerCase())) {
          results.add(message);
        }
      }

      return results;
    } catch (e) {
      DebugLogger().error('MessageService: 搜索消息失败 $e', tag: 'MESSAGE');
      return [];
    }
  }

  /// 删除消息
  Future<bool> deleteMessage(String groupId, String messageId) async {
    try {
      // 从本地缓存删除
      final messages = _groupMessages[groupId];
      if (messages != null) {
        messages.removeWhere((msg) => msg.id == messageId);
      }

      // 从存储删除
      final success = await StorageService.deleteMessage(groupId, messageId);

      if (success) {
        onMessageUpdated?.call(groupId);
      }

      return success;
    } catch (e) {
      DebugLogger().error('MessageService: 删除消息失败 $e', tag: 'MESSAGE');
      return false;
    }
  }

  /// 标记消息为已读
  Future<bool> markAsRead(String groupId, String messageId) async {
    try {
      final messages = _groupMessages[groupId];
      if (messages != null) {
        final message = messages.firstWhere(
          (msg) => msg.id == messageId,
          orElse: () => Message(
            id: '',
            groupId: '',
            senderId: '',
            content: MessageContent(
              text: '',
              type: MessageType.text,
              data: {},
              size: 0,
            ),
            type: MessageType.text,
            timestamp: DateTime.now(),
            status: MessageStatus.read,
            signature: '',
            metadata: {},
            sequenceNumber: 0,
          ),
        );

        if (message.id.isNotEmpty) {
          message.status = MessageStatus.read;
          // 暂时注释掉，因为StorageService可能没有这个方法
          // await StorageService.updateMessageStatus(groupId, messageId, MessageStatus.read);
          onMessageUpdated?.call(groupId);
          return true;
        }
      }

      return false;
    } catch (e) {
      DebugLogger().error('MessageService: 标记消息已读失败 $e', tag: 'MESSAGE');
      return false;
    }
  }

  /// 添加消息到群组
  void _addMessageToGroup(String groupId, Message message) {
    if (!_groupMessages.containsKey(groupId)) {
      _groupMessages[groupId] = [];
    }
    _groupMessages[groupId]!.add(message);

    // 限制消息数量，避免内存溢出
    if (_groupMessages[groupId]!.length > 1000) {
      _groupMessages[groupId] = _groupMessages[groupId]!.take(500).toList();
    }
  }

  /// 生成消息ID
  String _generateMessageId(String senderId, String groupId) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = Random.secure().nextInt(1000000);
    final combined = '$senderId$groupId$timestamp$random';
    final hash = sha256.convert(utf8.encode(combined));
    return hash.toString().substring(0, 24);
  }

  /// 获取下一个序列号
  int _getNextSequenceNumber(String groupId) {
    _sequenceNumbers[groupId] = (_sequenceNumbers[groupId] ?? 0) + 1;
    return _sequenceNumbers[groupId]!;
  }

  /// 检查重放攻击
  bool _isReplayAttack(NetworkMessage message) {
    // 简单的重放攻击检测
    // 检查消息时间戳是否在合理范围内
    final now = DateTime.now();
    final messageTime = message.timestamp;
    final timeDiff = now.difference(messageTime).abs();

    // 如果消息时间超过5分钟，可能是重放攻击
    if (timeDiff > Duration(minutes: 5)) {
      return true;
    }

    // 这里可以添加更复杂的重放攻击检测逻辑
    // 比如检查消息ID是否已经处理过

    return false;
  }

  /// 清空群组消息缓存
  void clearGroupMessages(String groupId) {
    _groupMessages.remove(groupId);
    _sequenceNumbers.remove(groupId);
    DebugLogger().info('MessageService: 清空群组 $groupId 消息缓存', tag: 'MESSAGE');
  }

  /// 清空所有消息缓存
  void clearAllMessages() {
    _groupMessages.clear();
    _sequenceNumbers.clear();
    DebugLogger().info('MessageService: 清空所有消息缓存', tag: 'MESSAGE');
  }

  /// 获取群组消息数量
  int getMessageCount(String groupId) {
    return _groupMessages[groupId]?.length ?? 0;
  }

  /// 获取未读消息数量
  int getUnreadMessageCount(String groupId) {
    final messages = _groupMessages[groupId] ?? [];
    return messages.where((msg) => msg.status != MessageStatus.read).length;
  }
}
