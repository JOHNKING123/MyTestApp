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

  /// 生成用户密钥对
  static Future<Map<String, String>> generateUserKeyPair() async {
    // 简化的密钥对生成（实际应用中应使用椭圆曲线加密）
    final random = Random.secure();

    // 生成私钥
    final privateKeyBytes = Uint8List.fromList(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );
    final privateKey = base64Encode(privateKeyBytes);

    // 生成公钥（这里简化处理，实际应基于私钥计算）
    final publicKeyBytes = Uint8List.fromList(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );
    final publicKey = base64Encode(publicKeyBytes);

    return {'privateKey': privateKey, 'publicKey': publicKey};
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
