import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

class KeyService {
  static const int _keyLength = 32; // 256 bits

  /// 生成群组会话密钥
  static Future<String> generateGroupKey() async {
    final random = Random.secure();
    final bytes = Uint8List.fromList(
      List<int>.generate(_keyLength, (_) => random.nextInt(256)),
    );
    return base64Encode(bytes);
  }

  /// 生成群组会话密钥
  static Future<String> generateGroupSessionKey() async {
    final random = Random.secure();
    final bytes = Uint8List.fromList(
      List<int>.generate(_keyLength, (_) => random.nextInt(256)),
    );
    return base64Encode(bytes);
  }

  /// 生成用户密钥对
  /// 已废弃：请勿使用！用户密钥对请统一用Ed25519Helper.generateKeyPair并持久化到KeyManager。
  @deprecated
  static Future<Map<String, String>> generateUserKeyPair() async {
    throw UnimplementedError(
      'generateUserKeyPair已废弃，请用Ed25519Helper.generateKeyPair并持久化到KeyManager',
    );
  }

  /// 生成密钥哈希
  static String generateKeyHash(String key) {
    final hash = sha256.convert(utf8.encode(key));
    return hash.toString();
  }

  /// 验证密钥格式
  static bool isValidKey(String key) {
    try {
      final decoded = base64Decode(key);
      return decoded.length == _keyLength;
    } catch (e) {
      return false;
    }
  }
}
