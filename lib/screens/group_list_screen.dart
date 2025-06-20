import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import 'chat_screen.dart';
import 'create_group_screen.dart';
import 'join_group_screen.dart';
import 'group_qr_screen.dart';

class GroupListScreen extends StatefulWidget {
  const GroupListScreen({super.key});

  @override
  State<GroupListScreen> createState() => _GroupListScreenState();
}

class _GroupListScreenState extends State<GroupListScreen> {
  @override
  void initState() {
    super.initState();
    // 群组数据已在AppProvider初始化时加载
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('群组'),
        actions: [
          Consumer<AppProvider>(
            builder: (context, appProvider, child) {
              return PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'create':
                      _showCreateGroup();
                      break;
                    case 'join':
                      _showJoinGroup();
                      break;
                    case 'profile':
                      _showProfile();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'create',
                    child: Row(
                      children: [
                        Icon(Icons.add),
                        SizedBox(width: 8),
                        Text('创建群组'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'join',
                    child: Row(
                      children: [
                        Icon(Icons.qr_code),
                        SizedBox(width: 8),
                        Text('加入群组'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'profile',
                    child: Row(
                      children: [
                        Icon(Icons.person),
                        SizedBox(width: 8),
                        Text('个人资料'),
                      ],
                    ),
                  ),
                ],
                child: const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Icon(Icons.more_vert),
                ),
              );
            },
          ),
        ],
      ),
      body: Consumer<AppProvider>(
        builder: (context, appProvider, child) {
          if (appProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (appProvider.groups.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.group_outlined,
                    size: 80,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '暂无群组',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '创建或加入一个群组开始聊天',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _showCreateGroup,
                    icon: const Icon(Icons.add),
                    label: const Text('创建群组'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _showJoinGroup,
                    icon: const Icon(Icons.qr_code),
                    label: const Text('加入群组'),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: appProvider.groups.length,
            itemBuilder: (context, index) {
              final group = appProvider.groups[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.blue,
                    child: Text(
                      group.name.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(group.name),
                  subtitle: Text(
                    '${group.memberCount} 个成员 • ${group.description}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ChatScreen(group: group),
                      ),
                    );
                  },
                  onLongPress: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      builder: (context) => SizedBox(
                        height: 500,
                        child: GroupQRScreen(group: group),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateGroup,
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showCreateGroup() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CreateGroupScreen()),
    );
  }

  void _showJoinGroup() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const JoinGroupScreen()),
    );
  }

  void _showProfile() {
    final appProvider = context.read<AppProvider>();
    final user = appProvider.currentUser;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('个人资料'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('姓名: ${user?.name}'),
            const SizedBox(height: 8),
            Text('昵称: ${user?.profile.nickname}'),
            const SizedBox(height: 8),
            Text('用户ID: ${user?.id}'),
            const SizedBox(height: 8),
            Text('创建时间: ${user?.createdAt.toString().substring(0, 19)}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}
