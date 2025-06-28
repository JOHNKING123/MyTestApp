import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/group.dart';
import '../models/user.dart';
import '../models/message.dart';
import '../models/member.dart';
import 'storage_service_hive.dart';
import 'dart:io' show Platform;
import '../utils/debug_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  // --- 统一接口 ---
  static Future<bool> saveUser(User user) async {
    try {
      if (kIsWeb) {
        // Web端使用SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        final userData = jsonEncode(user.toJson());
        final result = await prefs.setString('user_${user.deviceId}', userData);
        DebugLogger().info('[存储] Web端保存用户结果: $result', tag: 'STORAGE');
        return result;
      } else {
        // Native端使用SQLite
        final result = await _saveUserToSQLite(user);
        DebugLogger().info('[存储] Native端保存用户结果: $result', tag: 'STORAGE');
        return result;
      }
    } catch (e) {
      DebugLogger().error('[存储] 保存用户失败: $e', tag: 'STORAGE');
      return false;
    }
  }

  static Future<User?> loadUser(String userId) async {
    if (kIsWeb) {
      return StorageServiceHive.loadUser(userId);
    } else {
      return _loadUserFromSQLite(userId);
    }
  }

  /// 根据设备ID查找用户
  static Future<User?> loadUserByDeviceId(String deviceId) async {
    try {
      DebugLogger().info(
        '[存储] 开始根据设备ID查找用户: deviceId=$deviceId',
        tag: 'STORAGE',
      );

      if (kIsWeb) {
        // Web端使用SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        final userData = prefs.getString('user_$deviceId');
        final user = userData != null
            ? User.fromJson(jsonDecode(userData))
            : null;
        DebugLogger().info(
          '[存储] Web端查找用户结果: ${user != null ? "找到" : "未找到"}',
          tag: 'STORAGE',
        );
        return user;
      } else {
        // Native端使用SQLite
        final user = await _loadUserFromSQLite(deviceId);
        DebugLogger().info(
          '[存储] Native端查找用户结果: ${user != null ? "找到" : "未找到"}',
          tag: 'STORAGE',
        );
        return user;
      }
    } catch (e) {
      DebugLogger().error('[存储] 加载用户失败: $e', tag: 'STORAGE');
      return null;
    }
  }

  static Future<bool> saveGroup(Group group) async {
    if (kIsWeb) {
      return StorageServiceHive.saveGroup(group);
    } else {
      return _saveGroupNative(group);
    }
  }

  static Future<Group?> loadGroup(String groupId) async {
    if (kIsWeb) {
      return StorageServiceHive.loadGroup(groupId);
    } else {
      return _loadGroupNative(groupId);
    }
  }

  static Future<List<Group>> loadAllGroups() async {
    if (kIsWeb) {
      return StorageServiceHive.loadAllGroups();
    } else {
      return _loadAllGroupsNative();
    }
  }

  static Future<bool> saveMessage(String groupId, Message message) async {
    DebugLogger().debug('kIsWeb: $kIsWeb', tag: 'STORAGE');
    if (kIsWeb) {
      return StorageServiceHive.saveMessage(groupId, message);
    } else {
      return _saveMessageNative(groupId, message);
    }
  }

  static Future<List<Message>> loadMessages(
    String groupId, {
    int limit = 50,
    int offset = 0,
  }) async {
    if (kIsWeb) {
      return StorageServiceHive.loadMessages(
        groupId,
        limit: limit,
        offset: offset,
      );
    } else {
      return _loadMessagesNative(groupId, limit: limit, offset: offset);
    }
  }

  static Future<bool> deleteMessage(String groupId, String messageId) async {
    if (kIsWeb) {
      return StorageServiceHive.deleteMessage(groupId, messageId);
    } else {
      return _deleteMessageNative(groupId, messageId);
    }
  }

  /// 删除指定群组
  static Future<bool> deleteGroup(String groupId) async {
    if (kIsWeb) {
      return StorageServiceHive.deleteGroup(groupId);
    } else {
      return _deleteGroupNative(groupId);
    }
  }

  /// 删除指定群组的所有消息
  static Future<bool> deleteGroupMessages(String groupId) async {
    if (kIsWeb) {
      return StorageServiceHive.deleteGroupMessages(groupId);
    } else {
      return _deleteGroupMessagesNative(groupId);
    }
  }

  static Future<List<Message>> searchMessages(
    String groupId,
    String query,
  ) async {
    if (kIsWeb) {
      return StorageServiceHive.searchMessages(groupId, query);
    } else {
      return _searchMessagesNative(groupId, query);
    }
  }

  /// 删除所有数据（注销时使用）
  static Future<bool> clearAllData() async {
    if (kIsWeb) {
      return StorageServiceHive.clearAllData();
    } else {
      return _clearAllDataNative();
    }
  }

  /// 重置数据库（删除数据库文件重新创建）
  static Future<bool> resetDatabase() async {
    try {
      DebugLogger().info('[存储] 开始重置数据库...', tag: 'STORAGE');

      if (kIsWeb) {
        // Web端清空SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();
        DebugLogger().info('[存储] Web端数据库重置完成', tag: 'STORAGE');
        return true;
      } else {
        // Native端删除SQLite数据库文件
        final path = await getDatabasesPath();
        final dbPath = join(path, 'mytestapp.db');
        final file = File(dbPath);
        if (await file.exists()) {
          DebugLogger().info('[存储] 删除数据库文件: $path', tag: 'STORAGE');
          await file.delete();
        }
        DebugLogger().info('[存储] Native端数据库重置完成', tag: 'STORAGE');
        return true;
      }
    } catch (e) {
      DebugLogger().error('[存储] 重置数据库失败: $e', tag: 'STORAGE');
      return false;
    }
  }

  /// 只删除群组和消息数据，保留用户数据
  static Future<bool> clearGroupsAndMessages() async {
    if (kIsWeb) {
      return StorageServiceHive.clearGroupsAndMessages();
    } else {
      return _clearGroupsAndMessagesNative();
    }
  }

  // --- 原有本地实现（非Web） ---
  static Database? _database;
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  /// 获取数据库实例
  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// 初始化数据库
  static Future<Database> _initDatabase() async {
    // 为Web平台初始化SQLite
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final path = join(await getDatabasesPath(), 'secure_chat.db');

    return await openDatabase(path, version: 1, onCreate: _createTables);
  }

  /// 创建数据表
  static Future<void> _createTables(Database db, int version) async {
    // 用户表
    await db.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        profile TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        status TEXT NOT NULL,
        lastActiveAt TEXT NOT NULL,
        deviceId TEXT NOT NULL,
        sessionTokens TEXT
      )
    ''');

    // 群组表
    await db.execute('''
      CREATE TABLE groups (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        creatorId TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        groupKeys TEXT NOT NULL,
        sessionKey TEXT NOT NULL,
        description TEXT,
        maxMembers INTEGER NOT NULL,
        settings TEXT NOT NULL,
        status TEXT NOT NULL
      )
    ''');

    // 成员表
    await db.execute('''
      CREATE TABLE members (
        id TEXT PRIMARY KEY,
        userId TEXT NOT NULL,
        groupId TEXT NOT NULL,
        name TEXT NOT NULL,
        publicKey TEXT NOT NULL,
        joinedAt TEXT NOT NULL,
        lastSeen TEXT NOT NULL,
        role TEXT NOT NULL,
        status TEXT NOT NULL,
        permissions TEXT NOT NULL,
        groupNickname TEXT,
        isMuted INTEGER NOT NULL,
        mutedUntil TEXT
      )
    ''');

    // 消息表
    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        groupId TEXT NOT NULL,
        senderId TEXT NOT NULL,
        content TEXT NOT NULL,
        type TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        status TEXT NOT NULL,
        signature TEXT NOT NULL,
        metadata TEXT NOT NULL,
        sequenceNumber INTEGER NOT NULL,
        replyToMessageId TEXT,
        editHistory TEXT NOT NULL
      )
    ''');
  }

  /// 保存用户（Native实现）
  static Future<bool> _saveUserToSQLite(User user) async {
    try {
      final db = await database;
      DebugLogger().info(
        '[Native] 开始保存用户到SQLite: id=${user.id}, deviceId=${user.deviceId}',
        tag: 'STORAGE',
      );

      final result = await db.insert(
        'users',
        user.toJson(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      DebugLogger().info('[Native] 用户保存到SQLite成功', tag: 'STORAGE');
      return result > 0;
    } catch (e) {
      DebugLogger().error('[Native] 保存用户到SQLite失败: $e', tag: 'STORAGE');
      return false;
    }
  }

  /// 加载用户
  static Future<User?> _loadUserFromSQLite(String deviceId) async {
    try {
      final db = await database;
      DebugLogger().info(
        '[Native] 开始从SQLite查找用户: deviceId=$deviceId',
        tag: 'STORAGE',
      );

      final List<Map<String, dynamic>> maps = await db.query(
        'users',
        where: 'deviceId = ?',
        whereArgs: [deviceId],
      );

      DebugLogger().info(
        '[Native] SQLite查询结果: ${maps.length} 条记录',
        tag: 'STORAGE',
      );

      if (maps.isNotEmpty) {
        final userMap = maps.first;

        // 处理需要JSON解析的字段
        final processedMap = <String, dynamic>{
          'id': userMap['id'],
          'name': userMap['name'],
          'createdAt': userMap['createdAt'],
          'status': userMap['status'],
          'lastActiveAt': userMap['lastActiveAt'],
          'deviceId': userMap['deviceId'],
          'sessionTokens': userMap['sessionTokens'] != null
              ? List<String>.from(jsonDecode(userMap['sessionTokens']))
              : [],
        };

        // 解析profile字段
        if (userMap['profile'] is String) {
          try {
            final profileJson = jsonDecode(userMap['profile'] as String);
            processedMap['profile'] = profileJson;
          } catch (e) {
            DebugLogger().error('[Native] 解析profile字段失败: $e', tag: 'STORAGE');
            // 使用默认profile
            processedMap['profile'] = {'publicKey': '', 'customFields': {}};
          }
        } else {
          processedMap['profile'] = userMap['profile'];
        }

        final user = User.fromJson(processedMap);
        DebugLogger().info(
          '[Native] 成功解析用户: id=${user.id}, name=${user.name}',
          tag: 'STORAGE',
        );
        return user;
      } else {
        DebugLogger().info('[Native] 未找到用户记录', tag: 'STORAGE');
        return null;
      }
    } catch (e) {
      DebugLogger().error('[Native] 从SQLite加载用户失败: $e', tag: 'STORAGE');
      return null;
    }
  }

  /// 保存群组
  static Future<bool> _saveGroupNative(Group group) async {
    try {
      final db = await database;

      // 保存群组基本信息
      await db.insert('groups', {
        'id': group.id,
        'name': group.name,
        'creatorId': group.creatorId,
        'createdAt': group.createdAt.toIso8601String(),
        'groupKeys': jsonEncode(group.groupKeys.toJson()),
        'sessionKey': jsonEncode(group.sessionKey.toJson()),
        'description': group.description,
        'maxMembers': group.maxMembers,
        'settings': jsonEncode(group.settings.toJson()),
        'status': group.status.toString().split('.').last,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      // 保存成员信息
      for (final member in group.members) {
        await db.insert('members', {
          'id': member.id,
          'userId': member.userId,
          'groupId': member.groupId,
          'name': member.name,
          'publicKey': member.publicKey,
          'joinedAt': member.joinedAt.toIso8601String(),
          'lastSeen': member.lastSeen.toIso8601String(),
          'role': member.role.toString().split('.').last,
          'status': member.status.toString().split('.').last,
          'permissions': jsonEncode(
            member.permissions
                .map((p) => p.toString().split('.').last)
                .toList(),
          ),
          'groupNickname': member.groupNickname,
          'isMuted': member.isMuted ? 1 : 0,
          'mutedUntil': member.mutedUntil?.toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      return true;
    } catch (e) {
      DebugLogger().error('Failed to save group: $e', tag: 'STORAGE');
      return false;
    }
  }

  /// 加载群组
  static Future<Group?> _loadGroupNative(String groupId) async {
    try {
      final db = await database;

      // 加载群组基本信息
      final groupMaps = await db.query(
        'groups',
        where: 'id = ?',
        whereArgs: [groupId],
      );

      if (groupMaps.isEmpty) return null;

      final groupMap = groupMaps.first;

      // 加载成员信息
      final memberMaps = await db.query(
        'members',
        where: 'groupId = ?',
        whereArgs: [groupId],
      );

      final members = <Member>[];
      for (final memberMap in memberMaps) {
        final permissionsJson = jsonDecode(memberMap['permissions'] as String);
        final permissions = (permissionsJson as List)
            .map(
              (p) => Permission.values.firstWhere(
                (e) => e.toString() == 'Permission.$p',
                orElse: () => Permission.sendMessage,
              ),
            )
            .toList();

        members.add(
          Member(
            id: memberMap['id'] as String,
            userId: memberMap['userId'] as String,
            groupId: memberMap['groupId'] as String,
            name: memberMap['name'] as String,
            publicKey: memberMap['publicKey'] as String,
            joinedAt: DateTime.parse(memberMap['joinedAt'] as String),
            lastSeen: DateTime.parse(memberMap['lastSeen'] as String),
            role: MemberRole.values.firstWhere(
              (e) => e.toString() == 'MemberRole.${memberMap['role']}',
              orElse: () => MemberRole.member,
            ),
            status: MemberStatus.values.firstWhere(
              (e) => e.toString() == 'MemberStatus.${memberMap['status']}',
              orElse: () => MemberStatus.active,
            ),
            permissions: permissions,
            groupNickname: memberMap['groupNickname'] as String?,
            isMuted: (memberMap['isMuted'] as int) == 1,
            mutedUntil: memberMap['mutedUntil'] != null
                ? DateTime.parse(memberMap['mutedUntil'] as String)
                : null,
          ),
        );
      }

      final groupKeysJson = jsonDecode(groupMap['groupKeys'] as String);
      final sessionKeyJson = jsonDecode(groupMap['sessionKey'] as String);
      final settingsJson = jsonDecode(groupMap['settings'] as String);

      return Group(
        id: groupMap['id'] as String,
        name: groupMap['name'] as String,
        creatorId: groupMap['creatorId'] as String,
        createdAt: DateTime.parse(groupMap['createdAt'] as String),
        groupKeys: GroupKeyPair.fromJson(groupKeysJson),
        sessionKey: SessionKey.fromJson(sessionKeyJson),
        members: members,
        description: groupMap['description'] as String? ?? '',
        maxMembers: groupMap['maxMembers'] as int,
        settings: GroupSettings.fromJson(settingsJson),
        status: GroupStatus.values.firstWhere(
          (e) => e.toString() == 'GroupStatus.${groupMap['status']}',
          orElse: () => GroupStatus.active,
        ),
      );
    } catch (e) {
      DebugLogger().error('Failed to load group: $e', tag: 'STORAGE');
      return null;
    }
  }

  /// 加载所有群组
  static Future<List<Group>> _loadAllGroupsNative() async {
    try {
      final db = await database;
      final groupMaps = await db.query('groups');

      final groups = <Group>[];
      for (final groupMap in groupMaps) {
        final group = await loadGroup(groupMap['id'] as String);
        if (group != null) {
          groups.add(group);
        }
      }

      return groups;
    } catch (e) {
      DebugLogger().error('Failed to load all groups: $e', tag: 'STORAGE');
      return [];
    }
  }

  /// 保存消息
  static Future<bool> _saveMessageNative(
    String groupId,
    Message message,
  ) async {
    try {
      final db = await database;
      await db.insert('messages', {
        'id': message.id,
        'groupId': message.groupId,
        'senderId': message.senderId,
        'content': jsonEncode(message.content.toJson()),
        'type': message.type.toString().split('.').last,
        'timestamp': message.timestamp.toIso8601String(),
        'status': message.status.toString().split('.').last,
        'signature': message.signature,
        'metadata': jsonEncode(message.metadata),
        'sequenceNumber': message.sequenceNumber,
        'replyToMessageId': message.replyToMessageId,
        'editHistory': jsonEncode(
          message.editHistory.map((e) => e.toJson()).toList(),
        ),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return true;
    } catch (e) {
      DebugLogger().error('Failed to save message: $e', tag: 'STORAGE');
      return false;
    }
  }

  /// 加载消息
  static Future<List<Message>> _loadMessagesNative(
    String groupId, {
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final db = await database;
      final maps = await db.query(
        'messages',
        where: 'groupId = ?',
        whereArgs: [groupId],
        orderBy: 'timestamp ASC',
        limit: limit,
        offset: offset,
      );

      final messages = <Message>[];
      for (final map in maps) {
        final contentJson = jsonDecode(map['content'] as String);
        final editHistoryJson = jsonDecode(map['editHistory'] as String);
        final metadataJson = jsonDecode(map['metadata'] as String);

        messages.add(
          Message(
            id: map['id'] as String,
            groupId: map['groupId'] as String,
            senderId: map['senderId'] as String,
            content: MessageContent.fromJson(contentJson),
            type: MessageType.values.firstWhere(
              (e) => e.toString() == 'MessageType.${map['type']}',
              orElse: () => MessageType.text,
            ),
            timestamp: DateTime.parse(map['timestamp'] as String),
            status: MessageStatus.values.firstWhere(
              (e) => e.toString() == 'MessageStatus.${map['status']}',
              orElse: () => MessageStatus.sent,
            ),
            signature: map['signature'] as String,
            metadata: Map<String, dynamic>.from(metadataJson),
            sequenceNumber: map['sequenceNumber'] as int,
            replyToMessageId: map['replyToMessageId'] as String?,
            editHistory: (editHistoryJson as List)
                .map((e) => MessageEdit.fromJson(e))
                .toList(),
          ),
        );
      }

      return messages;
    } catch (e) {
      DebugLogger().error('Failed to load messages: $e', tag: 'STORAGE');
      return [];
    }
  }

  /// 删除消息
  static Future<bool> _deleteMessageNative(
    String groupId,
    String messageId,
  ) async {
    try {
      final db = await database;
      await db.delete(
        'messages',
        where: 'id = ? AND groupId = ?',
        whereArgs: [messageId, groupId],
      );
      return true;
    } catch (e) {
      DebugLogger().error('Failed to delete message: $e', tag: 'STORAGE');
      return false;
    }
  }

  /// 搜索消息
  static Future<List<Message>> _searchMessagesNative(
    String groupId,
    String query,
  ) async {
    try {
      final db = await database;
      final maps = await db.query(
        'messages',
        where: 'groupId = ? AND content LIKE ?',
        whereArgs: [groupId, '%$query%'],
        orderBy: 'timestamp DESC',
      );

      final messages = <Message>[];
      for (final map in maps) {
        final contentJson = jsonDecode(map['content'] as String);
        final editHistoryJson = jsonDecode(map['editHistory'] as String);
        final metadataJson = jsonDecode(map['metadata'] as String);

        messages.add(
          Message(
            id: map['id'] as String,
            groupId: map['groupId'] as String,
            senderId: map['senderId'] as String,
            content: MessageContent.fromJson(contentJson),
            type: MessageType.values.firstWhere(
              (e) => e.toString() == 'MessageType.${map['type']}',
              orElse: () => MessageType.text,
            ),
            timestamp: DateTime.parse(map['timestamp'] as String),
            status: MessageStatus.values.firstWhere(
              (e) => e.toString() == 'MessageStatus.${map['status']}',
              orElse: () => MessageStatus.sent,
            ),
            signature: map['signature'] as String,
            metadata: Map<String, dynamic>.from(metadataJson),
            sequenceNumber: map['sequenceNumber'] as int,
            replyToMessageId: map['replyToMessageId'] as String?,
            editHistory: (editHistoryJson as List)
                .map((e) => MessageEdit.fromJson(e))
                .toList(),
          ),
        );
      }

      return messages;
    } catch (e) {
      DebugLogger().error('Failed to search messages: $e', tag: 'STORAGE');
      return [];
    }
  }

  /// 删除所有数据（注销时使用）
  static Future<bool> _clearAllDataNative() async {
    try {
      final db = await database;
      await db.delete('users');
      await db.delete('groups');
      await db.delete('members');
      await db.delete('messages');
      return true;
    } catch (e) {
      DebugLogger().error('Failed to clear all data: $e', tag: 'STORAGE');
      return false;
    }
  }

  /// 只删除群组和消息数据，保留用户数据
  static Future<bool> _clearGroupsAndMessagesNative() async {
    try {
      final db = await database;
      await db.delete('groups');
      await db.delete('members');
      await db.delete('messages');
      return true;
    } catch (e) {
      DebugLogger().error(
        'Failed to clear groups and messages: $e',
        tag: 'STORAGE',
      );
      return false;
    }
  }

  /// 删除指定群组（Native实现）
  static Future<bool> _deleteGroupNative(String groupId) async {
    try {
      DebugLogger().info('[Native] 开始删除群组: $groupId', tag: 'STORAGE');
      final db = await database;

      // 删除群组
      await db.delete('groups', where: 'id = ?', whereArgs: [groupId]);

      // 删除群组成员
      await db.delete('members', where: 'groupId = ?', whereArgs: [groupId]);

      DebugLogger().info('[Native] 群组删除成功: $groupId', tag: 'STORAGE');
      return true;
    } catch (e) {
      DebugLogger().error('[Native] 删除群组失败: $e', tag: 'STORAGE');
      return false;
    }
  }

  /// 删除指定群组的所有消息（Native实现）
  static Future<bool> _deleteGroupMessagesNative(String groupId) async {
    try {
      DebugLogger().info('[Native] 开始删除群组消息: $groupId', tag: 'STORAGE');
      final db = await database;

      await db.delete('messages', where: 'groupId = ?', whereArgs: [groupId]);

      DebugLogger().info('[Native] 群组消息删除成功: $groupId', tag: 'STORAGE');
      return true;
    } catch (e) {
      DebugLogger().error('[Native] 删除群组消息失败: $e', tag: 'STORAGE');
      return false;
    }
  }
}
