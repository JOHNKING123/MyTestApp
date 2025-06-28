import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/debug_logger.dart';

class DebugPanelScreen extends StatefulWidget {
  const DebugPanelScreen({super.key});

  @override
  State<DebugPanelScreen> createState() => _DebugPanelScreenState();
}

class _DebugPanelScreenState extends State<DebugPanelScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _autoScroll = true;
  LogLevel _filterLevel = LogLevel.debug;

  @override
  void initState() {
    super.initState();
    DebugLogger().pushLogs(); // 主动推送历史日志
    // 添加测试日志
    DebugLogger().info('调试面板已打开', tag: 'DEBUG_PANEL');
    DebugLogger().warning('这是一条测试警告', tag: 'DEBUG_PANEL');
    DebugLogger().error('这是一条测试错误', tag: 'DEBUG_PANEL');
    DebugLogger().debug('这是一条测试调试信息', tag: 'DEBUG_PANEL');
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('调试面板'),
        actions: [
          // 过滤按钮
          PopupMenuButton<LogLevel>(
            icon: const Icon(Icons.filter_list),
            onSelected: (level) {
              setState(() {
                _filterLevel = level;
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: LogLevel.debug, child: Text('🔍 调试')),
              const PopupMenuItem(value: LogLevel.info, child: Text('ℹ️ 信息')),
              const PopupMenuItem(
                value: LogLevel.warning,
                child: Text('⚠️ 警告'),
              ),
              const PopupMenuItem(value: LogLevel.error, child: Text('❌ 错误')),
            ],
          ),
          // 清除按钮
          IconButton(
            icon: const Icon(Icons.clear_all),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('清除日志'),
                  content: const Text('确定要清除所有日志吗？'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                    TextButton(
                      onPressed: () {
                        DebugLogger().clear();
                        Navigator.pop(context);
                      },
                      child: const Text('确定'),
                    ),
                  ],
                ),
              );
            },
          ),
          // 导出按钮
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () {
              final logs = DebugLogger().exportLogs();
              Clipboard.setData(ClipboardData(text: logs));
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('日志已复制到剪贴板')));
            },
          ),
          // 测试日志按钮
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              DebugLogger().info('手动添加的测试日志', tag: 'DEBUG_PANEL');
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('已添加测试日志')));
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 控制栏
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.grey[100],
            child: Row(
              children: [
                const Text('自动滚动: '),
                Switch(
                  value: _autoScroll,
                  onChanged: (value) {
                    setState(() {
                      _autoScroll = value;
                    });
                  },
                ),
                const SizedBox(width: 16),
                Text('过滤级别: ${_filterLevel.emoji}'),
                const Spacer(),
                StreamBuilder<List<LogEntry>>(
                  stream: DebugLogger().logStream,
                  builder: (context, snapshot) {
                    final count = snapshot.data?.length ?? 0;
                    return Text('日志数量: $count');
                  },
                ),
              ],
            ),
          ),
          // 日志列表
          Expanded(
            child: StreamBuilder<List<LogEntry>>(
              stream: DebugLogger().logStream,
              initialData: DebugLogger().logs,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: Text('暂无日志'));
                }

                final logs = snapshot.data!;
                final filteredLogs = logs.where((log) {
                  return log.level.index >= _filterLevel.index;
                }).toList();

                if (filteredLogs.isEmpty) {
                  return const Center(child: Text('没有符合条件的日志'));
                }

                // 自动滚动到底部
                if (_autoScroll && _scrollController.hasClients) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _scrollController.animateTo(
                      _scrollController.position.maxScrollExtent,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  });
                }

                return ListView.builder(
                  controller: _scrollController,
                  itemCount: filteredLogs.length,
                  itemBuilder: (context, index) {
                    final log = filteredLogs[index];
                    return _buildLogItem(log);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogItem(LogEntry log) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(log.level.emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Text(
                log.tag ?? 'APP',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: log.level.color,
                ),
              ),
              const Spacer(),
              Text(
                '${log.timestamp.hour.toString().padLeft(2, '0')}:${log.timestamp.minute.toString().padLeft(2, '0')}:${log.timestamp.second.toString().padLeft(2, '0')}',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(log.message, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }
}
