/// 서버와 주고받는 시그널링 메시지 모델.
/// type 필드로 분기하는 discriminated union — Dart sealed class 사용.
sealed class SignalingMessage {
  const SignalingMessage();

  factory SignalingMessage.fromJson(Map<String, dynamic> json) {
    return switch (json['type'] as String) {
      'room_created' => RoomCreatedMessage(
          roomId: json['roomId'] as String,
        ),
      'room_joined' => RoomJoinedMessage(
          roomId: json['roomId'] as String,
        ),
      'room_error' => RoomErrorMessage(
          message: json['message'] as String,
        ),
      'offer' => OfferMessage(
          roomId: json['roomId'] as String,
          sdp: Map<String, dynamic>.from(json['sdp'] as Map),
        ),
      'answer' => AnswerMessage(
          roomId: json['roomId'] as String,
          sdp: Map<String, dynamic>.from(json['sdp'] as Map),
        ),
      'candidate' => CandidateMessage(
          roomId: json['roomId'] as String,
          candidate: Map<String, dynamic>.from(json['candidate'] as Map),
        ),
      'peer_disconnected' => const PeerDisconnectedMessage(),
      final type => UnknownMessage(type: type),
    };
  }

  Map<String, dynamic> toJson();
}

// ── Client → Server ──────────────────────────────────────────────────────────

class CreateRoomMessage extends SignalingMessage {
  const CreateRoomMessage();

  @override
  Map<String, dynamic> toJson() => {'type': 'create_room'};
}

class JoinRoomMessage extends SignalingMessage {
  final String roomId;

  const JoinRoomMessage({required this.roomId});

  @override
  Map<String, dynamic> toJson() => {'type': 'join_room', 'roomId': roomId};
}

class OfferMessage extends SignalingMessage {
  final String roomId;

  /// { 'type': 'offer', 'sdp': '...' }
  final Map<String, dynamic> sdp;

  const OfferMessage({required this.roomId, required this.sdp});

  @override
  Map<String, dynamic> toJson() => {
        'type': 'offer',
        'roomId': roomId,
        'sdp': sdp,
      };
}

class AnswerMessage extends SignalingMessage {
  final String roomId;

  /// { 'type': 'answer', 'sdp': '...' }
  final Map<String, dynamic> sdp;

  const AnswerMessage({required this.roomId, required this.sdp});

  @override
  Map<String, dynamic> toJson() => {
        'type': 'answer',
        'roomId': roomId,
        'sdp': sdp,
      };
}

class CandidateMessage extends SignalingMessage {
  final String roomId;

  /// { 'candidate': '...', 'sdpMid': '0', 'sdpMLineIndex': 0 }
  final Map<String, dynamic> candidate;

  const CandidateMessage({required this.roomId, required this.candidate});

  @override
  Map<String, dynamic> toJson() => {
        'type': 'candidate',
        'roomId': roomId,
        'candidate': candidate,
      };
}

// ── Server → Client ──────────────────────────────────────────────────────────

class RoomCreatedMessage extends SignalingMessage {
  final String roomId;

  const RoomCreatedMessage({required this.roomId});

  @override
  Map<String, dynamic> toJson() => {'type': 'room_created', 'roomId': roomId};
}

class RoomJoinedMessage extends SignalingMessage {
  final String roomId;

  const RoomJoinedMessage({required this.roomId});

  @override
  Map<String, dynamic> toJson() => {'type': 'room_joined', 'roomId': roomId};
}

class RoomErrorMessage extends SignalingMessage {
  final String message;

  const RoomErrorMessage({required this.message});

  @override
  Map<String, dynamic> toJson() => {'type': 'room_error', 'message': message};
}

class PeerDisconnectedMessage extends SignalingMessage {
  const PeerDisconnectedMessage();

  @override
  Map<String, dynamic> toJson() => {'type': 'peer_disconnected'};
}

class UnknownMessage extends SignalingMessage {
  final String type;

  const UnknownMessage({required this.type});

  @override
  Map<String, dynamic> toJson() => {'type': type};
}
