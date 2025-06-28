import 'dart:convert';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/group.dart';
import '../models/user.dart';
import '../models/message.dart';
import '../models/member.dart';
import '../utils/debug_logger.dart';

class StorageServiceHive {
  static bool _initialized = false;
  static late Box _userBox;
  static late Box _groupBox;
  static late Box _messageBox;

  static Future<void> initialize() async {
    if (_initialized) return;
    await Hive.initFlutter();
    _userBox = await Hive.openBox('users');
    _groupBox = await Hive.openBox('groups');
    _messageBox = await Hive.openBox('messages');
    _initialized = true;
  }

  /// 保存用户
  static Future<bool> saveUser(User user) async {
    try {
      DebugLogger().info(
        '[Hive] 开始保存用户到Hive: id=${user.id}, deviceId=${user.deviceId}',
        tag: 'HIVE',
      );
      await _userBox.put(user.deviceId, user.toJson());
      DebugLogger().info('[Hive] 用户保存到Hive成功', tag: 'HIVE');
      return true;
    } catch (e) {
      DebugLogger().error('[Hive] 保存用户到Hive失败: $e', tag: 'HIVE');
      return false;
    }
  }

  /// 加载用户
  static Future<User?> loadUser(String userId) async {
    try {
      await initialize();
      final userJson = _userBox.get(userId);
      if (userJson == null) return null;
      return User.fromJson(jsonDecode(userJson));
    } catch (e) {
      DebugLogger().error('加载用户失败: $e', tag: 'HIVE');
      return null;
    }
  }

  /// 根据设备ID加载用户
  static Future<User?> loadUserByDeviceId(String deviceId) async {
    try {
      DebugLogger().info('[Hive] 开始从Hive查找用户: deviceId=$deviceId', tag: 'HIVE');
      final userData = _userBox.get(deviceId);
      DebugLogger().info('[Hive] 从Hive获取的用户数据: $userData', tag: 'HIVE');

      if (userData != null) {
        final user = User.fromJson(Map<String, dynamic>.from(userData));
        DebugLogger().info(
          '[Hive] 成功解析用户: id=${user.id}, name=${user.name}',
          tag: 'HIVE',
        );
        return user;
      } else {
        DebugLogger().info('[Hive] 未找到用户数据', tag: 'HIVE');
        return null;
      }
    } catch (e) {
      DebugLogger().error('[Hive] 从Hive加载用户失败: $e', tag: 'HIVE');
      return null;
    }
  }

  // 群组
  static Future<bool> saveGroup(Group group) async {
    await initialize();
    await _groupBox.put(group.id, jsonEncode(group.toJson()));
    // 保存成员信息（可选，简化处理）
    return true;
  }

  static Future<Group?> loadGroup(String groupId) async {
    await initialize();
    final data = _groupBox.get(groupId);
    if (data == null) return null;
    return Group.fromJson(jsonDecode(data));
  }

  static Future<List<Group>> loadAllGroups() async {
    await initialize();
    return _groupBox.values.map((e) => Group.fromJson(jsonDecode(e))).toList();
  }

  /// 删除指定群组
  static Future<bool> deleteGroup(String groupId) async {
    try {
      DebugLogger().info('[Hive] 开始删除群组: $groupId', tag: 'HIVE');
      await initialize();
      await _groupBox.delete(groupId);
      DebugLogger().info('[Hive] 群组删除成功: $groupId', tag: 'HIVE');
      return true;
    } catch (e) {
      DebugLogger().error('[Hive] 删除群组失败: $e', tag: 'HIVE');
      return false;
    }
  }

  /// 删除指定群组的所有消息
  static Future<bool> deleteGroupMessages(String groupId) async {
    try {
      DebugLogger().info('[Hive] 开始删除群组消息: $groupId', tag: 'HIVE');
      await initialize();

      // 获取所有消息键
      final keysToDelete = <String>[];
      for (final key in _messageBox.keys) {
        if (key.toString().startsWith('${groupId}_')) {
          keysToDelete.add(key.toString());
        }
      }

      // 删除所有相关消息
      for (final key in keysToDelete) {
        await _messageBox.delete(key);
      }

      DebugLogger().info(
        '[Hive] 群组消息删除成功: $groupId (删除了 ${keysToDelete.length} 条消息)',
        tag: 'HIVE',
      );
      return true;
    } catch (e) {
      DebugLogger().error('[Hive] 删除群组消息失败: $e', tag: 'HIVE');
      return false;
    }
  }

  // 消息
  static Future<bool> saveMessage(String groupId, Message message) async {
    await initialize();
    final key = '${groupId}_${message.id}';
    await _messageBox.put(key, jsonEncode(message.toJson()));
    return true;
  }

  static Future<List<Message>> loadMessages(
    String groupId, {
    int limit = 50,
    int offset = 0,
  }) async {
    await initialize();
    final messages = _messageBox.values
        .map((e) => Message.fromJson(jsonDecode(e)))
        .where((m) => m.groupId == groupId)
        .toList();
    messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return messages.skip(offset).take(limit).toList();
  }

  static Future<bool> deleteMessage(String groupId, String messageId) async {
    await initialize();
    final key = '${groupId}_$messageId';
    await _messageBox.delete(key);
    return true;
  }

  /// 搜索消息
  static Future<List<Message>> searchMessages(
    String groupId,
    String query,
  ) async {
    try {
      final messages = await loadMessages(groupId);
      return messages
          .where(
            (message) => message.content.text.toLowerCase().contains(
              query.toLowerCase(),
            ),
          )
          .toList();
    } catch (e) {
      DebugLogger().error('搜索消息失败: $e', tag: 'HIVE');
      return [];
    }
  }

  /// 删除所有数据（注销时使用）
  static Future<bool> clearAllData() async {
    try {
      await _userBox.clear();
      await _groupBox.clear();
      await _messageBox.clear();
      DebugLogger().info('已清空所有Hive数据', tag: 'HIVE');
      return true;
    } catch (e) {
      DebugLogger().error('清空Hive数据失败: $e', tag: 'HIVE');
      return false;
    }
  }

  /// 只删除群组和消息数据，保留用户数据
  static Future<bool> clearGroupsAndMessages() async {
    try {
      await _groupBox.clear();
      await _messageBox.clear();
      DebugLogger().info('已清空群组和消息数据，保留用户数据', tag: 'HIVE');
      return true;
    } catch (e) {
      DebugLogger().error('清空群组和消息数据失败: $e', tag: 'HIVE');
      return false;
    }
  }
}
