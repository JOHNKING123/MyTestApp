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
import '../utils/debug_logger.dart';
import '../services/message_service.dart';
import 'key_manager.dart';

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
      final keyPair = await Ed25519Helper.generateKeyPair();
      final groupKeys = GroupKeyPair(
        publicKey: keyPair['publicKey']!,
        privateKey: keyPair['privateKey']!,
        createdAt: DateTime.now(),
      );

      // 生成会话密钥
      final sessionKey = SessionKey(
        key: await KeyService.generateGroupSessionKey(),
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

      // 添加创建者为成员（用注册时密钥）
      final userKeyPair = await KeyManager.loadUserKeyPair(creatorId);
      if (userKeyPair == null) {
        DebugLogger().error('创建群组失败：未找到当前用户密钥对', tag: 'GROUP');
        return null;
      }
      final creator = Member(
        id: _generateMemberId(),
        userId: creatorId,
        groupId: groupId,
        name: creatorName,
        publicKey: userKeyPair.publicKey,
        joinedAt: DateTime.now(),
        lastSeen: DateTime.now(),
        role: MemberRole.creator,
        status: MemberStatus.active,
      );

      group.addMember(creator);

      // 启动P2P服务器
      final serverStarted = await P2PService.startServer();
      if (!serverStarted) {
        DebugLogger().error('启动P2P服务器失败', tag: 'GROUP');
        return null;
      }

      // 设置消息处理回调
      P2PService.onMessageReceived = (message) {
        _handleIncomingMessage(group, message);
      };

      return group;
    } catch (e) {
      DebugLogger().error('创建群组失败: $e', tag: 'GROUP');
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

    DebugLogger().info(
      '生成二维码数据: ${JsonEncoder.withIndent('  ').convert(qrData)}',
      tag: 'GROUP',
    );
    DebugLogger().info('端口类型: ${serverInfo['port'].runtimeType}', tag: 'GROUP');

    return jsonEncode(qrData);
  }

  /// 为群组创建者启动P2P服务器（应用启动时调用）
  Future<bool> startGroupServer(Group group) async {
    try {
      DebugLogger().info('为群组 ${group.name} 启动P2P服务器...', tag: 'GROUP');

      // 启动P2P服务器
      final serverStarted = await P2PService.startServer();
      if (!serverStarted) {
        DebugLogger().error('启动P2P服务器失败', tag: 'GROUP');
        return false;
      }

      // 设置连接验证器
      DebugLogger().info('设置连接验证器...', tag: 'GROUP');
      P2PService.setConnectionValidator(_validateConnection);
      DebugLogger().info('连接验证器设置完成', tag: 'GROUP');

      // 显示服务器状态
      final status = P2PService.getServerStatus();
      DebugLogger().info('P2P服务器状态: $status', tag: 'GROUP');

      // 设置消息处理回调
      P2PService.onMessageReceived = (message) {
        _handleIncomingMessage(group, message);
      };

      // 监听连接事件
      P2PService.connectionEvents.listen((event) {
        _handleConnectionEvent(group, event);
      });

      DebugLogger().info('群组 ${group.name} 的P2P服务器启动成功', tag: 'GROUP');
      return true;
    } catch (e) {
      DebugLogger().error('启动群组服务器失败: $e', tag: 'GROUP');
      return false;
    }
  }

  /// 确保群组服务器运行
  Future<bool> ensureGroupServerRunning(Group group) async {
    try {
      DebugLogger().info('确保群组 ${group.name} 的P2P服务器运行', tag: 'GROUP');

      // 启动P2P服务器
      final success = await P2PService.startServer();
      if (success) {
        DebugLogger().info('P2P服务器启动成功', tag: 'GROUP');

        // 设置连接验证器
        DebugLogger().info('设置连接验证器...', tag: 'GROUP');
        P2PService.setConnectionValidator(_validateConnection);
        DebugLogger().info('连接验证器设置完成', tag: 'GROUP');

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
        DebugLogger().error('P2P服务器启动失败', tag: 'GROUP');
        return false;
      }
    } catch (e) {
      DebugLogger().error('确保群组服务器运行失败: $e', tag: 'GROUP');
      return false;
    }
  }

  /// 处理连接事件
  void _handleConnectionEvent(Group group, ConnectionEvent event) {
    switch (event.type) {
      case ConnectionEventType.connected:
        DebugLogger().info(
          '用户 ${event.userId} 连接到群组 ${group.name}',
          tag: 'GROUP',
        );
        break;
      case ConnectionEventType.disconnected:
        DebugLogger().info(
          '用户 ${event.userId} 从群组 ${group.name} 断开连接',
          tag: 'GROUP',
        );
        break;
      case ConnectionEventType.error:
        DebugLogger().error(
          '群组 ${group.name} 连接错误: ${event.error}',
          tag: 'GROUP',
        );
        break;
      default:
        break;
    }
  }

  /// 检查群组状态
  Future<bool> checkGroupStatus(Group group) async {
    try {
      DebugLogger().info('检查群组 ${group.name} 状态...', tag: 'GROUP');

      final serverStatus = P2PService.getServerStatus();
      final isRunning = serverStatus['isRunning'] as bool;

      if (!isRunning) {
        DebugLogger().info('P2P服务器未运行，尝试重启...', tag: 'GROUP');
        return await ensureGroupServerRunning(group);
      }

      // 检查群组连接数
      final groupConnections =
          serverStatus['groupConnections'] as Map<String, int>;
      final connectionCount = groupConnections[group.id] ?? 0;

      DebugLogger().info(
        '群组 ${group.name} 当前连接数: $connectionCount',
        tag: 'GROUP',
      );

      return true;
    } catch (e) {
      DebugLogger().error('检查群组状态失败: $e', tag: 'GROUP');
      return false;
    }
  }

  /// 重新连接群组
  Future<bool> reconnectToGroup(Group group, String userId) async {
    try {
      DebugLogger().info('重新连接到群组 ${group.name}...', tag: 'GROUP');

      // 先停止当前连接
      await P2PService.stopServer();

      // 重新启动服务器
      final success = await startGroupServer(group);
      if (success) {
        // 更新群组状态为可用
        group.status = GroupStatus.active;
        await StorageService.saveGroup(group);

        DebugLogger().info('重新连接群组 ${group.name} 成功', tag: 'GROUP');
        return true;
      } else {
        // 更新群组状态为不可用
        group.status = GroupStatus.unavailable;
        await StorageService.saveGroup(group);

        DebugLogger().error('重新连接群组 ${group.name} 失败', tag: 'GROUP');
        return false;
      }
    } catch (e) {
      // 更新群组状态为不可用
      group.status = GroupStatus.unavailable;
      await StorageService.saveGroup(group);

      DebugLogger().error('重新连接群组失败: $e', tag: 'GROUP');
      return false;
    }
  }

  /// 重启群组服务器
  Future<bool> restartGroupServer(Group group) async {
    try {
      DebugLogger().info('重启群组 ${group.name} 的P2P服务器...', tag: 'GROUP');

      // 停止服务器
      await P2PService.stopServer();

      // 重新启动
      final success = await startGroupServer(group);
      if (success) {
        DebugLogger().info('重启群组 ${group.name} 的P2P服务器成功', tag: 'GROUP');
        return true;
      } else {
        DebugLogger().error('重启群组 ${group.name} 的P2P服务器失败', tag: 'GROUP');
        return false;
      }
    } catch (e) {
      DebugLogger().error('重启群组服务器失败: $e', tag: 'GROUP');
      return false;
    }
  }

  /// 连接到群组服务器
  Future<bool> connectToGroupServer(Group group, String userId) async {
    try {
      DebugLogger().info(
        '连接到群组 ${group.name} 的P2P服务器 (用户: $userId)',
        tag: 'GROUP',
      );

      // 从群组二维码数据中解析连接信息
      final qrData = await generateGroupQRData(group);
      if (qrData == null) {
        DebugLogger().error('无法生成群组二维码数据', tag: 'GROUP');
        return false;
      }

      // 解析二维码数据获取IP和端口
      final qrDataMap = jsonDecode(qrData);
      final serverIP = qrDataMap['serverIP'];
      final serverPort = qrDataMap['serverPort'];

      DebugLogger().info('解析的服务器信息: $serverIP:$serverPort', tag: 'GROUP');

      // 连接到P2P服务器
      final success = await P2PService.connectToServer(
        serverIP,
        serverPort,
        userId,
        group.id,
      );
      if (success) {
        DebugLogger().info('成功连接到群组服务器', tag: 'GROUP');

        // 设置消息处理回调
        P2PService.onMessageReceived = (message) {
          _handleIncomingMessage(group, message);
        };

        return true;
      } else {
        DebugLogger().error('连接群组服务器失败', tag: 'GROUP');
        return false;
      }
    } catch (e) {
      DebugLogger().error('连接群组服务器异常: $e', tag: 'GROUP');
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
      DebugLogger().info(
        '验证连接: 用户 $userId 加入群组 $groupId (新成员: $isNewMember)',
        tag: 'GROUP',
      );

      // 检查群组是否存在
      final group = await StorageService.loadGroup(groupId);
      if (group == null) {
        DebugLogger().error('群组不存在: $groupId', tag: 'GROUP');
        return false;
      }

      // 检查群组状态
      if (group.status != GroupStatus.active) {
        DebugLogger().error('群组状态无效: ${group.status}', tag: 'GROUP');
        return false;
      }

      if (isNewMember) {
        // 新成员加入验证：检查群组是否已满
        if (group.members.length >= 10) {
          // 假设最大成员数为10
          DebugLogger().error('群组 $groupId 已满', tag: 'GROUP');
          return false;
        }
        DebugLogger().info('新成员验证通过', tag: 'GROUP');
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
          DebugLogger().error('用户 $userId 不是群组 $groupId 的成员', tag: 'GROUP');
          return false;
        }

        if (existingMember.status != MemberStatus.active) {
          DebugLogger().error('成员状态无效: ${existingMember.status}', tag: 'GROUP');
          return false;
        }

        DebugLogger().info('已加入成员验证通过', tag: 'GROUP');
        return true;
      }
    } catch (e) {
      DebugLogger().error('连接验证失败: $e', tag: 'GROUP');
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
      DebugLogger().info('开始加入群组...', tag: 'GROUP');
      DebugLogger().info('二维码数据: $qrCodeData', tag: 'GROUP');

      // 解析二维码数据
      final qrData = jsonDecode(qrCodeData);
      final groupId = qrData['groupId'];
      final serverIP = qrData['serverIP'];
      final serverPort = qrData['serverPort'];

      DebugLogger().info(
        '解析结果: 群组ID=$groupId, 服务器=$serverIP:$serverPort',
        tag: 'GROUP',
      );

      // 加载群组信息
      var group = await StorageService.loadGroup(groupId);
      if (group != null) {
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
          DebugLogger().info('用户已经是群组成员，直接连接...', tag: 'GROUP');
          return await connectToGroupServer(group, userId);
        }
      } else {
        // 创建新群组对象（不保存本地，等群主广播group_update）
        group = Group(
          id: groupId,
          name: qrData['groupName'],
          creatorId: 'unknown_creator', // 暂时设为未知，后续可以更新
          createdAt: DateTime.now(), // 暂时设为当前时间
          groupKeys: GroupKeyPair(
            publicKey: 'temp_public_key',
            privateKey: 'temp_private_key',
            createdAt: DateTime.now(),
          ),
          sessionKey: SessionKey(
            key: qrData['sessionKey'],
            createdAt: DateTime.now(),
            expiresAt: DateTime.now().add(Duration(days: 30)),
            version: 1,
          ),
        );
      }

      // 连接到P2P服务器
      final success = await P2PService.connectToServer(
        serverIP,
        serverPort,
        userId,
        groupId,
      );
      if (!success) {
        DebugLogger().error('连接P2P服务器失败', tag: 'GROUP');
        return false;
      }

      // 设置消息处理回调
      P2PService.onMessageReceived = (message) {
        _handleIncomingMessage(group!, message);
      };

      // 生成用户密钥对（改为用注册时密钥）
      final userKeyPair = await KeyManager.loadUserKeyPair(userId);
      if (userKeyPair == null) {
        DebugLogger().error('加入群组失败：未找到当前用户密钥对', tag: 'GROUP');
        return false;
      }
      // 发送 join_request 消息给群主端
      final joinRequest = {
        'type': NetworkMessage.TYPE_JOIN_REQUEST,
        'messageId': _generateMessageId(),
        'groupId': groupId,
        'senderId': userId,
        'userName': userName,
        'publicKey': userKeyPair.publicKey,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      P2PService.broadcastMessage(joinRequest);
      DebugLogger().info(
        '[GROUP] 已发送 join_request: $joinRequest',
        tag: 'GROUP',
      );

      // 不在本地直接addMember/saveGroup，等群主端广播group_update后再同步

      DebugLogger().info('等待群主端处理入群请求并同步群组数据...', tag: 'GROUP');
      return true;
    } catch (e) {
      DebugLogger().error('加入群组失败: $e', tag: 'GROUP');
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
      DebugLogger().info('发送消息到群组: $groupId', tag: 'GROUP');
      DebugLogger().info('发送者: $senderId', tag: 'GROUP');
      DebugLogger().info('内容: $content', tag: 'GROUP');

      // 获取群组
      final group = await StorageService.loadGroup(groupId);
      if (group == null) {
        DebugLogger().error('群组不存在: $groupId', tag: 'GROUP');
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
        DebugLogger().error('发送者不是群组成员: $senderId', tag: 'GROUP');
        return false;
      }

      // 只做业务校验，实际加密/签名/广播交给MessageService
      final message = await MessageService().sendMessage(
        groupId,
        content,
        senderId,
      );
      if (message != null) {
        DebugLogger().info('消息发送成功', tag: 'GROUP');
        return true;
      } else {
        DebugLogger().error('消息发送失败', tag: 'GROUP');
        return false;
      }
    } catch (e) {
      DebugLogger().error('发送消息失败: $e', tag: 'GROUP');
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
      DebugLogger().info('[GroupService] 开始加载群组消息: $groupId', tag: 'GROUP');
      final messages = await StorageService.loadMessages(
        groupId,
        limit: 100, // 加载最近100条消息
        offset: 0,
      );

      _groupMessages[groupId] = messages;
      DebugLogger().info(
        '[GroupService] 群组 $groupId 加载了 ${messages.length} 条消息',
        tag: 'GROUP',
      );
    } catch (e) {
      DebugLogger().error('[GroupService] 加载群组消息失败: $e', tag: 'GROUP');
      _groupMessages[groupId] = [];
    }
  }

  /// 加载所有群组的消息
  Future<void> loadAllGroupMessages() async {
    try {
      DebugLogger().info('[GroupService] 开始加载所有群组消息...', tag: 'GROUP');
      final groups = await StorageService.loadAllGroups();

      for (final group in groups) {
        await loadGroupMessagesFromStorage(group.id);
      }

      DebugLogger().info('[GroupService] 所有群组消息加载完成', tag: 'GROUP');
    } catch (e) {
      DebugLogger().error('[GroupService] 加载所有群组消息失败: $e', tag: 'GROUP');
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
      DebugLogger().info('处理接收消息: ${message['type']}', tag: 'GROUP');
      final messageType = message['type'];
      final groupId = message['groupId'] as String?;
      if (messageType == 'heartbeat' || groupId == null || groupId.isEmpty) {
        DebugLogger().info('跳过系统消息或无效groupId的消息: $messageType', tag: 'GROUP');
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
        case NetworkMessage.TYPE_GROUP_UPDATE:
          DebugLogger().info(
            '[GROUP] 收到group_update消息: groupId=$groupId, 消息内容=${jsonEncode(message)}',
            tag: 'GROUP',
          );
          _handleGroupUpdate(message);
          break;
        default:
          DebugLogger().error('未知消息类型: $messageType', tag: 'GROUP');
      }
    } catch (e) {
      DebugLogger().error('_handleIncomingMessage 处理接收消息失败: $e', tag: 'GROUP');
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
        DebugLogger().info('消息已处理过，跳过: $messageId', tag: 'GROUP');
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

      DebugLogger().info('处理新消息: $messageId (发送者: $senderId)', tag: 'GROUP');

      // ==== 新增：统一走MessageService.receiveMessage进行验签和解密 ====
      DebugLogger().info(
        'GroupService: 调用MessageService.receiveMessage进行验签和解密',
        tag: 'GROUP',
      );
      final chatMessage = await MessageService().receiveMessage(
        group.id,
        message,
      );
      if (chatMessage == null) {
        DebugLogger().error(
          'GroupService: 消息验签或解密失败，丢弃: $messageId',
          tag: 'GROUP',
        );
        return;
      }

      // 添加到本地消息列表
      _addMessageToGroup(group.id, chatMessage);

      // 保存到本地存储
      await StorageService.saveMessage(group.id, chatMessage);

      // 触发消息更新回调
      if (onMessageUpdated != null) {
        onMessageUpdated!(group.id);
      }

      DebugLogger().info('聊天消息处理完成: $messageId', tag: 'GROUP');
    } catch (e) {
      DebugLogger().error('处理聊天消息失败: $e', tag: 'GROUP');
    }
  }

  /// 处理加入请求
  void _handleJoinRequest(Group group, Map<String, dynamic> message) async {
    try {
      final userId = message['senderId'];
      final userName = message['userName'] ?? 'Unknown';
      final userPublicKey = message['publicKey'];
      DebugLogger().info(
        '[GROUP] 处理加入请求: 用户=$userId, 姓名=$userName, groupId=${group.id}, 当前成员数=${group.members.length}',
        tag: 'GROUP',
      );
      if (group.members.length >= 10) {
        DebugLogger().error('群组已满，拒绝加入请求', tag: 'GROUP');
        _sendJoinResponse(userId, group.id, false, '群组已满');
        return;
      }
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
      group.addMember(newMember);
      await StorageService.saveGroup(group);
      DebugLogger().info(
        '[GROUP] 新成员已加入: $userName, groupId=${group.id}, 新成员数=${group.members.length}',
        tag: 'GROUP',
      );
      _sendJoinResponse(userId, group.id, true, null);
      _broadcastMemberJoined(group, newMember);
      _broadcastGroupUpdate(group);
      if (onGroupUpdated != null) {
        onGroupUpdated!(group.id);
      }
      DebugLogger().info('成员加入成功: $userName', tag: 'GROUP');
      _debugPrintAllGroups();
    } catch (e) {
      DebugLogger().error('处理加入请求失败: $e', tag: 'GROUP');
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
      DebugLogger().error('群组不存在: $groupId', tag: 'GROUP');
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

      DebugLogger().info('成员加入: $name ($userId)', tag: 'GROUP');

      // 触发群组更新回调
      if (onGroupUpdated != null) {
        onGroupUpdated!(group.id);
      }
    } catch (e) {
      DebugLogger().error('处理成员加入消息失败: $e', tag: 'GROUP');
    }
  }

  /// 处理成员离开消息
  void _handleMemberLeft(Group group, Map<String, dynamic> message) {
    try {
      final content = message['content'];
      final userId = content['userId'];
      final name = content['name'];

      DebugLogger().info('成员离开: $name ($userId)', tag: 'GROUP');

      // 触发群组更新回调
      if (onGroupUpdated != null) {
        onGroupUpdated!(group.id);
      }
    } catch (e) {
      DebugLogger().error('处理成员离开消息失败: $e', tag: 'GROUP');
    }
  }

  /// 离开群组
  Future<bool> leaveGroup(String groupId, String userId) async {
    try {
      DebugLogger().info('用户 $userId 离开群组 $groupId', tag: 'GROUP');

      final group = await StorageService.loadGroup(groupId);
      if (group == null) {
        DebugLogger().error('群组不存在: $groupId', tag: 'GROUP');
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
        DebugLogger().error('用户不是群组成员: $userId', tag: 'GROUP');
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

      DebugLogger().info('成功离开群组', tag: 'GROUP');
      return true;
    } catch (e) {
      DebugLogger().error('离开群组失败: $e', tag: 'GROUP');
      return false;
    }
  }

  /// 解散群组
  Future<bool> disbandGroup(String groupId, String creatorId) async {
    try {
      DebugLogger().info('解散群组: $groupId', tag: 'GROUP');

      final group = await StorageService.loadGroup(groupId);
      if (group == null) {
        DebugLogger().error('群组不存在: $groupId', tag: 'GROUP');
        return false;
      }

      // 检查是否为创建者
      if (group.creatorId != creatorId) {
        DebugLogger().error('只有创建者可以解散群组', tag: 'GROUP');
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

      DebugLogger().info('群组解散成功', tag: 'GROUP');
      return true;
    } catch (e) {
      DebugLogger().error('解散群组失败: $e', tag: 'GROUP');
      return false;
    }
  }

  /// 检查群组连接状态
  Future<bool> checkGroupConnectionStatus(Group group) async {
    try {
      DebugLogger().info('检查群组 ${group.name} 连接状态...', tag: 'GROUP');

      final serverStatus = P2PService.getServerStatus();
      final isRunning = serverStatus['isRunning'] as bool;

      if (!isRunning) {
        DebugLogger().info('P2P服务器未运行', tag: 'GROUP');
        return false;
      }

      // 检查群组连接数
      final groupConnections =
          serverStatus['groupConnections'] as Map<String, int>;
      final connectionCount = groupConnections[group.id] ?? 0;

      DebugLogger().info(
        '群组 ${group.name} 当前连接数: $connectionCount',
        tag: 'GROUP',
      );

      return connectionCount > 0;
    } catch (e) {
      DebugLogger().error('检查群组连接状态失败: $e', tag: 'GROUP');
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
    DebugLogger().info('已清空所有群组消息缓存', tag: 'GROUP');
  }

  /// 广播群组更新消息（含所有成员）
  void _broadcastGroupUpdate(Group group) {
    final message = {
      'type': NetworkMessage.TYPE_GROUP_UPDATE,
      'messageId': _generateMessageId(),
      'groupId': group.id,
      'senderId': 'system',
      'content': group.toJson(),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    DebugLogger().info(
      '[GROUP] 广播群组更新: groupId=${group.id}, 成员数=${group.members.length}, 消息内容=${jsonEncode(message)}',
      tag: 'GROUP',
    );
    P2PService.broadcastMessage(message);
    _debugPrintAllGroups();
  }

  /// 处理群组更新消息
  void _handleGroupUpdate(Map<String, dynamic> message) async {
    try {
      final groupData = message['content'];
      final group = Group.fromJson(groupData);
      await StorageService.saveGroup(group);
      // 循环打出member的信息
      for (final member in group.members) {
        DebugLogger().info(
          '[GROUP] 成员: ${member.userId} (${member.name}) publicKey=${member.publicKey.substring(0, 8)}...',
          tag: 'GROUP',
        );
      }
      DebugLogger().info(
        '[GROUP] 已同步群组数据: groupId=${group.id}, 成员数=${group.members.length}',
        tag: 'GROUP',
      );
      if (onGroupUpdated != null) {
        onGroupUpdated!(group.id);
      }
      DebugLogger().info('群组数据已同步: ${group.id}', tag: 'GROUP');
      _debugPrintAllGroups();
    } catch (e) {
      DebugLogger().error('处理群组更新消息失败: $e', tag: 'GROUP');
    }
  }

  void _debugPrintAllGroups() async {
    DebugLogger().info('[GROUP][DEBUG] 调用_debugPrintAllGroups()', tag: 'GROUP');
    final groups = await StorageService.loadAllGroups();
    DebugLogger().info('[GROUP][DEBUG] 本地群组数量: ${groups.length}', tag: 'GROUP');
    for (final group in groups) {
      DebugLogger().info(
        '[GROUP][DEBUG] 群组: ${group.id} (${group.name})，成员数: ${group.members.length}，成员: ${group.members.map((m) => m.userId).toList()}',
        tag: 'GROUP',
      );
    }
  }
}
