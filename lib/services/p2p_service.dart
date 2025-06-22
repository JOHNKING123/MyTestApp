import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/group.dart';
import '../models/message.dart';
import '../models/user.dart';
import 'group_service.dart';

/// 连接断开回调函数类型
typedef ConnectionDisconnectCallback =
    void Function(String userId, String groupId);

/// 消息回调函数类型
typedef MessageCallback = void Function(Map<String, dynamic> message);

/// 群组更新回调函数类型
typedef GroupUpdateCallback = void Function(String groupId);

/// 连接验证器函数类型
typedef ConnectionValidator =
    Future<bool> Function(String userId, String groupId, bool isNewMember);

// 连接信息类
class P2PConnection {
  final WebSocket webSocket;
  final String userId;
  final String groupId;
  final String connectionId;
  DateTime lastHeartbeat;

  P2PConnection({
    required this.webSocket,
    required this.userId,
    required this.groupId,
    required this.connectionId,
  }) : lastHeartbeat = DateTime.now();

  void updateHeartbeat() {
    lastHeartbeat = DateTime.now();
  }

  bool isAlive() {
    return DateTime.now().difference(lastHeartbeat) < Duration(seconds: 5);
  }
}

class P2PService {
  static HttpServer? _server;
  static Map<String, P2PConnection> _connections = {};
  static Function(Map<String, dynamic>)? onMessage;
  static String? _localIP;
  static int _port = 36324;

  // 心跳相关
  static Timer? _heartbeatTimer;
  static const Duration _heartbeatInterval = Duration(seconds: 3);
  static const Duration _connectionTimeout = Duration(seconds: 5);

  // 连接管理
  static Map<String, DateTime> _lastHeartbeat = {};
  static Map<String, Timer> _connectionTimers = {};

  // 重连限制
  static Map<String, int> _reconnectAttempts = {};
  static const int _maxReconnectAttempts = 3;
  static const Duration _reconnectCooldown = Duration(seconds: 30);

  // 连接验证器回调函数类型
  static Future<bool> Function(String userId, String groupId, bool isNewMember)?
  _connectionValidator;

  // 回调函数
  static MessageCallback? onMessageReceived;
  static GroupUpdateCallback? onGroupUpdated;
  static ConnectionValidator? onConnectionValidate;
  static ConnectionDisconnectCallback? onConnectionDisconnect; // 新增连接断开回调

  // 设置连接验证器
  static void setConnectionValidator(
    Future<bool> Function(String userId, String groupId, bool isNewMember)?
    validator,
  ) {
    _connectionValidator = validator;
    print('连接验证器已设置: ${validator != null ? "启用" : "禁用"}');
  }

  // 获取本地IP地址
  static Future<String> getLocalIP() async {
    if (_localIP != null) return _localIP!;

    try {
      print('正在获取本地IP地址...');
      for (var interface in await NetworkInterface.list()) {
        print('网络接口: ${interface.name}');
        for (var addr in interface.addresses) {
          print('  - ${addr.address} (${addr.type})');
          if (addr.type == InternetAddressType.IPv4 &&
              !addr.address.startsWith('127.')) {
            _localIP = addr.address;
            print('选择IP地址: $_localIP');
            return _localIP!;
          }
        }
      }
    } catch (e) {
      print('获取IP失败: $e');
    }

    // 如果无法获取IP，使用localhost（适用于模拟器）
    _localIP = '127.0.0.1';
    print('使用localhost地址: $_localIP');
    return _localIP!;
  }

  /// 测试网络连通性（ping测试）
  static Future<bool> pingTest(String targetIP) async {
    try {
      print('开始网络连通性测试: $targetIP');

      // 尝试连接一个常用的端口来测试网络连通性
      // 这里使用80端口（HTTP）作为连通性测试，因为大多数设备都会响应
      final socket = await Socket.connect(
        targetIP,
        80,
        timeout: Duration(seconds: 3),
      );
      socket.destroy();
      print('网络连通性测试成功: $targetIP');
      return true;
    } catch (e) {
      print('网络连通性测试失败: $targetIP - $e');

      // 如果80端口失败，尝试其他常用端口
      final testPorts = [443, 22, 36324];
      for (final port in testPorts) {
        try {
          print('尝试连接端口 $port 进行连通性测试...');
          final socket = await Socket.connect(
            targetIP,
            port,
            timeout: Duration(seconds: 2),
          );
          socket.destroy();
          print('网络连通性测试成功: $targetIP (通过端口 $port)');
          return true;
        } catch (e) {
          print('端口 $port 连通性测试失败: $e');
        }
      }

      print('所有端口连通性测试都失败，网络可能不通');
      return false;
    }
  }

  /// 测试端口连通性
  static Future<bool> portTest(String targetIP, int port) async {
    try {
      print('开始端口测试: $targetIP:$port');

      final socket = await Socket.connect(
        targetIP,
        port,
        timeout: Duration(seconds: 5),
      );
      socket.destroy();
      print('端口测试成功: $targetIP:$port');
      return true;
    } catch (e) {
      print('端口测试失败: $targetIP:$port - $e');
      return false;
    }
  }

  /// 启动P2P服务器（群组创建者调用）
  static Future<bool> startServer() async {
    if (_server != null) {
      print('P2P服务器已经启动');
      return true;
    }

    try {
      print('正在启动P2P服务器...');
      print('绑定地址: 0.0.0.0:$_port');

      _server = await HttpServer.bind(InternetAddress.anyIPv4, _port);

      print('P2P服务器启动成功，监听端口: $_port');

      _server!.transform(WebSocketTransformer()).listen((WebSocket webSocket) {
        _handleNewConnection(webSocket);
      });

      // 启动心跳检测
      _startHeartbeatCheck();

      final serverIP = await getLocalIP();
      print('P2P服务器启动成功: $serverIP:$_port');
      return true;
    } catch (e) {
      print('启动P2P服务器失败: $e');
      return false;
    }
  }

  /// 处理新的WebSocket连接
  static void _handleNewConnection(WebSocket webSocket) {
    print('新的WebSocket连接: ${webSocket.hashCode}');

    webSocket.listen(
      (data) {
        _handleMessage(data, webSocket);
      },
      onDone: () {
        print('WebSocket连接断开: ${webSocket.hashCode}');
        _removeConnectionByWebSocket(webSocket);
      },
      onError: (e) {
        print('WebSocket连接错误: $e');
        _removeConnectionByWebSocket(webSocket);
      },
    );
  }

  /// 处理接收到的消息
  static void _handleMessage(dynamic data, WebSocket webSocket) {
    try {
      final message = jsonDecode(data.toString());
      final messageType = message['type'];

      if (messageType == 'auth') {
        print('开始处理身份验证消息...'); // 添加身份验证开始日志
        // 处理身份验证
        _handleAuthMessage(message, webSocket);
      } else if (messageType == 'auth_success') {
        // 处理认证成功响应
        final connectionId = message['connectionId'];
        print('收到认证成功响应: $connectionId');
        // 认证成功，不需要特殊处理，连接已建立
      } else if (messageType == 'ping') {
        // 处理心跳请求
        _handlePingMessage(webSocket);
      } else if (messageType == 'message') {
        // 处理聊天消息
        _handleChatMessage(message, webSocket);
      } else if (messageType == 'group_update') {
        // 处理群组更新消息
        _handleGroupUpdateMessage(message, webSocket);
      } else if (messageType == 'member_join') {
        // 处理成员加入消息
        _handleMemberJoinMessage(message, webSocket);
      } else if (messageType == 'auth_failure') {
        // 处理认证失败
        final userId = message['userId'];
        final groupId = message['groupId'];
        final reason = message['reason'];
        print('收到认证失败响应: 用户=$userId, 群组=$groupId, 原因=$reason');

        // 主动断开连接
        final connection = _connections.values
            .where((conn) => conn.userId == userId && conn.groupId == groupId)
            .firstOrNull;
        if (connection != null) {
          print('主动断开认证失败的连接: ${connection.connectionId}');
          connection.webSocket.close();
        }

        // 移除连接
        _removeConnection(connection!.connectionId);

        // 设置群组状态为不可用
        _setGroupUnavailable(groupId);

        // 通知本地应用
        if (onMessage != null) {
          onMessage!(message);
        }
      } else {
        print('_handleMessage 未知消息类型: $messageType');
      }
    } catch (e) {
      print('处理消息时发生错误: $e');
    }
  }

  /// 根据WebSocket移除连接
  static void _removeConnectionByWebSocket(WebSocket webSocket) {
    final connectionToRemove = _connections.values
        .where((conn) => conn.webSocket == webSocket)
        .firstOrNull;

    if (connectionToRemove != null) {
      print('移除连接: ${connectionToRemove.connectionId}');
      _removeConnection(connectionToRemove.connectionId);
    }
  }

  /// 启动心跳检测
  static void _startHeartbeatCheck() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (timer) {
      _checkConnections();
    });
    print('心跳检查已启动，间隔: ${_heartbeatInterval.inSeconds}秒');
  }

  /// 检查连接状态
  static void _checkConnections() {
    final now = DateTime.now();
    final toRemove = <String>[];

    for (final entry in _connections.entries) {
      final connectionId = entry.key;
      final connection = entry.value;

      if (!connection.isAlive()) {
        print('连接超时，准备移除: $connectionId (用户: ${connection.userId})');
        toRemove.add(connectionId);
      }
    }

    for (final connectionId in toRemove) {
      final connection = _connections[connectionId];
      if (connection != null) {
        print('关闭超时连接: $connectionId');
        connection.webSocket.close();
        _removeConnection(connectionId);
      }
    }
  }

  /// 停止P2P服务器
  static void stopServer() {
    print('正在停止P2P服务器...');
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    _server?.close();
    _server = null;

    for (var connection in _connections.values) {
      connection.webSocket.close();
    }
    _connections.clear();
    _lastHeartbeat.clear();

    for (var timer in _connectionTimers.values) {
      timer.cancel();
    }
    _connectionTimers.clear();

    // 清理重连计数
    _reconnectAttempts.clear();
    print('重连计数已清理');

    print('P2P服务器已停止');
  }

  /// 连接到P2P服务器（群组成员调用）
  static Future<bool> connectToServer(
    String serverIP,
    int port,
    String userId,
    String groupId, {
    bool isNewMember = false, // 新增参数标识是否为新成员
  }) async {
    // 检查是否已存在相同用户的连接
    final existingConnection = _connections.values
        .where((conn) => conn.userId == userId && conn.groupId == groupId)
        .firstOrNull;

    if (existingConnection != null) {
      print('已存在相同用户的连接，关闭旧连接: ${existingConnection.connectionId}');
      existingConnection.webSocket.close();
      _removeConnection(existingConnection.connectionId);
    }

    // 在模拟器环境中进行IP转换
    String targetIP = serverIP;
    int targetPort = port;

    // 如果目标IP是模拟器A的IP (10.0.2.15)，转换为主机地址和端口转发端口
    if (serverIP == '10.0.2.15') {
      print('检测到目标服务器是模拟器A，转换连接地址');
      print('原始地址: $serverIP:$port');
      targetIP = '10.0.2.2';
      targetPort = 8081; // 端口转发端口
      print('转换后地址: $targetIP:$targetPort');
    }

    // 尝试不同的IP地址
    final testIPs = [targetIP, '127.0.0.1', 'localhost'];

    for (final ip in testIPs) {
      try {
        print(
          '正在连接到P2P服务器: $ip:$targetPort (用户: $userId, 群组: $groupId, 是否新成员: $isNewMember)',
        );

        final uri = Uri.parse('ws://$ip:$targetPort');
        print('WebSocket URI: $uri');

        final webSocket = await WebSocket.connect(uri.toString());
        print('WebSocket连接成功: $ip:$targetPort');

        // 生成连接ID（由客户端生成）
        final connectionId =
            '${userId}_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000)}';
        print('生成连接ID: $connectionId');

        // 发送身份验证消息
        final authMessage = {
          'type': 'auth',
          'userId': userId,
          'groupId': groupId,
          'connectionId': connectionId, // 传递连接ID给服务器
          'isNewMember': isNewMember, // 添加是否为新成员的标识
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        };

        webSocket.add(jsonEncode(authMessage));
        print('发送身份验证消息: $authMessage');

        // 创建连接对象
        final connection = P2PConnection(
          webSocket: webSocket,
          userId: userId,
          groupId: groupId,
          connectionId: connectionId,
        );

        _connections[connectionId] = connection;
        _lastHeartbeat[connectionId] = DateTime.now();

        // 启动心跳定时器
        _startClientHeartbeat(connectionId);

        webSocket.listen(
          (data) {
            _handleClientMessage(data, connectionId);
          },
          onDone: () {
            print('P2P连接断开: $connectionId');
            _handleConnectionDisconnect(connectionId, userId, groupId);
          },
          onError: (e) {
            print('P2P连接错误: $e');
            _handleConnectionDisconnect(connectionId, userId, groupId);
          },
        );

        print('P2P客户端连接成功: $ip:$targetPort (用户: $userId)');

        // 连接成功，清除重连计数
        final reconnectKey = '${userId}_$groupId';
        _reconnectAttempts.remove(reconnectKey);
        print('连接成功，清除重连计数: $reconnectKey');

        return true;
      } catch (e) {
        print('连接P2P服务器失败 ($ip:$targetPort): $e');
      }
    }

    print('所有连接尝试都失败了');
    return false;
  }

  /// 处理连接断开
  static void _handleConnectionDisconnect(
    String connectionId,
    String userId,
    String groupId,
  ) {
    print('处理连接断开: $connectionId (用户: $userId, 群组: $groupId)');

    // 移除连接
    _removeConnection(connectionId);

    // 检查重连次数限制
    final reconnectKey = '${userId}_$groupId';
    final currentAttempts = _reconnectAttempts[reconnectKey] ?? 0;

    if (currentAttempts >= _maxReconnectAttempts) {
      print('重连次数已达上限 ($_maxReconnectAttempts 次)，停止重连');
      print('用户 $userId 在群组 $groupId 中的重连尝试次数: $currentAttempts');

      // 清除重连计数
      _reconnectAttempts.remove(reconnectKey);

      // 通知应用连接断开，但不触发重连
      if (onConnectionDisconnect != null) {
        onConnectionDisconnect!(userId, groupId);
      }
      return;
    }

    // 增加重连次数
    _reconnectAttempts[reconnectKey] = currentAttempts + 1;
    print(
      '重连尝试次数: ${_reconnectAttempts[reconnectKey]} / $_maxReconnectAttempts',
    );

    // 通知应用连接断开，触发重连逻辑
    if (onConnectionDisconnect != null) {
      onConnectionDisconnect!(userId, groupId);
    }
  }

  /// 启动客户端心跳
  static void _startClientHeartbeat(String connectionId) {
    _connectionTimers[connectionId]?.cancel();
    _connectionTimers[connectionId] = Timer.periodic(_heartbeatInterval, (
      timer,
    ) {
      final connection = _connections[connectionId];
      if (connection != null) {
        final pingMessage = {
          'type': 'ping',
          'userId': connection.userId,
          'groupId': connection.groupId,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        };

        try {
          connection.webSocket.add(jsonEncode(pingMessage));
          final timestamp = pingMessage['timestamp'];
          if (timestamp != null && (timestamp as int) % 100 == 0) {
            print('发送心跳: ${connection.userId} -> ${connection.groupId}');
          }
        } catch (e) {
          print('发送心跳失败: $e');
          timer.cancel();
          _removeConnection(connectionId);
        }
      } else {
        timer.cancel();
      }
    });
  }

  /// 处理客户端消息
  static void _handleClientMessage(dynamic data, String connectionId) {
    try {
      final message = jsonDecode(data);
      if (message is Map<String, dynamic>) {
        final messageType = message['type'];
        if (messageType != 'pong') {
          print('收到服务器消息: $data');
        }
        if (messageType == 'pong') {
          // 处理心跳响应
          final connection = _connections[connectionId];
          if (connection != null) {
            connection.updateHeartbeat();
          }
        } else if (messageType == 'auth_failure') {
          // 处理认证失败
          final userId = message['userId'];
          final groupId = message['groupId'];
          final reason = message['reason'];
          print('认证失败: 用户=$userId, 群组=$groupId, 原因=$reason');

          // 移除连接
          _removeConnection(connectionId);

          // 设置群组状态为不可用
          _setGroupUnavailable(groupId);

          // 通知本地应用
          if (onMessage != null) {
            onMessage!(message);
          }
        } else {
          // 处理其他消息
          if (onMessage != null) {
            onMessage!(message);
          }
        }
      }
    } catch (e) {
      print('处理客户端消息失败: $e');
    }
  }

  /// 发送消息到所有连接的客户端
  static void broadcastMessage(Map<String, dynamic> message) {
    final messageStr = jsonEncode(message);
    print('广播消息: $messageStr');
    print('当前连接数: ${_connections.length}');

    for (var entry in _connections.entries) {
      try {
        final connection = entry.value;
        print('发送消息到连接: ${entry.key} (用户: ${connection.userId})');
        connection.webSocket.add(messageStr);
      } catch (e) {
        print('发送消息失败: $e');
        _removeConnection(entry.key);
      }
    }
  }

  /// 发送消息到特定用户
  static void sendMessageToUser(String userId, Map<String, dynamic> message) {
    final messageStr = jsonEncode(message);
    print('发送消息到用户: $userId');
    print('消息内容: $messageStr');

    // 查找该用户的连接
    final userConnection = _connections.values
        .where((conn) => conn.userId == userId)
        .firstOrNull;

    if (userConnection != null) {
      try {
        userConnection.webSocket.add(messageStr);
        print('消息已发送到用户: $userId');
      } catch (e) {
        print('发送消息到用户失败: $e');
        _removeConnection(userConnection.connectionId);
      }
    } else {
      print('用户 $userId 的连接未找到');
    }
  }

  /// 处理心跳消息
  static void _handlePingMessage(WebSocket webSocket) {
    final connection = _connections.values
        .where((conn) => conn.webSocket == webSocket)
        .firstOrNull;
    if (connection != null) {
      connection.updateHeartbeat();

      // 发送心跳响应
      final pongMessage = {
        'type': 'pong',
        'userId': connection.userId,
        'groupId': connection.groupId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      webSocket.add(jsonEncode(pongMessage));
    }
  }

  /// 获取群组详细信息
  static Future<Map<String, dynamic>?> _getGroupInfo(String groupId) async {
    try {
      // 使用GroupService来获取群组信息
      final groupService = GroupService();
      final group = await groupService.getGroup(groupId);

      if (group == null) {
        print('群组不存在: $groupId');
        return null;
      }

      // 构建群组信息
      final groupInfo = {
        'id': group.id,
        'name': group.name,
        'creatorId': group.creatorId,
        'createdAt': group.createdAt.toIso8601String(),
        'status': group.status.toString(),
        'sessionKey': {
          'key': group.sessionKey.key,
          'createdAt': group.sessionKey.createdAt.toIso8601String(),
          'expiresAt': group.sessionKey.expiresAt.toIso8601String(),
          'version': group.sessionKey.version,
        },
        'members': group.members
            .map(
              (member) => {
                'id': member.id,
                'userId': member.userId,
                'name': member.name,
                'publicKey': member.publicKey,
                'joinedAt': member.joinedAt.toIso8601String(),
                'lastSeen': member.lastSeen.toIso8601String(),
                'role': member.role.toString(),
                'status': member.status.toString(),
              },
            )
            .toList(),
      };

      print('群组信息获取成功: ${group.name} (${group.members.length} 个成员)');
      return groupInfo;
    } catch (e) {
      print('获取群组信息失败: $e');
      return null;
    }
  }

  /// 处理群组更新消息
  static void _handleGroupUpdateMessage(
    Map<String, dynamic> message,
    WebSocket webSocket,
  ) {
    final groupId = message['groupId'];
    print('收到群组更新消息: $groupId');

    // 处理群组更新逻辑
    if (onGroupUpdated != null) {
      onGroupUpdated!(groupId);
    }
  }

  /// 获取服务器地址信息（支持模拟器环境）
  static Future<Map<String, dynamic>> getServerInfo() async {
    final ip = await getLocalIP();
    print('服务器信息: $ip:$_port');

    return {'ip': ip, 'port': _port};
  }

  /// 检查服务器是否正在运行
  static bool isServerRunning() {
    return _server != null;
  }

  /// 获取服务器监听信息
  static Map<String, dynamic> getServerStatus() {
    if (_server == null) {
      return {'running': false, 'port': null, 'address': null};
    }

    return {
      'running': true,
      'port': _port,
      'address': _server!.address.address,
      'connections': _connections.length,
      'activeConnections': _connections.values
          .map(
            (conn) => {
              'userId': conn.userId,
              'groupId': conn.groupId,
              'lastHeartbeat': conn.lastHeartbeat.toIso8601String(),
            },
          )
          .toList(),
    };
  }

  /// 断开所有连接
  static void disconnect() {
    print('断开所有P2P连接');
    for (var connection in _connections.values) {
      connection.webSocket.close();
    }
    _connections.clear();
    _lastHeartbeat.clear();

    for (var timer in _connectionTimers.values) {
      timer.cancel();
    }
    _connectionTimers.clear();

    // 清理重连计数
    _reconnectAttempts.clear();
    print('重连计数已清理');
  }

  /// 测试P2P服务器连接
  static Future<bool> testConnection(String serverIP, int port) async {
    print('开始P2P连接测试...');
    print('目标服务器: $serverIP:$port');

    // 在模拟器环境中进行IP转换
    String targetIP = serverIP;
    int targetPort = port;

    // 如果目标IP是模拟器A的IP (10.0.2.15)，转换为主机地址和端口转发端口
    if (serverIP == '10.0.2.15') {
      print('检测到目标服务器是模拟器A，转换连接地址');
      print('原始地址: $serverIP:$port');
      targetIP = '10.0.2.2';
      targetPort = 8081; // 端口转发端口
      print('转换后地址: $targetIP:$targetPort');
    }

    // 先进行普通的TCP端口连接测试
    print('=== 开始TCP端口连接测试 ===');
    final tcpTestResult = await _testTcpConnection(targetIP, targetPort);
    if (!tcpTestResult) {
      print('TCP端口连接测试失败，无法进行WebSocket连接');
      return false;
    }
    print('TCP端口连接测试成功，开始WebSocket连接测试');

    // 然后进行WebSocket连接测试
    print('=== 开始WebSocket连接测试 ===');
    final testIPs = [targetIP];

    // 如果是localhost，也尝试127.0.0.1
    if (targetIP == 'localhost') {
      testIPs.add('127.0.0.1');
    }

    print('将尝试以下IP地址进行WebSocket连接: $testIPs');

    for (final ip in testIPs) {
      try {
        print('测试WebSocket连接到: $ip:$targetPort');
        print('端口类型: ${targetPort.runtimeType}');
        final uri = Uri.parse('ws://$ip:$targetPort');
        print('WebSocket URI: $uri');

        print('尝试建立WebSocket连接...');
        final webSocket = await WebSocket.connect(uri.toString());
        print('WebSocket连接建立成功');

        print('关闭测试连接...');
        webSocket.close();
        print('WebSocket连接测试成功: $ip:$targetPort');
        return true;
      } catch (e) {
        print('WebSocket连接测试失败 ($ip:$targetPort): $e');
        if (e.toString().contains('Connection refused')) {
          print('WebSocket连接被拒绝，可能的原因：');
          print('1. P2P服务器未启动');
          print('2. 端口号不正确');
          print('3. 防火墙阻止连接');
          print('4. 网络配置问题');
          print('5. 服务器不支持WebSocket协议');
          if (targetIP == '10.0.2.2' && targetPort == 8080) {
            print('6. 模拟器端口转发未设置');
            print('   请运行: adb -s emulator-5554 forward tcp:8080 tcp:36324');
          }
        } else if (e.toString().contains('timeout')) {
          print('WebSocket连接超时，可能的原因：');
          print('1. 网络延迟过高');
          print('2. 服务器响应慢');
          print('3. 网络不稳定');
        }
      }
    }

    print('所有WebSocket连接测试都失败了');
    print('建议检查：');
    print('1. 群组创建者是否已启动P2P服务器');
    print('2. 服务器IP地址是否正确');
    print('3. 端口号是否正确');
    print('4. 网络连接是否正常');
    print('5. 防火墙设置');
    print('6. 服务器是否支持WebSocket协议');
    if (targetIP == '10.0.2.2' && targetPort == 8080) {
      print('7. 模拟器端口转发设置');
      print('   群组创建者: adb -s emulator-5554 forward tcp:8080 tcp:36324');
    }
    return false;
  }

  /// 测试TCP端口连接
  static Future<bool> _testTcpConnection(String ip, int port) async {
    try {
      print('测试TCP连接到: $ip:$port');
      final socket = await Socket.connect(
        ip,
        port,
        timeout: Duration(seconds: 5),
      );
      print('TCP连接成功: $ip:$port');
      socket.destroy();
      return true;
    } catch (e) {
      print('TCP连接失败 ($ip:$port): $e');
      if (e.toString().contains('Connection refused')) {
        print('TCP连接被拒绝，可能的原因：');
        print('1. 目标端口没有服务监听');
        print('2. 端口号不正确');
        print('3. 防火墙阻止连接');
        print('4. 网络配置问题');
        if (ip == '10.0.2.2' && port == 8080) {
          print('5. 模拟器端口转发未设置');
          print('   请运行: adb -s emulator-5554 forward tcp:8080 tcp:36324');
        }
      } else if (e.toString().contains('timeout')) {
        print('TCP连接超时，可能的原因：');
        print('1. 网络延迟过高');
        print('2. 目标主机无响应');
        print('3. 网络不稳定');
      }
      return false;
    }
  }

  /// 测试端口号解析
  static void testPortParsing(String portStr) {
    try {
      final port = int.parse(portStr);
      print('端口解析成功: $port (类型: ${port.runtimeType})');
    } catch (e) {
      print('端口解析失败: $e');
    }
  }

  /// 设置群组状态为不可用
  static void _setGroupUnavailable(String groupId) async {
    try {
      print('设置群组状态为不可用: $groupId');

      // 获取群组服务实例
      final groupService = GroupService();

      // 加载群组
      final group = await groupService.getGroup(groupId);
      if (group != null) {
        // 设置群组状态为不可用
        final success = await groupService.setGroupUnavailable(group);
        if (success) {
          print('群组 $groupId 状态已设置为不可用');
        } else {
          print('设置群组 $groupId 状态失败');
        }
      } else {
        print('未找到群组: $groupId');
      }
    } catch (e) {
      print('设置群组状态失败: $e');
    }
  }

  /// 移除连接
  static void _removeConnection(String connectionId) {
    final connection = _connections[connectionId];
    if (connection != null) {
      print(
        '移除连接: $connectionId (用户: ${connection.userId}, 群组: ${connection.groupId})',
      );
      _connections.remove(connectionId);
      _lastHeartbeat.remove(connectionId);
      _connectionTimers[connectionId]?.cancel();
      _connectionTimers.remove(connectionId);
    }
  }

  /// 处理身份验证消息
  static void _handleAuthMessage(
    Map<String, dynamic> data,
    WebSocket webSocket,
  ) async {
    final userId = data['userId'] as String;
    final groupId = data['groupId'] as String;
    final connectionId = data['connectionId'] as String; // 使用客户端传递的连接ID
    final isNewMember = data['isNewMember'] as bool? ?? false;
    final timestamp = data['timestamp'] as int;

    print(
      '收到身份验证消息: 用户=$userId, 群组=$groupId, 连接ID=$connectionId, 是否新成员=$isNewMember',
    );

    // 检查是否已存在相同用户的连接
    final existingConnection = _connections.values
        .where((conn) => conn.userId == userId && conn.groupId == groupId)
        .firstOrNull;

    if (existingConnection != null) {
      print('已存在相同用户的连接，关闭旧连接: ${existingConnection.connectionId}');
      existingConnection.webSocket.close();
      _removeConnection(existingConnection.connectionId);
    }

    // 验证连接
    bool isValid = true;
    String failureReason = '';
    if (onConnectionValidate != null) {
      try {
        isValid = await onConnectionValidate!(userId, groupId, isNewMember);
        print('连接验证结果: $isValid');
        if (!isValid) {
          failureReason = '用户不是群组成员或群组状态无效';
        }
      } catch (e) {
        print('连接验证异常: $e');
        isValid = false;
        failureReason = '验证过程发生异常: $e';
      }
    }

    if (!isValid) {
      print('连接验证失败，发送认证失败响应: $connectionId');
      print('失败原因: $failureReason');

      // 发送认证失败响应，而不是主动断开连接
      final failureResponse = {
        'type': 'auth_failure',
        'connectionId': connectionId,
        'userId': userId,
        'groupId': groupId,
        'reason': failureReason,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      try {
        webSocket.add(jsonEncode(failureResponse));
        print('认证失败响应已发送，等待客户端断开连接');
      } catch (e) {
        print('发送认证失败响应失败: $e');
        // 如果发送失败，才主动断开连接
        webSocket.close();
      }
      return;
    }

    // 创建连接对象
    final connection = P2PConnection(
      webSocket: webSocket,
      userId: userId,
      groupId: groupId,
      connectionId: connectionId, // 使用客户端传递的连接ID
    );

    _connections[connectionId] = connection;
    _lastHeartbeat[connectionId] = DateTime.now();

    print('P2P连接建立成功: $connectionId (用户: $userId, 群组: $groupId)');

    // 发送验证成功响应
    final response = {
      'type': 'auth_success',
      'connectionId': connectionId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    webSocket.add(jsonEncode(response));

    // 如果是新成员，发送群组信息
    if (isNewMember) {
      print('新成员连接，准备发送群组信息');
      // 这里会由GroupService处理群组信息发送
    }

    // 启动心跳检测
    _startHeartbeatCheck();
  }

  /// 处理聊天消息
  static void _handleChatMessage(
    Map<String, dynamic> message,
    WebSocket webSocket,
  ) {
    // 转发消息给其他客户端
    final messageStr = jsonEncode(message);
    for (var entry in _connections.entries) {
      final connection = entry.value;
      if (connection.webSocket != webSocket) {
        try {
          print('转发消息到: ${entry.key} (用户: ${connection.userId})');
          connection.webSocket.add(messageStr);
        } catch (e) {
          print('转发消息失败: $e');
          _removeConnection(entry.key);
        }
      }
    }

    // 通知本地应用
    if (onMessageReceived != null) {
      onMessageReceived!(message);
    }
  }

  /// 处理成员加入消息
  static void _handleMemberJoinMessage(
    Map<String, dynamic> message,
    WebSocket webSocket,
  ) {
    print('收到成员加入消息: $message');

    // 转发消息给GroupService处理
    if (onMessage != null) {
      onMessage!(message);
    }
  }
}
