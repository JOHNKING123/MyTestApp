import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/group.dart';
import '../models/message.dart';
import '../models/member.dart';
import '../providers/app_provider.dart';
import '../screens/group_qr_screen.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/group_service.dart';
import 'package:flutter/services.dart';

class ChatScreen extends StatefulWidget {
  final Group group;

  const ChatScreen({super.key, required this.group});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // 选择当前群组
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppProvider>().selectGroup(widget.group);
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.group.name),
            Consumer<AppProvider>(
              builder: (context, appProvider, child) {
                final group = appProvider.groups.firstWhere(
                  (g) => g.id == widget.group.id,
                  orElse: () => widget.group,
                );
                return Text(
                  '${group.memberCount} 个成员',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.normal,
                  ),
                );
              },
            ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.info), onPressed: _showGroupInfo),
        ],
      ),
      body: Column(
        children: [
          // 群组状态提示
          if (widget.group.status == GroupStatus.unavailable)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.red.shade50,
              child: Row(
                children: [
                  Icon(Icons.warning, color: Colors.red.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '群组不可用，可能已被删除或服务器不可用',
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Consumer<AppProvider>(
              builder: (context, appProvider, child) {
                if (appProvider.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = appProvider.getGroupMessages(widget.group.id);

                if (messages.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 80,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 16),
                        Text(
                          '暂无消息',
                          style: TextStyle(fontSize: 18, color: Colors.grey),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '发送第一条消息开始聊天',
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[messages.length - 1 - index];
                    final isMe =
                        message.senderId == appProvider.currentUser?.id;

                    return _buildMessageBubble(message, isMe);
                  },
                );
              },
            ),
          ),
          // 只在群组可用时显示消息输入
          if (widget.group.status == GroupStatus.active)
            _buildMessageInput()
          else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.2),
                    spreadRadius: 1,
                    blurRadius: 3,
                    offset: const Offset(0, -1),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      enabled: false,
                      decoration: InputDecoration(
                        hintText: '群组不可用，无法发送消息',
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade200,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: null,
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Message message, bool isMe) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.blue,
              child: Text(
                message.senderId.substring(0, 1).toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isMe ? Colors.blue : Colors.grey[200],
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isMe)
                    Builder(
                      builder: (context) {
                        final appProvider = context.read<AppProvider>();
                        final group = appProvider.groups.firstWhere(
                          (g) => g.id == widget.group.id,
                          orElse: () => widget.group,
                        );
                        final member = group.members.firstWhere(
                          (m) => m.userId == message.senderId,
                          orElse: () => Member(
                            id: '',
                            userId: '',
                            groupId: '',
                            name: '',
                            publicKey: '',
                            joinedAt: DateTime.now(),
                            lastSeen: DateTime.now(),
                          ),
                        );
                        final displayName = member.userId.isEmpty
                            ? message.senderId
                            : (member.groupNickname?.isNotEmpty == true
                                  ? member.groupNickname!
                                  : (member.name.isNotEmpty
                                        ? member.name
                                        : member.userId));
                        return Text(
                          displayName,
                          style: TextStyle(
                            fontSize: 12,
                            color: isMe ? Colors.white70 : Colors.grey[600],
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      },
                    ),
                  const SizedBox(height: 4),
                  Text(
                    message.content.text,
                    style: TextStyle(
                      color: isMe ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(message.timestamp),
                    style: TextStyle(
                      fontSize: 10,
                      color: isMe ? Colors.white70 : Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isMe) const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: const InputDecoration(
                hintText: '输入消息...',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              maxLines: null,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: _sendMessage,
            color: Colors.blue,
          ),
        ],
      ),
    );
  }

  void _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    final provider = context.read<AppProvider>();
    final success = await provider.sendMessage(message);

    if (success) {
      _messageController.clear();
      // 滚动到底部
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.error ?? '发送失败')));
    }
  }

  void _showGroupInfo() {
    final appProvider = context.read<AppProvider>();
    final isCreator = widget.group.creatorId == appProvider.currentUser?.id;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.group.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('群组ID: ${widget.group.id}'),
            Text('创建者: ${widget.group.creatorId}'),
            Consumer<AppProvider>(
              builder: (context, appProvider, child) {
                final group = appProvider.groups.firstWhere(
                  (g) => g.id == widget.group.id,
                  orElse: () => widget.group,
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('成员数: ${group.memberCount}'),
                    const SizedBox(height: 4),
                    ...group.members.map(
                      (m) => Text(
                        m.groupNickname?.isNotEmpty == true
                            ? m.groupNickname!
                            : (m.name.isNotEmpty ? m.name : m.userId),
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            Text('创建时间: ${_formatTime(widget.group.createdAt)}'),
            if (isCreator)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '群组创建者',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.qr_code),
                    label: const Text('显示二维码'),
                    onPressed: () {
                      Navigator.pop(context);
                      _showGroupQRCode();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (isCreator)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.delete_forever, color: Colors.white),
                  label: const Text(
                    '解散群组',
                    style: TextStyle(color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () {
                    Navigator.pop(context);
                    _disbandGroup();
                  },
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.exit_to_app, color: Colors.white),
                  label: const Text(
                    '离开群组',
                    style: TextStyle(color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    _leaveGroup();
                  },
                ),
              ),
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

  void _showGroupQRCode() async {
    // 如果是群组创建者，确保P2P服务器正在运行
    final appProvider = context.read<AppProvider>();
    if (widget.group.creatorId == appProvider.currentUser?.id) {
      final success = await GroupService().ensureGroupServerRunning(
        widget.group,
      );
      if (!success) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('启动P2P服务器失败，无法显示二维码')));
        return;
      }
    }

    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '群组二维码',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            FutureBuilder<String?>(
              future: context.read<AppProvider>().generateGroupQRData(
                widget.group,
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const CircularProgressIndicator();
                }

                if (snapshot.hasError || !snapshot.hasData) {
                  return const Text('生成二维码失败');
                }

                return Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: QrImageView(
                        data: snapshot.data!,
                        version: QrVersions.auto,
                        size: 200.0,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.copy),
                      label: const Text('复制二维码数据'),
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: snapshot.data!),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('二维码数据已复制')),
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    const Text('扫描此二维码加入群组', style: TextStyle(fontSize: 14)),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inDays > 0) {
      return '${difference.inDays}天前';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}小时前';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}分钟前';
    } else {
      return '刚刚';
    }
  }

  Future<void> _leaveGroup() async {
    final appProvider = context.read<AppProvider>();
    final success = await appProvider.leaveGroup(widget.group);
    if (success) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('成功离开群组')));
      Navigator.pop(context); // 返回群组列表
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appProvider.error ?? '离开群组失败')));
    }
  }

  Future<void> _disbandGroup() async {
    final appProvider = context.read<AppProvider>();
    final success = await appProvider.disbandGroup(widget.group);
    if (success) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('成功解散群组')));
      Navigator.pop(context); // 返回群组列表
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appProvider.error ?? '解散群组失败')));
    }
  }
}
