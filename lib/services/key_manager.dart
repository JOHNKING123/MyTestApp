import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/group.dart';
import '../models/user.dart';
import '../models/member.dart';

class KeyManager {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _groupKeyPrefix = 'group_key_';
  static const String _sessionKeyPrefix = 'session_key_';
  static const String _userKeyPrefix = 'user_key_';

  /// 生成群组密钥对
  static Future<GroupKeyPair> generateGroupKeyPair() async {
    try {
      final random = Random.secure();

      // 生成私钥（32字节）
      final privateKeyBytes = Uint8List.fromList(
        List<int>.generate(32, (_) => random.nextInt(256)),
      );

      // 生成公钥（模拟，实际应该从私钥派生）
      final publicKeyBytes = Uint8List.fromList(
        List<int>.generate(64, (_) => random.nextInt(256)),
      );

      return GroupKeyPair(
        publicKey: base64Encode(publicKeyBytes),
        privateKey: base64Encode(privateKeyBytes),
        createdAt: DateTime.now(),
        algorithm: KeyAlgorithm.ecdsa,
      );
    } catch (e) {
      throw KeyException('Failed to generate group key pair: $e');
    }
  }

  /// 生成用户密钥对
  static Future<UserKeyPair> generateUserKeyPair() async {
    try {
      final random = Random.secure();

      // 生成私钥（32字节）
      final privateKeyBytes = Uint8List.fromList(
        List<int>.generate(32, (_) => random.nextInt(256)),
      );

      // 生成公钥（模拟，实际应该从私钥派生）
      final publicKeyBytes = Uint8List.fromList(
        List<int>.generate(64, (_) => random.nextInt(256)),
      );

      return UserKeyPair(
        publicKey: base64Encode(publicKeyBytes),
        privateKey: base64Encode(privateKeyBytes),
        createdAt: DateTime.now(),
        algorithm: KeyAlgorithm.ecdsa,
      );
    } catch (e) {
      throw KeyException('Failed to generate user key pair: $e');
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

  /// 分发会话密钥
  static Map<String, String> distributeSessionKey(
    SessionKey sessionKey,
    List<Member> members,
  ) {
    final encryptedKeys = <String, String>{};

    for (final member in members) {
      try {
        // 简单的XOR加密（实际应该使用RSA）
        final encrypted = _simpleEncrypt(sessionKey.key, member.publicKey);
        encryptedKeys[member.id] = encrypted;
      } catch (e) {
        print('Failed to encrypt session key for member ${member.id}: $e');
      }
    }

    return encryptedKeys;
  }

  /// 简单加密（仅用于演示）
  static String _simpleEncrypt(String data, String key) {
    final dataBytes = utf8.encode(data);
    final keyBytes = utf8.encode(key);
    final encryptedBytes = Uint8List(dataBytes.length);

    for (int i = 0; i < dataBytes.length; i++) {
      encryptedBytes[i] = dataBytes[i] ^ keyBytes[i % keyBytes.length];
    }

    return base64Encode(encryptedBytes);
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
      final data = jsonEncode(keyPair.toJson());
      await _storage.write(key: key, value: data);
      return true;
    } catch (e) {
      throw KeyException('Failed to save group key pair: $e');
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
      throw KeyException('Failed to load group key pair: $e');
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
      throw KeyException('Failed to save session key: $e');
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
      throw KeyException('Failed to load session key: $e');
    }
  }

  /// 保存用户密钥对
  static Future<bool> saveUserKeyPair(
    String userId,
    UserKeyPair keyPair,
  ) async {
    try {
      final key = '$_userKeyPrefix$userId';
      final data = jsonEncode(keyPair.toJson());
      await _storage.write(key: key, value: data);
      return true;
    } catch (e) {
      throw KeyException('Failed to save user key pair: $e');
    }
  }

  /// 加载用户密钥对
  static Future<UserKeyPair?> loadUserKeyPair(String userId) async {
    try {
      final key = '$_userKeyPrefix$userId';
      final data = await _storage.read(key: key);
      if (data == null) return null;

      final json = jsonDecode(data);
      return UserKeyPair.fromJson(json);
    } catch (e) {
      throw KeyException('Failed to load user key pair: $e');
    }
  }

  /// 销毁密钥
  static Future<bool> destroyKey(String keyId) async {
    try {
      await _storage.delete(key: keyId);
      return true;
    } catch (e) {
      throw KeyException('Failed to destroy key: $e');
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
