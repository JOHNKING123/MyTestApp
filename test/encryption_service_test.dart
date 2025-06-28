import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';
import 'package:group_chat/services/encryption_service.dart';

void main() {
  group('Ed25519 签名与验签', () {
    test('签名-验签流程', () async {
      final keyPair = await Ed25519Helper.generateKeyPair();
      final privateKey = keyPair['privateKey']!;
      final publicKey = keyPair['publicKey']!;
      final message = 'Hello, Secure World!';

      final signature = await Ed25519Helper.sign(
        message,
        privateKey,
        publicKey,
      );
      final isValid = await Ed25519Helper.verify(message, signature, publicKey);
      expect(isValid, isTrue);
    });

    test('验签失败场景', () async {
      final keyPair1 = await Ed25519Helper.generateKeyPair();
      final keyPair2 = await Ed25519Helper.generateKeyPair();
      final privateKey1 = keyPair1['privateKey']!;
      final publicKey2 = keyPair2['publicKey']!;
      final message = 'Hello, Secure World!';
      final signature = await Ed25519Helper.sign(
        message,
        privateKey1,
        publicKey2,
      );
      final isValid = await Ed25519Helper.verify(
        message,
        signature,
        publicKey2,
      );
      expect(isValid, isFalse);
    });

    test('消息内容被篡改验签失败', () async {
      final keyPair = await Ed25519Helper.generateKeyPair();
      final privateKey = keyPair['privateKey']!;
      final publicKey = keyPair['publicKey']!;
      final message = 'Hello, Secure World!';
      final signature = await Ed25519Helper.sign(
        message,
        privateKey,
        publicKey,
      );
      final isValid = await Ed25519Helper.verify(
        'Hacked!',
        signature,
        publicKey,
      );
      expect(isValid, isFalse);
    });
  });
}
