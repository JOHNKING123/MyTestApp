import 'dart:convert';
import 'dart:math';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/group.dart';
import '../models/member.dart';
import '../models/message.dart';
import 'encryption_service.dart';
import 'key_service.dart';
import 'p2p_service.dart';
import 'storage_service.dart';
import 'dart:io';
import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/user.dart';
import '../services/encryption_service.dart';

class GroupService {
  static final GroupService _instance = GroupService._internal();
  factory GroupService() => _instance;
  GroupService._internal();

  final Map<String, List<Message>> _groupMessages = {};
  final Map<String, int> _sequenceNumbers = {};

  // 添加消息更新回调
  Function(String groupId)? onMessageUpdated;
  Function(String groupId)? onGroupUpdated;

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
      P2PService.onMessage = (message) {
        _handleIncomingMessage(group, message);
      };

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
        P2PService.onMessage = (message) {
          _handleIncomingMessage(group, message);
        };

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
      final serverIp = qrDataMap['serverIP'];
      final serverPort = qrDataMap['serverPort'];

      print('尝试连接到P2P服务器: $serverIp:$serverPort');

      // 在模拟器环境中进行IP和端口转换
      String targetIP = serverIp;
      int targetPort = serverPort;

      // 如果目标IP是模拟器A的IP (10.0.2.15)，转换为主机地址和端口转发端口
      if (serverIp == '10.0.2.15') {
        print('检测到目标服务器是模拟器A，转换连接地址');
        targetIP = '10.0.2.2';
        targetPort = 8081; // 端口转发端口
        print('转换后地址: $targetIP:$targetPort');
      }

      // 连接到P2P服务器
      final success = await P2PService.connectToServer(
        targetIP,
        targetPort,
        userId,
        group.id,
        isNewMember: false, // 标识为已加入成员重新连接
      );
      if (success) {
        print('P2P连接建立成功');

        // 设置消息处理回调
        P2PService.onMessage = (message) {
          _handleIncomingMessage(group, message);
        };

        return true;
      } else {
        print('P2P连接建立失败');
        return false;
      }
    } catch (e) {
      print('连接到群组服务器失败: $e');
      return false;
    }
  }

  /// 加入群组
  Future<bool> joinGroup(String qrData, String userId, String userName) async {
    try {
      print('开始解析二维码数据...');
      final data = jsonDecode(qrData);
      print('二维码数据解析结果: $data');

      if (data['type'] != 'group_join') {
        print('无效的二维码数据，期望类型: group_join，实际类型: ${data['type']}');
        return false;
      }

      final serverIP = data['serverIP'];
      final serverPort = int.parse(data['serverPort'].toString());
      final groupId = data['groupId'];

      print('尝试加入群组: ${data['groupName']}');
      print('服务器地址: $serverIP:$serverPort');
      print('端口类型: ${serverPort.runtimeType}');
      print('群组ID: $groupId');

      // 打印本地IP地址
      print('=== 网络诊断信息 ===');
      final localIP = await P2PService.getLocalIP();
      print('本地IP地址: $localIP');
      print('目标服务器IP: $serverIP');
      print('目标服务器端口: $serverPort');

      // 在模拟器环境中进行IP和端口转换
      String targetIP = serverIP;
      int targetPort = serverPort;

      // 如果目标IP是模拟器A的IP (10.0.2.15)，转换为主机地址和端口转发端口
      if (serverIP == '10.0.2.15') {
        print('检测到目标服务器是模拟器A，转换连接地址');
        print('原始地址: $serverIP:$serverPort');
        targetIP = '10.0.2.2';
        targetPort = 8081; // 端口转发端口
        print('转换后地址: $targetIP:$targetPort');
      }

      print('最终连接地址: $targetIP:$targetPort');

      // 先测试连接
      print('=== 开始WebSocket连接测试 ===');
      final testResult = await P2PService.testConnection(targetIP, targetPort);
      if (!testResult) {
        print('WebSocket连接测试失败，无法加入群组');
        print('请确保群组创建者的P2P服务器已启动');
        return false;
      }

      print('WebSocket连接测试成功，开始建立WebSocket连接...');
      // 连接到P2P服务器
      final connected = await P2PService.connectToServer(
        targetIP,
        targetPort,
        userId,
        groupId,
        isNewMember: true, // 标识为新成员加入
      );

      if (!connected) {
        print('连接P2P服务器失败');
        return false;
      }

      print('WebSocket连接成功，设置消息处理回调...');

      // 创建本地群组对象
      final group = Group(
        id: groupId,
        name: data['groupName'],
        creatorId: 'unknown_creator', // 暂时设为未知，后续可以更新
        createdAt: DateTime.now(), // 暂时设为当前时间
        groupKeys: GroupKeyPair(
          publicKey: 'temp_public_key',
          privateKey: 'temp_private_key',
          createdAt: DateTime.now(),
        ),
        sessionKey: SessionKey(
          key: data['sessionKey'],
          createdAt: DateTime.now(),
          expiresAt: DateTime.now().add(Duration(days: 30)),
          version: 1,
        ),
      );

      // 初始化群组消息列表
      _groupMessages[group.id] = [];

      // 设置消息处理回调
      P2PService.onMessage = (message) {
        _handleIncomingMessage(group, message);
      };

      print('发送成员加入请求...');
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
      print('成员加入请求已发送');

      // 保存群组到本地存储
      await StorageService.saveGroup(group);
      print('群组已保存到本地存储');

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

      // 创建发送用的消息内容（只包含加密内容，不包含明文）
      final sendMessageContent = MessageContent(
        text: '', // 不发送明文
        type: MessageType.text,
        size: content.length,
        encryptedContent: encryptedContent,
      );

      // 创建本地消息（包含解密后的内容）
      final localMessageContent = MessageContent(
        text: content, // 本地存储解密后的内容
        type: MessageType.text,
        size: content.length,
        encryptedContent: encryptedContent,
      );

      final message = Message(
        id: _generateMessageId(),
        groupId: group.id,
        senderId: senderId,
        content: localMessageContent, // 使用包含明文的内容用于本地显示
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

      // 保存消息到本地存储
      await StorageService.saveMessage(group.id, message);
      print('消息已保存到本地存储');

      print('消息已添加到本地列表，当前消息数: ${_groupMessages[group.id]!.length}');

      // 广播消息（使用不包含明文的内容）
      final messageData = {
        'type': 'message',
        'groupId': group.id,
        'message': {
          'id': message.id,
          'senderId': message.senderId,
          'senderName': _getSenderName(group, senderId),
          'content': sendMessageContent.toJson(), // 使用不包含明文的内容
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

  /// 从本地存储加载群组消息
  Future<void> loadGroupMessages(String groupId) async {
    try {
      final messages = await StorageService.loadMessages(groupId);
      _groupMessages[groupId] = messages;
      print('从本地存储加载群组 $groupId 的消息，共 ${messages.length} 条');
    } catch (e) {
      print('加载群组消息失败: $e');
      _groupMessages[groupId] = [];
    }
  }

  /// 检查群组状态（验证群组是否仍然可用）
  Future<bool> checkGroupStatus(Group group, String currentUserId) async {
    try {
      print('[群组状态] 开始检查群组状态: ${group.name} (${group.id})');

      // 如果群组创建者是自己，直接返回true
      if (group.creatorId == currentUserId) {
        print('[群组状态] 群组创建者是当前用户，状态正常');
        return true;
      }

      // 尝试连接到群组创建者的P2P服务器
      final qrData = await generateGroupQRData(group);

      if (qrData == null) {
        print('[群组状态] 无法生成群组二维码数据');
        return false;
      }

      // 解析二维码数据获取IP和端口
      final qrDataMap = jsonDecode(qrData);
      final serverIp = qrDataMap['serverIP'];
      final serverPort = qrDataMap['serverPort'];

      print('[群组状态] 尝试连接群组服务器: $serverIp:$serverPort');

      // 在模拟器环境中进行IP和端口转换
      String targetIP = serverIp;
      int targetPort = serverPort;

      // 如果目标IP是模拟器A的IP (10.0.2.15)，转换为主机地址和端口转发端口
      if (serverIp == '10.0.2.15') {
        print('[群组状态] 检测到目标服务器是模拟器A，转换连接地址');
        targetIP = '10.0.2.2';
        targetPort = 8081; // 端口转发端口
        print('[群组状态] 转换后地址: $targetIP:$targetPort');
      }

      // 使用testConnection方法进行状态检查，不影响现有连接
      final connected = await P2PService.testConnection(targetIP, targetPort);

      if (connected) {
        print('[群组状态] 群组服务器连接测试成功，群组状态正常');
        return true;
      } else {
        print('[群组状态] 群组服务器连接测试失败，群组可能已被删除');
        return false;
      }
    } catch (e) {
      print('[群组状态] 检查群组状态失败: $e');
      return false;
    }
  }

  /// 批量检查群组状态
  Future<void> checkAllGroupsStatus(
    List<Group> groups,
    String currentUserId,
  ) async {
    print('[群组状态] 开始批量检查群组状态，共 ${groups.length} 个群组');

    for (final group in groups) {
      try {
        // 如果群组已经被标记为不可用，跳过检查
        if (group.status == GroupStatus.unavailable) {
          print('[群组状态] 群组 ${group.name} 已被标记为不可用，跳过检查');
          continue;
        }

        final isAvailable = await checkGroupStatus(group, currentUserId);

        if (!isAvailable && group.status == GroupStatus.active) {
          print('[群组状态] 群组 ${group.name} 不可用，更新状态为 unavailable');
          group.status = GroupStatus.unavailable;

          // 保存更新后的群组状态
          await StorageService.saveGroup(group);

          // 通知UI更新
          if (onGroupUpdated != null) {
            onGroupUpdated!(group.id);
          }
        }
      } catch (e) {
        print('[群组状态] 检查群组 ${group.name} 状态失败: $e');
      }
    }

    print('[群组状态] 批量检查群组状态完成');
  }

  /// 处理接收到的消息
  void _handleIncomingMessage(Group? group, Map<String, dynamic> message) {
    try {
      switch (message['type']) {
        case 'message':
          handleChatMessage(group, message);
          break;
        case 'member_join':
          _handleMemberJoin(group, message);
          break;
        case 'member_join_confirmed':
          _handleMemberJoinConfirmed(group, message);
          break;
        case 'member_leave':
          _handleMemberLeave(group, message);
          break;
        case 'group_info':
          _handleGroupInfo(message);
          break;
        case 'auth_failure':
          _handleAuthFailure(message);
          break;
        case 'auth_success':
          print('收到认证成功响应: ${message['id']}');
          break;
        default:
          print('_handleIncomingMessage 未知消息类型: ${message['type']}');
      }
    } catch (e) {
      print('处理消息失败: $e');
    }
  }

  /// 处理聊天消息
  void handleChatMessage(Group? group, Map<String, dynamic> message) async {
    print('处理聊天消息，group: ${group?.id}');

    try {
      final messageData = message['message'];
      final contentData = messageData['content'];

      // 创建消息内容
      final messageContent = MessageContent.fromJson(contentData);

      print(
        '收到加密消息，text字段: "${messageContent.text}"，encryptedContent: ${messageContent.encryptedContent?.substring(0, 50)}...',
      );

      // 解密消息
      final decryptedText = EncryptionService.decryptMessage(
        messageContent.encryptedContent ?? '',
        group?.sessionKey.key ?? '',
      );

      print('消息解密成功: $decryptedText');

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
        metadata: {
          'senderName': messageData['senderName'] ?? '未知用户', // 保存发送者昵称
        },
      );

      // 添加到群组消息列表
      final groupId = chatMessage.groupId;
      if (_groupMessages[groupId] == null) {
        _groupMessages[groupId] = [];
      }
      _groupMessages[groupId]!.add(chatMessage);

      // 保存消息到本地存储
      await StorageService.saveMessage(groupId, chatMessage);
      print('消息已保存到本地存储');

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
  void _handleMemberJoin(Group? group, Map<String, dynamic> message) async {
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

    // 保存更新后的群组到本地存储
    await StorageService.saveGroup(group);
    print('群组成员更新已保存到本地存储');

    // 群组创建者确认新人加入并广播给所有成员
    final confirmMessage = {
      'type': 'member_join_confirmed',
      'groupId': group.id,
      'member': {
        'id': member.id,
        'userId': member.userId,
        'name': member.name,
        'publicKey': member.publicKey,
        'joinedAt': member.joinedAt.toIso8601String(),
        'role': member.role.toString(),
      },
      'timestamp': DateTime.now().toIso8601String(),
    };

    // 广播确认消息给所有成员
    P2PService.broadcastMessage(confirmMessage);
    print('已广播成员加入确认消息');

    // 发送完整的群组信息给新成员
    final groupInfo = await _getGroupInfo(group.id);
    if (groupInfo != null) {
      final groupInfoMessage = {
        'type': 'group_info',
        'groupId': group.id,
        'groupInfo': groupInfo,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      // 发送给新成员
      P2PService.sendMessageToUser(member.userId, groupInfoMessage);
      print('已发送完整群组信息给新成员: ${member.name}');
    }

    // 通知UI更新群组信息
    if (onGroupUpdated != null) {
      onGroupUpdated!(group.id);
    }
  }

  /// 获取群组详细信息
  Future<Map<String, dynamic>?> _getGroupInfo(String groupId) async {
    try {
      final group = await getGroup(groupId);
      if (group == null) {
        print('群组不存在: $groupId');
        return null;
      }

      // 构建群组信息
      final groupInfo = {
        'id': group.id,
        'name': group.name,
        'creatorId': group.creatorId,
        'createdAt': group.createdAt.toIso8601String(),
        'status': group.status.toString(),
        'sessionKey': {
          'key': group.sessionKey.key,
          'createdAt': group.sessionKey.createdAt.toIso8601String(),
          'expiresAt': group.sessionKey.expiresAt.toIso8601String(),
          'version': group.sessionKey.version,
        },
        'members': group.members
            .map(
              (member) => {
                'id': member.id,
                'userId': member.userId,
                'name': member.name,
                'publicKey': member.publicKey,
                'joinedAt': member.joinedAt.toIso8601String(),
                'lastSeen': member.lastSeen.toIso8601String(),
                'role': member.role.toString(),
                'status': member.status.toString(),
              },
            )
            .toList(),
      };

      print('群组信息获取成功: ${group.name} (${group.members.length} 个成员)');
      return groupInfo;
    } catch (e) {
      print('获取群组信息失败: $e');
      return null;
    }
  }

  /// 处理成员加入确认
  void _handleMemberJoinConfirmed(
    Group? group,
    Map<String, dynamic> message,
  ) async {
    if (group == null) return;

    final member = Member(
      id: message['member']['id'],
      userId: message['member']['userId'],
      groupId: group.id,
      name: message['member']['name'],
      publicKey: message['member']['publicKey'],
      joinedAt: DateTime.parse(message['member']['joinedAt']),
      lastSeen: DateTime.now(),
      role: MemberRole.values.firstWhere(
        (e) => e.toString() == message['member']['role'],
      ),
      status: MemberStatus.active,
    );

    group.addMember(member);
    print('成员加入确认: ${member.name}');

    // 保存更新后的群组到本地存储
    await StorageService.saveGroup(group);
    print('群组成员确认更新已保存到本地存储');

    // 通知UI更新群组信息
    if (onGroupUpdated != null) {
      onGroupUpdated!(group.id);
    }
  }

  /// 处理成员离开
  void _handleMemberLeave(Group? group, Map<String, dynamic> message) async {
    if (group == null) return;

    group.removeMember(message['userId']);
    print('成员离开: ${message['userName']}');

    // 保存更新后的群组到本地存储
    await StorageService.saveGroup(group);
    print('群组成员离开更新已保存到本地存储');

    // 通知UI更新群组信息
    if (onGroupUpdated != null) {
      onGroupUpdated!(group.id);
    }
  }

  /// 处理群组信息消息
  void _handleGroupInfo(Map<String, dynamic> message) async {
    try {
      print('收到群组信息消息');
      final groupInfo = message['groupInfo'];

      if (groupInfo != null) {
        // 创建或更新本地群组信息
        final group = Group(
          id: groupInfo['id'],
          name: groupInfo['name'],
          creatorId: groupInfo['creatorId'],
          createdAt: DateTime.parse(groupInfo['createdAt']),
          groupKeys: GroupKeyPair(
            publicKey: 'temp_public_key',
            privateKey: 'temp_private_key',
            createdAt: DateTime.now(),
          ),
          sessionKey: SessionKey(
            key: groupInfo['sessionKey']['key'],
            createdAt: DateTime.parse(groupInfo['sessionKey']['createdAt']),
            expiresAt: DateTime.parse(groupInfo['sessionKey']['expiresAt']),
            version: groupInfo['sessionKey']['version'],
          ),
        );

        // 添加成员
        final members = groupInfo['members'] as List;
        for (final memberData in members) {
          final member = Member(
            id: memberData['id'],
            userId: memberData['userId'],
            groupId: group.id,
            name: memberData['name'],
            publicKey: memberData['publicKey'],
            joinedAt: DateTime.parse(memberData['joinedAt']),
            lastSeen: DateTime.parse(memberData['lastSeen']),
            role: MemberRole.values.firstWhere(
              (e) => e.toString() == memberData['role'],
            ),
            status: MemberStatus.values.firstWhere(
              (e) => e.toString() == memberData['status'],
            ),
          );
          group.addMember(member);
        }

        // 保存群组到本地存储
        await StorageService.saveGroup(group);
        print('群组信息已保存到本地存储: ${group.name} (${group.members.length} 个成员)');

        // 通知UI更新
        if (onGroupUpdated != null) {
          onGroupUpdated!(group.id);
        }
      }
    } catch (e) {
      print('处理群组信息消息失败: $e');
    }
  }

  /// 处理认证失败
  void _handleAuthFailure(Map<String, dynamic> message) {
    final userId = message['userId'];
    final groupId = message['groupId'];
    final reason = message['reason'];

    print('认证失败: 用户=$userId, 群组=$groupId, 原因=$reason');

    // 可以在这里添加UI通知逻辑，比如显示错误提示
    // 或者自动重试连接等
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

  /// 获取发送者昵称
  String _getSenderName(Group group, String senderId) {
    // 从群组成员中查找发送者昵称
    final member = group.members.firstWhere(
      (m) => m.userId == senderId,
      orElse: () => Member(
        id: 'unknown',
        userId: senderId,
        groupId: group.id,
        name: '未知用户',
        publicKey: '',
        joinedAt: DateTime.now(),
        lastSeen: DateTime.now(),
        role: MemberRole.member,
        status: MemberStatus.active,
      ),
    );
    return member.name;
  }

  /// 清空所有群组消息缓存
  void clearAllMessages() {
    _groupMessages.clear();
    print('已清空所有群组消息缓存');
  }

  /// 异步验证连接是否有效
  Future<bool> _validateConnection(
    String userId,
    String groupId,
    bool isNewMember,
  ) async {
    try {
      print('=== 开始异步验证连接 ===');
      print('验证连接: 用户=$userId, 群组=$groupId, 是否新成员=$isNewMember');

      // 1. 检查群组是否存在
      print('1. 检查群组是否存在...');
      final group = await StorageService.loadGroup(groupId);
      if (group == null) {
        print('❌ 群组不存在: $groupId');
        return false;
      }
      print('✅ 群组存在: ${group.name}');
      print('群组状态: ${group.status}');
      print('群组成员数: ${group.members.length}');
      print('群组成员列表:');
      for (var member in group.members) {
        print(
          '  - userId: ${member.userId}, name: ${member.name}, status: ${member.status}',
        );
      }

      // 2. 检查群组状态是否有效
      print('2. 检查群组状态...');
      if (group.status != GroupStatus.active) {
        print('❌ 群组状态无效: ${group.status}');
        return false;
      }
      print('✅ 群组状态有效: ${group.status}');

      // 3. 根据是否为新成员进行不同的验证
      if (isNewMember) {
        // 新成员加入验证：只检查群组是否存在且状态有效
        print('3. 新成员加入验证：跳过成员身份检查');
        print('✅ 新成员验证通过');
        return true;
      } else {
        // 已加入成员连接验证：检查用户是否为群组成员
        print('3. 已加入成员验证：检查用户是否为群组成员...');
        print(
          '群组成员列表: ${group.members.map((m) => '${m.userId}(${m.name})').join(', ')}',
        );

        // 检查用户是否已经是群组成员
        final existingMember = group.members.firstWhere(
          (m) => m.userId == userId,
          orElse: () => throw Exception('用户不是群组成员'),
        );
        print('✅ 用户是群组成员: ${existingMember.name}');

        // 4. 检查成员状态是否有效
        print('4. 检查成员状态...');
        if (existingMember.status != MemberStatus.active) {
          print('❌ 成员状态无效: ${existingMember.status}');
          return false;
        }
        print('✅ 成员状态有效: ${existingMember.status}');
      }

      print('=== 连接验证通过 ===');
      print('连接验证通过: 用户=$userId, 群组=$groupId');
      return true;
    } catch (e) {
      print('=== 连接验证失败 ===');
      print('连接验证失败: $e');
      return false;
    }
  }

  /// 获取群组
  Future<Group?> getGroup(String groupId) async {
    try {
      print('获取群组: $groupId');

      // 从本地存储加载群组
      final groups = await StorageService.loadAllGroups();
      final group = groups.firstWhere(
        (g) => g.id == groupId,
        orElse: () => throw Exception('群组不存在'),
      );

      print('找到群组: ${group.name}');
      return group;
    } catch (e) {
      print('获取群组失败: $e');
      return null;
    }
  }

  /// 设置群组状态为不可用
  Future<bool> setGroupUnavailable(Group group) async {
    try {
      print('设置群组 ${group.name} 状态为不可用');

      // 更新群组状态
      group.status = GroupStatus.unavailable;
      print('群组状态已更新为: ${group.status}');

      // 保存到本地存储
      await StorageService.saveGroup(group);
      print('群组状态已保存到本地存储');

      // 通知UI更新
      if (onGroupUpdated != null) {
        print('触发onGroupUpdated回调: ${group.id}');
        onGroupUpdated!(group.id);
        print('onGroupUpdated回调已触发');
      } else {
        print('警告: onGroupUpdated回调未设置');
      }

      return true;
    } catch (e) {
      print('设置群组状态失败: $e');
      return false;
    }
  }

  /// 重新连接群组（群组成员使用）
  Future<bool> reconnectToGroup(Group group, String userId) async {
    try {
      print('GroupService: 开始重新连接群组: ${group.name} (用户: $userId)');

      // 检查用户是否为群组成员
      final member = group.members.firstWhere(
        (m) => m.userId == userId,
        orElse: () => throw Exception('用户不是群组成员'),
      );

      if (member.role == MemberRole.creator) {
        print('GroupService: 群组创建者不需要重新连接，启动服务器即可');
        return await ensureGroupServerRunning(group);
      }

      // 群组成员重新连接
      print('GroupService: 群组成员重新连接群组服务器...');
      final success = await connectToGroupServer(group, userId);

      print('GroupService: connectToGroupServer 返回结果: $success');

      if (success) {
        print('GroupService: 群组重新连接成功: ${group.name}');
        // 更新群组状态
        group.status = GroupStatus.active;
        await StorageService.saveGroup(group);

        // 不触发onGroupUpdated回调，避免重复加载
        // 由AppProvider直接处理状态更新
        print('GroupService: 群组状态已更新，等待AppProvider处理');
        print('GroupService: 重新连接成功，返回 true');
        return true;
      } else {
        print('GroupService: 群组重新连接失败: ${group.name}');
        print('GroupService: 重新连接失败，返回 false');
        return false;
      }
    } catch (e) {
      print('GroupService: 重新连接群组失败: $e');
      print('GroupService: 重新连接异常，返回 false');
      return false;
    }
  }

  /// 检查群组连接状态
  Future<bool> checkGroupConnectionStatus(Group group) async {
    try {
      print('检查群组连接状态: ${group.name}');

      // 从群组二维码数据中解析连接信息
      final qrData = await generateGroupQRData(group);
      if (qrData == null) {
        print('无法生成群组二维码数据');
        return false;
      }

      // 解析二维码数据获取IP和端口
      final qrDataMap = jsonDecode(qrData);
      final serverIp = qrDataMap['serverIP'];
      final serverPort = qrDataMap['serverPort'];

      // 在模拟器环境中进行IP和端口转换
      String targetIP = serverIp;
      int targetPort = serverPort;

      if (serverIp == '10.0.2.15') {
        targetIP = '10.0.2.2';
        targetPort = 8081;
      }

      // 测试连接
      final testResult = await P2PService.testConnection(targetIP, targetPort);
      print('群组连接状态检查结果: $testResult');

      return testResult;
    } catch (e) {
      print('检查群组连接状态失败: $e');
      return false;
    }
  }
}
