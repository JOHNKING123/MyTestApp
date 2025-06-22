import 'dart:io';
import 'dart:async';
import 'dart:convert';

// 模拟P2P连接管理测试
void main() async {
  print('=== P2P连接管理测试 ===');

  // 模拟服务器状态
  Map<String, Map<String, dynamic>> connections = {};
  Timer? heartbeatTimer;

  // 检查连接状态
  void checkConnections() {
    final now = DateTime.now();
    final toRemove = <String>[];

    for (final entry in connections.entries) {
      final connectionId = entry.key;
      final connection = entry.value;
      final lastHeartbeat = DateTime.parse(connection['lastHeartbeat']);

      if (now.difference(lastHeartbeat).inSeconds > 5) {
        print('连接超时，准备移除: $connectionId (用户: ${connection['userId']})');
        toRemove.add(connectionId);
      }
    }

    for (final connectionId in toRemove) {
      print('关闭超时连接: $connectionId');
      connections.remove(connectionId);
    }

    print('当前活跃连接数: ${connections.length}');
  }

  // 启动心跳检查
  void startHeartbeatCheck() {
    heartbeatTimer?.cancel();
    heartbeatTimer = Timer.periodic(Duration(seconds: 3), (timer) {
      checkConnections();
    });
    print('心跳检查已启动，间隔: 3秒');
  }

  // 模拟新连接
  void handleNewConnection(String connectionId, String userId, String groupId) {
    print('处理新连接: $connectionId (用户: $userId, 群组: $groupId)');

    // 检查是否已存在相同用户的连接
    final existingConnection = connections.values
        .where((conn) => conn['userId'] == userId && conn['groupId'] == groupId)
        .firstOrNull;

    if (existingConnection != null) {
      final existingId = connections.keys.firstWhere(
        (key) => connections[key] == existingConnection,
      );
      print('检测到重复连接，关闭旧连接: $existingId');
      connections.remove(existingId);
    }

    // 创建新连接
    connections[connectionId] = {
      'userId': userId,
      'groupId': groupId,
      'lastHeartbeat': DateTime.now().toIso8601String(),
    };

    print('新连接已建立: $connectionId');
  }

  // 模拟心跳更新
  void updateHeartbeat(String connectionId) {
    final connection = connections[connectionId];
    if (connection != null) {
      connection['lastHeartbeat'] = DateTime.now().toIso8601String();
      print('心跳更新: $connectionId (用户: ${connection['userId']})');
    }
  }

  // 启动心跳检查
  startHeartbeatCheck();

  // 模拟连接场景
  print('\n=== 测试场景1: 正常连接 ===');
  handleNewConnection('conn1', 'user1', 'group1');
  await Future.delayed(Duration(seconds: 2));
  updateHeartbeat('conn1');

  print('\n=== 测试场景2: 重复连接 ===');
  handleNewConnection('conn2', 'user1', 'group1'); // 应该关闭conn1
  await Future.delayed(Duration(seconds: 2));
  updateHeartbeat('conn2');

  print('\n=== 测试场景3: 不同用户连接 ===');
  handleNewConnection('conn3', 'user2', 'group1');
  await Future.delayed(Duration(seconds: 2));
  updateHeartbeat('conn3');

  print('\n=== 测试场景4: 心跳超时 ===');
  handleNewConnection('conn4', 'user3', 'group1');
  // 不更新心跳，等待超时
  print('等待心跳超时...');
  await Future.delayed(Duration(seconds: 8));

  print('\n=== 测试场景5: 多用户多群组 ===');
  handleNewConnection('conn5', 'user1', 'group2');
  handleNewConnection('conn6', 'user2', 'group2');
  await Future.delayed(Duration(seconds: 2));
  updateHeartbeat('conn5');
  updateHeartbeat('conn6');

  // 等待一段时间观察心跳检查
  print('\n=== 观察心跳检查 ===');
  await Future.delayed(Duration(seconds: 10));

  // 停止心跳检查
  heartbeatTimer?.cancel();
  print('\n=== 测试完成 ===');
  print('最终连接状态:');
  for (final entry in connections.entries) {
    print(
      '  ${entry.key}: 用户=${entry.value['userId']}, 群组=${entry.value['groupId']}',
    );
  }
}
