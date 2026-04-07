import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/signaling_message.dart';

class SignalingService {
  WebSocketChannel? _channel;
  final _messageController = StreamController<SignalingMessage>.broadcast();

  Stream<SignalingMessage> get messages => _messageController.stream;

  bool get isConnected => _channel != null;

  /// [url] 예: 'ws://192.168.0.100:9090'
  Future<void> connect(String url) async {
    _channel = WebSocketChannel.connect(Uri.parse(url));
    await _channel!.ready;

    _channel!.stream.listen(
      (data) {
        try {
          final json = jsonDecode(data as String) as Map<String, dynamic>;
          _messageController.add(SignalingMessage.fromJson(json));
        } catch (e) {
          _messageController.addError(e);
        }
      },
      onError: _messageController.addError,
      onDone: disconnect,
    );
  }

  void send(SignalingMessage message) {
    _channel?.sink.add(jsonEncode(message.toJson()));
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    disconnect();
    _messageController.close();
  }
}
