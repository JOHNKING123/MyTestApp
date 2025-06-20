import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import 'user_setup_screen.dart';
import 'group_list_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // 初始化应用
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppProvider>().initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, appProvider, child) {
        if (appProvider.isLoading) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在初始化...'),
                ],
              ),
            ),
          );
        }

        // 显示错误信息
        if (appProvider.error != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(appProvider.error!),
                backgroundColor: Colors.red,
                action: SnackBarAction(
                  label: '清除',
                  textColor: Colors.white,
                  onPressed: () => appProvider.clearError(),
                ),
              ),
            );
          });
        }

        // 如果用户未创建，显示用户设置界面
        if (appProvider.currentUser == null) {
          return const UserSetupScreen();
        }

        // 显示群组列表
        return const GroupListScreen();
      },
    );
  }
}
