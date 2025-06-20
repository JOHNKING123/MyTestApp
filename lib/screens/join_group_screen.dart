import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../providers/app_provider.dart';
import 'qr_scan_screen.dart';

class JoinGroupScreen extends StatefulWidget {
  const JoinGroupScreen({super.key});

  @override
  State<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends State<JoinGroupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _qrCodeController = TextEditingController();

  @override
  void dispose() {
    _qrCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('加入群组')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.qr_code_scanner, size: 80, color: Colors.blue),
              const SizedBox(height: 24),
              const Text(
                '扫描二维码加入群组',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              TextFormField(
                controller: _qrCodeController,
                decoration: const InputDecoration(
                  labelText: '二维码内容',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.qr_code),
                  hintText: '粘贴二维码内容或手动输入',
                ),
                maxLines: 3,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '请输入二维码内容';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              if (!kIsWeb)
                OutlinedButton.icon(
                  onPressed: _scanQRCode,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('扫描二维码'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              if (kIsWeb)
                const Text(
                  'Web端暂不支持扫码，请粘贴二维码内容',
                  style: TextStyle(fontSize: 14, color: Colors.orange),
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 32),
              Consumer<AppProvider>(
                builder: (context, appProvider, child) {
                  return ElevatedButton(
                    onPressed: appProvider.isLoading ? null : _joinGroup,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: appProvider.isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('加入群组', style: TextStyle(fontSize: 16)),
                  );
                },
              ),
              const SizedBox(height: 16),
              const Text(
                '请确保二维码来自可信的群组创建者',
                style: TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _scanQRCode() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Web端暂不支持扫码功能'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // 跳转到扫码页面
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QRScanScreen()),
    );
    if (result != null && result is String) {
      setState(() {
        _qrCodeController.text = result;
      });
    }
  }

  void _joinGroup() async {
    if (_formKey.currentState!.validate()) {
      final appProvider = context.read<AppProvider>();
      final success = await appProvider.joinGroup(
        _qrCodeController.text.trim(),
      );

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('成功加入群组！'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    }
  }
}
