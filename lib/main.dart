import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/home_screen.dart';
import 'providers/app_provider.dart';
import 'utils/debug_logger.dart';

void main() {
  // 记录应用启动日志
  DebugLogger().info('应用启动', tag: 'MAIN');

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    DebugLogger().info('构建应用界面', tag: 'MAIN');

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) {
            final provider = AppProvider();
            // 初始化应用
            provider.initialize();
            return provider;
          },
        ),
      ],
      child: MaterialApp(
        title: '端到端加密群聊',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
        ),
        home: const HomeScreen(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
