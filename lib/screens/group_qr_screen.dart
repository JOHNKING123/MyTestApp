import 'package:flutter/material.dart';
import '../models/group.dart';
import '../services/group_service.dart';
import 'package:qr_flutter/qr_flutter.dart';

class GroupQRScreen extends StatelessWidget {
  final Group group;

  const GroupQRScreen({super.key, required this.group});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: GroupService().generateGroupQRData(group),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.hasError) {
          return const Center(child: Text('二维码生成失败'));
        }
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '群组二维码',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            QrImageView(
              data: snapshot.data!,
              version: QrVersions.auto,
              size: 200.0,
            ),
            const SizedBox(height: 16),
            const Text('扫描二维码加入群组', style: TextStyle(fontSize: 14)),
          ],
        );
      },
    );
  }
}
