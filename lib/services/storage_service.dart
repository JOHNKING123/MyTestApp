import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/group.dart';
import '../models/user.dart';
import '../models/message.dart';
import '../models/member.dart';
import 'storage_service_hive.dart';
import 'dart:io' show Platform;

class StorageService {
  // --- 统一接口 ---
  static Future<bool> saveUser(User user) async {
    if (kIsWeb) {
      return StorageServiceHive.saveUser(user);
    } else {
      return _saveUserNative(user);
    }
  }

  static Future<User?> loadUser(String userId) async {
    if (kIsWeb) {
      return StorageServiceHive.loadUser(userId);
    } else {
      return _loadUserNative(userId);
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
        deviceId TEXT NOT NULL
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

  /// 保存用户
  static Future<bool> _saveUserNative(User user) async {
    try {
      final db = await database;
      await db.insert('users', {
        'id': user.id,
        'name': user.name,
        'profile': jsonEncode(user.profile.toJson()),
        'createdAt': user.createdAt.toIso8601String(),
        'status': user.status.toString().split('.').last,
        'lastActiveAt': user.lastActiveAt.toIso8601String(),
        'deviceId': user.deviceId,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return true;
    } catch (e) {
      print('Failed to save user: $e');
      return false;
    }
  }

  /// 加载用户
  static Future<User?> _loadUserNative(String userId) async {
    try {
      final db = await database;
      final maps = await db.query(
        'users',
        where: 'id = ?',
        whereArgs: [userId],
      );

      if (maps.isEmpty) return null;

      final map = maps.first;
      final profileJson = jsonDecode(map['profile'] as String);

      return User(
        id: map['id'] as String,
        name: map['name'] as String,
        profile: UserProfile.fromJson(profileJson),
        createdAt: DateTime.parse(map['createdAt'] as String),
        status: UserStatus.values.firstWhere(
          (e) => e.toString() == 'UserStatus.${map['status']}',
          orElse: () => UserStatus.active,
        ),
        lastActiveAt: DateTime.parse(map['lastActiveAt'] as String),
        deviceId: map['deviceId'] as String,
      );
    } catch (e) {
      print('Failed to load user: $e');
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
      print('Failed to save group: $e');
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
      print('Failed to load group: $e');
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
      print('Failed to load all groups: $e');
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
      print('Failed to save message: $e');
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
        orderBy: 'timestamp DESC',
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
      print('Failed to load messages: $e');
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
      print('Failed to delete message: $e');
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
      print('Failed to search messages: $e');
      return [];
    }
  }
}
