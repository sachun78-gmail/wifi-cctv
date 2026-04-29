/// 연결/통신 과정에서 발생할 수 있는 에러를 분류한 sealed class.
///
/// sealed class를 사용하면 switch 문에서 exhaustive check(모든 케이스 강제)가 적용된다.
/// 새 에러 타입을 추가했을 때 처리 누락을 컴파일 시점에 발견할 수 있어 안전하다.
///
/// View에서는 switch expression으로 에러 유형별 한국어 메시지·아이콘·액션을 각각 제공한다.
/// ViewModel에서는 catch한 예외를 이 타입으로 변환하여 UI와 에러 분류를 분리한다.
sealed class ConnectionError {
  const ConnectionError();
}

/// 네트워크에 도달할 수 없음 — 잘못된 IP, 방화벽 차단, 서버 미기동 등
class NetworkUnreachable extends ConnectionError {
  const NetworkUnreachable();
}

/// 연결 시도 타임아웃 — IP는 유효하지만 지정 시간(10초) 내 응답 없음
class ConnectionTimeout extends ConnectionError {
  const ConnectionTimeout();
}

/// 협상 단계 타임아웃 — 방 참여 후 카메라로부터 Offer가 오지 않음 (뷰어 전용)
class NegotiationTimeout extends ConnectionError {
  const NegotiationTimeout();
}

/// 존재하지 않는 방 ID
class RoomNotFound extends ConnectionError {
  const RoomNotFound();
}

/// 방이 가득 참 — 이미 뷰어가 참여 중
class RoomFull extends ConnectionError {
  const RoomFull();
}

/// 카메라 또는 마이크 권한 거부
class MediaPermissionDenied extends ConnectionError {
  const MediaPermissionDenied();
}

/// ICE 협상 실패 — P2P 네트워크 경로를 찾지 못함
class IceFailed extends ConnectionError {
  const IceFailed();
}

/// 상대방(카메라/뷰어)이 연결을 끊음
class PeerDisconnected extends ConnectionError {
  const PeerDisconnected();
}

/// 시그널링 서버 연결 끊김 — 서버 종료, WiFi 단절 등
class ServerClosed extends ConnectionError {
  const ServerClosed();
}

/// 분류되지 않은 에러 — 메시지를 포함해 디버깅에 활용
class UnknownConnectionError extends ConnectionError {
  const UnknownConnectionError(this.message);
  final String message;
}
