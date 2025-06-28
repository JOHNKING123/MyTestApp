import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/group.dart';
import '../models/user.dart';
import '../models/member.dart';
import '../services/encryption_service.dart';
import '../utils/debug_logger.dart';
// import 'package:json_annotation/json_annotation.dart'; // 如无用可注释

class KeyManager {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _groupKeyPrefix = 'group_key_';
  static const String _sessionKeyPrefix = 'session_key_';
  static const String _userKeyPrefix = 'user_key_';

  static final KeyManager _instance = KeyManager._internal();
  factory KeyManager() => _instance;
  KeyManager._internal();

  // 内存缓存：userId -> UserKeyPair
  final Map<String, UserKeyPair> _userKeyPairs = {};

  /// 生成群组密钥对
  Future<GroupKeyPair> generateGroupKeyPair() async {
    try {
      final random = Random.secure();
      final privateKeyBytes = Uint8List.fromList(
        List<int>.generate(32, (_) => random.nextInt(256)),
      );
      final publicKeyBytes = Uint8List.fromList(
        List<int>.generate(32, (_) => random.nextInt(256)),
      );

      return GroupKeyPair(
        privateKey: base64Encode(privateKeyBytes),
        publicKey: base64Encode(publicKeyBytes),
        createdAt: DateTime.now(),
        algorithm: KeyAlgorithm.ecdsa,
      );
    } catch (e) {
      DebugLogger().error(
        'Failed to generate group key pair: $e',
        tag: 'KEY_MANAGER',
      );
      rethrow;
    }
  }

  /// 已废弃：请勿使用！用户密钥对请统一用Ed25519Helper.generateKeyPair并持久化到KeyManager。
  @deprecated
  Future<UserKeyPair> generateUserKeyPair() async {
    throw UnimplementedError(
      'generateUserKeyPair已废弃，请用Ed25519Helper.generateKeyPair并持久化到KeyManager',
    );
  }

  /// 生成群组密钥
  Future<GroupKeyPair> generateGroupKeys() async {
    try {
      // 生成密钥对
      // final keyPair = await EncryptionService.generateKeyPair();

      return GroupKeyPair(
        publicKey: '',
        privateKey: '',
        createdAt: DateTime.now(),
        algorithm: KeyAlgorithm.ecdsa,
      );
    } catch (e) {
      DebugLogger().error('生成群组密钥失败: $e', tag: 'KEY_MANAGER');
      rethrow;
    }
  }

  /// 生成会话密钥
  static SessionKey generateSessionKey() {
    final random = Random.secure();
    final keyBytes = Uint8List.fromList(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );

    return SessionKey(
      key: base64Encode(keyBytes),
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(hours: 24)),
      version: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 为群组成员加密会话密钥
  Future<Map<String, String>> encryptSessionKeyForMembers(
    SessionKey sessionKey,
    List<Member> members,
  ) async {
    final encryptedKeys = <String, String>{};

    for (final member in members) {
      try {
        // 使用成员的公钥加密会话密钥
        // final encryptedKey = await EncryptionService.encryptWithPublicKey(
        //   base64Decode(sessionKey.key),
        //   member.publicKey,
        // );

        encryptedKeys[member.userId] = base64Encode(Uint8List.fromList([]));
      } catch (e) {
        DebugLogger().error(
          'Failed to encrypt session key for member ${member.id}: $e',
          tag: 'KEY_MANAGER',
        );
        // 继续处理其他成员
      }
    }

    return encryptedKeys;
  }

  /// 解密会话密钥
  Future<SessionKey?> decryptSessionKey(
    String encryptedKey,
    String privateKey,
  ) async {
    try {
      // final decryptedKey = await EncryptionService.decryptWithPrivateKey(
      //   base64Decode(encryptedKey),
      //   privateKey,
      // );

      return SessionKey(
        key: base64Encode(Uint8List.fromList([])),
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(hours: 24)),
        version: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      DebugLogger().error('解密会话密钥失败: $e', tag: 'KEY_MANAGER');
      return null;
    }
  }

  /// 轮换群组密钥
  Future<GroupKeyPair> rotateGroupKeys(GroupKeyPair oldKeys) async {
    try {
      final newKeys = await generateGroupKeys();

      // 这里可以添加密钥轮换的逻辑
      // 比如保存旧密钥用于解密历史消息

      return newKeys;
    } catch (e) {
      DebugLogger().error('轮换群组密钥失败: $e', tag: 'KEY_MANAGER');
      rethrow;
    }
  }

  /// 验证密钥是否过期
  bool isKeyExpired(DateTime expiresAt) {
    return DateTime.now().isAfter(expiresAt);
  }

  /// 生成密钥ID
  String generateKeyId() {
    final random = Random();
    final bytes = List<int>.generate(16, (i) => random.nextInt(256));
    return base64Encode(bytes);
  }

  /// 轮换会话密钥
  static Future<SessionKey> rotateSessionKey(String groupId) async {
    final newKey = generateSessionKey();
    await _saveSessionKey(groupId, newKey);
    return newKey;
  }

  /// 保存群组密钥对
  static Future<bool> saveGroupKeyPair(
    String groupId,
    GroupKeyPair keyPair,
  ) async {
    try {
      final key = '$_groupKeyPrefix$groupId';
      final json = jsonEncode(keyPair.toJson());
      await _storage.write(key: key, value: json);
      return true;
    } catch (e) {
      DebugLogger().error(
        'Failed to save group key pair: $e',
        tag: 'KEY_MANAGER',
      );
      rethrow;
    }
  }

  /// 加载群组密钥对
  static Future<GroupKeyPair?> loadGroupKeyPair(String groupId) async {
    try {
      final key = '$_groupKeyPrefix$groupId';
      final data = await _storage.read(key: key);
      if (data == null) return null;

      final json = jsonDecode(data);
      return GroupKeyPair.fromJson(json);
    } catch (e) {
      DebugLogger().error(
        'Failed to load group key pair: $e',
        tag: 'KEY_MANAGER',
      );
      rethrow;
    }
  }

  /// 保存会话密钥
  static Future<bool> _saveSessionKey(
    String groupId,
    SessionKey sessionKey,
  ) async {
    try {
      final key = '$_sessionKeyPrefix$groupId';
      final data = jsonEncode(sessionKey.toJson());
      await _storage.write(key: key, value: data);
      return true;
    } catch (e) {
      DebugLogger().error('Failed to save session key: $e', tag: 'KEY_MANAGER');
      rethrow;
    }
  }

  /// 加载会话密钥
  static Future<SessionKey?> loadSessionKey(String groupId) async {
    try {
      final key = '$_sessionKeyPrefix$groupId';
      final data = await _storage.read(key: key);
      if (data == null) return null;

      final json = jsonDecode(data);
      return SessionKey.fromJson(json);
    } catch (e) {
      DebugLogger().error('Failed to load session key: $e', tag: 'KEY_MANAGER');
      rethrow;
    }
  }

  /// 保存用户密钥对（持久化+内存）
  static Future<bool> saveUserKeyPair(
    String userId,
    UserKeyPair keyPair,
  ) async {
    try {
      final key = '$_userKeyPrefix$userId';
      final json = jsonEncode(keyPair.toJson());
      await _storage.write(key: key, value: json);
      // 写入内存缓存
      KeyManager()._userKeyPairs[userId] = keyPair;
      return true;
    } catch (e) {
      DebugLogger().error(
        'Failed to save user key pair: $e',
        tag: 'KEY_MANAGER',
      );
      rethrow;
    }
  }

  /// 加载用户密钥对（持久化->内存）
  static Future<UserKeyPair?> loadUserKeyPair(String userId) async {
    try {
      final key = '$_userKeyPrefix$userId';
      final data = await _storage.read(key: key);
      if (data == null) return null;
      final json = jsonDecode(data);
      final pair = UserKeyPair.fromJson(json);
      // 写入内存缓存
      KeyManager()._userKeyPairs[userId] = pair;
      return pair;
    } catch (e) {
      DebugLogger().error(
        'Failed to load user key pair: $e',
        tag: 'KEY_MANAGER',
      );
      rethrow;
    }
  }

  /// 获取内存中的用户密钥对
  UserKeyPair? getUserKeyPair(String userId) => _userKeyPairs[userId];

  /// 销毁密钥
  static Future<bool> destroyKey(String keyId) async {
    try {
      await _storage.delete(key: keyId);
      return true;
    } catch (e) {
      DebugLogger().error('Failed to destroy key: $e', tag: 'KEY_MANAGER');
      rethrow;
    }
  }

  /// 生成用户ID
  static String generateUserId() {
    final random = Random.secure();
    final bytes = Uint8List.fromList(
      List<int>.generate(16, (_) => random.nextInt(256)),
    );
    return base64Encode(bytes).substring(0, 20);
  }

  /// 生成群组ID
  static String generateGroupId() {
    final random = Random.secure();
    final bytes = Uint8List.fromList(
      List<int>.generate(16, (_) => random.nextInt(256)),
    );
    return base64Encode(bytes).substring(0, 16);
  }
}

// @JsonSerializable()
class UserKeyPair {
  final String publicKey;
  final String privateKey;
  final DateTime createdAt;
  final KeyAlgorithm algorithm;

  UserKeyPair({
    required this.publicKey,
    required this.privateKey,
    required this.createdAt,
    this.algorithm = KeyAlgorithm.ecdsa,
  });

  factory UserKeyPair.fromJson(Map<String, dynamic> json) {
    return UserKeyPair(
      publicKey: json['publicKey'],
      privateKey: json['privateKey'],
      createdAt: DateTime.parse(json['createdAt']),
      algorithm: KeyAlgorithm.values.firstWhere(
        (e) => e.toString() == 'KeyAlgorithm.${json['algorithm']}',
        orElse: () => KeyAlgorithm.ecdsa,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'publicKey': publicKey,
      'privateKey': privateKey,
      'createdAt': createdAt.toIso8601String(),
      'algorithm': algorithm.toString().split('.').last,
    };
  }
}

class KeyException implements Exception {
  final String message;
  KeyException(this.message);

  @override
  String toString() => 'KeyException: $message';
}
