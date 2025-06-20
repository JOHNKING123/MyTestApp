import 'package:flutter/foundation.dart';
import '../models/user.dart';
import '../models/group.dart';
import '../models/message.dart';
import '../services/storage_service.dart';
import '../services/group_service.dart';
import '../services/p2p_service.dart';
import '../services/key_service.dart';

class AppProvider with ChangeNotifier {
  User? _currentUser;
  List<Group> _groups = [];
  Group? _currentGroup;
  bool _isLoading = false;
  String? _error;

  // Getters
  User? get currentUser => _currentUser;
  List<Group> get groups => _groups;
  Group? get currentGroup => _currentGroup;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // 初始化应用
  Future<void> initialize() async {
    _setLoading(true);
    try {
      // 加载用户数据
      await _loadUser();
      // 加载群组数据
      await _loadGroups();
      // 设置消息更新监听
      setupMessageListener();
      _setError(null);
    } catch (e) {
      _setError('初始化失败: $e');
    } finally {
      _setLoading(false);
    }
  }

  // 用户设置
  Future<bool> setupUser(String name) async {
    _setLoading(true);
    try {
      // 生成用户密钥对
      final userKeyPair = await KeyService.generateUserKeyPair();

      // 创建用户资料
      final profile = UserProfile(
        nickname: name,
        publicKey: userKeyPair['publicKey']!,
      );

      final user = User(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        profile: profile,
        createdAt: DateTime.now(),
        lastActiveAt: DateTime.now(),
        deviceId: 'device_${DateTime.now().millisecondsSinceEpoch}',
      );

      await StorageService.saveUser(user);
      _currentUser = user;
      _setError(null);
      notifyListeners();
      return true;
    } catch (e) {
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
        _currentUser!.name,
      );

      if (success) {
        _setError(null);
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
    GroupService().onMessageUpdated = (groupId) {
      // 当有新消息时，通知UI更新
      notifyListeners();
    };
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
      final success = await GroupService().leaveGroup(group, _currentUser!.id);
      if (success) {
        _groups.remove(group);
        if (_currentGroup?.id == group.id) {
          _currentGroup = null;
        }
        notifyListeners();
        return true;
      } else {
        _setError('离开群组失败');
        return false;
      }
    } catch (e) {
      _setError('离开群组失败: $e');
      return false;
    }
  }

  // 解散群组
  Future<bool> disbandGroup(Group group) async {
    try {
      final success = await GroupService().disbandGroup(group);
      if (success) {
        _groups.remove(group);
        if (_currentGroup?.id == group.id) {
          _currentGroup = null;
        }
        notifyListeners();
        return true;
      } else {
        _setError('解散群组失败');
        return false;
      }
    } catch (e) {
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
    // 简化实现：从存储中加载第一个用户
    final groups = await StorageService.loadAllGroups();
    if (groups.isNotEmpty) {
      // 如果有群组，说明有用户，这里简化处理
      // 实际应用中应该从用户存储中加载
      _currentUser = User(
        id: 'temp_user',
        name: '临时用户',
        profile: UserProfile(publicKey: 'temp_key'),
        createdAt: DateTime.now(),
        lastActiveAt: DateTime.now(),
        deviceId: 'temp_device',
      );
    }
  }

  Future<void> _loadGroups() async {
    _groups = await StorageService.loadAllGroups();
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String? error) {
    _error = error;
    notifyListeners();
  }
}
