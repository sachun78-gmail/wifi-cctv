import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:wifi_cctv/models/signaling_message.dart';
import 'package:wifi_cctv/services/signaling_service.dart';

/// 테스트용 인메모리 WebSocketChannel.
/// [inbound]: 서버→클라이언트 방향으로 보낼 데이터를 주입하는 컨트롤러.
/// [outbound]: 클라이언트가 send()한 데이터를 수집하는 스트림.
class _FakeChannel extends Fake implements WebSocketChannel {
  _FakeChannel({
    required this.inbound,
    required StreamController<Object?> outboundController,
  }) : _outboundController = outboundController;

  final StreamController<Object?> inbound;
  final StreamController<Object?> _outboundController;

  @override
  Stream<Object?> get stream => inbound.stream;

  @override
  WebSocketSink get sink => _FakeSink(_outboundController);

  @override
  Future<void> get ready => Future.value();
}

class _FakeSink extends Fake implements WebSocketSink {
  _FakeSink(this._controller);
  final StreamController<Object?> _controller;

  @override
  void add(Object? data) => _controller.add(data);

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    await _controller.close();
  }
}

void main() {
  late StreamController<Object?> inbound;
  late StreamController<Object?> outbound;
  late SignalingService service;

  setUp(() {
    inbound = StreamController<Object?>();
    outbound = StreamController<Object?>();

    service = SignalingService(
      channelFactory: (_) => _FakeChannel(
        inbound: inbound,
        outboundController: outbound,
      ),
    );
  });

  tearDown(() {
    service.dispose();
  });

  group('SignalingService.connect', () {
    test('connect 후 isConnected == true', () async {
      await service.connect('ws://localhost:9090');
      expect(service.isConnected, isTrue);
    });
  });

  group('SignalingService.disconnect', () {
    test('disconnect 후 isConnected == false', () async {
      await service.connect('ws://localhost:9090');
      service.disconnect();
      expect(service.isConnected, isFalse);
    });
  });

  group('SignalingService.send', () {
    test('send → 채널에 JSON 전송', () async {
      await service.connect('ws://localhost:9090');

      final received = <Object?>[];
      outbound.stream.listen(received.add);

      service.send(const CreateRoomMessage());

      await Future<void>.delayed(Duration.zero);
      expect(received, hasLength(1));
      final decoded = jsonDecode(received.first! as String) as Map<String, dynamic>;
      expect(decoded['type'], 'create_room');
    });

    test('send(JoinRoomMessage) → roomId 포함', () async {
      await service.connect('ws://localhost:9090');

      final received = <Object?>[];
      outbound.stream.listen(received.add);

      service.send(const JoinRoomMessage(roomId: '123456'));

      await Future<void>.delayed(Duration.zero);
      final decoded = jsonDecode(received.first! as String) as Map<String, dynamic>;
      expect(decoded['type'], 'join_room');
      expect(decoded['roomId'], '123456');
    });
  });

  group('SignalingService.messages', () {
    test('서버에서 room_created 수신 → 스트림으로 emit', () async {
      await service.connect('ws://localhost:9090');

      final future = service.messages.first;
      inbound.add(jsonEncode({'type': 'room_created', 'roomId': 'ABCD99'}));

      final msg = await future;
      expect(msg, isA<RoomCreatedMessage>());
      expect((msg as RoomCreatedMessage).roomId, 'ABCD99');
    });

    test('서버에서 room_joined 수신 → 스트림으로 emit', () async {
      await service.connect('ws://localhost:9090');

      final future = service.messages.first;
      inbound.add(jsonEncode({'type': 'room_joined', 'roomId': '999999'}));

      final msg = await future;
      expect(msg, isA<RoomJoinedMessage>());
    });

    test('서버에서 peer_disconnected 수신 → 스트림으로 emit', () async {
      await service.connect('ws://localhost:9090');

      final future = service.messages.first;
      inbound.add(jsonEncode({'type': 'peer_disconnected'}));

      final msg = await future;
      expect(msg, isA<PeerDisconnectedMessage>());
    });

    test('잘못된 JSON 수신 → 스트림 에러 발생', () async {
      await service.connect('ws://localhost:9090');

      final errorFuture = service.messages.first.catchError((_) => const PeerDisconnectedMessage() as SignalingMessage);
      service.messages.listen(null, onError: (_) {});

      inbound.add('not valid json{{{{');

      // 에러가 발생해도 앱이 크래시되지 않음을 확인
      await expectLater(
        service.messages,
        emitsError(isA<FormatException>()),
      );
    });
  });
}
