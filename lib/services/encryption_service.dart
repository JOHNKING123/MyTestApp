import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/cryptography.dart' as crypt;

class EncryptionService {
  static const String _algorithm = 'AES-256-GCM';
  static const int _keyLength = 32; // 256 bits
  static const int _ivLength = 12; // 96 bits for GCM
  static const int _authTagLength = 128; // 128 bits for GCM

  /// 生成随机密钥
  static String generateSessionKey() {
    final random = Random.secure();
    final bytes = Uint8List.fromList(
      List<int>.generate(_keyLength, (_) => random.nextInt(256)),
    );
    return base64Encode(bytes);
  }

  /// 生成随机IV
  static Uint8List _generateRandomIV() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(_ivLength, (_) => random.nextInt(256)),
    );
  }

  /// 加密消息内容
  static String encryptMessage(String plaintext, String sessionKey) {
    try {
      // 1. 解码会话密钥
      final keyBytes = base64Decode(sessionKey);

      // 2. 生成随机IV
      final iv = _generateRandomIV();

      // 3. 创建GCM密码
      final cipher = GCMBlockCipher(AESEngine());
      final params = AEADParameters(
        KeyParameter(keyBytes),
        _authTagLength,
        iv,
        Uint8List(0), // 关联数据为空
      );

      cipher.init(true, params);

      // 4. 加密数据
      final plaintextBytes = utf8.encode(plaintext);
      final encryptedBytes = cipher.process(plaintextBytes);
      final authTag = cipher.mac;

      // 5. 组合结果
      final result = {
        'iv': base64Encode(iv),
        'data': base64Encode(encryptedBytes),
        'tag': base64Encode(authTag),
        'algorithm': _algorithm,
      };

      return jsonEncode(result);
    } catch (e) {
      throw EncryptionException('Failed to encrypt message: $e');
    }
  }

  /// 解密消息内容
  static String decryptMessage(String encryptedData, String sessionKey) {
    try {
      // 1. 解析加密数据
      final data = jsonDecode(encryptedData);
      final iv = base64Decode(data['iv']);
      final encryptedBytes = base64Decode(data['data']);
      final authTag = base64Decode(data['tag']);

      // 2. 解码会话密钥
      final keyBytes = base64Decode(sessionKey);

      // 3. 创建GCM密码
      final cipher = GCMBlockCipher(AESEngine());
      final params = AEADParameters(
        KeyParameter(keyBytes),
        _authTagLength,
        iv,
        Uint8List(0), // 关联数据为空
      );

      cipher.init(false, params);

      // 4. 解密数据
      final decryptedBytes = cipher.process(encryptedBytes);

      // 5. 验证认证标签
      if (!_verifyAuthTag(cipher.mac, authTag)) {
        throw EncryptionException('Authentication tag verification failed');
      }

      // 6. 返回明文
      return utf8.decode(decryptedBytes);
    } catch (e) {
      throw EncryptionException('Failed to decrypt message: $e');
    }
  }

  /// 验证认证标签
  static bool _verifyAuthTag(Uint8List computed, Uint8List expected) {
    if (computed.length != expected.length) return false;
    for (int i = 0; i < computed.length; i++) {
      if (computed[i] != expected[i]) return false;
    }
    return true;
  }

  /// 生成消息哈希
  static String createMessageHash(
    String messageId,
    String groupId,
    String senderId,
    String content,
    int sequenceNumber,
  ) {
    final dataToHash = {
      'id': messageId,
      'groupId': groupId,
      'senderId': senderId,
      'content': content,
      'sequenceNumber': sequenceNumber,
    };

    final jsonString = jsonEncode(dataToHash);
    final hash = sha256.convert(utf8.encode(jsonString));

    return hash.toString();
  }

  /// 生成随机字节
  static Uint8List generateRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }
}

class EncryptionException implements Exception {
  final String message;
  EncryptionException(this.message);

  @override
  String toString() => 'EncryptionException: $message';
}

class Ed25519Helper {
  /// 生成Ed25519密钥对，返回base64字符串（async）
  static Future<Map<String, String>> generateKeyPair() async {
    final algorithm = crypt.Ed25519();
    final keyPair = await algorithm.newKeyPair();
    final privateKey = await keyPair.extractPrivateKeyBytes();
    final publicKey = await keyPair.extractPublicKey();
    return {
      'privateKey': base64Encode(privateKey),
      'publicKey': base64Encode(publicKey.bytes),
    };
  }

  /// 用私钥签名，参数和返回值均为base64字符串（async）
  static Future<String> sign(
    String message,
    String base64PrivateKey,
    String base64PublicKey,
  ) async {
    final algorithm = crypt.Ed25519();
    final privateKey = base64Decode(base64PrivateKey);
    final publicKey = crypt.SimplePublicKey(
      base64Decode(base64PublicKey),
      type: crypt.KeyPairType.ed25519,
    );
    final keyPair = crypt.SimpleKeyPairData(
      privateKey,
      publicKey: publicKey,
      type: crypt.KeyPairType.ed25519,
    );
    final signature = await algorithm.sign(
      utf8.encode(message),
      keyPair: keyPair,
    );
    return base64Encode(signature.bytes);
  }

  /// 用公钥验签，参数和签名均为base64字符串（async）
  static Future<bool> verify(
    String message,
    String base64Signature,
    String base64PublicKey,
  ) async {
    final algorithm = crypt.Ed25519();
    final publicKey = crypt.SimplePublicKey(
      base64Decode(base64PublicKey),
      type: crypt.KeyPairType.ed25519,
    );
    final signature = crypt.Signature(
      base64Decode(base64Signature),
      publicKey: publicKey,
    );
    return await algorithm.verify(utf8.encode(message), signature: signature);
  }
}
