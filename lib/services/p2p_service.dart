import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/group.dart';
import '../models/message.dart';
import '../models/user.dart';
import 'group_service.dart';
import '../utils/debug_logger.dart';

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

/// 连接事件类型
enum ConnectionEventType {
  connected,
  disconnected,
  messageReceived,
  error,
  heartbeat,
}

/// 连接状态
enum ConnectionStatus {
  connecting, // 连接中
  connected, // 已连接
  disconnected, // 已断开
  error, // 错误状态
}

/// 连接事件
class ConnectionEvent {
  final ConnectionEventType type;
  final String connectionId;
  final String userId;
  final String groupId;
  final DateTime timestamp;
  final String? error;

  ConnectionEvent({
    required this.type,
    required this.connectionId,
    required this.userId,
    required this.groupId,
    required this.timestamp,
    this.error,
  });
}

/// 网络消息类
class NetworkMessage {
  final String type;
  final String messageId;
  final String? groupId;
  final String senderId;
  final dynamic content;
  final DateTime timestamp;
  final Map<String, dynamic> metadata;

  // 消息类型常量
  static const String TYPE_JOIN_REQUEST = 'join_request';
  static const String TYPE_JOIN_RESPONSE = 'join_response';
  static const String TYPE_CHAT_MESSAGE = 'chat_message';
  static const String TYPE_HEARTBEAT = 'heartbeat';
  static const String TYPE_MEMBER_JOINED = 'member_joined';
  static const String TYPE_MEMBER_LEFT = 'member_left';
  static const String TYPE_GROUP_UPDATE = 'group_update';
  static const String TYPE_ERROR = 'error';

  NetworkMessage({
    required this.type,
    required this.messageId,
    this.groupId,
    required this.senderId,
    required this.content,
    required this.timestamp,
    Map<String, dynamic>? metadata,
  }) : metadata = metadata ?? {};

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'messageId': messageId,
      'groupId': groupId,
      'senderId': senderId,
      'content': content,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'metadata': metadata,
    };
  }

  factory NetworkMessage.fromJson(Map<String, dynamic> json) {
    return NetworkMessage(
      type: json['type'],
      messageId: json['messageId'],
      groupId: json['groupId'],
      senderId: json['senderId'],
      content: json['content'],
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp']),
      metadata: json['metadata'] ?? {},
    );
  }
}

/// 服务器信息类
class ServerInfo {
  final String serverIP;
  final int serverPort;
  final bool isRunning;
  final int connectionCount;
  final DateTime startTime;
  final Map<String, int> groupConnections;

  ServerInfo({
    required this.serverIP,
    required this.serverPort,
    required this.isRunning,
    required this.connectionCount,
    required this.startTime,
    required this.groupConnections,
  });

  Map<String, dynamic> toJson() {
    return {
      'serverIP': serverIP,
      'serverPort': serverPort,
      'isRunning': isRunning,
      'connectionCount': connectionCount,
      'startTime': startTime.millisecondsSinceEpoch,
      'groupConnections': groupConnections,
    };
  }
}

/// P2P连接类
class P2PConnection {
  final WebSocket webSocket;
  String userId; // 改为非final，允许后续设置
  String groupId; // 改为非final，允许后续设置
  final String connectionId;
  DateTime lastHeartbeat;
  ConnectionStatus status;

  // 连接统计
  int messageCount;
  DateTime connectedAt;
  String? lastError;

  P2PConnection({
    required this.webSocket,
    required this.userId,
    required this.groupId,
    required this.connectionId,
  }) : lastHeartbeat = DateTime.now(),
       status = ConnectionStatus.connecting,
       messageCount = 0,
       connectedAt = DateTime.now();

  void updateHeartbeat() {
    lastHeartbeat = DateTime.now();
  }

  bool isAlive() {
    // 检查连接状态
    if (status == ConnectionStatus.disconnected ||
        status == ConnectionStatus.error) {
      return false;
    }

    // 检查心跳时间（允许更长的超时时间）
    final heartbeatTimeout = Duration(seconds: 30);
    if (DateTime.now().difference(lastHeartbeat) > heartbeatTimeout) {
      DebugLogger().info('连接 ${connectionId} 心跳超时', tag: 'P2P');
      status = ConnectionStatus.error;
      return false;
    }

    return true;
  }

  bool sendMessage(String message) {
    try {
      if (status != ConnectionStatus.connected) {
        DebugLogger().info('连接 ${connectionId} 状态不正确: $status', tag: 'P2P');
        return false;
      }

      webSocket.add(message);
      messageCount++;
      updateHeartbeat(); // 发送消息时更新心跳
      return true;
    } catch (e) {
      lastError = e.toString();
      status = ConnectionStatus.error;
      DebugLogger().error('发送消息失败: $e', tag: 'P2P');
      return false;
    }
  }

  void close() {
    try {
      webSocket.close();
      status = ConnectionStatus.disconnected;
    } catch (e) {
      lastError = e.toString();
    }
  }
}

/// 消息路由器
class MessageRouter {
  static void broadcastToGroup(String groupId, Map<String, dynamic> message) {
    final messageStr = jsonEncode(message);
    final connections = P2PService.getConnectionsByGroup(groupId);
    final senderId = message['senderId'];

    DebugLogger().info(
      '广播消息到群组 $groupId，连接数: ${connections.length}，发送者: $senderId',
      tag: 'P2P',
    );

    // 检查是否有有效连接
    final aliveConnections = connections
        .where((conn) => conn.isAlive())
        .toList();
    if (aliveConnections.isEmpty) {
      DebugLogger().info('群组 $groupId 没有活跃连接，消息无法发送', tag: 'P2P');
      return;
    }

    for (final connection in aliveConnections) {
      // 在P2P架构中，所有连接都应该接收消息
      // 发送者自己的连接也需要接收消息，因为这是服务器端的连接
      // 消息去重机制会防止消息循环
      try {
        final success = connection.sendMessage(messageStr);
        if (!success) {
          DebugLogger().info(
            '发送消息到连接 ${connection.connectionId} 失败',
            tag: 'P2P',
          );
          P2PService.removeConnection(connection.connectionId);
        } else {
          DebugLogger().info(
            '消息发送成功到连接: ${connection.connectionId} (用户: ${connection.userId})',
            tag: 'P2P',
          );
        }
      } catch (e) {
        DebugLogger().error(
          '发送消息到连接 ${connection.connectionId} 出错: $e',
          tag: 'P2P',
        );
        P2PService.removeConnection(connection.connectionId);
      }
    }
  }

  static void sendToUser(
    String userId,
    String groupId,
    Map<String, dynamic> message,
  ) {
    final messageStr = jsonEncode(message);
    final connections = P2PService.getConnectionsByGroup(groupId);

    // 查找用户的活跃连接
    final userConnections = connections
        .where((conn) => conn.userId == userId && conn.isAlive())
        .toList();

    if (userConnections.isEmpty) {
      DebugLogger().info('用户 $userId 在群组 $groupId 中没有活跃连接', tag: 'P2P');
      return;
    }

    // 发送给用户的第一个活跃连接
    final connection = userConnections.first;
    try {
      final success = connection.sendMessage(messageStr);
      if (success) {
        DebugLogger().info(
          '消息发送成功到用户: $userId (连接: ${connection.connectionId})',
          tag: 'P2P',
        );
        return;
      } else {
        DebugLogger().info('发送消息到用户 $userId 失败', tag: 'P2P');
        P2PService.removeConnection(connection.connectionId);
      }
    } catch (e) {
      DebugLogger().error('发送消息到用户 $userId 出错: $e', tag: 'P2P');
      P2PService.removeConnection(connection.connectionId);
    }
  }

  static void routeMessage(Map<String, dynamic> message) {
    final messageType = message['type'];

    // 优先处理心跳消息，不取groupId
    if (messageType == NetworkMessage.TYPE_HEARTBEAT) {
      DebugLogger().info('收到心跳消息，直接处理', tag: 'P2P');
      _handleHeartbeat(message);
      return;
    }

    // 其他类型消息需要groupId
    final groupId = message['groupId'] as String?;
    DebugLogger().info('路由消息: type=$messageType, groupId=$groupId', tag: 'P2P');

    switch (messageType) {
      case NetworkMessage.TYPE_CHAT_MESSAGE:
        if (groupId != null && groupId.isNotEmpty) {
          broadcastToGroup(groupId, message);
        }
        break;
      case NetworkMessage.TYPE_JOIN_REQUEST:
        if (groupId != null && groupId.isNotEmpty) {
          _handleJoinRequest(message);
        }
        break;
      case NetworkMessage.TYPE_JOIN_RESPONSE:
        if (groupId != null && groupId.isNotEmpty) {
          final senderId = message['senderId'];
          if (senderId != null) {
            sendToUser(senderId, groupId, message);
          }
        }
        break;
      case NetworkMessage.TYPE_MEMBER_JOINED:
      case NetworkMessage.TYPE_MEMBER_LEFT:
        if (groupId != null && groupId.isNotEmpty) {
          broadcastToGroup(groupId, message);
        }
        break;
      case NetworkMessage.TYPE_GROUP_UPDATE:
        if (groupId != null && groupId.isNotEmpty) {
          broadcastToGroup(groupId, message);
        }
        break;
      default:
        DebugLogger().info('未知消息类型: $messageType', tag: 'P2P');
    }
  }

  static void _handleJoinRequest(Map<String, dynamic> message) {
    // 处理加入请求的逻辑
    final senderId = message['senderId'];
    final groupId = message['groupId'];
    DebugLogger().info('处理加入请求: $senderId -> $groupId', tag: 'P2P');
  }

  static void _handleHeartbeat(Map<String, dynamic> message) {
    // 处理心跳消息的逻辑 - 更新所有连接的心跳
    final connections = P2PService.getConnections();
    for (final connection in connections.values) {
      connection.updateHeartbeat();
    }
    DebugLogger().info('心跳消息处理成功，更新了 ${connections.length} 个连接的心跳', tag: 'P2P');
  }
}

/// 连接管理器
class ConnectionManager {
  static final Map<String, P2PConnection> _connections = {};
  static Timer? _heartbeatTimer;
  static Timer? _cleanupTimer;

  static void addConnection(P2PConnection connection) {
    _connections[connection.connectionId] = connection;
    connection.status = ConnectionStatus.connected;
    DebugLogger().info(
      '添加连接: ${connection.connectionId} (用户: ${connection.userId}, 群组: ${connection.groupId})',
      tag: 'P2P',
    );
  }

  static void removeConnection(String connectionId) {
    final connection = _connections.remove(connectionId);
    if (connection != null) {
      connection.close();
      DebugLogger().info('移除连接: $connectionId', tag: 'P2P');
    }
  }

  static P2PConnection? getConnection(String connectionId) {
    return _connections[connectionId];
  }

  static List<P2PConnection> getConnectionsByGroup(String groupId) {
    return _connections.values
        .where((connection) => connection.groupId == groupId)
        .toList();
  }

  static void startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      _sendHeartbeatToAll();
    });
  }

  static void _sendHeartbeatToAll() {
    final heartbeatMessage = NetworkMessage(
      type: NetworkMessage.TYPE_HEARTBEAT,
      messageId: _generateMessageId(),
      groupId: '0',
      senderId: '',
      content: null,
      timestamp: DateTime.now(),
    );

    final messageStr = jsonEncode(heartbeatMessage.toJson());

    for (final connection in _connections.values) {
      if (connection.isAlive()) {
        try {
          connection.sendMessage(messageStr);
        } catch (e) {
          DebugLogger().error(
            '发送心跳到 ${connection.connectionId} 失败: $e',
            tag: 'P2P',
          );
        }
      }
    }
  }

  static void startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(Duration(seconds: 60), (timer) {
      cleanupDeadConnections();
    });
  }

  static void cleanupDeadConnections() {
    final deadConnections = <String>[];

    for (final entry in _connections.entries) {
      final connection = entry.value;
      if (!connection.isAlive()) {
        deadConnections.add(entry.key);
        DebugLogger().info('标记死连接: ${connection.connectionId}', tag: 'P2P');
      }
    }

    for (final connectionId in deadConnections) {
      removeConnection(connectionId);
    }

    if (deadConnections.isNotEmpty) {
      DebugLogger().info('清理了 ${deadConnections.length} 个死连接', tag: 'P2P');
    }
  }

  static Map<String, P2PConnection> getConnections() {
    return Map.unmodifiable(_connections);
  }

  static int getConnectionCount() {
    return _connections.length;
  }

  static Map<String, int> getGroupConnections() {
    final groupConnections = <String, int>{};
    for (final connection in _connections.values) {
      groupConnections[connection.groupId] =
          (groupConnections[connection.groupId] ?? 0) + 1;
    }
    return groupConnections;
  }

  static String _generateMessageId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = Random().nextInt(1000000);
    return 'msg_${timestamp}_$random';
  }

  /// 断开并移除所有连接
  static void disconnectAllConnections() {
    final connectionIds = _connections.keys.toList();
    for (final connectionId in connectionIds) {
      final connection = _connections[connectionId];
      if (connection != null) {
        connection.close();
        DebugLogger().info('断开连接: $connectionId', tag: 'P2P');
      }
      _connections.remove(connectionId);
    }
    DebugLogger().info('已断开并清理所有P2P连接', tag: 'P2P');
  }
}

/// 网络工具类
class NetworkUtils {
  static Future<String> getLocalIP() async {
    try {
      DebugLogger().info('正在获取本地IP地址...', tag: 'NETWORK');
      for (var interface in await NetworkInterface.list()) {
        DebugLogger().debug('网络接口: ${interface.name}', tag: 'NETWORK');
        for (var addr in interface.addresses) {
          DebugLogger().debug(
            '  - ${addr.address} (${addr.type})',
            tag: 'NETWORK',
          );
          if (addr.type == InternetAddressType.IPv4 &&
              !addr.address.startsWith('127.')) {
            DebugLogger().info('选择IP地址: ${addr.address}', tag: 'NETWORK');
            return addr.address;
          }
        }
      }
    } catch (e) {
      DebugLogger().error('获取IP失败: $e', tag: 'NETWORK');
    }

    // 如果无法获取IP，使用localhost（适用于模拟器）
    DebugLogger().info('使用localhost地址: 127.0.0.1', tag: 'NETWORK');
    return '127.0.0.1';
  }

  static Future<int> getAvailablePort() async {
    // 查找可用端口
    for (int port = 36324; port < 36400; port++) {
      if (await isPortAvailable(port)) {
        DebugLogger().info('找到可用端口: $port', tag: 'NETWORK');
        return port;
      }
    }
    throw Exception('没有可用的端口');
  }

  static Future<bool> isPortAvailable(int port) async {
    try {
      final server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      await server.close();
      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> testConnection(String ip, int port) async {
    try {
      DebugLogger().info('开始连接测试: $ip:$port', tag: 'NETWORK');
      final socket = await Socket.connect(
        ip,
        port,
        timeout: Duration(seconds: 5),
      );
      await socket.close();
      DebugLogger().info('连接测试成功: $ip:$port', tag: 'NETWORK');
      return true;
    } catch (e) {
      DebugLogger().error('连接测试失败: $ip:$port - $e', tag: 'NETWORK');
      return false;
    }
  }

  static Future<bool> pingTest(String targetIP) async {
    try {
      DebugLogger().info('开始网络连通性测试: $targetIP', tag: 'NETWORK');
      final socket = await Socket.connect(
        targetIP,
        80,
        timeout: Duration(seconds: 3),
      );
      socket.destroy();
      DebugLogger().info('网络连通性测试成功: $targetIP', tag: 'NETWORK');
      return true;
    } catch (e) {
      DebugLogger().error('网络连通性测试失败: $targetIP - $e', tag: 'NETWORK');

      // 如果80端口失败，尝试其他常用端口
      final testPorts = [443, 22, 36324];
      for (final port in testPorts) {
        try {
          DebugLogger().info('尝试连接端口 $port 进行连通性测试...', tag: 'NETWORK');
          final socket = await Socket.connect(
            targetIP,
            port,
            timeout: Duration(seconds: 2),
          );
          socket.destroy();
          DebugLogger().info(
            '网络连通性测试成功: $targetIP (通过端口 $port)',
            tag: 'NETWORK',
          );
          return true;
        } catch (e) {
          DebugLogger().error('端口 $port 连通性测试失败: $e', tag: 'NETWORK');
        }
      }

      DebugLogger().info('所有端口连通性测试都失败，网络可能不通', tag: 'NETWORK');
      return false;
    }
  }
}

/// P2P服务主类
class P2PService {
  static HttpServer? _server;
  static String? _localIP;
  static int _port = 36324;
  static bool _isRunning = false;
  static DateTime? _startTime;

  // 事件控制器
  static final StreamController<ConnectionEvent> _eventController =
      StreamController<ConnectionEvent>.broadcast();
  static final StreamController<NetworkMessage> _messageController =
      StreamController<NetworkMessage>.broadcast();

  // 回调函数
  static MessageCallback? onMessageReceived;
  static GroupUpdateCallback? onGroupUpdated;
  static ConnectionValidator? onConnectionValidate;
  static ConnectionDisconnectCallback? onConnectionDisconnect;

  // 消息去重缓存 - 防止消息循环
  static final Set<String> _processedMessageIds = {};
  static const int _maxProcessedMessages = 1000;

  // 获取事件流
  static Stream<ConnectionEvent> get connectionEvents =>
      _eventController.stream;
  static Stream<NetworkMessage> get messageEvents => _messageController.stream;

  // 设置连接验证器
  static void setConnectionValidator(ConnectionValidator? validator) {
    onConnectionValidate = validator;
    DebugLogger().info(
      '连接验证器已设置: ${validator != null ? "启用" : "禁用"}',
      tag: 'P2P',
    );
  }

  // 获取本地IP地址
  static Future<String> getLocalIP() async {
    if (_localIP != null) return _localIP!;
    _localIP = await NetworkUtils.getLocalIP();
    return _localIP!;
  }

  /// 启动P2P服务器
  static Future<bool> startServer([int? port]) async {
    if (_isRunning) {
      DebugLogger().info('P2P服务器已经启动', tag: 'P2P');
      return true;
    }

    if (port != null) {
      _port = port;
    }

    try {
      DebugLogger().info('正在启动P2P服务器...', tag: 'P2P');
      DebugLogger().info('绑定地址: 0.0.0.0:$_port', tag: 'P2P');

      _server = await HttpServer.bind(InternetAddress.anyIPv4, _port);

      DebugLogger().info('P2P服务器启动成功，监听端口: $_port', tag: 'P2P');

      _server!.transform(WebSocketTransformer()).listen((WebSocket webSocket) {
        _handleNewConnection(webSocket);
      });

      // 启动连接管理
      ConnectionManager.startHeartbeat();
      ConnectionManager.startCleanupTimer();

      _isRunning = true;
      _startTime = DateTime.now();

      final serverIP = await getLocalIP();
      DebugLogger().info('P2P服务器启动成功: $serverIP:$_port', tag: 'P2P');
      return true;
    } catch (e) {
      DebugLogger().error('启动P2P服务器失败: $e', tag: 'P2P');
      return false;
    }
  }

  /// 停止P2P服务器
  static Future<void> stopServer() async {
    if (!_isRunning) {
      DebugLogger().info('P2P服务器未运行', tag: 'P2P');
      return;
    }

    try {
      DebugLogger().info('正在停止P2P服务器...', tag: 'P2P');

      // 关闭所有连接
      final connections = ConnectionManager.getConnections();
      for (final connection in connections.values) {
        connection.close();
      }

      // 停止定时器
      ConnectionManager._heartbeatTimer?.cancel();
      ConnectionManager._cleanupTimer?.cancel();

      // 关闭服务器
      await _server?.close();
      _server = null;

      _isRunning = false;
      _startTime = null;

      DebugLogger().info('P2P服务器已停止', tag: 'P2P');
    } catch (e) {
      DebugLogger().error('停止P2P服务器失败: $e', tag: 'P2P');
    }
  }

  /// 连接到P2P服务器
  static Future<bool> connectToServer(
    String serverIP,
    int port,
    String userId,
    String groupId,
  ) async {
    try {
      DebugLogger().info(
        '连接到P2P服务器: $serverIP:$port (用户: $userId, 群组: $groupId)',
        tag: 'P2P',
      );

      // 修复模拟器IP地址问题
      if (serverIP == '10.0.2.15') {
        // 这里是我为了模拟器网络设置的，不要变更这里的代码，否则会连接失败
        serverIP = '10.0.2.2';
        port = 8081;
      }

      DebugLogger().info('最终连接地址: $serverIP:$port', tag: 'P2P');
      final webSocket = await WebSocket.connect('ws://$serverIP:$port');

      final connectionId = _generateConnectionId();
      final connection = P2PConnection(
        webSocket: webSocket,
        userId: userId,
        groupId: groupId,
        connectionId: connectionId,
      );

      // 设置消息处理器
      webSocket.listen(
        (data) => _handleIncomingMessage(connection, data),
        onError: (error) => _handleConnectionError(connection, error),
        onDone: () => _handleConnectionDisconnect(connection),
      );

      // 发送连接初始化消息
      final initMessage = {
        'type': 'connection_init',
        'userId': userId,
        'groupId': groupId,
        'connectionId': connectionId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final initMessageStr = jsonEncode(initMessage);
      webSocket.add(initMessageStr);
      DebugLogger().info('发送连接初始化消息: $initMessageStr', tag: 'P2P');

      // 添加到连接管理器
      ConnectionManager.addConnection(connection);

      // 发送连接事件
      _eventController.add(
        ConnectionEvent(
          type: ConnectionEventType.connected,
          connectionId: connectionId,
          userId: userId,
          groupId: groupId,
          timestamp: DateTime.now(),
        ),
      );

      DebugLogger().info('成功连接到P2P服务器', tag: 'P2P');
      return true;
    } catch (e) {
      DebugLogger().error('连接P2P服务器失败: $e', tag: 'P2P');
      return false;
    }
  }

  /// 处理新连接
  static void _handleNewConnection(WebSocket webSocket) {
    final connectionId = _generateConnectionId();

    // 创建临时连接对象
    final connection = P2PConnection(
      webSocket: webSocket,
      userId: '',
      groupId: '',
      connectionId: connectionId,
    );

    // 设置消息处理器
    webSocket.listen(
      (data) => _handleIncomingMessage(connection, data),
      onError: (error) => _handleConnectionError(connection, error),
      onDone: () => _handleConnectionDisconnect(connection),
    );

    DebugLogger().info('新的WebSocket连接: $connectionId', tag: 'P2P');
  }

  /// 处理接收到的消息
  static void _handleIncomingMessage(P2PConnection connection, dynamic data) {
    try {
      final messageStr = data.toString();
      final messageData = jsonDecode(messageStr);

      DebugLogger().info('收到消息: ${messageData['type']}', tag: 'P2P');

      // 处理连接初始化消息
      if (messageData['type'] == 'connection_init') {
        connection.userId = messageData['userId'] ?? '';
        connection.groupId = messageData['groupId'] ?? '';
        connection.status = ConnectionStatus.connected;

        // 检查是否已存在相同用户的连接，如果存在则移除旧连接
        final existingConnections = ConnectionManager.getConnectionsByGroup(
          connection.groupId,
        );
        for (final existingConn in existingConnections) {
          if (existingConn.userId == connection.userId &&
              existingConn.connectionId != connection.connectionId) {
            DebugLogger().info(
              '发现重复连接，移除旧连接: ${existingConn.connectionId}',
              tag: 'P2P',
            );
            ConnectionManager.removeConnection(existingConn.connectionId);
          }
        }

        // 添加到连接管理器
        ConnectionManager.addConnection(connection);

        // 发送连接事件
        _eventController.add(
          ConnectionEvent(
            type: ConnectionEventType.connected,
            connectionId: connection.connectionId,
            userId: connection.userId,
            groupId: connection.groupId,
            timestamp: DateTime.now(),
          ),
        );

        DebugLogger().info(
          '连接已注册: ${connection.connectionId} (用户: ${connection.userId}, 群组: ${connection.groupId})',
          tag: 'P2P',
        );
        return;
      }

      // 更新连接信息（如果是第一次收到消息且不是初始化消息）
      if (connection.userId.isEmpty && messageData['userId'] != null) {
        connection.userId = messageData['userId'];
        connection.groupId = messageData['groupId'] ?? '';
        connection.status = ConnectionStatus.connected;

        // 检查是否已存在相同用户的连接，如果存在则移除旧连接
        final existingConnections = ConnectionManager.getConnectionsByGroup(
          connection.groupId,
        );
        for (final existingConn in existingConnections) {
          if (existingConn.userId == connection.userId &&
              existingConn.connectionId != connection.connectionId) {
            DebugLogger().info(
              '发现重复连接，移除旧连接: ${existingConn.connectionId}',
              tag: 'P2P',
            );
            ConnectionManager.removeConnection(existingConn.connectionId);
          }
        }

        // 添加到连接管理器
        ConnectionManager.addConnection(connection);

        // 发送连接事件
        _eventController.add(
          ConnectionEvent(
            type: ConnectionEventType.connected,
            connectionId: connection.connectionId,
            userId: connection.userId,
            groupId: connection.groupId,
            timestamp: DateTime.now(),
          ),
        );

        DebugLogger().info(
          '连接已注册: ${connection.connectionId} (用户: ${connection.userId}, 群组: ${connection.groupId})',
          tag: 'P2P',
        );
      }

      // 更新心跳
      connection.updateHeartbeat();

      // 检查消息是否已经处理过（防止消息循环）
      final messageId = messageData['messageId'];
      if (messageId != null && _processedMessageIds.contains(messageId)) {
        DebugLogger().info('消息已处理过，跳过: $messageId', tag: 'P2P');
        return;
      }

      // 添加到已处理消息列表
      if (messageId != null) {
        _processedMessageIds.add(messageId);

        // 清理过期的消息ID（保持缓存大小）
        if (_processedMessageIds.length > _maxProcessedMessages) {
          final toRemove = _processedMessageIds
              .take(_processedMessageIds.length - _maxProcessedMessages)
              .toList();
          for (final id in toRemove) {
            _processedMessageIds.remove(id);
          }
        }
      }

      // 路由消息
      DebugLogger().info(
        '准备路由消息: type=${messageData['type']}, groupId=${messageData['groupId']}',
        tag: 'P2P',
      );
      MessageRouter.routeMessage(messageData);

      // 发送消息事件
      try {
        final networkMessage = NetworkMessage.fromJson(messageData);
        _messageController.add(networkMessage);
      } catch (e) {
        DebugLogger().error('解析网络消息失败: $e', tag: 'P2P');
      }

      // 调用消息回调
      onMessageReceived?.call(messageData);
    } catch (e) {
      DebugLogger().error('p2p 处理接收消息失败: $e', tag: 'P2P');
    }
  }

  /// 处理连接错误
  static void _handleConnectionError(P2PConnection connection, dynamic error) {
    DebugLogger().error(
      '连接错误: ${connection.connectionId} - $error',
      tag: 'P2P',
    );
    connection.status = ConnectionStatus.error;
    connection.lastError = error.toString();

    _eventController.add(
      ConnectionEvent(
        type: ConnectionEventType.error,
        connectionId: connection.connectionId,
        userId: connection.userId,
        groupId: connection.groupId,
        timestamp: DateTime.now(),
        error: error.toString(),
      ),
    );
  }

  /// 处理连接断开
  static void _handleConnectionDisconnect(P2PConnection connection) {
    DebugLogger().info('连接断开: ${connection.connectionId}', tag: 'P2P');
    connection.status = ConnectionStatus.disconnected;

    // 调用断开回调
    onConnectionDisconnect?.call(connection.userId, connection.groupId);

    // 从连接管理器中移除
    ConnectionManager.removeConnection(connection.connectionId);

    _eventController.add(
      ConnectionEvent(
        type: ConnectionEventType.disconnected,
        connectionId: connection.connectionId,
        userId: connection.userId,
        groupId: connection.groupId,
        timestamp: DateTime.now(),
      ),
    );

    // 检查群组是否还有其他连接
    if (connection.groupId.isNotEmpty) {
      final remainingConnections = ConnectionManager.getConnectionsByGroup(
        connection.groupId,
      );
      DebugLogger().info(
        '群组 ${connection.groupId} 剩余连接数: ${remainingConnections.length}',
        tag: 'P2P',
      );
    }
  }

  /// 广播消息
  static void broadcastMessage(Map<String, dynamic> message) {
    final groupId = message['groupId'];
    if (groupId != null && groupId.isNotEmpty) {
      MessageRouter.broadcastToGroup(groupId, message);
    } else {
      DebugLogger().info('消息缺少groupId字段或groupId为空，无法广播', tag: 'P2P');
    }
  }

  /// 发送消息给指定用户
  static void sendToUser(
    String userId,
    String groupId,
    Map<String, dynamic> message,
  ) {
    MessageRouter.sendToUser(userId, groupId, message);
  }

  /// 获取连接
  static P2PConnection? getConnection(String connectionId) {
    return ConnectionManager.getConnection(connectionId);
  }

  /// 获取群组连接
  static List<P2PConnection> getConnectionsByGroup(String groupId) {
    return ConnectionManager.getConnectionsByGroup(groupId);
  }

  /// 移除连接
  static void removeConnection(String connectionId) {
    ConnectionManager.removeConnection(connectionId);
  }

  /// 获取所有连接
  static Map<String, P2PConnection> getConnections() {
    return ConnectionManager.getConnections();
  }

  /// 获取连接数量
  static int getConnectionCount() {
    return ConnectionManager.getConnectionCount();
  }

  /// 获取服务器信息
  static Future<Map<String, dynamic>> getServerInfo() async {
    final serverIP = await getLocalIP();
    final groupConnections = ConnectionManager.getGroupConnections();

    return {
      'ip': serverIP,
      'port': _port,
      'isRunning': _isRunning,
      'connectionCount': getConnectionCount(),
      'startTime': _startTime?.millisecondsSinceEpoch,
      'groupConnections': groupConnections,
    };
  }

  /// 获取服务器状态
  static Map<String, dynamic> getServerStatus() {
    final groupConnections = ConnectionManager.getGroupConnections();

    return {
      'isRunning': _isRunning,
      'port': _port,
      'connectionCount': getConnectionCount(),
      'groupConnections': groupConnections,
      'startTime': _startTime?.millisecondsSinceEpoch,
    };
  }

  /// 测试连接
  static Future<bool> testConnection(String targetIP, int port) async {
    return NetworkUtils.testConnection(targetIP, port);
  }

  /// 网络连通性测试
  static Future<bool> pingTest(String targetIP) async {
    return NetworkUtils.pingTest(targetIP);
  }

  /// 生成连接ID
  static String _generateConnectionId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = Random().nextInt(10000);
    return 'conn_${timestamp}_$random';
  }
}
