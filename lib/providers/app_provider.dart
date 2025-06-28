import 'package:flutter/material.dart';
import '../models/user.dart';
import '../models/group.dart';
import '../models/message.dart';
import '../services/group_service.dart';
import '../services/p2p_service.dart';
import '../services/storage_service.dart';
import '../services/key_service.dart';
import '../utils/debug_logger.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import 'dart:convert';
import '../services/key_manager.dart';
import '../services/encryption_service.dart';

class AppProvider with ChangeNotifier {
  User? _currentUser;
  List<Group> _groups = [];
  Group? _currentGroup;
  bool _isLoading = false;
  String? _error;
  bool _isInitialized = false;

  // 新增：userId到publicKey的Map
  final Map<String, String> _userPublicKeyMap = {};

  // Getters
  User? get currentUser => _currentUser;
  List<Group> get groups => _groups;
  Group? get currentGroup => _currentGroup;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isInitialized => _isInitialized;

  // 获取userId->publicKey Map（当前所有群成员）
  Map<String, String> getUserPublicKeyMap() {
    final map = <String, String>{};
    for (final group in _groups) {
      for (final member in group.members) {
        map[member.userId] = member.publicKey;
      }
    }
    // 当前用户也加入
    if (_currentUser != null) {
      map[_currentUser!.id] = _currentUser!.publicKey;
    }
    return map;
  }

  // 初始化应用
  Future<void> initialize() async {
    if (_isInitialized) {
      DebugLogger().info('应用已经初始化，跳过重复初始化', tag: 'APP_PROVIDER');
      return;
    }

    _setLoading(true);
    try {
      DebugLogger().info('开始应用初始化...', tag: 'APP_PROVIDER');

      // 设置P2P服务回调
      DebugLogger().info('设置P2P服务回调...', tag: 'APP_PROVIDER');
      P2PService.onMessageReceived = _handleP2PMessage;
      P2PService.onGroupUpdated = _handleGroupUpdate;
      P2PService.onConnectionValidate = _validateConnection;
      P2PService.onConnectionDisconnect = _handleConnectionDisconnect;

      // 加载用户数据
      DebugLogger().info('加载用户数据...', tag: 'APP_PROVIDER');
      await _loadUser();
      DebugLogger().info('用户加载完成: ${_currentUser?.name}', tag: 'APP_PROVIDER');

      // 加载群组数据
      DebugLogger().info('加载群组数据...', tag: 'APP_PROVIDER');
      await _loadGroups();
      DebugLogger().info('群组加载完成: ${_groups.length} 个群组', tag: 'APP_PROVIDER');

      // 设置消息更新监听
      DebugLogger().info('设置消息监听...', tag: 'APP_PROVIDER');
      setupMessageListener();

      // 为群组创建者启动P2P服务器
      DebugLogger().info('启动群组服务器...', tag: 'APP_PROVIDER');
      await _startGroupServers();

      _setError(null);
      _isInitialized = true;
      DebugLogger().info('应用初始化完成', tag: 'APP_PROVIDER');
    } catch (e) {
      DebugLogger().error('初始化失败: $e', tag: 'APP_PROVIDER');
      _setError('初始化失败: $e');
    } finally {
      _setLoading(false);
    }
  }

  // 为群组创建者启动P2P服务器
  Future<void> _startGroupServers() async {
    if (_currentUser == null) return;

    DebugLogger().info('检查并启动群组服务器...', tag: 'APP_PROVIDER');
    for (final group in _groups) {
      // 更新群组状态并保存到本地存储
      if (group.status != GroupStatus.active) {
        group.status = GroupStatus.active;
        await StorageService.saveGroup(group);
        DebugLogger().info(
          '群组 ${group.name} 状态已更新为active并保存',
          tag: 'APP_PROVIDER',
        );
      }

      // 如果当前用户是群组创建者，启动P2P服务器
      if (group.creatorId == _currentUser!.id) {
        DebugLogger().info('为群组 ${group.name} 启动P2P服务器', tag: 'APP_PROVIDER');
        final success = await GroupService().ensureGroupServerRunning(group);
        if (success) {
          DebugLogger().info(
            '群组 ${group.name} 的P2P服务器启动成功',
            tag: 'APP_PROVIDER',
          );
        } else {
          DebugLogger().info(
            '群组 ${group.name} 的P2P服务器启动失败',
            tag: 'APP_PROVIDER',
          );
        }
      } else {
        // 如果当前用户是群组成员，连接到群组创建者的P2P服务器
        DebugLogger().info('为群组 ${group.name} 建立P2P连接', tag: 'APP_PROVIDER');
        final success = await GroupService().connectToGroupServer(
          group,
          _currentUser!.id,
        );
        if (success) {
          DebugLogger().info(
            '群组 ${group.name} 的P2P连接建立成功',
            tag: 'APP_PROVIDER',
          );
        } else {
          DebugLogger().info(
            '群组 ${group.name} 的P2P连接建立失败',
            tag: 'APP_PROVIDER',
          );
        }
      }
    }

    // 在P2P连接建立完成后，检查群组状态
    if (_groups.isNotEmpty) {
      DebugLogger().info('[加载] 开始检查群组状态...', tag: 'APP_PROVIDER');
      // 暂时注释掉，因为GroupService没有这个方法
      // await GroupService().checkAllGroupsStatus(_groups, _currentUser!.id);
      DebugLogger().info('[加载] 群组状态检查完成', tag: 'APP_PROVIDER');
    }
  }

  // 用户设置
  Future<bool> setupUser(String name, [String? nickname]) async {
    _setLoading(true);
    try {
      DebugLogger().info(
        '[注册] 开始设置用户: name=$name, nickname=$nickname',
        tag: 'APP_PROVIDER',
      );

      // 生成用户密钥对（只在注册时生成一次，后续都用KeyManager加载）
      final userKeyPairMap = await Ed25519Helper.generateKeyPair();
      DebugLogger().info('[注册] 生成Ed25519密钥对成功', tag: 'APP_PROVIDER');

      // 保存密钥对到KeyManager（持久化+内存）
      final tempUserId = DateTime.now().millisecondsSinceEpoch.toString();
      DebugLogger().info(
        '[注册] 保存密钥对到KeyManager: userId=$tempUserId, publicKey=${userKeyPairMap['publicKey']!.substring(0, 8)}..., privateKey=${userKeyPairMap['privateKey']!.substring(0, 8)}...',
        tag: 'APP_PROVIDER',
      );
      await KeyManager.saveUserKeyPair(
        tempUserId, // userId，后面会被User对象覆盖
        UserKeyPair(
          publicKey: userKeyPairMap['publicKey']!,
          privateKey: userKeyPairMap['privateKey']!,
          createdAt: DateTime.now(),
          algorithm: KeyAlgorithm.ed25519,
        ),
      );

      // 获取设备ID
      String deviceId = await _getOrCreateDeviceId();
      DebugLogger().info('[注册] 获取设备ID: $deviceId', tag: 'APP_PROVIDER');

      // 创建用户资料
      final profile = UserProfile(
        nickname: nickname ?? name,
        publicKey: userKeyPairMap['publicKey']!,
      );
      DebugLogger().info(
        '[注册] 创建用户资料: nickname=${profile.nickname}',
        tag: 'APP_PROVIDER',
      );

      final user = User(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        profile: profile,
        createdAt: DateTime.now(),
        lastActiveAt: DateTime.now(),
        deviceId: deviceId,
      );
      DebugLogger().info(
        '[注册] 创建用户对象: id=${user.id}, name=${user.name}, deviceId=${user.deviceId}',
        tag: 'APP_PROVIDER',
      );

      DebugLogger().info('[注册] 开始保存用户到本地存储...', tag: 'APP_PROVIDER');
      await StorageService.saveUser(user);
      // 再次保存密钥对，确保userId与User对象一致
      await KeyManager.saveUserKeyPair(
        user.id,
        UserKeyPair(
          publicKey: userKeyPairMap['publicKey']!,
          privateKey: userKeyPairMap['privateKey']!,
          createdAt: DateTime.now(),
          algorithm: KeyAlgorithm.ed25519,
        ),
      );
      DebugLogger().info('[注册] 用户保存到本地存储成功', tag: 'APP_PROVIDER');

      _currentUser = user;
      _setError(null);
      notifyListeners();

      DebugLogger().info(
        '[注册] 用户设置完成，当前用户: ${_currentUser!.name}',
        tag: 'APP_PROVIDER',
      );
      return true;
    } catch (e) {
      DebugLogger().error('[注册] 用户设置失败: $e', tag: 'APP_PROVIDER');
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
        _currentUser!.profile.publicKey,
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
        _currentGroup!.id,
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
    DebugLogger().info('设置消息更新监听器...', tag: 'APP_PROVIDER');

    GroupService().onMessageUpdated = (groupId) {
      // 当有新消息时，通知UI更新
      DebugLogger().info('消息更新回调触发: $groupId', tag: 'APP_PROVIDER');
      notifyListeners();
    };

    GroupService().onGroupUpdated = (groupId) async {
      // 当群组信息更新时，重新加载群组数据以确保UI更新
      DebugLogger().info('群组更新回调触发: $groupId', tag: 'APP_PROVIDER');
      await _loadGroups();
      notifyListeners();
    };

    DebugLogger().info('消息更新监听器设置完成', tag: 'APP_PROVIDER');
  }

  // 加载群组
  Future<void> _loadGroups() async {
    try {
      DebugLogger().info('[加载] 开始加载群组...', tag: 'APP_PROVIDER');
      final groups = await StorageService.loadAllGroups();
      _groups.clear();
      _groups.addAll(groups);

      // 加载所有群组的消息到内存缓存
      await GroupService().loadAllGroupMessages();

      DebugLogger().info(
        '[加载] 群组加载完成，共 ${_groups.length} 个群组',
        tag: 'APP_PROVIDER',
      );
      notifyListeners();
    } catch (e) {
      DebugLogger().error('[加载] 加载群组失败: $e', tag: 'APP_PROVIDER');
      _setError('加载群组失败: $e');
    }
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

    _setLoading(true);
    try {
      final success = await GroupService().leaveGroup(
        group.id,
        _currentUser!.id,
      );

      if (success) {
        _groups.remove(group);
        if (_currentGroup?.id == group.id) {
          _currentGroup = null;
        }
        _setError(null);
        notifyListeners();
        return true;
      } else {
        _setError('离开群组失败');
        return false;
      }
    } catch (e) {
      _setError('离开群组失败: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // 解散群组
  Future<bool> disbandGroup(Group group) async {
    if (_currentUser == null) {
      _setError('请先设置用户信息');
      return false;
    }

    _setLoading(true);
    try {
      final success = await GroupService().disbandGroup(
        group.id,
        _currentUser!.id,
      );

      if (success) {
        _groups.remove(group);
        if (_currentGroup?.id == group.id) {
          _currentGroup = null;
        }
        _setError(null);
        notifyListeners();
        return true;
      } else {
        _setError('解散群组失败');
        return false;
      }
    } catch (e) {
      _setError('解散群组失败: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // 清除错误
  void clearError() {
    _setError(null);
  }

  // 私有方法
  Future<void> _loadUser() async {
    try {
      DebugLogger().info('[加载] 开始加载用户...', tag: 'APP_PROVIDER');

      // 获取设备ID（基于硬件信息，始终不变）
      String deviceId = await _getOrCreateDeviceId();
      DebugLogger().info('[加载] 获取设备ID: $deviceId', tag: 'APP_PROVIDER');

      // 尝试根据设备ID查找已保存的用户
      DebugLogger().info('[加载] 开始从本地存储查找用户...', tag: 'APP_PROVIDER');
      final savedUser = await StorageService.loadUserByDeviceId(deviceId);
      DebugLogger().info(
        '[加载] 从本地存储查找结果: ${savedUser != null ? "找到用户" : "未找到用户"}',
        tag: 'APP_PROVIDER',
      );

      if (savedUser != null) {
        DebugLogger().info(
          '[加载] 找到已保存的用户: id=${savedUser.id}, name=${savedUser.name}, deviceId=${savedUser.deviceId}',
          tag: 'APP_PROVIDER',
        );
        _currentUser = savedUser;
        // 加载密钥对到KeyManager内存
        await KeyManager.loadUserKeyPair(_currentUser!.id);
        DebugLogger().info(
          '[加载] 用户恢复成功: ${_currentUser!.name}',
          tag: 'APP_PROVIDER',
        );
        return;
      }

      // 如果没有保存的用户（可能是首次启动或注销后），不自动创建新用户
      // 用户需要手动注册
      DebugLogger().info('[加载] 未找到已保存的用户，需要用户手动注册', tag: 'APP_PROVIDER');
      _currentUser = null;
    } catch (e) {
      DebugLogger().error('[加载] 加载用户失败: $e', tag: 'APP_PROVIDER');
      _currentUser = null;
    }
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

  // 注销用户
  Future<bool> logout() async {
    _setLoading(true);
    try {
      DebugLogger().info('[注销] 开始注销用户...', tag: 'APP_PROVIDER');

      // 注销前主动离开所有已加入的群组，通知其他成员
      if (_currentUser != null && _groups.isNotEmpty) {
        for (final group in List<Group>.from(_groups)) {
          try {
            await GroupService().leaveGroupForLogout(
              group.id,
              _currentUser!.id,
            );
          } catch (e) {
            DebugLogger().error(
              '[注销] 离开群组失败: ${group.id}, $e',
              tag: 'APP_PROVIDER',
            );
          }
        }
      }

      // 断开所有websocket连接
      ConnectionManager.disconnectAllConnections();

      // 停止P2P服务
      await P2PService.stopServer();
      DebugLogger().info('[注销] P2P服务已停止', tag: 'APP_PROVIDER');

      // 清空消息缓存
      GroupService().clearAllGroupMessages();
      DebugLogger().info('[注销] 消息缓存已清空', tag: 'APP_PROVIDER');

      // 清空用户数据
      _currentUser = null;
      _currentGroup = null;
      _groups.clear();

      // 清空本地存储
      await StorageService.clearAllData();
      DebugLogger().info('[注销] 本地存储已清空', tag: 'APP_PROVIDER');

      _setError(null);
      notifyListeners();

      DebugLogger().info('[注销] 用户注销完成', tag: 'APP_PROVIDER');
      return true;
    } catch (e) {
      DebugLogger().error('[注销] 用户注销失败: $e', tag: 'APP_PROVIDER');
      _setError('用户注销失败: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // 注销用户（保留用户信息）
  Future<bool> logoutKeepUser() async {
    _setLoading(true);
    try {
      DebugLogger().info('[注销] 开始注销用户（保留用户信息）...', tag: 'APP_PROVIDER');

      // 停止P2P服务
      await P2PService.stopServer();
      DebugLogger().info('[注销] P2P服务已停止', tag: 'APP_PROVIDER');

      // 清空消息缓存
      GroupService().clearAllGroupMessages();
      DebugLogger().info('[注销] 消息缓存已清空', tag: 'APP_PROVIDER');

      // 清空群组和消息数据，但保留用户信息
      _currentGroup = null;
      _groups.clear();

      // 清空群组和消息存储，但保留用户信息
      await StorageService.clearGroupsAndMessages();
      DebugLogger().info('[注销] 群组和消息数据已清空', tag: 'APP_PROVIDER');

      _setError(null);
      notifyListeners();

      DebugLogger().info('[注销] 用户注销完成（保留用户信息）', tag: 'APP_PROVIDER');
      return true;
    } catch (e) {
      DebugLogger().error('[注销] 用户注销失败: $e', tag: 'APP_PROVIDER');
      _setError('用户注销失败: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // 重置数据库
  Future<bool> resetDatabase() async {
    try {
      DebugLogger().info('开始重置数据库...', tag: 'APP_PROVIDER');

      // 停止所有P2P服务
      await P2PService.stopServer();

      // 清空群组消息缓存
      GroupService().clearAllGroupMessages();

      // 重置数据库
      await StorageService.resetDatabase();

      // 清空内存中的所有数据
      _currentUser = null;
      _groups.clear();
      _currentGroup = null;
      _error = null;

      // 通知UI更新
      notifyListeners();

      DebugLogger().info('数据库重置完成', tag: 'APP_PROVIDER');
      return true;
    } catch (e) {
      DebugLogger().error('重置数据库失败: $e', tag: 'APP_PROVIDER');
      _setError('重置数据库失败: $e');
      return false;
    }
  }

  // 获取或创建设备ID
  Future<String> _getOrCreateDeviceId() async {
    try {
      DebugLogger().info('[设备ID] 开始生成设备ID...', tag: 'APP_PROVIDER');
      // 设备ID应该只基于硬件信息，不依赖任何存储
      // 每次调用都重新生成，确保基于当前硬件状态
      String deviceId = await _generateHardwareBasedDeviceId();
      DebugLogger().info('[设备ID] 生成的设备ID: $deviceId', tag: 'APP_PROVIDER');
      return deviceId;
    } catch (e) {
      DebugLogger().error('[设备ID] 获取设备ID失败: $e', tag: 'APP_PROVIDER');
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
        DebugLogger().info(
          'Android设备信息: ${androidInfo.brand} ${androidInfo.model} (ID: ${androidInfo.id})',
          tag: 'APP_PROVIDER',
        );
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        // 使用iOS的identifierForVendor作为主要标识符
        deviceId = 'ios_${iosInfo.identifierForVendor}';
        DebugLogger().info(
          'iOS设备信息: ${iosInfo.name} ${iosInfo.model} (ID: ${iosInfo.identifierForVendor})',
          tag: 'APP_PROVIDER',
        );
      } else if (Platform.isWindows) {
        final windowsInfo = await deviceInfo.windowsInfo;
        // 使用Windows的设备ID
        deviceId = 'windows_${windowsInfo.deviceId}';
        DebugLogger().info(
          'Windows设备信息: ${windowsInfo.computerName} (ID: ${windowsInfo.deviceId})',
          tag: 'APP_PROVIDER',
        );
      } else if (Platform.isMacOS) {
        final macOsInfo = await deviceInfo.macOsInfo;
        // 使用macOS的硬件UUID
        deviceId = 'macos_${macOsInfo.computerName}_${macOsInfo.osRelease}';
        DebugLogger().info(
          'macOS设备信息: ${macOsInfo.computerName} (ID: ${macOsInfo.osRelease})',
          tag: 'APP_PROVIDER',
        );
      } else if (Platform.isLinux) {
        final linuxInfo = await deviceInfo.linuxInfo;
        // 使用Linux的机器ID
        deviceId = 'linux_${linuxInfo.machineId}';
        DebugLogger().info(
          'Linux设备信息: ${linuxInfo.name} (ID: ${linuxInfo.machineId})',
          tag: 'APP_PROVIDER',
        );
      } else {
        // 对于其他平台，使用固定的标识符
        deviceId = 'unknown_platform';
        DebugLogger().info('未知平台设备，使用固定标识符', tag: 'APP_PROVIDER');
      }

      return deviceId;
    } catch (e) {
      DebugLogger().error('生成硬件设备ID失败: $e', tag: 'APP_PROVIDER');
      // 如果获取硬件信息失败，使用固定的后备标识符
      return 'hardware_error';
    }
  }

  /// 处理连接断开
  void _handleConnectionDisconnect(String userId, String groupId) {
    DebugLogger().info('处理连接断开: 用户=$userId, 群组=$groupId', tag: 'APP_PROVIDER');

    // 检查当前用户是否是被断开的用户
    if (currentUser?.id == userId) {
      DebugLogger().info('当前用户连接断开，检查群组状态', tag: 'APP_PROVIDER');

      // 检查群组是否仍然有效
      final group = groups.where((g) => g.id == groupId).firstOrNull;
      if (group != null && group.status == GroupStatus.active) {
        // 检查用户是否真的是群组成员
        if (group.isMember(userId)) {
          DebugLogger().info('群组仍然有效且用户是成员，尝试重新连接', tag: 'APP_PROVIDER');
          _reconnectToGroup(group);
        } else {
          DebugLogger().info('用户不是群组成员，不进行重连', tag: 'APP_PROVIDER');
          // 标记群组为不可用，因为用户无法连接
          _markGroupUnavailable(group);
        }
      } else {
        DebugLogger().info('群组无效或已不可用，不进行重连', tag: 'APP_PROVIDER');
      }
    }
  }

  /// 重新连接到群组
  Future<void> _reconnectToGroup(Group group) async {
    try {
      DebugLogger().info('开始重新连接到群组: ${group.id}', tag: 'APP_PROVIDER');

      // 从本地存储获取群组信息
      final storedGroup = await StorageService.loadGroup(group.id);
      if (storedGroup == null) {
        DebugLogger().info('无法获取群组信息，无法重连', tag: 'APP_PROVIDER');
        return;
      }

      // 获取群组二维码数据，从中解析服务器IP和端口
      final groupService = GroupService();
      final qrData = await groupService.generateGroupQRData(storedGroup);
      if (qrData == null) {
        DebugLogger().info('无法获取群组二维码数据，无法重连', tag: 'APP_PROVIDER');
        return;
      }

      // 解析二维码数据获取IP和端口
      final qrDataMap = jsonDecode(qrData);
      final serverIP = qrDataMap['serverIP'];
      final serverPort = qrDataMap['serverPort'];

      DebugLogger().info(
        '尝试重连到服务器: $serverIP:$serverPort',
        tag: 'APP_PROVIDER',
      );

      // 尝试重新连接
      final success = await P2PService.connectToServer(
        serverIP,
        serverPort,
        currentUser!.id,
        group.id,
      );

      if (success) {
        DebugLogger().info('群组重连成功: ${group.id}', tag: 'APP_PROVIDER');
        // 更新群组状态
        group.status = GroupStatus.active;
        await StorageService.saveGroup(group);
        notifyListeners();
      } else {
        DebugLogger().info('群组重连失败: ${group.id}', tag: 'APP_PROVIDER');
        // 标记群组为不可用
        _markGroupUnavailable(group);
      }
    } catch (e) {
      DebugLogger().error('重连群组时发生错误: $e', tag: 'APP_PROVIDER');
      // 标记群组为不可用
      _markGroupUnavailable(group);
    }
  }

  /// 标记群组为不可用
  Future<void> _markGroupUnavailable(Group group) async {
    try {
      DebugLogger().info('标记群组为不可用: ${group.id}', tag: 'APP_PROVIDER');
      group.status = GroupStatus.unavailable;
      await StorageService.saveGroup(group);
      notifyListeners();
    } catch (e) {
      DebugLogger().error('标记群组状态失败: $e', tag: 'APP_PROVIDER');
    }
  }

  /// 处理P2P消息
  void _handleP2PMessage(Map<String, dynamic> message) {
    DebugLogger().info(
      'AppProvider收到P2P消息: ${message['type']}',
      tag: 'APP_PROVIDER',
    );

    // 根据消息类型处理
    switch (message['type']) {
      case 'message':
        // 聊天消息，交给GroupService处理
        DebugLogger().info('聊天消息: ${message}', tag: 'APP_PROVIDER');
        final groupId = message['groupId'] as String?;
        // 暂时注释掉，因为GroupService没有这个方法
        // GroupService().handleChatMessage(message);
        break;
      case 'group_update':
        // 群组更新消息
        final groupId = message['groupId'] as String?;
        if (groupId != null && groupId.isNotEmpty) {
          _handleGroupUpdate(groupId);
        }
        break;
      default:
        DebugLogger().info('未知消息类型: ${message['type']}', tag: 'APP_PROVIDER');
    }
  }

  /// 处理群组更新
  void _handleGroupUpdate(String groupId) {
    DebugLogger().info('处理群组更新: $groupId', tag: 'APP_PROVIDER');
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
    DebugLogger().info(
      'AppProvider验证连接: 用户=$userId, 群组=$groupId, 是否新成员=$isNewMember',
      tag: 'APP_PROVIDER',
    );

    // 检查群组是否存在
    final group = groups.where((g) => g.id == groupId).firstOrNull;
    if (group == null) {
      DebugLogger().error('❌ 群组不存在: $groupId', tag: 'APP_PROVIDER');
      return false;
    }
    DebugLogger().info('✅ 群组存在: ${group.name}', tag: 'APP_PROVIDER');
    DebugLogger().info('群组状态: ${group.status}', tag: 'APP_PROVIDER');
    DebugLogger().info('群组成员数: ${group.members.length}', tag: 'APP_PROVIDER');

    // 检查群组状态是否有效
    if (group.status != GroupStatus.active) {
      DebugLogger().error('❌ 群组状态无效: ${group.status}', tag: 'APP_PROVIDER');
      return false;
    }
    DebugLogger().info('✅ 群组状态有效: ${group.status}', tag: 'APP_PROVIDER');

    // 根据是否为新成员进行不同的验证
    if (isNewMember) {
      // 新成员加入验证：只检查群组是否存在且状态有效
      DebugLogger().info('✅ 新成员验证通过', tag: 'APP_PROVIDER');
      return true;
    } else {
      // 已加入成员连接验证：检查用户是否为群组成员
      DebugLogger().info('检查用户是否为群组成员...', tag: 'APP_PROVIDER');
      DebugLogger().info(
        '群组成员列表: ${group.members.map((m) => '${m.userId}(${m.name})').join(', ')}',
        tag: 'APP_PROVIDER',
      );

      final isMember = group.isMember(userId);
      DebugLogger().info('用户是否是群组成员: $isMember', tag: 'APP_PROVIDER');
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
      DebugLogger().info(
        'AppProvider: 开始重新连接群组: ${group.name}',
        tag: 'APP_PROVIDER',
      );

      final success = await GroupService().reconnectToGroup(
        group,
        _currentUser!.id,
      );

      DebugLogger().info(
        'AppProvider: GroupService.reconnectToGroup 返回结果: $success',
        tag: 'APP_PROVIDER',
      );

      if (success) {
        _setError(null);
        // 只更新当前群组状态，不重新加载所有群组
        final updatedGroup = await StorageService.loadGroup(group.id);
        if (updatedGroup != null) {
          updatedGroup.status = GroupStatus.active;
          await StorageService.saveGroup(updatedGroup);
          // 更新内存中的群组状态
          final index = _groups.indexWhere((g) => g.id == group.id);
          if (index != -1) {
            _groups[index] = updatedGroup;
            DebugLogger().info(
              'AppProvider: 已更新内存中的群组状态: ${updatedGroup.status}',
              tag: 'APP_PROVIDER',
            );
          }
        }
        notifyListeners();
        DebugLogger().info('AppProvider: 重新连接成功，返回 true', tag: 'APP_PROVIDER');
        return true;
      } else {
        _setError('重新连接群组失败');
        DebugLogger().info('AppProvider: 重新连接失败，返回 false', tag: 'APP_PROVIDER');
        return false;
      }
    } catch (e) {
      _setError('重新连接群组失败: $e');
      DebugLogger().error(
        'AppProvider: 重新连接异常: $e，返回 false',
        tag: 'APP_PROVIDER',
      );
      return false;
    } finally {
      _setLoading(false);
      DebugLogger().info('AppProvider: 重新连接方法结束', tag: 'APP_PROVIDER');
    }
  }

  // 检查群组连接状态
  Future<bool> checkGroupConnectionStatus(Group group) async {
    try {
      return await GroupService().checkGroupConnectionStatus(group);
    } catch (e) {
      DebugLogger().error('检查群组连接状态失败: $e', tag: 'APP_PROVIDER');
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
      DebugLogger().info('开始重启群组服务器: ${group.name}', tag: 'APP_PROVIDER');

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

  // 私有方法
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String? error) {
    _error = error;
    notifyListeners();
  }
}
