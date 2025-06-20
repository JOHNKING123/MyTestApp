import 'dart:convert';
import 'dart:io';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/group.dart';
import '../models/message.dart';

class P2PService {
  static HttpServer? _server;
  static Map<String, WebSocket> _connections = {};
  static Function(Map<String, dynamic>)? onMessage;
  static String? _localIP;
  static int _port = 8080;

  // 获取本地IP地址
  static Future<String> getLocalIP() async {
    if (_localIP != null) return _localIP!;

    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 &&
              !addr.address.startsWith('127.')) {
            _localIP = addr.address;
            return _localIP!;
          }
        }
      }
    } catch (e) {
      print('获取IP失败: $e');
    }
    return '127.0.0.1';
  }

  /// 启动P2P服务器（群组创建者调用）
  static Future<bool> startServer() async {
    if (_server != null) return true;

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
      _server!.transform(WebSocketTransformer()).listen((WebSocket webSocket) {
        final connectionId = webSocket.hashCode.toString();
        _connections[connectionId] = webSocket;

        webSocket.listen(
          (data) {
            _handleMessage(data, webSocket);
          },
          onDone: () {
            _connections.remove(connectionId);
          },
          onError: (e) {
            print('WebSocket错误: $e');
            _connections.remove(connectionId);
          },
        );
      });

      print('P2P服务器启动成功: ${await getLocalIP()}:$_port');
      return true;
    } catch (e) {
      print('启动P2P服务器失败: $e');
      return false;
    }
  }

  /// 停止P2P服务器
  static void stopServer() {
    _server?.close();
    _server = null;
    for (var ws in _connections.values) {
      ws.close();
    }
    _connections.clear();
  }

  /// 连接到P2P服务器（群组成员调用）
  static Future<bool> connectToServer(String serverIP, int port) async {
    try {
      final uri = Uri.parse('ws://$serverIP:$port');
      final webSocket = await WebSocket.connect(uri.toString());

      webSocket.listen(
        (data) {
          if (onMessage != null) {
            try {
              final msg = jsonDecode(data);
              if (msg is Map<String, dynamic>) {
                onMessage!(msg);
              }
            } catch (e) {
              print('解析消息失败: $e');
            }
          }
        },
        onDone: () {
          print('P2P连接断开');
        },
        onError: (e) {
          print('P2P连接错误: $e');
        },
      );

      _connections['client'] = webSocket;
      return true;
    } catch (e) {
      print('连接P2P服务器失败: $e');
      return false;
    }
  }

  /// 发送消息到所有连接的客户端
  static void broadcastMessage(Map<String, dynamic> message) {
    final messageStr = jsonEncode(message);
    for (var webSocket in _connections.values) {
      try {
        webSocket.add(messageStr);
      } catch (e) {
        print('发送消息失败: $e');
      }
    }
  }

  /// 处理接收到的消息
  static void _handleMessage(dynamic data, WebSocket sender) {
    try {
      final message = jsonDecode(data);
      if (message is Map<String, dynamic>) {
        // 转发消息给其他客户端
        final messageStr = jsonEncode(message);
        for (var entry in _connections.entries) {
          if (entry.value != sender) {
            try {
              entry.value.add(messageStr);
            } catch (e) {
              print('转发消息失败: $e');
            }
          }
        }

        // 通知本地应用
        if (onMessage != null) {
          onMessage!(message);
        }
      }
    } catch (e) {
      print('处理消息失败: $e');
    }
  }

  /// 获取服务器地址信息
  static Future<Map<String, dynamic>> getServerInfo() async {
    return {'ip': await getLocalIP(), 'port': _port};
  }

  /// 断开所有连接
  static void disconnect() {
    for (var webSocket in _connections.values) {
      webSocket.close();
    }
    _connections.clear();
  }
}
