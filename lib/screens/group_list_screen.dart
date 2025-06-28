import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/group.dart';
import 'chat_screen.dart';
import 'create_group_screen.dart';
import 'join_group_screen.dart';
import 'group_qr_screen.dart';
import '../services/group_service.dart';
import '../utils/debug_logger.dart';

class GroupListScreen extends StatefulWidget {
  const GroupListScreen({super.key});

  @override
  State<GroupListScreen> createState() => _GroupListScreenState();
}

class _GroupListScreenState extends State<GroupListScreen> {
  bool _isReconnecting = false; // 添加重新连接状态标志

  @override
  void initState() {
    super.initState();
    // 群组数据已在AppProvider初始化时加载
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Consumer<AppProvider>(
          builder: (context, appProvider, child) {
            final user = appProvider.currentUser;
            return GestureDetector(
              onTap: () => _showUserProfile(),
              child: Container(
                margin: const EdgeInsets.all(8),
                child: CircleAvatar(
                  backgroundColor: Colors.white,
                  child: Text(
                    user?.name.substring(0, 1).toUpperCase() ?? 'U',
                    style: const TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
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
              final isCreator = group.creatorId == appProvider.currentUser?.id;

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                color: group.status == GroupStatus.unavailable
                    ? Colors.grey.shade100
                    : null,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: group.status == GroupStatus.unavailable
                        ? Colors.grey
                        : Colors.blue,
                    child: Text(
                      group.name.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          group.name,
                          style: TextStyle(
                            color: group.status == GroupStatus.unavailable
                                ? Colors.grey
                                : null,
                          ),
                        ),
                      ),
                      if (isCreator)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            '创建者',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      if (group.status == GroupStatus.unavailable)
                        Container(
                          margin: const EdgeInsets.only(left: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            '不可用',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Consumer<AppProvider>(
                        builder: (context, appProvider, child) {
                          final updatedGroup = appProvider.groups.firstWhere(
                            (g) => g.id == group.id,
                            orElse: () => group,
                          );
                          return Text(
                            '${updatedGroup.memberCount} 个成员 • ${updatedGroup.description}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: group.status == GroupStatus.unavailable
                                  ? Colors.grey
                                  : null,
                            ),
                          );
                        },
                      ),
                      if (group.status == GroupStatus.unavailable)
                        const Text(
                          '群组可能已被删除或服务器不可用',
                          style: TextStyle(color: Colors.red, fontSize: 12),
                        ),
                    ],
                  ),
                  trailing: group.status == GroupStatus.unavailable
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 重新连接/重启按钮
                            IconButton(
                              icon: Icon(
                                isCreator ? Icons.play_arrow : Icons.refresh,
                                color: Colors.blue,
                              ),
                              onPressed: () => isCreator
                                  ? _restartGroupServer(group)
                                  : _reconnectToGroup(group),
                              tooltip: isCreator ? '重启服务器' : '重新连接',
                            ),
                            // 更多选项按钮
                            PopupMenuButton<String>(
                              onSelected: (value) async {
                                switch (value) {
                                  case 'qr':
                                    await _showGroupQR(group);
                                    break;
                                  case 'leave':
                                    await _leaveGroup(group);
                                    break;
                                  case 'disband':
                                    await _disbandGroup(group);
                                    break;
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'qr',
                                  child: Row(
                                    children: [
                                      Icon(Icons.qr_code),
                                      SizedBox(width: 8),
                                      Text('显示二维码'),
                                    ],
                                  ),
                                ),
                                if (isCreator)
                                  const PopupMenuItem(
                                    value: 'disband',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.delete_forever,
                                          color: Colors.red,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          '解散群组',
                                          style: TextStyle(color: Colors.red),
                                        ),
                                      ],
                                    ),
                                  )
                                else
                                  const PopupMenuItem(
                                    value: 'leave',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.exit_to_app,
                                          color: Colors.orange,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          '离开群组',
                                          style: TextStyle(
                                            color: Colors.orange,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                              child: const Icon(Icons.more_vert),
                            ),
                          ],
                        )
                      : PopupMenuButton<String>(
                          onSelected: (value) async {
                            switch (value) {
                              case 'chat':
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        ChatScreen(group: group),
                                  ),
                                );
                                break;
                              case 'qr':
                                await _showGroupQR(group);
                                break;
                              case 'leave':
                                await _leaveGroup(group);
                                break;
                              case 'disband':
                                await _disbandGroup(group);
                                break;
                            }
                          },
                          itemBuilder: (context) => [
                            if (group.status != GroupStatus.unavailable)
                              const PopupMenuItem(
                                value: 'chat',
                                child: Row(
                                  children: [
                                    Icon(Icons.chat),
                                    SizedBox(width: 8),
                                    Text('进入聊天'),
                                  ],
                                ),
                              ),
                            const PopupMenuItem(
                              value: 'qr',
                              child: Row(
                                children: [
                                  Icon(Icons.qr_code),
                                  SizedBox(width: 8),
                                  Text('显示二维码'),
                                ],
                              ),
                            ),
                            if (isCreator)
                              const PopupMenuItem(
                                value: 'disband',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.delete_forever,
                                      color: Colors.red,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      '解散群组',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ],
                                ),
                              )
                            else
                              const PopupMenuItem(
                                value: 'leave',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.exit_to_app,
                                      color: Colors.orange,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      '离开群组',
                                      style: TextStyle(color: Colors.orange),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                          child: const Icon(Icons.more_vert),
                        ),
                  onTap: () {
                    // 在重新连接期间禁用点击
                    if (_isReconnecting) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('正在重新连接中，请稍候...'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      return;
                    }

                    if (group.status == GroupStatus.unavailable) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('群组不可用，无法进入聊天'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ChatScreen(group: group),
                      ),
                    );
                  },
                  onLongPress: () async {
                    await _showGroupQR(group);
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
    final nicknameController = TextEditingController(
      text: user?.profile.nickname ?? '',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('用户信息'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.blue,
                  radius: 30,
                  child: Text(
                    user?.name.substring(0, 1).toUpperCase() ?? 'U',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.name ?? '未知用户',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '用户ID: ${user?.id ?? '未知'}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              '昵称',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: nicknameController,
              decoration: const InputDecoration(
                hintText: '请输入昵称',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              maxLength: 20,
            ),
            const SizedBox(height: 16),
            const Text(
              '其他信息',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('设备ID: ${user?.deviceId ?? '未知'}'),
            const SizedBox(height: 4),
            Text(
              '创建时间: ${user?.createdAt.toString().substring(0, 19) ?? '未知'}',
            ),
            const SizedBox(height: 4),
            Text(
              '最后活跃: ${user?.lastActiveAt.toString().substring(0, 19) ?? '未知'}',
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.logout, color: Colors.white),
                label: const Text(
                  '注销账户',
                  style: TextStyle(color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () {
                  Navigator.pop(context);
                  _showLogoutConfirm();
                },
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newNickname = nicknameController.text.trim();
              if (newNickname.isNotEmpty) {
                final success = await appProvider.updateUserNickname(
                  newNickname,
                );
                if (success) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('昵称更新成功')));
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(appProvider.error ?? '昵称更新失败')),
                  );
                }
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _showGroupQR(Group group) async {
    final success = await GroupService().ensureGroupServerRunning(group);
    if (!success) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('启动P2P服务器失败，无法显示二维码')));
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          SizedBox(height: 500, child: GroupQRScreen(group: group)),
    );
  }

  Future<void> _leaveGroup(Group group) async {
    final appProvider = context.read<AppProvider>();

    // 显示确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('离开群组'),
        content: Text('确定要离开群组"${group.name}"吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final success = await appProvider.leaveGroup(group);
    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('成功离开群组')));
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appProvider.error ?? '离开群组失败')));
    }
  }

  Future<void> _disbandGroup(Group group) async {
    final appProvider = context.read<AppProvider>();

    // 显示确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('解散群组'),
        content: Text('确定要解散群组"${group.name}"吗？\n\n解散后所有成员将被移除，群组将无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('解散'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final success = await appProvider.disbandGroup(group);
    if (success) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('成功解散群组')));
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appProvider.error ?? '解散群组失败')));
    }
  }

  void _showUserProfile() {
    final appProvider = context.read<AppProvider>();
    final user = appProvider.currentUser;
    final nicknameController = TextEditingController(
      text: user?.profile.nickname ?? '',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('用户信息'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.blue,
                  radius: 30,
                  child: Text(
                    user?.name.substring(0, 1).toUpperCase() ?? 'U',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.name ?? '未知用户',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '用户ID: ${user?.id ?? '未知'}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              '昵称',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: nicknameController,
              decoration: const InputDecoration(
                hintText: '请输入昵称',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              maxLength: 20,
            ),
            const SizedBox(height: 16),
            const Text(
              '其他信息',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('设备ID: ${user?.deviceId ?? '未知'}'),
            const SizedBox(height: 4),
            Text(
              '创建时间: ${user?.createdAt.toString().substring(0, 19) ?? '未知'}',
            ),
            const SizedBox(height: 4),
            Text(
              '最后活跃: ${user?.lastActiveAt.toString().substring(0, 19) ?? '未知'}',
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.logout, color: Colors.white),
                label: const Text(
                  '注销账户',
                  style: TextStyle(color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () {
                  Navigator.pop(context);
                  _showLogoutConfirm();
                },
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newNickname = nicknameController.text.trim();
              if (newNickname.isNotEmpty) {
                final success = await appProvider.updateUserNickname(
                  newNickname,
                );
                if (success) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('昵称更新成功')));
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(appProvider.error ?? '昵称更新失败')),
                  );
                }
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showLogoutConfirm() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('注销账户'),
        content: const Text('确定要注销账户吗？\n\n注销后将删除所有用户信息、群组数据和聊天记录，此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _performLogout();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('注销', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _performLogout() async {
    final appProvider = context.read<AppProvider>();
    try {
      final success = await appProvider.logout();
      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('注销成功，请重新启动应用')));
        // 这里可以考虑跳转到登录页或主界面
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(appProvider.error ?? '注销失败')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('注销失败: $e')));
      }
    }
  }

  void _reconnectToGroup(Group group) async {
    final appProvider = context.read<AppProvider>();

    // 显示确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重新连接群组'),
        content: Text('确定要重新连接到群组"${group.name}"吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('重新连接'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    DebugLogger().info('UI: 开始重新连接群组', tag: 'GROUP_LIST');

    // 设置重新连接状态
    setState(() {
      _isReconnecting = true;
    });

    // 显示开始重新连接的提示
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('正在重新连接群组"${group.name}"...'),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 2),
      ),
    );

    // 在后台执行重新连接
    try {
      DebugLogger().info(
        'UI: 开始调用AppProvider.reconnectToGroup',
        tag: 'GROUP_LIST',
      );

      // 执行重新连接
      final success = await appProvider.reconnectToGroup(group);

      DebugLogger().info(
        'UI: AppProvider.reconnectToGroup 返回结果: $success',
        tag: 'GROUP_LIST',
      );

      // 检查Widget是否仍然挂载
      if (!mounted) {
        DebugLogger().info('UI: Widget已卸载，不执行UI操作', tag: 'GROUP_LIST');
        return;
      }

      // 重置重新连接状态
      setState(() {
        _isReconnecting = false;
      });

      if (success) {
        DebugLogger().info('UI: 显示成功提示', tag: 'GROUP_LIST');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('群组"${group.name}"重新连接成功'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        DebugLogger().info('UI: 显示失败提示', tag: 'GROUP_LIST');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('群组"${group.name}"重新连接失败，请检查网络连接或联系群组创建者'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      DebugLogger().error('UI: 重新连接过程中发生异常: $e', tag: 'GROUP_LIST');

      // 检查Widget是否仍然挂载
      if (!mounted) {
        DebugLogger().info('UI: Widget已卸载，不执行UI操作', tag: 'GROUP_LIST');
        return;
      }

      // 重置重新连接状态
      setState(() {
        _isReconnecting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('重新连接失败: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _restartGroupServer(Group group) async {
    final appProvider = context.read<AppProvider>();

    // 显示确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重启群组服务器'),
        content: Text('确定要重启群组"${group.name}"的服务器吗？\n\n重启后群组将重新可用，成员可以重新连接。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('重启'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    DebugLogger().info('UI: 开始重启群组服务器', tag: 'GROUP_LIST');

    // 设置重新连接状态
    setState(() {
      _isReconnecting = true;
    });

    // 显示开始重启服务器的提示
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('正在重启群组"${group.name}"的服务器...'),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 2),
      ),
    );

    // 在后台执行重启服务器
    try {
      DebugLogger().info(
        'UI: 开始调用AppProvider.restartGroupServer',
        tag: 'GROUP_LIST',
      );

      // 执行重启服务器
      final success = await appProvider.restartGroupServer(group);

      DebugLogger().info(
        'UI: AppProvider.restartGroupServer 返回结果: $success',
        tag: 'GROUP_LIST',
      );

      // 检查Widget是否仍然挂载
      if (!mounted) {
        DebugLogger().info('UI: Widget已卸载，不执行UI操作', tag: 'GROUP_LIST');
        return;
      }

      // 重置重新连接状态
      setState(() {
        _isReconnecting = false;
      });

      if (success) {
        DebugLogger().info('UI: 显示重启成功提示', tag: 'GROUP_LIST');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('群组服务器"${group.name}"重启成功'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        DebugLogger().info('UI: 显示重启失败提示', tag: 'GROUP_LIST');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('群组服务器"${group.name}"重启失败'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      DebugLogger().error('UI: 重启服务器过程中发生异常: $e', tag: 'GROUP_LIST');

      // 检查Widget是否仍然挂载
      if (!mounted) {
        DebugLogger().info('UI: Widget已卸载，不执行UI操作', tag: 'GROUP_LIST');
        return;
      }

      // 重置重新连接状态
      setState(() {
        _isReconnecting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('重启服务器失败: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  void dispose() {
    // 页面销毁时不需要手动关闭对话框，Flutter会自动处理
    super.dispose();
  }
}
