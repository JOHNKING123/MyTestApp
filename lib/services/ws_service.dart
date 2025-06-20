import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

class WSService {
  WebSocketChannel? _channel;
  Function(Map<String, dynamic>)? onMessage;
  bool get isConnected => _channel != null;

  void connect(String url) {
    if (_channel != null) return;
    _channel = WebSocketChannel.connect(Uri.parse(url));
    _channel!.stream.listen(
      (data) {
        try {
          final msg = jsonDecode(data);
          if (onMessage != null && msg is Map<String, dynamic>) {
            onMessage!(msg);
          }
        } catch (e) {
          // ignore
        }
      },
      onDone: () {
        _channel = null;
      },
      onError: (e) {
        _channel = null;
      },
    );
  }

  void send(Map<String, dynamic> data) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode(data));
    }
  }

  void disconnect() {
    _channel?.sink.close(status.goingAway);
    _channel = null;
  }
}
