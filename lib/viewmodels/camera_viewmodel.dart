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

/// 카메라 모드의 연결 단계를 나타내는 열거형.
///
/// UI는 이 값을 보고 화면에 표시할 내용을 결정한다.
enum CameraConnectionState {
  idle, // 초기 상태 — 아무것도 시작하지 않음
  connecting, // 시그널링 서버에 WebSocket 연결 중 (초기 연결 또는 재연결)
  waitingForViewer, // 방 생성 완료, 뷰어 참여 대기 중
  streaming, // WebRTC P2P 연결 완료, 영상 스트리밍 중
  error, // 에러 발생 — error 필드에 구체적인 유형 저장
}

/// ViewModel이 관리하는 전체 상태.
///
/// 불변(immutable) 설계: 값을 바꿀 때는 copyWith()로 새 객체를 생성해 교체한다.
/// 상태가 새 객체로 교체될 때마다 Riverpod이 UI에 변경을 알린다.
class CameraState {
  const CameraState({
    this.connectionState = CameraConnectionState.idle,
    this.roomId,
    this.error,
  });

  final CameraConnectionState connectionState;
  final String? roomId; // 시그널링 서버가 발급한 6자리 방 ID
  // ConnectionError: sealed class로 에러 유형을 구조화.
  // View에서 switch expression으로 유형별 메시지/아이콘/액션을 다르게 표시할 수 있다.
  // connection_error.dart 참조.
  final ConnectionError? error;

  /// ConnectionError를 한국어 문자열로 변환하는 편의 getter.
  ///
  /// sealed class + switch expression 패턴:
  ///   - sealed class: 컴파일 시점에 모든 케이스 처리를 강제한다.
  ///   - switch expression: 표현식(값을 반환)이라 if-else보다 간결하다.
  ///   새 ConnectionError 타입을 추가하면 여기에 케이스를 추가하지 않으면 컴파일 오류가 난다.
  String? get errorMessage => switch (error) {
        null => null,
        NetworkUnreachable() => '서버에 연결할 수 없습니다. IP와 방화벽을 확인하세요.',
        ConnectionTimeout() => '연결 시간이 초과됐습니다. 서버 IP를 확인하세요.',
        NegotiationTimeout() => '카메라 응답을 기다리다 시간이 초과됐습니다.',
        RoomNotFound() => '존재하지 않는 방 번호입니다.',
        RoomFull() => '이미 뷰어가 참여 중입니다.',
        MediaPermissionDenied() => '카메라 또는 마이크 권한이 필요합니다.',
        IceFailed() => 'P2P 연결에 실패했습니다. 같은 WiFi인지 확인하세요.',
        PeerDisconnected() => '뷰어가 연결을 종료했습니다.',
        ServerClosed() => '서버와의 연결이 끊어졌습니다.',
        UnknownConnectionError(:final message) => '오류: $message',
      };

  /// 일부 필드만 바꾼 새 CameraState를 반환.
  ///
  /// null을 명시적으로 설정하고 싶을 때(에러 초기화 등)는
  /// copyWith 대신 CameraState() 생성자를 직접 호출한다.
  CameraState copyWith({
    CameraConnectionState? connectionState,
    String? roomId,
    ConnectionError? error,
  }) {
    return CameraState(
      connectionState: connectionState ?? this.connectionState,
      roomId: roomId ?? this.roomId,
      error: error ?? this.error,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Provider 정의
// ══════════════════════════════════════════════════════════════════════════════

/// CameraViewModel을 Riverpod에 등록하는 Provider.
///
/// autoDispose: 구독 위젯이 모두 사라지면 자동으로 dispose()를 호출한다.
final cameraViewModelProvider =
    StateNotifierProvider.autoDispose<CameraViewModel, CameraState>(
  (ref) => CameraViewModel(
    webRTCService: WebRTCService(),
    signalingService: SignalingService(),
  ),
);

// ══════════════════════════════════════════════════════════════════════════════
// ViewModel
// ══════════════════════════════════════════════════════════════════════════════

/// 카메라 모드의 비즈니스 로직을 담당하는 ViewModel.
class CameraViewModel extends StateNotifier<CameraState> {
  CameraViewModel({
    required WebRTCService webRTCService,
    required SignalingService signalingService,
  })  : _webRTCService = webRTCService,
        _signalingService = signalingService,
        super(const CameraState());

  final WebRTCService _webRTCService;
  final SignalingService _signalingService;

  // Stream 구독 객체를 변수에 저장해야 나중에 cancel()할 수 있다.
  // 취소하지 않으면 위젯이 사라진 후에도 콜백이 실행되어 메모리 누수가 생긴다.
  StreamSubscription<SignalingMessage>? _signalingSubscription;
  StreamSubscription<RTCIceCandidate>? _iceCandidateSubscription;
  StreamSubscription<RTCPeerConnectionState>? _connectionStateSubscription;
  // 시그널링 서버 연결 종료 이벤트 — 자동 재연결 로직의 진입점
  StreamSubscription<void>? _closedSubscription;
  // ICE 연결 상태 — failed 감지 시 restartIce() 호출
  StreamSubscription<RTCIceConnectionState>? _iceConnectionStateSubscription;

  String? _roomId;
  // 재연결 시 동일 서버에 접속하기 위해 저장한다
  String? _serverHost;

  // ── 재연결 정책 (지수 백오프) ─────────────────────────────────────────────────
  // 시도 횟수별 지연: 1회→1s, 2회→2s, 3회→4s. 초과 시 error 상태 전환.
  static const _maxReconnectAttempts = 3;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;

  // dispose 후 Timer/async 콜백에서 state에 접근하는 것을 방지하기 위한 플래그.
  // StateNotifier는 dispose 후 state 접근 시 예외를 발생시킬 수 있다.
  bool _disposed = false;

  MediaStream? get localStream => _webRTCService.localStream;

  // ── 공개 메서드 ─────────────────────────────────────────────────────────────

  /// 카메라 모드 시작.
  Future<void> startCamera(String serverHost) async {
    if (state.connectionState != CameraConnectionState.idle &&
        state.connectionState != CameraConnectionState.error) {
      return;
    }

    _serverHost = serverHost;
    _reconnectAttempts = 0;

    state = CameraState(
      connectionState: CameraConnectionState.connecting,
      roomId: state.roomId,
    );

    try {
      await _webRTCService.initialize();
      await _webRTCService.startLocalStream();

      final url = AppConstants.signalingUrl(serverHost);
      // timeout: 10초 내 연결 실패 시 TimeoutException → ConnectionTimeout 에러로 변환
      await _signalingService.connect(url);

      _listenToSignaling();
      _listenToIceCandidates();
      _listenToConnectionState();
      _listenToIceConnectionState();
      _listenToSignalingClosed();

      _signalingService.send(const CreateRoomMessage());

      state = state.copyWith(
        connectionState: CameraConnectionState.waitingForViewer,
      );
    } on TimeoutException {
      // TimeoutException: Future.timeout()이 던지는 예외
      // 잘못된 IP나 방화벽으로 연결 응답이 없을 때 발생한다
      state = CameraState(
        connectionState: CameraConnectionState.error,
        error: const ConnectionTimeout(),
      );
    } on Object catch (e) {
      // 권한 거부는 메시지에 'permission' 또는 'notallowed'가 포함된다 (플랫폼마다 다를 수 있음)
      final message = e.toString().toLowerCase();
      final ConnectionError error;
      if (message.contains('permission') || message.contains('notallowed')) {
        error = const MediaPermissionDenied();
      } else {
        error = UnknownConnectionError(e.toString());
      }
      state = CameraState(
        connectionState: CameraConnectionState.error,
        error: error,
      );
    }
  }

  /// 카메라 모드 중지 및 리소스 해제.
  Future<void> stopCamera() async {
    // 재연결 타이머가 있으면 즉시 취소
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
    await _cleanup();
    state = const CameraState();
  }

  // ── 비공개 메서드 ───────────────────────────────────────────────────────────

  /// 시그널링 서버로부터 오는 메시지를 처리.
  ///
  /// Dart 3 sealed class + switch 패턴 매칭으로 타입별 분기.
  void _listenToSignaling() {
    _signalingSubscription = _signalingService.messages.listen(
      (message) async {
        switch (message) {
          case RoomCreatedMessage(:final roomId):
            _roomId = roomId;
            if (!_disposed) {
              state = state.copyWith(
                roomId: roomId,
                connectionState: CameraConnectionState.waitingForViewer,
              );
            }

          case RoomJoinedMessage():
            await _createAndSendOffer();

          case AnswerMessage(:final sdp):
            final description = RTCSessionDescription(
              sdp['sdp'] as String,
              sdp['type'] as String,
            );
            await _webRTCService.setRemoteDescription(description);

          case CandidateMessage(:final candidate):
            final iceCandidate = RTCIceCandidate(
              candidate['candidate'] as String,
              candidate['sdpMid'] as String?,
              candidate['sdpMLineIndex'] as int?,
            );
            await _webRTCService.addIceCandidate(iceCandidate);

          // peer_disconnected: 뷰어가 앱을 종료하거나 연결을 끊음.
          // PeerConnection을 재초기화해 새 뷰어 접속을 준비한다.
          // 방 ID는 유지 — 같은 번호로 재참여할 수 있게 한다.
          case PeerDisconnectedMessage():
            await _resetForNewViewer();

          // 서버가 보내는 에러 메시지를 ConnectionError 타입으로 매핑.
          // switch expression: room-manager.js의 한국어 메시지 문자열을 타입으로 변환한다.
          case RoomErrorMessage(:final message):
            final ConnectionError error = switch (message) {
              '존재하지 않는 방입니다.' => const RoomNotFound(),
              '이미 뷰어가 연결된 방입니다.' => const RoomFull(),
              _ => UnknownConnectionError(message),
            };
            if (!_disposed) {
              state = CameraState(
                connectionState: CameraConnectionState.error,
                error: error,
              );
            }

          default:
            break;
        }
      },
      onError: (Object e) {
        if (!_disposed) {
          state = CameraState(
            connectionState: CameraConnectionState.error,
            error: UnknownConnectionError(e.toString()),
          );
        }
      },
    );
  }

  /// 시그널링 서버 연결 끊김 감지 — 자동 재연결 스케줄링.
  ///
  /// WiFi 단절, 서버 재기동 등으로 WebSocket이 닫힐 때 호출된다.
  /// idle/error 상태이면 사용자가 이미 중지했거나 에러 처리 중이므로 재연결하지 않는다.
  void _listenToSignalingClosed() {
    _closedSubscription = _signalingService.onClosed.listen((_) {
      if (_disposed) return;
      if (state.connectionState == CameraConnectionState.idle ||
          state.connectionState == CameraConnectionState.error) return;
      _scheduleReconnect();
    });
  }

  /// 지수 백오프 재연결 스케줄링.
  ///
  /// 지수 백오프(exponential backoff): 재시도 간격을 매번 2배씩 늘려
  /// 서버에 과부하를 주지 않으면서 일시적 장애에서 회복하는 패턴.
  /// 1 << n: 비트 시프트로 2^n을 계산한다. (1<<0=1, 1<<1=2, 1<<2=4)
  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectAttempts++;
    if (_reconnectAttempts > _maxReconnectAttempts) {
      state = CameraState(
        connectionState: CameraConnectionState.error,
        error: const ServerClosed(),
      );
      return;
    }

    final delay = Duration(seconds: 1 << (_reconnectAttempts - 1));
    if (!_disposed) {
      state = state.copyWith(connectionState: CameraConnectionState.connecting);
    }
    _reconnectTimer = Timer(delay, _reconnect);
  }

  /// 실제 재연결 수행.
  ///
  /// 시그널링 구독만 재구독하고, PeerConnection도 재초기화한다.
  /// ICE/ConnectionState 구독(_iceCandidateSubscription 등)은 그대로 유지한다:
  ///   resetPeerConnection()은 StreamController를 닫지 않으므로
  ///   새 PeerConnection의 콜백이 같은 StreamController에 이벤트를 추가하고
  ///   기존 구독이 이를 계속 수신한다.
  Future<void> _reconnect() async {
    if (_disposed || _serverHost == null) return;

    try {
      await _signalingSubscription?.cancel();
      _signalingSubscription = null;

      await _webRTCService.resetPeerConnection();
      await _webRTCService.initialize();
      await _webRTCService.startLocalStream();

      final url = AppConstants.signalingUrl(_serverHost!);
      await _signalingService.connect(url);

      _listenToSignaling();
      _signalingService.send(const CreateRoomMessage());

      if (!_disposed) {
        state = state.copyWith(
          connectionState: CameraConnectionState.waitingForViewer,
        );
        _reconnectAttempts = 0;
      }
    } on Object {
      if (!_disposed) _scheduleReconnect();
    }
  }

  /// peer_disconnected 수신 후 새 뷰어 접속을 위해 PeerConnection 재초기화.
  Future<void> _resetForNewViewer() async {
    if (_disposed) return;
    await _webRTCService.resetPeerConnection();
    await _webRTCService.initialize();
    await _webRTCService.startLocalStream();

    if (!_disposed) {
      state = state.copyWith(
        connectionState: CameraConnectionState.waitingForViewer,
      );
    }
  }

  Future<void> _createAndSendOffer() async {
    final offer = await _webRTCService.createOffer();
    _signalingService.send(
      OfferMessage(
        roomId: _roomId!,
        sdp: {
          'type': offer.type,
          'sdp': offer.sdp,
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
              connectionState: CameraConnectionState.streaming,
            );
          case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
            state = state.copyWith(
              connectionState: CameraConnectionState.waitingForViewer,
            );
          case RTCPeerConnectionState.RTCPeerConnectionStateNew:
          case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
          case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
            break;
        }
      },
    );
  }

  /// ICE 연결 상태 감지 — failed 시 restartIce() 1회 시도.
  ///
  /// RTCIceConnectionState 주요 전이:
  ///   new → checking → connected → (disconnected →) failed
  ///
  /// restartIce(): SDP 재협상 없이 ICE 후보 수집만 재시작한다.
  /// 일시적 네트워크 경로 단절(WiFi 이동 등)에서 자동 복구를 시도한다.
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

  /// 모든 비동기 리소스를 정리.
  Future<void> _cleanup() async {
    // Timer 먼저 취소 — 타이머 콜백이 실행되기 전에 정리
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    // Stream 구독 취소 — 취소하지 않으면 객체가 GC되지 않는다
    await _signalingSubscription?.cancel();
    await _iceCandidateSubscription?.cancel();
    await _connectionStateSubscription?.cancel();
    await _closedSubscription?.cancel();
    await _iceConnectionStateSubscription?.cancel();
    _signalingSubscription = null;
    _iceCandidateSubscription = null;
    _connectionStateSubscription = null;
    _closedSubscription = null;
    _iceConnectionStateSubscription = null;

    _signalingService.dispose();
    await _webRTCService.dispose();
    _roomId = null;
  }

  /// StateNotifier.dispose(): Provider가 소멸될 때 Riverpod이 자동 호출.
  @override
  Future<void> dispose() async {
    // _disposed 플래그를 먼저 세워 진행 중인 Timer/async 콜백에서 state 접근을 막는다
    _disposed = true;
    await _cleanup();
    super.dispose();
  }
}
