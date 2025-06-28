import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'dart:convert';
import '../utils/debug_logger.dart';

class QRScanScreen extends StatefulWidget {
  const QRScanScreen({super.key});

  @override
  State<QRScanScreen> createState() => _QRScanScreenState();
}

class _QRScanScreenState extends State<QRScanScreen> {
  bool _scanned = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('扫码二维码')),
      body: MobileScanner(
        onDetect: (capture) {
          if (_scanned) return;
          final List<Barcode> barcodes = capture.barcodes;
          for (final barcode in barcodes) {
            final String? code = barcode.rawValue;
            if (code != null && code.isNotEmpty) {
              _scanned = true;
              DebugLogger().info('扫描到二维码内容: $code', tag: 'QR_SCAN');

              // 尝试解析二维码内容
              try {
                final data = jsonDecode(code);
                DebugLogger().info('二维码解析成功: $data', tag: 'QR_SCAN');
                if (data['serverPort'] != null) {
                  DebugLogger().info(
                    '端口号: ${data['serverPort']} (类型: ${data['serverPort'].runtimeType})',
                    tag: 'QR_SCAN',
                  );
                }
              } catch (e) {
                DebugLogger().error('二维码解析失败: $e', tag: 'QR_SCAN');
              }

              Navigator.of(context).pop(code);
              break;
            }
          }
        },
      ),
    );
  }
}
