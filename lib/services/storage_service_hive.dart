import 'dart:convert';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/group.dart';
import '../models/user.dart';
import '../models/message.dart';
import '../models/member.dart';

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

  // 用户
  static Future<bool> saveUser(User user) async {
    await initialize();
    await _userBox.put(user.id, jsonEncode(user.toJson()));
    return true;
  }

  static Future<User?> loadUser(String userId) async {
    await initialize();
    final data = _userBox.get(userId);
    if (data == null) return null;
    return User.fromJson(jsonDecode(data));
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

  static Future<List<Message>> searchMessages(
    String groupId,
    String query,
  ) async {
    await initialize();
    final messages = _messageBox.values
        .map((e) => Message.fromJson(jsonDecode(e)))
        .where((m) => m.groupId == groupId && m.content.text.contains(query))
        .toList();
    messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return messages;
  }
}
