import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:wifi_cctv/models/connection_error.dart';
import 'package:wifi_cctv/models/signaling_message.dart';
import 'package:wifi_cctv/services/signaling_service.dart';
import 'package:wifi_cctv/services/webrtc_service.dart';
import 'package:wifi_cctv/utils/constants.dart';

// ══════════════════════════════════════════════════════════════════════════════
// State (상태 데이터)
// ══════════════════════════════════════════════════════════════════════════════

/// 뷰어 모드의 연결 단계를 나타내는 열거형.
///
/// CameraConnectionState와 대칭 구조이지만 역할이 다르다.
/// - 카메라: 방을 만들고 Offer를 보내는 쪽
/// - 뷰어: 방에 참여하고 Answer를 보내는 쪽
enum ViewerConnectionState {
  idle, // 초기 상태 — 방 ID 입력 전
  connecting, // 시그널링 서버에 WebSocket 연결 중 (초기 연결 또는 재연결)
  waitingForOffer, // 방 참여 완료, 카메라의 Offer 대기 중
  streaming, // WebRTC P2P 연결 완료, 영상 수신 중
  error, // 에러 발생 — error 필드에 구체적인 유형 저장
}

/// ViewerViewModel이 관리하는 전체 상태.
///
/// 불변(immutable) 설계 — 값을 바꿀 때는 copyWith()로 새 객체를 생성해 교체한다.
class ViewerState {
  const ViewerState({
    this.connectionState = ViewerConnectionState.idle,
    this.roomId,
    this.error,
  });

  final ViewerConnectionState connectionState;
  final String? roomId; // 참여한 방의 ID
  // ConnectionError: sealed class로 에러 유형 구조화.
  // camera_viewmodel.dart의 CameraState와 동일한 패턴.
  final ConnectionError? error;

  /// ConnectionError를 한국어 문자열로 변환하는 편의 getter.
  ///
  /// sealed class + switch expression 패턴 — exhaustive check 적용.
  /// View에서 switch(error)로 직접 분기하면 아이콘/버튼 등 더 세밀한 UI 구현이 가능하다.
  String? get errorMessage => switch (error) {
        null => null,
        NetworkUnreachable() => '서버에 연결할 수 없습니다. IP와 방화벽을 확인하세요.',
        ConnectionTimeout() => '연결 시간이 초과됐습니다. 서버 IP를 확인하세요.',
        NegotiationTimeout() => '카메라 응답을 기다리다 시간이 초과됐습니다 (30초).',
        RoomNotFound() => '존재하지 않는 방 번호입니다.',
        RoomFull() => '이미 뷰어가 참여 중입니다.',
        MediaPermissionDenied() => '카메라 또는 마이크 권한이 필요합니다.',
        IceFailed() => 'P2P 연결에 실패했습니다. 같은 WiFi인지 확인하세요.',
        PeerDisconnected() => '카메라가 연결을 종료했습니다.',
        ServerClosed() => '서버와의 연결이 끊어졌습니다.',
        UnknownConnectionError(:final message) => '오류: $message',
      };

  /// 일부 필드만 바꾼 새 ViewerState를 반환.
  ///
  /// null을 명시적으로 지우고 싶은 경우(error, roomId 초기화)는
  /// 직접 ViewerState() 생성자를 호출하는 방식으로 처리한다.
  ViewerState copyWith({
    ViewerConnectionState? connectionState,
    String? roomId,
    ConnectionError? error,
  }) {
    return ViewerState(
      connectionState: connectionState ?? this.connectionState,
      roomId: roomId ?? this.roomId,
      error: error ?? this.error,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Provider 정의
// ══════════════════════════════════════════════════════════════════════════════

/// ViewerViewModel을 Riverpod에 등록하는 Provider.
///
/// autoDispose: ViewerView가 사라질 때 자동으로 dispose()를 호출한다.
final viewerViewModelProvider =
    StateNotifierProvider.autoDispose<ViewerViewModel, ViewerState>(
  (ref) => ViewerViewModel(
    webRTCService: WebRTCService(),
    signalingService: SignalingService(),
  ),
);

// ══════════════════════════════════════════════════════════════════════════════
// ViewModel
// ══════════════════════════════════════════════════════════════════════════════

/// 뷰어 모드의 비즈니스 로직을 담당하는 ViewModel.
class ViewerViewModel extends StateNotifier<ViewerState> {
  ViewerViewModel({
    required WebRTCService webRTCService,
    required SignalingService signalingService,
  })  : _webRTCService = webRTCService,
        _signalingService = signalingService,
        super(const ViewerState());

  final WebRTCService _webRTCService;
  final SignalingService _signalingService;

  StreamSubscription<SignalingMessage>? _signalingSubscription;
  StreamSubscription<RTCIceCandidate>? _iceCandidateSubscription;
  StreamSubscription<RTCPeerConnectionState>? _connectionStateSubscription;
  StreamSubscription<MediaStream>? _remoteStreamSubscription;
  StreamSubscription<void>? _closedSubscription;
  StreamSubscription<RTCIceConnectionState>? _iceConnectionStateSubscription;

  String? _roomId;
  String? _serverHost;

  // ── 재연결 정책 ─────────────────────────────────────────────────────────────
  static const _maxReconnectAttempts = 3;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;

  // ── 협상 타임아웃 ────────────────────────────────────────────────────────────
  // 방 참여(RoomJoined) 후 이 시간 내에 Offer가 오지 않으면 NegotiationTimeout 에러.
  // 카메라가 켜져 있지 않거나 꺼진 경우를 감지한다.
  static const _negotiationTimeoutDuration = Duration(seconds: 30);
  Timer? _negotiationTimer;

  // dispose 후 Timer/async 콜백이 state에 접근하는 것을 방지하는 플래그
  bool _disposed = false;

  MediaStream? get remoteStream => _remoteStream;
  MediaStream? _remoteStream;

  // ── 공개 메서드 ─────────────────────────────────────────────────────────────

  /// 뷰어 모드 시작.
  Future<void> joinRoom(String serverHost, String roomId) async {
    if (state.connectionState != ViewerConnectionState.idle &&
        state.connectionState != ViewerConnectionState.error) {
      return;
    }

    _serverHost = serverHost;
    _reconnectAttempts = 0;

    state = ViewerState(
      connectionState: ViewerConnectionState.connecting,
      roomId: roomId,
    );

    try {
      await _webRTCService.initialize();

      final url = AppConstants.signalingUrl(serverHost);
      await _signalingService.connect(url);

      _listenToSignaling();
      _listenToIceCandidates();
      _listenToConnectionState();
      _listenToRemoteStream();
      _listenToIceConnectionState();
      _listenToSignalingClosed();

      _roomId = roomId;
      _signalingService.send(JoinRoomMessage(roomId: roomId));
    } on TimeoutException {
      state = ViewerState(
        connectionState: ViewerConnectionState.error,
        error: const ConnectionTimeout(),
      );
    } on Object catch (e) {
      state = ViewerState(
        connectionState: ViewerConnectionState.error,
        error: UnknownConnectionError(e.toString()),
      );
    }
  }

  /// 뷰어 모드 중지 및 리소스 해제.
  Future<void> stopViewer() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
    _negotiationTimer?.cancel();
    _negotiationTimer = null;
    await _cleanup();
    state = const ViewerState();
  }

  // ── 비공개 메서드 ───────────────────────────────────────────────────────────

  void _listenToSignaling() {
    _signalingSubscription = _signalingService.messages.listen(
      (message) async {
        switch (message) {
          case RoomJoinedMessage():
            if (!_disposed) {
              state = state.copyWith(
                connectionState: ViewerConnectionState.waitingForOffer,
              );
            }
            // 협상 타임아웃 타이머 시작.
            // Timer(duration, callback): duration 후에 callback을 1회 실행하는 일회성 타이머.
            // Offer가 도착하면 cancel()로 취소된다.
            _negotiationTimer?.cancel();
            _negotiationTimer = Timer(_negotiationTimeoutDuration, () {
              if (_disposed) return;
              if (state.connectionState == ViewerConnectionState.waitingForOffer) {
                state = ViewerState(
                  connectionState: ViewerConnectionState.error,
                  error: const NegotiationTimeout(),
                );
              }
            });

          case OfferMessage(:final sdp):
            // Offer 수신 → 협상 타이머 불필요 → 즉시 취소
            _negotiationTimer?.cancel();
            _negotiationTimer = null;
            await _handleOffer(sdp);

          case CandidateMessage(:final candidate):
            final iceCandidate = RTCIceCandidate(
              candidate['candidate'] as String,
              candidate['sdpMid'] as String?,
              candidate['sdpMLineIndex'] as int?,
            );
            await _webRTCService.addIceCandidate(iceCandidate);

          // PeerDisconnectedMessage: 카메라가 사라짐 → idle로 복귀.
          // 카메라와 달리 뷰어는 방 ID를 다시 입력해야 하므로 idle이 적절하다.
          case PeerDisconnectedMessage():
            await _cleanup();
            if (!_disposed) {
              state = ViewerState(
                connectionState: ViewerConnectionState.idle,
                error: const PeerDisconnected(),
              );
            }

          case RoomErrorMessage(:final message):
            final ConnectionError error = switch (message) {
              '존재하지 않는 방입니다.' => const RoomNotFound(),
              '이미 뷰어가 연결된 방입니다.' => const RoomFull(),
              _ => UnknownConnectionError(message),
            };
            if (!_disposed) {
              state = ViewerState(
                connectionState: ViewerConnectionState.error,
                error: error,
              );
            }

          default:
            break;
        }
      },
      onError: (Object e) {
        if (!_disposed) {
          state = ViewerState(
            connectionState: ViewerConnectionState.error,
            error: UnknownConnectionError(e.toString()),
          );
        }
      },
    );
  }

  void _listenToSignalingClosed() {
    _closedSubscription = _signalingService.onClosed.listen((_) {
      if (_disposed) return;
      if (state.connectionState == ViewerConnectionState.idle ||
          state.connectionState == ViewerConnectionState.error) return;
      _scheduleReconnect();
    });
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectAttempts++;
    if (_reconnectAttempts > _maxReconnectAttempts) {
      state = ViewerState(
        connectionState: ViewerConnectionState.error,
        error: const ServerClosed(),
      );
      return;
    }

    final delay = Duration(seconds: 1 << (_reconnectAttempts - 1));
    if (!_disposed) {
      state = state.copyWith(connectionState: ViewerConnectionState.connecting);
    }
    _reconnectTimer = Timer(delay, _reconnect);
  }

  /// 뷰어 재연결: 같은 방 ID로 재참여 시도.
  ///
  /// 카메라와 달리 뷰어는 저장된 roomId로 join_room을 재전송한다.
  /// 방이 서버에서 이미 사라진 경우 room_error가 와서 error 상태로 전환된다.
  Future<void> _reconnect() async {
    if (_disposed || _serverHost == null || _roomId == null) return;

    try {
      await _signalingSubscription?.cancel();
      _signalingSubscription = null;

      await _webRTCService.resetPeerConnection();
      await _webRTCService.initialize();

      final url = AppConstants.signalingUrl(_serverHost!);
      await _signalingService.connect(url);

      _listenToSignaling();
      _signalingService.send(JoinRoomMessage(roomId: _roomId!));

      if (!_disposed) {
        _reconnectAttempts = 0;
      }
    } on Object {
      if (!_disposed) _scheduleReconnect();
    }
  }

  /// SDP Offer를 수신해 처리하고 Answer를 전송.
  Future<void> _handleOffer(Map<String, dynamic> sdp) async {
    final description = RTCSessionDescription(
      sdp['sdp'] as String,
      sdp['type'] as String,
    );
    await _webRTCService.setRemoteDescription(description);
    final answer = await _webRTCService.createAnswer();
    _signalingService.send(
      AnswerMessage(
        roomId: _roomId!,
        sdp: {
          'type': answer.type,
          'sdp': answer.sdp,
        },
      ),
    );
  }

  void _listenToIceCandidates() {
    _iceCandidateSubscription = _webRTCService.onIceCandidate.listen(
      (candidate) {
        if (_roomId == null) return;
        _signalingService.send(
          CandidateMessage(
            roomId: _roomId!,
            candidate: {
              'candidate': candidate.candidate,
              'sdpMid': candidate.sdpMid,
              'sdpMLineIndex': candidate.sdpMLineIndex,
            },
          ),
        );
      },
    );
  }

  void _listenToConnectionState() {
    _connectionStateSubscription = _webRTCService.onConnectionState.listen(
      (rtcState) {
        if (_disposed) return;
        switch (rtcState) {
          case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
            state = state.copyWith(
              connectionState: ViewerConnectionState.streaming,
            );
          case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
            // 연결 끊어짐 — idle로 복귀. 뷰어는 카메라와 달리 방 ID를 다시 입력해야 한다.
            state = ViewerState(
              connectionState: ViewerConnectionState.idle,
              error: const ServerClosed(),
            );
          case RTCPeerConnectionState.RTCPeerConnectionStateNew:
          case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
          case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
            break;
        }
      },
    );
  }

  void _listenToRemoteStream() {
    _remoteStreamSubscription = _webRTCService.onRemoteStream.listen(
      (stream) {
        _remoteStream = stream;
        // state를 교체해서 View의 ref.listen이 트리거되도록 한다
        state = state.copyWith();
      },
    );
  }

  /// ICE 연결 상태 감지 — failed 시 restartIce() 1회 시도.
  void _listenToIceConnectionState() {
    _iceConnectionStateSubscription =
        _webRTCService.onIceConnectionState.listen(
      (iceState) async {
        if (_disposed) return;
        if (iceState == RTCIceConnectionState.RTCIceConnectionStateFailed) {
          await _webRTCService.restartIce();
        }
      },
    );
  }

  Future<void> _cleanup() async {
    _negotiationTimer?.cancel();
    _negotiationTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    await _signalingSubscription?.cancel();
    await _iceCandidateSubscription?.cancel();
    await _connectionStateSubscription?.cancel();
    await _remoteStreamSubscription?.cancel();
    await _closedSubscription?.cancel();
    await _iceConnectionStateSubscription?.cancel();
    _signalingSubscription = null;
    _iceCandidateSubscription = null;
    _connectionStateSubscription = null;
    _remoteStreamSubscription = null;
    _closedSubscription = null;
    _iceConnectionStateSubscription = null;

    _signalingService.dispose();
    await _webRTCService.dispose();
    _roomId = null;
    _remoteStream = null;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _cleanup();
    super.dispose();
  }
}
