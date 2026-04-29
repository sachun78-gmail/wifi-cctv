import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:wifi_cctv/models/signaling_message.dart';

class SignalingService {
  SignalingService({WebSocketChannel Function(Uri)? channelFactory})
      : _channelFactory = channelFactory ?? WebSocketChannel.connect;

  final WebSocketChannel Function(Uri) _channelFactory;
  WebSocketChannel? _channel;
  final _messageController = StreamController<SignalingMessage>.broadcast();
  // WebSocket 연결이 끊어질 때(서버 종료, WiFi 단절 등) 이벤트를 발행.
  // ViewModel이 구독해 자동 재연결 로직을 시작한다.
  // broadcast(): 여러 구독자를 허용 — ViewModel에서 한 번, 테스트에서 한 번 구독 가능.
  final _closedController = StreamController<void>.broadcast();

  Stream<SignalingMessage> get messages => _messageController.stream;
  Stream<void> get onClosed => _closedController.stream;

  bool get isConnected => _channel != null;

  /// [url] 예: 'ws://192.168.0.100:9090'
  /// [timeout] WebSocket 핸드셰이크 최대 대기 시간 (기본 10초).
  ///           초과 시 TimeoutException 발생 — ViewModel에서 ConnectionTimeout으로 변환한다.
  Future<void> connect(
    String url, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    _channel = _channelFactory(Uri.parse(url));
    // timeout(): Future가 지정 시간 내 완료되지 않으면 TimeoutException을 던진다.
    // 잘못된 IP나 방화벽으로 인해 응답이 없을 때 무한 대기를 방지한다.
    await _channel!.ready.timeout(timeout);

    _channel!.stream.listen(
      (data) {
        try {
          final json = jsonDecode(data as String) as Map<String, dynamic>;
          _messageController.add(SignalingMessage.fromJson(json));
        } on FormatException catch (e) {
          _messageController.addError(e);
        }
      },
      onError: _messageController.addError,
      // _handleClosed: 서버 연결 종료를 ViewModel에 알림.
      // 기존 disconnect()만 호출하던 것과 달리, onClosed 이벤트를 발행해 재연결 로직을 트리거한다.
      onDone: _handleClosed,
    );
  }

  void _handleClosed() {
    _channel = null;
    // 연결 종료 이벤트 발행 — 서버 종료, WiFi 단절 등 모든 원인에 공통 처리
    if (!_closedController.isClosed) {
      _closedController.add(null);
    }
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
    _closedController.close();
  }
}
