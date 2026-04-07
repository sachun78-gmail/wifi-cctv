import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_cctv/models/signaling_message.dart';

void main() {
  group('SignalingMessage.fromJson', () {
    test('room_created', () {
      final msg = SignalingMessage.fromJson({
        'type': 'room_created',
        'roomId': '123456',
      });
      expect(msg, isA<RoomCreatedMessage>());
      expect((msg as RoomCreatedMessage).roomId, '123456');
    });

    test('room_joined', () {
      final msg = SignalingMessage.fromJson({
        'type': 'room_joined',
        'roomId': '654321',
      });
      expect(msg, isA<RoomJoinedMessage>());
      expect((msg as RoomJoinedMessage).roomId, '654321');
    });

    test('room_error', () {
      final msg = SignalingMessage.fromJson({
        'type': 'room_error',
        'message': '존재하지 않는 방입니다.',
      });
      expect(msg, isA<RoomErrorMessage>());
      expect((msg as RoomErrorMessage).message, '존재하지 않는 방입니다.');
    });

    test('offer', () {
      final msg = SignalingMessage.fromJson({
        'type': 'offer',
        'roomId': '111111',
        'sdp': {'type': 'offer', 'sdp': 'v=0...'},
      });
      expect(msg, isA<OfferMessage>());
      final offer = msg as OfferMessage;
      expect(offer.roomId, '111111');
      expect(offer.sdp['type'], 'offer');
      expect(offer.sdp['sdp'], 'v=0...');
    });

    test('answer', () {
      final msg = SignalingMessage.fromJson({
        'type': 'answer',
        'roomId': '222222',
        'sdp': {'type': 'answer', 'sdp': 'v=0...'},
      });
      expect(msg, isA<AnswerMessage>());
      final answer = msg as AnswerMessage;
      expect(answer.roomId, '222222');
      expect(answer.sdp['type'], 'answer');
    });

    test('candidate', () {
      final msg = SignalingMessage.fromJson({
        'type': 'candidate',
        'roomId': '333333',
        'candidate': {
          'candidate': 'candidate:...',
          'sdpMid': '0',
          'sdpMLineIndex': 0,
        },
      });
      expect(msg, isA<CandidateMessage>());
      final cand = msg as CandidateMessage;
      expect(cand.roomId, '333333');
      expect(cand.candidate['sdpMid'], '0');
      expect(cand.candidate['sdpMLineIndex'], 0);
    });

    test('peer_disconnected', () {
      final msg = SignalingMessage.fromJson({'type': 'peer_disconnected'});
      expect(msg, isA<PeerDisconnectedMessage>());
    });

    test('알 수 없는 type → UnknownMessage', () {
      final msg = SignalingMessage.fromJson({'type': 'something_new'});
      expect(msg, isA<UnknownMessage>());
      expect((msg as UnknownMessage).type, 'something_new');
    });
  });

  group('SignalingMessage.toJson', () {
    test('create_room', () {
      expect(
        const CreateRoomMessage().toJson(),
        {'type': 'create_room'},
      );
    });

    test('join_room', () {
      expect(
        const JoinRoomMessage(roomId: '123456').toJson(),
        {'type': 'join_room', 'roomId': '123456'},
      );
    });

    test('offer', () {
      final sdp = {'type': 'offer', 'sdp': 'v=0...'};
      final json = OfferMessage(roomId: '111111', sdp: sdp).toJson();
      expect(json['type'], 'offer');
      expect(json['roomId'], '111111');
      expect(json['sdp'], sdp);
    });

    test('answer', () {
      final sdp = {'type': 'answer', 'sdp': 'v=0...'};
      final json = AnswerMessage(roomId: '222222', sdp: sdp).toJson();
      expect(json['type'], 'answer');
      expect(json['roomId'], '222222');
      expect(json['sdp'], sdp);
    });

    test('candidate', () {
      final candidate = {
        'candidate': 'candidate:...',
        'sdpMid': '0',
        'sdpMLineIndex': 0,
      };
      final json = CandidateMessage(roomId: '333333', candidate: candidate).toJson();
      expect(json['type'], 'candidate');
      expect(json['roomId'], '333333');
      expect(json['candidate'], candidate);
    });
  });

  group('SignalingMessage 라운드트립 (toJson → fromJson)', () {
    test('offer', () {
      final original = OfferMessage(
        roomId: '123456',
        sdp: {'type': 'offer', 'sdp': 'v=0...'},
      );
      final restored = SignalingMessage.fromJson(original.toJson()) as OfferMessage;
      expect(restored.roomId, original.roomId);
      expect(restored.sdp, original.sdp);
    });

    test('answer', () {
      final original = AnswerMessage(
        roomId: '654321',
        sdp: {'type': 'answer', 'sdp': 'v=0...'},
      );
      final restored = SignalingMessage.fromJson(original.toJson()) as AnswerMessage;
      expect(restored.roomId, original.roomId);
      expect(restored.sdp, original.sdp);
    });

    test('candidate', () {
      final original = CandidateMessage(
        roomId: '111111',
        candidate: {
          'candidate': 'candidate:...',
          'sdpMid': '0',
          'sdpMLineIndex': 0,
        },
      );
      final restored =
          SignalingMessage.fromJson(original.toJson()) as CandidateMessage;
      expect(restored.roomId, original.roomId);
      expect(restored.candidate, original.candidate);
    });

    test('join_room', () {
      final original = const JoinRoomMessage(roomId: '999999');
      final restored =
          SignalingMessage.fromJson(original.toJson()) as JoinRoomMessage;
      expect(restored.roomId, original.roomId);
    });
  });
}
