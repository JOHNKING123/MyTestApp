import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import 'dart:collection';
import '../models/user.dart';
import '../models/group.dart';
import '../models/message.dart';
import '../services/storage_service.dart';
import '../services/group_service.dart';
import '../services/p2p_service.dart';
import '../services/key_service.dart';
import 'dart:convert';

class AppProvider with ChangeNotifier {
  User? _currentUser;
  List<Group> _groups = [];
  Group? _currentGroup;
  bool _isLoading = false;
  String? _error;
  bool _isInitialized = false;

  // Getters
  User? get currentUser => _currentUser;
  List<Group> get groups => _groups;
  Group? get currentGroup => _currentGroup;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isInitialized => _isInitialized;

  // 初始化应用
  Future<void> initialize() async {
    if (_isInitialized) {
      print('应用已经初始化，跳过重复初始化');
      return;
    }

    _setLoading(true);
    try {
      print('开始应用初始化...');

      // 设置P2P服务回调
      print('设置P2P服务回调...');
      P2PService.onMessageReceived = _handleP2PMessage;
      P2PService.onGroupUpdated = _handleGroupUpdate;
      P2PService.onConnectionValidate = _validateConnection;
      P2PService.onConnectionDisconnect = _handleConnectionDisconnect;

      // 加载用户数据
      print('加载用户数据...');
      await _loadUser();
      print('用户加载完成: ${_currentUser?.name}');

      // 加载群组数据
      print('加载群组数据...');
      await _loadGroups();
      print('群组加载完成: ${_groups.length} 个群组');

      // 设置消息更新监听
      print('设置消息监听...');
      setupMessageListener();

      // 为群组创建者启动P2P服务器
      print('启动群组服务器...');
      await _startGroupServers();

      _setError(null);
      _isInitialized = true;
      print('应用初始化完成');
    } catch (e) {
      print('初始化失败: $e');
      _setError('初始化失败: $e');
    } finally {
      _setLoading(false);
    }
  }

  // 为群组创建者启动P2P服务器
  Future<void> _startGroupServers() async {
    if (_currentUser == null) return;

    print('检查并启动群组服务器...');
    for (final group in _groups) {
      // 更新群组状态并保存到本地存储
      if (group.status != GroupStatus.active) {
        group.status = GroupStatus.active;
        await StorageService.saveGroup(group);
        print('群组 ${group.name} 状态已更新为active并保存');
      }

      // 如果当前用户是群组创建者，启动P2P服务器
      if (group.creatorId == _currentUser!.id) {
        print('为群组 ${group.name} 启动P2P服务器');
        final success = await GroupService().ensureGroupServerRunning(group);
        if (success) {
          print('群组 ${group.name} 的P2P服务器启动成功');
        } else {
          print('群组 ${group.name} 的P2P服务器启动失败');
        }
      } else {
        // 如果当前用户是群组成员，连接到群组创建者的P2P服务器
        print('为群组 ${group.name} 建立P2P连接');
        final success = await GroupService().connectToGroupServer(
          group,
          _currentUser!.id,
        );
        if (success) {
          print('群组 ${group.name} 的P2P连接建立成功');
        } else {
          print('群组 ${group.name} 的P2P连接建立失败');
        }
      }
    }

    // 在P2P连接建立完成后，检查群组状态
    if (_groups.isNotEmpty) {
      print('[加载] 开始检查群组状态...');
      await GroupService().checkAllGroupsStatus(_groups, _currentUser!.id);
      print('[加载] 群组状态检查完成');
    }
  }

  // 用户设置
  Future<bool> setupUser(String name, [String? nickname]) async {
    _setLoading(true);
    try {
      print('[注册] 开始设置用户: name=$name, nickname=$nickname');

      // 生成用户密钥对
      final userKeyPair = await KeyService.generateUserKeyPair();
      print('[注册] 生成密钥对成功');

      // 获取设备ID
      String deviceId = await _getOrCreateDeviceId();
      print('[注册] 获取设备ID: $deviceId');

      // 创建用户资料
      final profile = UserProfile(
        nickname: nickname ?? name,
        publicKey: userKeyPair['publicKey']!,
      );
      print('[注册] 创建用户资料: nickname=${profile.nickname}');

      final user = User(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        profile: profile,
        createdAt: DateTime.now(),
        lastActiveAt: DateTime.now(),
        deviceId: deviceId,
      );
      print(
        '[注册] 创建用户对象: id=${user.id}, name=${user.name}, deviceId=${user.deviceId}',
      );

      print('[注册] 开始保存用户到本地存储...');
      await StorageService.saveUser(user);
      print('[注册] 用户保存到本地存储成功');

      _currentUser = user;
      _setError(null);
      notifyListeners();

      print('[注册] 用户设置完成，当前用户: ${_currentUser!.name}');
      return true;
    } catch (e) {
      print('[注册] 用户设置失败: $e');
      _setError('用户设置失败: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // 创建群组
  Future<bool> createGroup(String name) async {
    if (_currentUser == null) {
      _setError('请先设置用户信息');
      return false;
    }

    _setLoading(true);
    try {
      final group = await GroupService().createGroup(
        name,
        _currentUser!.id,
        _currentUser!.name,
      );

      if (group != null) {
        await StorageService.saveGroup(group);
        _groups.add(group);
        _setError(null);
        notifyListeners();
        return true;
      } else {
        _setError('创建群组失败');
        return false;
      }
    } catch (e) {
      _setError('创建群组失败: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // 加入群组
  Future<bool> joinGroup(String qrData) async {
    if (_currentUser == null) {
      _setError('请先设置用户信息');
      return false;
    }

    _setLoading(true);
    try {
      final success = await GroupService().joinGroup(
        qrData,
        _currentUser!.id,
        _currentUser!.profile.nickname ?? _currentUser!.name,
      );

      if (success) {
        _setError(null);
        // 重新加载群组列表以包含新加入的群组
        await _loadGroups();
        notifyListeners();
        return true;
      } else {
        _setError('加入群组失败');
        return false;
      }
    } catch (e) {
      _setError('加入群组失败: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // 选择群组
  void selectGroup(Group group) {
    _currentGroup = group;
    notifyListeners();
  }

  // 发送消息
  Future<bool> sendMessage(String content) async {
    if (_currentGroup == null || _currentUser == null) {
      _setError('请先选择群组');
      return false;
    }

    // 检查群组状态
    if (_currentGroup!.status != GroupStatus.active) {
      _setError('群组不可用，无法发送消息');
      return false;
    }

    try {
      final success = await GroupService().sendMessage(
        _currentGroup!,
        _currentUser!.id,
        content,
      );

      if (success) {
        // 消息已通过P2P服务发送，通知UI更新
        notifyListeners();
        return true;
      } else {
        _setError('发送消息失败');
        return false;
      }
    } catch (e) {
      _setError('发送消息失败: $e');
      return false;
    }
  }

  // 获取群组消息
  List<Message> getGroupMessages(String groupId) {
    return GroupService().getGroupMessages(groupId);
  }

  // 设置消息更新监听
  void setupMessageListener() {
    print('设置消息更新监听器...');

    GroupService().onMessageUpdated = (groupId) {
      // 当有新消息时，通知UI更新
      print('消息更新回调触发: $groupId');
      notifyListeners();
    };

    GroupService().onGroupUpdated = (groupId) async {
      // 当群组信息更新时，重新加载群组数据以确保UI更新
      print('群组更新回调触发: $groupId');
      await _loadGroups();
      notifyListeners();
    };

    print('消息更新监听器设置完成');
  }

  // 生成群组二维码数据
  Future<String?> generateGroupQRData(Group group) async {
    try {
      return await GroupService().generateGroupQRData(group);
    } catch (e) {
      _setError('生成二维码失败: $e');
      return null;
    }
  }

  // 离开群组
  Future<bool> leaveGroup(Group group) async {
    if (_currentUser == null) {
      _setError('请先设置用户信息');
      return false;
    }

    try {
      print('开始离开群组: ${group.name}');

      final success = await GroupService().leaveGroup(group, _currentUser!.id);
      if (success) {
        // 从内存中移除群组
        _groups.remove(group);

        // 从本地存储中删除群组数据
        await StorageService.deleteGroup(group.id);
        print('群组数据已从本地存储删除: ${group.id}');

        // 删除群组相关的消息
        await StorageService.deleteGroupMessages(group.id);
        print('群组消息已从本地存储删除: ${group.id}');

        // 清除当前选中的群组
        if (_currentGroup?.id == group.id) {
          _currentGroup = null;
        }

        notifyListeners();
        print('离开群组成功: ${group.name}');
        return true;
      } else {
        _setError('离开群组失败');
        return false;
      }
    } catch (e) {
      print('离开群组失败: $e');
      _setError('离开群组失败: $e');
      return false;
    }
  }

  // 解散群组
  Future<bool> disbandGroup(Group group) async {
    try {
      print('开始解散群组: ${group.name}');

      final success = await GroupService().disbandGroup(group);
      if (success) {
        // 从内存中移除群组
        _groups.remove(group);

        // 从本地存储中删除群组数据
        await StorageService.deleteGroup(group.id);
        print('群组数据已从本地存储删除: ${group.id}');

        // 删除群组相关的消息
        await StorageService.deleteGroupMessages(group.id);
        print('群组消息已从本地存储删除: ${group.id}');

        // 清除当前选中的群组
        if (_currentGroup?.id == group.id) {
          _currentGroup = null;
        }

        notifyListeners();
        print('解散群组成功: ${group.name}');
        return true;
      } else {
        _setError('解散群组失败');
        return false;
      }
    } catch (e) {
      print('解散群组失败: $e');
      _setError('解散群组失败: $e');
      return false;
    }
  }

  // 清除错误
  void clearError() {
    _setError(null);
  }

  // 私有方法
  Future<void> _loadUser() async {
    try {
      print('[加载] 开始加载用户...');

      // 获取设备ID（基于硬件信息，始终不变）
      String deviceId = await _getOrCreateDeviceId();
      print('[加载] 获取设备ID: $deviceId');

      // 尝试根据设备ID查找已保存的用户
      print('[加载] 开始从本地存储查找用户...');
      final savedUser = await StorageService.loadUserByDeviceId(deviceId);
      print('[加载] 从本地存储查找结果: ${savedUser != null ? "找到用户" : "未找到用户"}');

      if (savedUser != null) {
        print(
          '[加载] 找到已保存的用户: id=${savedUser.id}, name=${savedUser.name}, deviceId=${savedUser.deviceId}',
        );
        _currentUser = savedUser;
        print('[加载] 用户恢复成功: ${_currentUser!.name}');
        return;
      }

      // 如果没有保存的用户（可能是首次启动或注销后），不自动创建新用户
      // 用户需要手动注册
      print('[加载] 未找到已保存的用户，需要用户手动注册');
      _currentUser = null;
    } catch (e) {
      print('[加载] 加载用户失败: $e');
      _currentUser = null;
    }
  }

  /// 加载群组列表
  Future<void> _loadGroups() async {
    try {
      print('开始加载群组列表...');
      final groups = await StorageService.loadAllGroups();
      _groups.clear();
      _groups.addAll(groups);

      print('=== 当前群组列表 ===');
      for (var group in _groups) {
        print('群组: ${group.name} (${group.id})');
        print('状态: ${group.status}');
        print('成员数: ${group.members.length}');
        for (var member in group.members) {
          print('  - ${member.name} (${member.userId})');
        }
        print('---');

        // 加载每个群组的消息
        print('开始加载群组 ${group.name} 的消息...');
        await GroupService().loadGroupMessages(group.id);
      }

      notifyListeners();
    } catch (e) {
      print('加载群组列表失败: $e');
      _setError('加载群组列表失败: $e');
    }
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String? error) {
    _error = error;
    notifyListeners();
  }

  // 更新用户昵称
  Future<bool> updateUserNickname(String newNickname) async {
    if (_currentUser == null) {
      _setError('用户未初始化');
      return false;
    }

    try {
      // 创建新的用户资料
      final updatedProfile = UserProfile(
        nickname: newNickname,
        publicKey: _currentUser!.profile.publicKey,
      );

      // 创建更新后的用户对象
      final updatedUser = User(
        id: _currentUser!.id,
        name: _currentUser!.name,
        profile: updatedProfile,
        createdAt: _currentUser!.createdAt,
        lastActiveAt: DateTime.now(),
        deviceId: _currentUser!.deviceId,
      );

      // 保存到本地存储
      await StorageService.saveUser(updatedUser);

      // 更新当前用户
      _currentUser = updatedUser;
      _setError(null);
      notifyListeners();

      return true;
    } catch (e) {
      _setError('更新昵称失败: $e');
      return false;
    }
  }

  // 注销账户
  Future<bool> logout() async {
    try {
      print('开始注销账户...');

      // 停止所有P2P服务
      P2PService.stopServer();
      P2PService.disconnect();

      // 清空群组消息缓存
      GroupService().clearAllMessages();

      // 删除所有数据，包括用户数据
      await StorageService.clearAllData();

      // 清空内存中的所有数据
      _currentUser = null;
      _groups.clear();
      _currentGroup = null;
      _error = null;

      // 通知UI更新
      notifyListeners();

      print('账户注销完成，所有数据已清除');
      return true;
    } catch (e) {
      print('注销失败: $e');
      _setError('注销失败: $e');
      return false;
    }
  }

  // 重置数据库（用于测试）
  Future<bool> resetDatabase() async {
    try {
      print('开始重置数据库...');

      // 停止所有P2P服务
      P2PService.stopServer();
      P2PService.disconnect();

      // 清空群组消息缓存
      GroupService().clearAllMessages();

      // 重置数据库
      await StorageService.resetDatabase();

      // 清空内存中的所有数据
      _currentUser = null;
      _groups.clear();
      _currentGroup = null;
      _error = null;

      // 通知UI更新
      notifyListeners();

      print('数据库重置完成');
      return true;
    } catch (e) {
      print('重置数据库失败: $e');
      _setError('重置数据库失败: $e');
      return false;
    }
  }

  // 获取或创建设备ID
  Future<String> _getOrCreateDeviceId() async {
    try {
      print('[设备ID] 开始生成设备ID...');
      // 设备ID应该只基于硬件信息，不依赖任何存储
      // 每次调用都重新生成，确保基于当前硬件状态
      String deviceId = await _generateHardwareBasedDeviceId();
      print('[设备ID] 生成的设备ID: $deviceId');
      return deviceId;
    } catch (e) {
      print('[设备ID] 获取设备ID失败: $e');
      // 如果获取失败，使用固定的后备标识符
      return 'device_error';
    }
  }

  // 基于硬件信息生成设备ID
  Future<String> _generateHardwareBasedDeviceId() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      String deviceId = '';

      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        // 使用Android ID作为主要标识符
        deviceId = 'android_${androidInfo.id}';
        print(
          'Android设备信息: ${androidInfo.brand} ${androidInfo.model} (ID: ${androidInfo.id})',
        );
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        // 使用iOS的identifierForVendor作为主要标识符
        deviceId = 'ios_${iosInfo.identifierForVendor}';
        print(
          'iOS设备信息: ${iosInfo.name} ${iosInfo.model} (ID: ${iosInfo.identifierForVendor})',
        );
      } else if (Platform.isWindows) {
        final windowsInfo = await deviceInfo.windowsInfo;
        // 使用Windows的设备ID
        deviceId = 'windows_${windowsInfo.deviceId}';
        print(
          'Windows设备信息: ${windowsInfo.computerName} (ID: ${windowsInfo.deviceId})',
        );
      } else if (Platform.isMacOS) {
        final macOsInfo = await deviceInfo.macOsInfo;
        // 使用macOS的硬件UUID
        deviceId = 'macos_${macOsInfo.computerName}_${macOsInfo.osRelease}';
        print(
          'macOS设备信息: ${macOsInfo.computerName} (ID: ${macOsInfo.osRelease})',
        );
      } else if (Platform.isLinux) {
        final linuxInfo = await deviceInfo.linuxInfo;
        // 使用Linux的机器ID
        deviceId = 'linux_${linuxInfo.machineId}';
        print('Linux设备信息: ${linuxInfo.name} (ID: ${linuxInfo.machineId})');
      } else {
        // 对于其他平台，使用固定的标识符
        deviceId = 'unknown_platform';
        print('未知平台设备，使用固定标识符');
      }

      return deviceId;
    } catch (e) {
      print('生成硬件设备ID失败: $e');
      // 如果获取硬件信息失败，使用固定的后备标识符
      return 'hardware_error';
    }
  }

  /// 处理连接断开
  void _handleConnectionDisconnect(String userId, String groupId) {
    print('处理连接断开: 用户=$userId, 群组=$groupId');

    // 检查当前用户是否是被断开的用户
    if (currentUser?.id == userId) {
      print('当前用户连接断开，检查群组状态');

      // 检查群组是否仍然有效
      final group = groups.where((g) => g.id == groupId).firstOrNull;
      if (group != null && group.status == GroupStatus.active) {
        // 检查用户是否真的是群组成员
        if (group.isMember(userId)) {
          print('群组仍然有效且用户是成员，尝试重新连接');
          _reconnectToGroup(group);
        } else {
          print('用户不是群组成员，不进行重连');
          // 标记群组为不可用，因为用户无法连接
          _markGroupUnavailable(group);
        }
      } else {
        print('群组无效或已不可用，不进行重连');
      }
    }
  }

  /// 重新连接到群组
  Future<void> _reconnectToGroup(Group group) async {
    try {
      print('开始重新连接到群组: ${group.id}');

      // 从本地存储获取群组信息
      final storedGroup = await StorageService.loadGroup(group.id);
      if (storedGroup == null) {
        print('无法获取群组信息，无法重连');
        return;
      }

      // 获取群组二维码数据，从中解析服务器IP和端口
      final groupService = GroupService();
      final qrData = await groupService.generateGroupQRData(storedGroup);
      if (qrData == null) {
        print('无法获取群组二维码数据，无法重连');
        return;
      }

      // 解析二维码数据获取IP和端口
      final qrDataMap = jsonDecode(qrData);
      final serverIP = qrDataMap['serverIP'];
      final serverPort = qrDataMap['serverPort'];

      print('尝试重连到服务器: $serverIP:$serverPort');

      // 尝试重新连接
      final success = await P2PService.connectToServer(
        serverIP,
        serverPort,
        currentUser!.id,
        group.id,
        isNewMember: false, // 不是新成员，是重连
      );

      if (success) {
        print('群组重连成功: ${group.id}');
        // 更新群组状态
        group.status = GroupStatus.active;
        await StorageService.saveGroup(group);
        notifyListeners();
      } else {
        print('群组重连失败: ${group.id}');
        // 标记群组为不可用
        _markGroupUnavailable(group);
      }
    } catch (e) {
      print('重连群组时发生错误: $e');
      // 标记群组为不可用
      _markGroupUnavailable(group);
    }
  }

  /// 标记群组为不可用
  Future<void> _markGroupUnavailable(Group group) async {
    try {
      print('标记群组为不可用: ${group.id}');
      group.status = GroupStatus.unavailable;
      await StorageService.saveGroup(group);
      notifyListeners();
    } catch (e) {
      print('标记群组状态失败: $e');
    }
  }

  /// 处理P2P消息
  void _handleP2PMessage(Map<String, dynamic> message) {
    print('AppProvider收到P2P消息: ${message['type']}');

    // 根据消息类型处理
    switch (message['type']) {
      case 'message':
        // 聊天消息，交给GroupService处理
        print('聊天消息: ${message}');
        final groupId = message['groupId'];
        if (groupId != null) {
          final group = groups.where((g) => g.id == groupId).firstOrNull;
          // 使用GroupService的onMessage回调
          final groupService = GroupService();

          groupService.handleChatMessage(group, message);
        }
        break;
      case 'group_update':
        // 群组更新消息
        final groupId = message['groupId'];
        if (groupId != null) {
          _handleGroupUpdate(groupId);
        }
        break;
      default:
        print('未知的P2P消息类型: ${message['type']}');
    }
  }

  /// 处理群组更新
  void _handleGroupUpdate(String groupId) {
    print('处理群组更新: $groupId');
    // 重新加载群组数据
    _loadGroups();
    notifyListeners();
  }

  /// 验证连接
  Future<bool> _validateConnection(
    String userId,
    String groupId,
    bool isNewMember,
  ) async {
    print('AppProvider验证连接: 用户=$userId, 群组=$groupId, 是否新成员=$isNewMember');

    // 检查群组是否存在
    final group = groups.where((g) => g.id == groupId).firstOrNull;
    if (group == null) {
      print('❌ 群组不存在: $groupId');
      return false;
    }
    print('✅ 群组存在: ${group.name}');
    print('群组状态: ${group.status}');
    print('群组成员数: ${group.members.length}');

    // 检查群组状态是否有效
    if (group.status != GroupStatus.active) {
      print('❌ 群组状态无效: ${group.status}');
      return false;
    }
    print('✅ 群组状态有效: ${group.status}');

    // 根据是否为新成员进行不同的验证
    if (isNewMember) {
      // 新成员加入验证：只检查群组是否存在且状态有效
      print('✅ 新成员验证通过');
      return true;
    } else {
      // 已加入成员连接验证：检查用户是否为群组成员
      print('检查用户是否为群组成员...');
      print(
        '群组成员列表: ${group.members.map((m) => '${m.userId}(${m.name})').join(', ')}',
      );

      final isMember = group.isMember(userId);
      print('用户是否是群组成员: $isMember');
      return isMember;
    }
  }

  // 重新连接群组
  Future<bool> reconnectToGroup(Group group) async {
    if (_currentUser == null) {
      _setError('用户未初始化');
      return false;
    }

    _setLoading(true);
    try {
      print('AppProvider: 开始重新连接群组: ${group.name}');

      final success = await GroupService().reconnectToGroup(
        group,
        _currentUser!.id,
      );

      print('AppProvider: GroupService.reconnectToGroup 返回结果: $success');

      if (success) {
        _setError(null);
        // 只更新当前群组状态，不重新加载所有群组
        final updatedGroup = await StorageService.loadGroup(group.id);
        if (updatedGroup != null) {
          // 更新内存中的群组状态
          final index = _groups.indexWhere((g) => g.id == group.id);
          if (index != -1) {
            _groups[index] = updatedGroup;
            print('AppProvider: 已更新内存中的群组状态: ${updatedGroup.status}');
          }
        }
        notifyListeners();
        print('AppProvider: 重新连接成功，返回 true');
        return true;
      } else {
        _setError('重新连接群组失败');
        print('AppProvider: 重新连接失败，返回 false');
        return false;
      }
    } catch (e) {
      _setError('重新连接群组失败: $e');
      print('AppProvider: 重新连接异常: $e，返回 false');
      return false;
    } finally {
      _setLoading(false);
      print('AppProvider: 重新连接方法结束');
    }
  }

  // 检查群组连接状态
  Future<bool> checkGroupConnectionStatus(Group group) async {
    try {
      return await GroupService().checkGroupConnectionStatus(group);
    } catch (e) {
      print('检查群组连接状态失败: $e');
      return false;
    }
  }

  // 重启群组服务器（群组创建者使用）
  Future<bool> restartGroupServer(Group group) async {
    if (_currentUser == null) {
      _setError('用户未初始化');
      return false;
    }

    // 检查是否为群组创建者
    if (group.creatorId != _currentUser!.id) {
      _setError('只有群组创建者可以重启服务器');
      return false;
    }

    _setLoading(true);
    try {
      print('开始重启群组服务器: ${group.name}');

      // 停止当前服务器
      P2PService.stopServer();

      // 重新启动服务器
      final success = await GroupService().ensureGroupServerRunning(group);

      if (success) {
        _setError(null);
        // 只更新当前群组状态，不重新加载所有群组
        final updatedGroup = await StorageService.loadGroup(group.id);
        if (updatedGroup != null) {
          // 更新内存中的群组状态
          final index = _groups.indexWhere((g) => g.id == group.id);
          if (index != -1) {
            _groups[index] = updatedGroup;
          }
        }
        notifyListeners();
        return true;
      } else {
        _setError('重启群组服务器失败');
        return false;
      }
    } catch (e) {
      _setError('重启群组服务器失败: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }
}
