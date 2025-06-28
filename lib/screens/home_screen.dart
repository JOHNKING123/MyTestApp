import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../utils/debug_logger.dart';
import 'user_setup_screen.dart';
import 'group_list_screen.dart';
import 'debug_panel_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    DebugLogger().info('HomeScreen初始化', tag: 'HOME');
    // 移除重复的初始化调用，因为main.dart中已经调用了initialize
    // WidgetsBinding.instance.addPostFrameCallback((_) {
    //   context.read<AppProvider>().initialize();
    // });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, appProvider, child) {
        if (appProvider.isLoading) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('端到端加密群聊'),
              actions: [
                // 调试面板入口
                IconButton(
                  icon: const Icon(Icons.bug_report),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const DebugPanelScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
            body: const Center(
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
          DebugLogger().error('应用错误: ${appProvider.error}', tag: 'HOME');
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
          return Scaffold(
            appBar: AppBar(
              title: const Text('端到端加密群聊'),
              automaticallyImplyLeading: false,
              actions: [
                // 调试面板入口
                IconButton(
                  icon: const Icon(Icons.bug_report),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const DebugPanelScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
            body: const UserSetupScreen(),
          );
        }

        // 显示群组列表
        return Scaffold(
          appBar: AppBar(
            title: const Text('端到端加密群聊'),
            actions: [
              // 调试面板入口
              IconButton(
                icon: const Icon(Icons.bug_report),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const DebugPanelScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
          body: const GroupListScreen(),
        );
      },
    );
  }
}
