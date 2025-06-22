import 'dart:convert';
import 'dart:math';
import '../models/group.dart';
import '../models/member.dart';
import '../models/message.dart';
import 'encryption_service.dart';
import 'key_service.dart';
import 'p2p_service.dart';
import 'storage_service.dart';
import 'dart:async';
import '../services/encryption_service.dart';

class GroupService {
  static final GroupService _instance = GroupService._internal();
  factory GroupService() => _instance;
  GroupService._internal();

  // 消息缓存
  final Map<String, List<Message>> _groupMessages = {};

  // 消息去重缓存 - 防止消息循环
  final Set<String> _processedMessageIds = {};
  final int _maxProcessedMessages = 1000; // 最多缓存1000条消息ID

  // 消息更新回调
  Function(String groupId)? onMessageUpdated;
  Function(String groupId)? onGroupUpdated;

  // 序列号管理
  final Map<String, int> _sequenceNumbers = {};

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
      P2PService.onMessageReceived = (message) {
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

    print('生成二维码数据: ${JsonEncoder.withIndent('  ').convert(qrData)}');
    print('端口类型: ${serverInfo['port'].runtimeType}');

    return jsonEncode(qrData);
  }

  /// 为群组创建者启动P2P服务器（应用启动时调用）
  Future<bool> startGroupServer(Group group) async {
    try {
      print('为群组 ${group.name} 启动P2P服务器...');

      // 启动P2P服务器
      final serverStarted = await P2PService.startServer();
      if (!serverStarted) {
        print('启动P2P服务器失败');
        return false;
      }

      // 设置连接验证器
      print('设置连接验证器...');
      P2PService.setConnectionValidator(_validateConnection);
      print('连接验证器设置完成');

      // 显示服务器状态
      final status = P2PService.getServerStatus();
      print('P2P服务器状态: $status');

      // 设置消息处理回调
      P2PService.onMessageReceived = (message) {
        _handleIncomingMessage(group, message);
      };

      // 监听连接事件
      P2PService.connectionEvents.listen((event) {
        _handleConnectionEvent(group, event);
      });

      print('群组 ${group.name} 的P2P服务器启动成功');
      return true;
    } catch (e) {
      print('启动群组服务器失败: $e');
      return false;
    }
  }

  /// 确保群组服务器运行
  Future<bool> ensureGroupServerRunning(Group group) async {
    try {
      print('确保群组 ${group.name} 的P2P服务器运行');

      // 启动P2P服务器
      final success = await P2PService.startServer();
      if (success) {
        print('P2P服务器启动成功');

        // 设置连接验证器
        print('设置连接验证器...');
        P2PService.setConnectionValidator(_validateConnection);
        print('连接验证器设置完成');

        // 设置消息处理回调
        P2PService.onMessageReceived = (message) {
          _handleIncomingMessage(group, message);
        };

        // 监听连接事件
        P2PService.connectionEvents.listen((event) {
          _handleConnectionEvent(group, event);
        });

        return true;
      } else {
        print('P2P服务器启动失败');
        return false;
      }
    } catch (e) {
      print('确保群组服务器运行失败: $e');
      return false;
    }
  }

  /// 处理连接事件
  void _handleConnectionEvent(Group group, ConnectionEvent event) {
    switch (event.type) {
      case ConnectionEventType.connected:
        print('用户 ${event.userId} 连接到群组 ${group.name}');
        break;
      case ConnectionEventType.disconnected:
        print('用户 ${event.userId} 从群组 ${group.name} 断开连接');
        break;
      case ConnectionEventType.error:
        print('群组 ${group.name} 连接错误: ${event.error}');
        break;
      default:
        break;
    }
  }

  /// 检查群组状态
  Future<bool> checkGroupStatus(Group group) async {
    try {
      print('检查群组 ${group.name} 状态...');

      final serverStatus = P2PService.getServerStatus();
      final isRunning = serverStatus['isRunning'] as bool;

      if (!isRunning) {
        print('P2P服务器未运行，尝试重启...');
        return await ensureGroupServerRunning(group);
      }

      // 检查群组连接数
      final groupConnections =
          serverStatus['groupConnections'] as Map<String, int>;
      final connectionCount = groupConnections[group.id] ?? 0;

      print('群组 ${group.name} 当前连接数: $connectionCount');

      return true;
    } catch (e) {
      print('检查群组状态失败: $e');
      return false;
    }
  }

  /// 重新连接群组
  Future<bool> reconnectToGroup(Group group, String userId) async {
    try {
      print('重新连接到群组 ${group.name}...');

      // 先停止当前连接
      await P2PService.stopServer();

      // 重新启动服务器
      final success = await startGroupServer(group);
      if (success) {
        // 更新群组状态为可用
        group.status = GroupStatus.active;
        await StorageService.saveGroup(group);

        print('重新连接群组 ${group.name} 成功');
        return true;
      } else {
        // 更新群组状态为不可用
        group.status = GroupStatus.unavailable;
        await StorageService.saveGroup(group);

        print('重新连接群组 ${group.name} 失败');
        return false;
      }
    } catch (e) {
      // 更新群组状态为不可用
      group.status = GroupStatus.unavailable;
      await StorageService.saveGroup(group);

      print('重新连接群组失败: $e');
      return false;
    }
  }

  /// 重启群组服务器
  Future<bool> restartGroupServer(Group group) async {
    try {
      print('重启群组 ${group.name} 的P2P服务器...');

      // 停止服务器
      await P2PService.stopServer();

      // 重新启动
      final success = await startGroupServer(group);
      if (success) {
        print('重启群组 ${group.name} 的P2P服务器成功');
        return true;
      } else {
        print('重启群组 ${group.name} 的P2P服务器失败');
        return false;
      }
    } catch (e) {
      print('重启群组服务器失败: $e');
      return false;
    }
  }

  /// 连接到群组服务器
  Future<bool> connectToGroupServer(Group group, String userId) async {
    try {
      print('连接到群组 ${group.name} 的P2P服务器 (用户: $userId)');

      // 从群组二维码数据中解析连接信息
      final qrData = await generateGroupQRData(group);
      if (qrData == null) {
        print('无法生成群组二维码数据');
        return false;
      }

      // 解析二维码数据获取IP和端口
      final qrDataMap = jsonDecode(qrData);
      final serverIP = qrDataMap['serverIP'];
      final serverPort = qrDataMap['serverPort'];

      print('解析的服务器信息: $serverIP:$serverPort');

      // 连接到P2P服务器
      final success = await P2PService.connectToServer(
        serverIP,
        serverPort,
        userId,
        group.id,
      );
      if (success) {
        print('成功连接到群组服务器');

        // 设置消息处理回调
        P2PService.onMessageReceived = (message) {
          _handleIncomingMessage(group, message);
        };

        return true;
      } else {
        print('连接群组服务器失败');
        return false;
      }
    } catch (e) {
      print('连接群组服务器异常: $e');
      return false;
    }
  }

  /// 验证连接
  Future<bool> _validateConnection(
    String userId,
    String groupId,
    bool isNewMember,
  ) async {
    try {
      print('验证连接: 用户 $userId 加入群组 $groupId (新成员: $isNewMember)');

      // 检查群组是否存在
      final group = await StorageService.loadGroup(groupId);
      if (group == null) {
        print('群组不存在: $groupId');
        return false;
      }

      // 检查群组状态
      if (group.status != GroupStatus.active) {
        print('群组状态无效: ${group.status}');
        return false;
      }

      if (isNewMember) {
        // 新成员加入验证：检查群组是否已满
        if (group.members.length >= 10) {
          // 假设最大成员数为10
          print('群组 $groupId 已满');
          return false;
        }
        print('新成员验证通过');
        return true;
      } else {
        // 已加入成员验证：检查用户是否为群组成员
        final existingMember = group.members.firstWhere(
          (member) => member.userId == userId,
          orElse: () => Member(
            id: '',
            userId: '',
            groupId: '',
            name: '',
            publicKey: '',
            joinedAt: DateTime.now(),
            lastSeen: DateTime.now(),
            role: MemberRole.member,
            status: MemberStatus.inactive,
          ),
        );

        if (existingMember.userId.isEmpty) {
          print('用户 $userId 不是群组 $groupId 的成员');
          return false;
        }

        if (existingMember.status != MemberStatus.active) {
          print('成员状态无效: ${existingMember.status}');
          return false;
        }

        print('已加入成员验证通过');
        return true;
      }
    } catch (e) {
      print('连接验证失败: $e');
      return false;
    }
  }

  /// 加入群组
  Future<bool> joinGroup(
    String qrCodeData,
    String userId,
    String userName,
  ) async {
    try {
      print('开始加入群组...');
      print('二维码数据: $qrCodeData');

      // 解析二维码数据
      final qrData = jsonDecode(qrCodeData);
      final groupId = qrData['groupId'];
      final serverIP = qrData['serverIP'];
      final serverPort = qrData['serverPort'];

      print('解析结果: 群组ID=$groupId, 服务器=$serverIP:$serverPort');

      // 加载群组信息
      final group = await StorageService.loadGroup(groupId);
      if (group == null) {
        print('群组不存在: $groupId');
        return false;
      }

      // 检查用户是否已经是群组成员
      final existingMember = group.members.firstWhere(
        (member) => member.userId == userId,
        orElse: () => Member(
          id: '',
          userId: '',
          groupId: '',
          name: '',
          publicKey: '',
          joinedAt: DateTime.now(),
          lastSeen: DateTime.now(),
          role: MemberRole.member,
          status: MemberStatus.inactive,
        ),
      );

      if (existingMember.userId.isNotEmpty) {
        print('用户已经是群组成员，直接连接...');
        return await connectToGroupServer(group, userId);
      }

      // 连接到P2P服务器
      final success = await P2PService.connectToServer(
        serverIP,
        serverPort,
        userId,
        groupId,
      );
      if (!success) {
        print('连接P2P服务器失败');
        return false;
      }

      // 设置消息处理回调
      P2PService.onMessageReceived = (message) {
        _handleIncomingMessage(group, message);
      };

      // 生成用户密钥对
      final userKeyPair = await KeyService.generateUserKeyPair();

      // 创建新成员
      final newMember = Member(
        id: _generateMemberId(),
        userId: userId,
        groupId: groupId,
        name: userName,
        publicKey: userKeyPair['publicKey']!,
        joinedAt: DateTime.now(),
        lastSeen: DateTime.now(),
        role: MemberRole.member,
        status: MemberStatus.active,
      );

      // 添加到群组
      group.addMember(newMember);

      // 保存群组
      await StorageService.saveGroup(group);

      // 初始化群组消息列表
      _groupMessages[groupId] = [];

      print('成功加入群组: ${group.name}');
      return true;
    } catch (e) {
      print('加入群组失败: $e');
      return false;
    }
  }

  /// 发送消息
  Future<bool> sendMessage(
    String groupId,
    String senderId,
    String content,
  ) async {
    try {
      print('发送消息到群组: $groupId');
      print('发送者: $senderId');
      print('内容: $content');

      // 获取群组
      final group = await StorageService.loadGroup(groupId);
      if (group == null) {
        print('群组不存在: $groupId');
        return false;
      }

      // 检查发送者是否为群组成员
      final sender = group.members.firstWhere(
        (member) => member.userId == senderId,
        orElse: () => Member(
          id: '',
          userId: '',
          groupId: '',
          name: '',
          publicKey: '',
          joinedAt: DateTime.now(),
          lastSeen: DateTime.now(),
          role: MemberRole.member,
          status: MemberStatus.inactive,
        ),
      );

      if (sender.userId.isEmpty) {
        print('发送者不是群组成员: $senderId');
        return false;
      }

      // 生成消息ID
      final messageId = _generateMessageId();
      final sequenceNumber = DateTime.now().millisecondsSinceEpoch;

      // 创建消息
      final message = Message(
        id: messageId,
        groupId: groupId,
        senderId: senderId,
        content: MessageContent(
          text: content,
          type: MessageType.text,
          data: {},
          size: content.length,
        ),
        type: MessageType.text,
        timestamp: DateTime.now(),
        status: MessageStatus.sending,
        signature: '',
        metadata: {},
        sequenceNumber: sequenceNumber,
      );

      // 加密消息内容
      final encryptedContent = EncryptionService.encryptMessage(
        message.content.text,
        group.sessionKey.key,
      );

      // 创建网络消息
      final networkMessage = {
        'type': NetworkMessage.TYPE_CHAT_MESSAGE,
        'messageId': messageId,
        'groupId': groupId,
        'senderId': senderId,
        'content': encryptedContent,
        'timestamp': message.timestamp.millisecondsSinceEpoch,
        'metadata': {'senderName': sender.name, 'messageType': 'text'},
        'sequenceNumber': sequenceNumber,
      };

      // 广播消息
      print('准备广播消息到群组: $groupId');
      print('消息内容: ${jsonEncode(networkMessage)}');

      // 检查P2P服务是否运行
      final serverStatus = P2PService.getServerStatus();
      print('P2P服务器状态: ${jsonEncode(serverStatus)}');

      // 获取群组连接信息
      final connections = P2PService.getConnectionsByGroup(groupId);
      print('群组 $groupId 的连接数: ${connections.length}');
      for (final conn in connections) {
        print(
          '  - 连接: ${conn.connectionId} (用户: ${conn.userId}, 状态: ${conn.status})',
        );
      }

      P2PService.broadcastMessage(networkMessage);

      // 注意：不要在这里立即添加消息到本地列表
      // 消息会通过P2P网络广播，然后通过_handleChatMessage方法接收并添加
      // 这样可以避免重复消息问题

      print('消息发送成功');
      return true;
    } catch (e) {
      print('发送消息失败: $e');
      return false;
    }
  }

  /// 获取群组消息
  List<Message> getGroupMessages(String groupId) {
    return _groupMessages[groupId] ?? [];
  }

  /// 从本地存储加载群组消息到内存缓存
  Future<void> loadGroupMessagesFromStorage(String groupId) async {
    try {
      print('[GroupService] 开始加载群组消息: $groupId');
      final messages = await StorageService.loadMessages(
        groupId,
        limit: 100, // 加载最近100条消息
        offset: 0,
      );

      _groupMessages[groupId] = messages;
      print('[GroupService] 群组 $groupId 加载了 ${messages.length} 条消息');
    } catch (e) {
      print('[GroupService] 加载群组消息失败: $e');
      _groupMessages[groupId] = [];
    }
  }

  /// 加载所有群组的消息
  Future<void> loadAllGroupMessages() async {
    try {
      print('[GroupService] 开始加载所有群组消息...');
      final groups = await StorageService.loadAllGroups();

      for (final group in groups) {
        await loadGroupMessagesFromStorage(group.id);
      }

      print('[GroupService] 所有群组消息加载完成');
    } catch (e) {
      print('[GroupService] 加载所有群组消息失败: $e');
    }
  }

  /// 添加消息到群组
  void _addMessageToGroup(String groupId, Message message) {
    if (!_groupMessages.containsKey(groupId)) {
      _groupMessages[groupId] = [];
    }
    _groupMessages[groupId]!.add(message);
  }

  /// 处理接收到的消息
  void _handleIncomingMessage(Group group, Map<String, dynamic> message) {
    try {
      print('处理接收消息: ${message['type']}');

      final messageType = message['type'];
      final groupId = message['groupId'] as String?;

      // 对于心跳消息等不需要groupId的消息，直接跳过
      if (messageType == 'heartbeat' || groupId == null || groupId.isEmpty) {
        print('跳过系统消息或无效groupId的消息: $messageType');
        return;
      }

      switch (messageType) {
        case NetworkMessage.TYPE_CHAT_MESSAGE:
          _handleChatMessage(group, message);
          break;
        case NetworkMessage.TYPE_JOIN_REQUEST:
          _handleJoinRequest(group, message);
          break;
        case NetworkMessage.TYPE_MEMBER_JOINED:
          _handleMemberJoined(group, message);
          break;
        case NetworkMessage.TYPE_MEMBER_LEFT:
          _handleMemberLeft(group, message);
          break;
        default:
          print('未知消息类型: $messageType');
      }
    } catch (e) {
      print('_handleIncomingMessage 处理接收消息失败: $e');
    }
  }

  /// 处理聊天消息
  void _handleChatMessage(Group group, Map<String, dynamic> message) async {
    try {
      final messageId = message['messageId'];
      final senderId = message['senderId'];
      final encryptedContent = message['content'];
      final sequenceNumber =
          message['sequenceNumber'] ?? DateTime.now().millisecondsSinceEpoch;

      // 检查消息是否已经处理过（防止消息循环）
      if (_processedMessageIds.contains(messageId)) {
        print('消息已处理过，跳过: $messageId');
        return;
      }

      // 添加到已处理消息列表
      _processedMessageIds.add(messageId);

      // 清理过期的消息ID（保持缓存大小）
      if (_processedMessageIds.length > _maxProcessedMessages) {
        final toRemove = _processedMessageIds
            .take(_processedMessageIds.length - _maxProcessedMessages)
            .toList();
        for (final id in toRemove) {
          _processedMessageIds.remove(id);
        }
      }

      print('处理新消息: $messageId (发送者: $senderId)');

      // 解密消息内容
      final decryptedContent = EncryptionService.decryptMessage(
        encryptedContent,
        group.sessionKey.key,
      );

      // 创建消息对象
      final chatMessage = Message(
        id: messageId,
        groupId: group.id,
        senderId: senderId,
        content: MessageContent(
          text: decryptedContent,
          type: MessageType.text,
          data: {},
          size: decryptedContent.length,
        ),
        type: MessageType.text,
        timestamp: DateTime.fromMillisecondsSinceEpoch(message['timestamp']),
        status: MessageStatus.delivered,
        signature: message['signature'] ?? '',
        metadata: message['metadata'] ?? {},
        sequenceNumber: sequenceNumber,
      );

      // 添加到本地消息列表
      _addMessageToGroup(group.id, chatMessage);

      // 保存到本地存储
      await StorageService.saveMessage(group.id, chatMessage);

      // 触发消息更新回调
      if (onMessageUpdated != null) {
        onMessageUpdated!(group.id);
      }

      print('聊天消息处理完成: $messageId');
    } catch (e) {
      print('处理聊天消息失败: $e');
    }
  }

  /// 处理加入请求
  void _handleJoinRequest(Group group, Map<String, dynamic> message) async {
    try {
      final userId = message['senderId'];
      final userName = message['userName'] ?? 'Unknown';
      final userPublicKey = message['publicKey'];

      print('处理加入请求: 用户=$userId, 姓名=$userName');

      // 检查群组是否已满
      if (group.members.length >= 10) {
        print('群组已满，拒绝加入请求');
        _sendJoinResponse(userId, group.id, false, '群组已满');
        return;
      }

      // 创建新成员
      final newMember = Member(
        id: _generateMemberId(),
        userId: userId,
        groupId: group.id,
        name: userName,
        publicKey: userPublicKey,
        joinedAt: DateTime.now(),
        lastSeen: DateTime.now(),
        role: MemberRole.member,
        status: MemberStatus.active,
      );

      // 添加到群组
      group.addMember(newMember);

      // 保存群组
      await StorageService.saveGroup(group);

      // 发送加入响应
      _sendJoinResponse(userId, group.id, true, null);

      // 广播成员加入消息
      _broadcastMemberJoined(group, newMember);

      // 触发群组更新回调
      if (onGroupUpdated != null) {
        onGroupUpdated!(group.id);
      }

      print('成员加入成功: $userName');
    } catch (e) {
      print('处理加入请求失败: $e');
    }
  }

  /// 发送加入响应
  void _sendJoinResponse(
    String userId,
    String groupId,
    bool success,
    String? reason,
  ) async {
    // 需要从存储中获取群组信息
    final group = await StorageService.loadGroup(groupId);
    if (group == null) {
      print('群组不存在: $groupId');
      return;
    }

    final response = {
      'type': NetworkMessage.TYPE_JOIN_RESPONSE,
      'messageId': _generateMessageId(),
      'groupId': groupId,
      'senderId': 'system',
      'content': {
        'success': success,
        'reason': reason,
        'sessionKey': success ? group.sessionKey.key : null,
      },
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    P2PService.sendToUser(userId, groupId, response);
  }

  /// 广播成员加入消息
  void _broadcastMemberJoined(Group group, Member member) {
    final message = {
      'type': NetworkMessage.TYPE_MEMBER_JOINED,
      'messageId': _generateMessageId(),
      'groupId': group.id,
      'senderId': 'system',
      'content': {
        'memberId': member.id,
        'userId': member.userId,
        'name': member.name,
        'joinedAt': member.joinedAt.millisecondsSinceEpoch,
      },
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    P2PService.broadcastMessage(message);
  }

  /// 处理成员加入消息
  void _handleMemberJoined(Group group, Map<String, dynamic> message) {
    try {
      final content = message['content'];
      final memberId = content['memberId'];
      final userId = content['userId'];
      final name = content['name'];

      print('成员加入: $name ($userId)');

      // 触发群组更新回调
      if (onGroupUpdated != null) {
        onGroupUpdated!(group.id);
      }
    } catch (e) {
      print('处理成员加入消息失败: $e');
    }
  }

  /// 处理成员离开消息
  void _handleMemberLeft(Group group, Map<String, dynamic> message) {
    try {
      final content = message['content'];
      final userId = content['userId'];
      final name = content['name'];

      print('成员离开: $name ($userId)');

      // 触发群组更新回调
      if (onGroupUpdated != null) {
        onGroupUpdated!(group.id);
      }
    } catch (e) {
      print('处理成员离开消息失败: $e');
    }
  }

  /// 离开群组
  Future<bool> leaveGroup(String groupId, String userId) async {
    try {
      print('用户 $userId 离开群组 $groupId');

      final group = await StorageService.loadGroup(groupId);
      if (group == null) {
        print('群组不存在: $groupId');
        return false;
      }

      // 查找成员
      final member = group.members.firstWhere(
        (m) => m.userId == userId,
        orElse: () => Member(
          id: '',
          userId: '',
          groupId: '',
          name: '',
          publicKey: '',
          joinedAt: DateTime.now(),
          lastSeen: DateTime.now(),
          role: MemberRole.member,
          status: MemberStatus.inactive,
        ),
      );

      if (member.userId.isEmpty) {
        print('用户不是群组成员: $userId');
        return false;
      }

      // 移除成员
      group.members.remove(member);

      // 保存群组
      await StorageService.saveGroup(group);

      // 广播成员离开消息
      final message = {
        'type': NetworkMessage.TYPE_MEMBER_LEFT,
        'messageId': _generateMessageId(),
        'groupId': groupId,
        'senderId': 'system',
        'content': {
          'userId': userId,
          'name': member.name,
          'leftAt': DateTime.now().millisecondsSinceEpoch,
        },
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      P2PService.broadcastMessage(message);

      // 触发群组更新回调
      if (onGroupUpdated != null) {
        onGroupUpdated!(groupId);
      }

      print('成功离开群组');
      return true;
    } catch (e) {
      print('离开群组失败: $e');
      return false;
    }
  }

  /// 解散群组
  Future<bool> disbandGroup(String groupId, String creatorId) async {
    try {
      print('解散群组: $groupId');

      final group = await StorageService.loadGroup(groupId);
      if (group == null) {
        print('群组不存在: $groupId');
        return false;
      }

      // 检查是否为创建者
      if (group.creatorId != creatorId) {
        print('只有创建者可以解散群组');
        return false;
      }

      // 广播群组解散消息
      final message = {
        'type': NetworkMessage.TYPE_GROUP_UPDATE,
        'messageId': _generateMessageId(),
        'groupId': groupId,
        'senderId': 'system',
        'content': {'action': 'disband', 'reason': '群组被创建者解散'},
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      P2PService.broadcastMessage(message);

      // 删除群组
      await StorageService.deleteGroup(groupId);

      // 清理消息缓存
      _groupMessages.remove(groupId);

      print('群组解散成功');
      return true;
    } catch (e) {
      print('解散群组失败: $e');
      return false;
    }
  }

  /// 检查群组连接状态
  Future<bool> checkGroupConnectionStatus(Group group) async {
    try {
      print('检查群组 ${group.name} 连接状态...');

      final serverStatus = P2PService.getServerStatus();
      final isRunning = serverStatus['isRunning'] as bool;

      if (!isRunning) {
        print('P2P服务器未运行');
        return false;
      }

      // 检查群组连接数
      final groupConnections =
          serverStatus['groupConnections'] as Map<String, int>;
      final connectionCount = groupConnections[group.id] ?? 0;

      print('群组 ${group.name} 当前连接数: $connectionCount');

      return connectionCount > 0;
    } catch (e) {
      print('检查群组连接状态失败: $e');
      return false;
    }
  }

  /// 获取群组
  Group? getGroup(String groupId) {
    // 这里需要从存储中加载群组
    // 暂时返回null，实际应该从StorageService加载
    return null;
  }

  /// 获取所有群组
  List<Group> getAllGroups() {
    // 这里需要从存储中加载所有群组
    // 暂时返回空列表，实际应该从StorageService加载
    return [];
  }

  /// 生成群组ID
  String _generateGroupId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = Random().nextInt(10000);
    return 'group_${timestamp}_$random';
  }

  /// 生成成员ID
  String _generateMemberId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = Random().nextInt(10000);
    return 'member_${timestamp}_$random';
  }

  /// 生成消息ID
  String _generateMessageId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = Random().nextInt(1000000);
    return 'msg_${timestamp}_$random';
  }

  /// 清空所有群组消息缓存
  void clearAllGroupMessages() {
    _groupMessages.clear();
    print('已清空所有群组消息缓存');
  }
}
