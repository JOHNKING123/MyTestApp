import 'dart:convert';
import 'dart:math';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/group.dart';
import '../models/member.dart';
import '../models/message.dart';
import 'encryption_service.dart';
import 'key_service.dart';
import 'p2p_service.dart';

class GroupService {
  static final GroupService _instance = GroupService._internal();
  factory GroupService() => _instance;
  GroupService._internal();

  final Map<String, List<Message>> _groupMessages = {};
  final Map<String, int> _sequenceNumbers = {};

  // 添加消息更新回调
  Function(String groupId)? onMessageUpdated;

  /// 创建群组
  Future<Group?> createGroup(
    String name,
    String creatorId,
    String creatorName,
  ) async {
    try {
      // 生成群组ID
      final groupId = _generateGroupId();

      // 生成群组密钥对
      final keyPair = await KeyService.generateUserKeyPair();
      final groupKeys = GroupKeyPair(
        publicKey: keyPair['publicKey']!,
        privateKey: keyPair['privateKey']!,
        createdAt: DateTime.now(),
      );

      // 生成会话密钥
      final sessionKey = SessionKey(
        key: await KeyService.generateGroupKey(),
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(Duration(days: 30)),
        version: 1,
      );

      // 创建群组
      final group = Group(
        id: groupId,
        name: name,
        creatorId: creatorId,
        createdAt: DateTime.now(),
        groupKeys: groupKeys,
        sessionKey: sessionKey,
        status: GroupStatus.active,
      );

      // 初始化群组消息列表
      _groupMessages[groupId] = [];

      // 添加创建者为成员
      final userKeyPair = await KeyService.generateUserKeyPair();
      final creator = Member(
        id: _generateMemberId(),
        userId: creatorId,
        groupId: groupId,
        name: creatorName,
        publicKey: userKeyPair['publicKey']!,
        joinedAt: DateTime.now(),
        lastSeen: DateTime.now(),
        role: MemberRole.creator,
        status: MemberStatus.active,
      );

      group.addMember(creator);

      // 启动P2P服务器
      final serverStarted = await P2PService.startServer();
      if (!serverStarted) {
        print('启动P2P服务器失败');
        return null;
      }

      // 设置消息处理回调
      P2PService.onMessage = (message) {
        _handleIncomingMessage(group, message);
      };

      return group;
    } catch (e) {
      print('创建群组失败: $e');
      return null;
    }
  }

  /// 生成群组二维码数据
  Future<String> generateGroupQRData(Group group) async {
    final serverInfo = await P2PService.getServerInfo();
    final qrData = {
      'type': 'group_join',
      'groupId': group.id,
      'groupName': group.name,
      'serverIP': serverInfo['ip'],
      'serverPort': serverInfo['port'],
      'sessionKey': group.sessionKey.key,
    };
    return jsonEncode(qrData);
  }

  /// 加入群组
  Future<bool> joinGroup(String qrData, String userId, String userName) async {
    try {
      final data = jsonDecode(qrData);
      if (data['type'] != 'group_join') {
        print('无效的二维码数据');
        return false;
      }

      // 连接到P2P服务器
      final connected = await P2PService.connectToServer(
        data['serverIP'],
        data['serverPort'],
      );

      if (!connected) {
        print('连接P2P服务器失败');
        return false;
      }

      // 设置消息处理回调
      P2PService.onMessage = (message) {
        _handleIncomingMessage(null, message);
      };

      // 发送加入请求
      final userKeyPair = await KeyService.generateUserKeyPair();
      final joinMessage = {
        'type': 'member_join',
        'userId': userId,
        'userName': userName,
        'publicKey': userKeyPair['publicKey'],
        'timestamp': DateTime.now().toIso8601String(),
      };

      P2PService.broadcastMessage(joinMessage);

      return true;
    } catch (e) {
      print('加入群组失败: $e');
      return false;
    }
  }

  /// 发送消息
  Future<bool> sendMessage(Group group, String senderId, String content) async {
    try {
      print('开始发送消息: $content');

      // 加密消息
      final encryptedContent = EncryptionService.encryptMessage(
        content,
        group.sessionKey.key,
      );

      print('消息加密成功');

      // 创建消息内容
      final messageContent = MessageContent(
        text: content,
        type: MessageType.text,
        size: content.length,
        encryptedContent: encryptedContent,
      );

      final message = Message(
        id: _generateMessageId(),
        groupId: group.id,
        senderId: senderId,
        content: messageContent,
        type: MessageType.text,
        timestamp: DateTime.now(),
        signature: _generateSignature(senderId, content),
        sequenceNumber: _getNextSequenceNumber(group.id),
      );

      // 添加到本地消息列表
      if (_groupMessages[group.id] == null) {
        _groupMessages[group.id] = [];
      }
      _groupMessages[group.id]!.add(message);

      print('消息已添加到本地列表，当前消息数: ${_groupMessages[group.id]!.length}');

      // 广播消息
      final messageData = {
        'type': 'message',
        'groupId': group.id,
        'message': {
          'id': message.id,
          'senderId': message.senderId,
          'content': message.content.toJson(),
          'timestamp': message.timestamp.toIso8601String(),
          'type': message.type.toString(),
          'signature': message.signature,
          'sequenceNumber': message.sequenceNumber,
        },
      };

      print('准备广播消息到P2P网络');
      P2PService.broadcastMessage(messageData);
      print('消息广播完成');

      return true;
    } catch (e) {
      print('发送消息失败: $e');
      return false;
    }
  }

  /// 获取群组消息
  List<Message> getGroupMessages(String groupId) {
    final messages = _groupMessages[groupId] ?? [];
    print('获取群组 $groupId 的消息，共 ${messages.length} 条');
    return messages;
  }

  /// 处理接收到的消息
  void _handleIncomingMessage(Group? group, Map<String, dynamic> message) {
    try {
      print('收到消息: ${message['type']}');
      switch (message['type']) {
        case 'message':
          _handleChatMessage(group, message);
          break;
        case 'member_join':
          _handleMemberJoin(group, message);
          break;
        case 'member_leave':
          _handleMemberLeave(group, message);
          break;
        default:
          print('未知消息类型: ${message['type']}');
      }
    } catch (e) {
      print('处理消息失败: $e');
    }
  }

  /// 处理聊天消息
  void _handleChatMessage(Group? group, Map<String, dynamic> message) {
    print('处理聊天消息，group: ${group?.id}');

    try {
      final messageData = message['message'];
      final contentData = messageData['content'];

      // 创建消息内容
      final messageContent = MessageContent.fromJson(contentData);

      // 解密消息
      final decryptedText = EncryptionService.decryptMessage(
        messageContent.encryptedContent ?? '',
        group?.sessionKey.key ?? '',
      );

      // 创建解密后的消息内容
      final decryptedContent = MessageContent(
        text: decryptedText,
        type: MessageType.text,
        size: decryptedText.length,
        encryptedContent: messageContent.encryptedContent,
      );

      final chatMessage = Message(
        id: messageData['id'],
        groupId: messageData['groupId'] ?? group?.id ?? '',
        senderId: messageData['senderId'],
        content: decryptedContent,
        timestamp: DateTime.parse(messageData['timestamp']),
        type: MessageType.values.firstWhere(
          (e) => e.toString() == messageData['type'],
        ),
        signature: messageData['signature'],
        sequenceNumber: messageData['sequenceNumber'],
      );

      // 添加到群组消息列表
      final groupId = chatMessage.groupId;
      if (_groupMessages[groupId] == null) {
        _groupMessages[groupId] = [];
      }
      _groupMessages[groupId]!.add(chatMessage);

      // 通知UI更新
      print(
        '收到消息: $decryptedText，群组: $groupId，总消息数: ${_groupMessages[groupId]!.length}',
      );

      // 调用回调通知UI更新
      if (onMessageUpdated != null) {
        onMessageUpdated!(groupId);
      }
    } catch (e) {
      print('处理聊天消息失败: $e');
    }
  }

  /// 处理成员加入
  void _handleMemberJoin(Group? group, Map<String, dynamic> message) {
    if (group == null) return;

    final member = Member(
      id: _generateMemberId(),
      userId: message['userId'],
      groupId: group.id,
      name: message['userName'],
      publicKey: message['publicKey'],
      joinedAt: DateTime.parse(message['timestamp']),
      lastSeen: DateTime.now(),
      role: MemberRole.member,
      status: MemberStatus.active,
    );

    group.addMember(member);
    print('成员加入: ${member.name}');
  }

  /// 处理成员离开
  void _handleMemberLeave(Group? group, Map<String, dynamic> message) {
    if (group == null) return;

    group.removeMember(message['userId']);
    print('成员离开: ${message['userName']}');
  }

  /// 离开群组
  Future<bool> leaveGroup(Group group, String userId) async {
    try {
      final leaveMessage = {
        'type': 'member_leave',
        'userId': userId,
        'timestamp': DateTime.now().toIso8601String(),
      };

      P2PService.broadcastMessage(leaveMessage);
      P2PService.disconnect();

      return true;
    } catch (e) {
      print('离开群组失败: $e');
      return false;
    }
  }

  /// 解散群组
  Future<bool> disbandGroup(Group group) async {
    try {
      final disbandMessage = {
        'type': 'group_disband',
        'groupId': group.id,
        'timestamp': DateTime.now().toIso8601String(),
      };

      P2PService.broadcastMessage(disbandMessage);
      P2PService.stopServer();

      return true;
    } catch (e) {
      print('解散群组失败: $e');
      return false;
    }
  }

  /// 生成群组ID
  String _generateGroupId() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return String.fromCharCodes(
      Iterable.generate(
        8,
        (_) => chars.codeUnitAt(random.nextInt(chars.length)),
      ),
    );
  }

  /// 生成唯一ID
  String _generateId() {
    return DateTime.now().millisecondsSinceEpoch.toString() +
        Random().nextInt(1000).toString();
  }

  /// 生成消息ID
  String _generateMessageId() {
    return 'msg_${_generateId()}';
  }

  /// 生成成员ID
  String _generateMemberId() {
    return 'member_${_generateId()}';
  }

  /// 生成签名
  String _generateSignature(String senderId, String content) {
    return 'sig_${senderId}_${content.hashCode}';
  }

  /// 获取下一个序列号
  int _getNextSequenceNumber(String groupId) {
    _sequenceNumbers[groupId] = (_sequenceNumbers[groupId] ?? 0) + 1;
    return _sequenceNumbers[groupId]!;
  }
}
