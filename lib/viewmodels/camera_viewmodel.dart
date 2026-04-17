import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

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
  connecting, // 시그널링 서버에 WebSocket 연결 중
  waitingForViewer, // 방 생성 완료, 뷰어 참여 대기 중
  streaming, // WebRTC P2P 연결 완료, 영상 스트리밍 중
  error, // 에러 발생
}

/// ViewModel이 관리하는 전체 상태.
///
/// Flutter에서는 상태(State)를 불변(immutable)으로 관리하는 것이 일반적이다.
/// 값을 바꿀 때는 copyWith()로 새 객체를 생성하여 교체한다.
/// → 상태 변화가 명확하고, 이전 상태와 비교가 쉬워진다.
class CameraState {
  const CameraState({
    this.connectionState = CameraConnectionState.idle,
    this.roomId,
    this.errorMessage,
  });

  final CameraConnectionState connectionState;
  final String? roomId; // 시그널링 서버가 발급한 6자리 방 ID
  final String? errorMessage; // 에러 발생 시 사용자에게 보여줄 메시지

  /// 일부 필드만 바꾼 새 CameraState를 반환하는 패턴.
  ///
  /// Dart에는 built-in copyWith가 없으므로 직접 구현한다.
  /// (freezed 패키지를 쓰면 자동 생성 가능하지만, 학습 목적으로 직접 작성)
  CameraState copyWith({
    CameraConnectionState? connectionState,
    String? roomId,
    String? errorMessage,
  }) {
    return CameraState(
      connectionState: connectionState ?? this.connectionState,
      // null을 명시적으로 설정하고 싶을 때를 위해 sentinal 패턴을 쓸 수도 있지만,
      // 이 프로젝트에서는 단순하게 ?? 연산자로 처리한다.
      roomId: roomId ?? this.roomId,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Provider 정의
// ══════════════════════════════════════════════════════════════════════════════

/// CameraViewModel을 Riverpod에 등록하는 Provider.
///
/// StateNotifierProvider: StateNotifier(ViewModel)를 관리하는 Provider 타입.
///   - 첫 번째 타입: StateNotifier 구현 클래스 (CameraViewModel)
///   - 두 번째 타입: 관리할 상태 클래스 (CameraState)
///
/// autoDispose: 이 Provider를 구독하는 위젯이 모두 사라지면 자동으로
///   dispose()를 호출하여 리소스를 해제한다. 메모리 누수 방지에 중요하다.
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
///
/// `StateNotifier<CameraState>`:
///   - state 프로퍼티로 현재 상태를 읽는다.
///   - state = newState 로 상태를 교체한다 (UI 자동 갱신).
///   - 직접 state를 mutate(변경)하지 않고, 항상 새 객체로 교체한다.
class CameraViewModel extends StateNotifier<CameraState> {
  CameraViewModel({
    required WebRTCService webRTCService,
    required SignalingService signalingService,
  })  : _webRTCService = webRTCService,
        _signalingService = signalingService,
        super(const CameraState()); // StateNotifier 생성자에 초기 상태 전달

  final WebRTCService _webRTCService;
  final SignalingService _signalingService;

  // Stream 구독 객체를 변수에 저장해두어야 나중에 cancel() 할 수 있다.
  // 구독을 취소하지 않으면 위젯이 사라진 후에도 콜백이 실행되어 메모리 누수가 생긴다.
  StreamSubscription<SignalingMessage>? _signalingSubscription;
  StreamSubscription<RTCIceCandidate>? _iceCandidateSubscription;
  StreamSubscription<RTCPeerConnectionState>? _connectionStateSubscription;

  String? _roomId; // 생성된 방 ID — 시그널링 메시지 전송 시 필요

  /// 로컬 카메라 스트림 — View에서 RTCVideoRenderer에 연결하기 위해 노출.
  MediaStream? get localStream => _webRTCService.localStream;

  // ── 공개 메서드 ─────────────────────────────────────────────────────────────

  /// 카메라 모드 시작.
  ///
  /// [serverHost]: 시그널링 서버의 IP 주소 (예: '192.168.0.100')
  ///
  /// 흐름:
  ///   1. WebRTC PeerConnection 초기화
  ///   2. 로컬 카메라 스트림 획득
  ///   3. 시그널링 서버에 WebSocket 연결
  ///   4. 이벤트 리스너 등록
  ///   5. create_room 메시지 전송
  Future<void> startCamera(String serverHost) async {
    // 이미 진행 중이면 중복 실행 방지
    if (state.connectionState != CameraConnectionState.idle &&
        state.connectionState != CameraConnectionState.error) {
      return;
    }

    // errorMessage는 copyWith로 지울 수 없으므로(null이 ?? 연산자에 걸림)
    // 새 CameraState 객체를 직접 생성하여 errorMessage를 명시적으로 null로 초기화한다.
    state = CameraState(
      connectionState: CameraConnectionState.connecting,
      roomId: state.roomId,
    );

    try {
      // Step 1: WebRTC PeerConnection 초기화
      // - ICE Candidate 이벤트 리스너, 원격 트랙 수신 리스너 등이 내부에서 설정됨
      await _webRTCService.initialize();

      // Step 2: 로컬 카메라 스트림 획득
      // - getUserMedia()로 카메라 접근 권한 요청
      // - 성공하면 스트림을 PeerConnection에 트랙으로 추가
      await _webRTCService.startLocalStream();

      // Step 3: 시그널링 서버에 WebSocket 연결
      // - ws://[serverHost]:9090 형태의 URL로 연결
      final url = AppConstants.signalingUrl(serverHost);
      await _signalingService.connect(url);

      // Step 4: 이벤트 리스너 등록 (연결 성공 후 등록해야 메시지를 받을 수 있음)
      _listenToSignaling();
      _listenToIceCandidates();
      _listenToConnectionState();

      // Step 5: 방 생성 요청
      // - 서버는 6자리 랜덤 ID를 생성하고 room_created 메시지로 응답
      _signalingService.send(const CreateRoomMessage());

      state = state.copyWith(
        connectionState: CameraConnectionState.waitingForViewer,
      );
    } on Object catch (e) {
      // on Object: 모든 예외(Exception, Error 포함)를 잡는다.
      // 일반 'catch (e)' 대신 'on 타입 catch (e)' 형식을 사용하는 것이 권장된다.
      state = state.copyWith(
        connectionState: CameraConnectionState.error,
        errorMessage: '연결 실패: $e',
      );
    }
  }

  /// 카메라 모드 중지 및 리소스 해제.
  Future<void> stopCamera() async {
    await _cleanup();
    // 초기 상태로 리셋
    state = const CameraState();
  }

  // ── 비공개 메서드 ───────────────────────────────────────────────────────────

  /// 시그널링 서버로부터 오는 메시지를 처리.
  ///
  /// Dart 3의 sealed class + switch 패턴 매칭으로 타입별로 분기한다.
  /// sealed class는 모든 하위 타입이 같은 파일에 정의되어 있어서
  /// switch에서 모든 케이스를 컴파일 타임에 검사할 수 있다(exhaustive check).
  void _listenToSignaling() {
    _signalingSubscription = _signalingService.messages.listen(
      (message) async {
        switch (message) {
          // 방 생성 완료 — 서버가 발급한 roomId를 저장
          case RoomCreatedMessage(:final roomId):
            _roomId = roomId;
            state = state.copyWith(
              roomId: roomId,
              connectionState: CameraConnectionState.waitingForViewer,
            );

          // 뷰어가 방에 참여 — SDP Offer를 생성해서 전송
          // room_joined는 카메라 폰과 뷰어 폰 양쪽에 전달되지만,
          // 카메라 폰은 이 시점에 Offer를 만들어야 한다.
          case RoomJoinedMessage():
            await _createAndSendOffer();

          // 뷰어가 보낸 SDP Answer 수신
          // - Offer에 대한 응답: "나도 H.264 지원해, 이 IP/포트로 연결해"
          // - setRemoteDescription()으로 WebRTC에 알려주면 ICE 협상 시작
          case AnswerMessage(:final sdp):
            final description = RTCSessionDescription(
              sdp['sdp'] as String,
              sdp['type'] as String,
            );
            await _webRTCService.setRemoteDescription(description);

          // 상대방이 보낸 ICE Candidate 수신
          // - 상대방의 네트워크 경로 정보 → addCandidate()로 PeerConnection에 추가
          case CandidateMessage(:final candidate):
            final iceCandidate = RTCIceCandidate(
              candidate['candidate'] as String,
              candidate['sdpMid'] as String?,
              candidate['sdpMLineIndex'] as int?,
            );
            await _webRTCService.addIceCandidate(iceCandidate);

          // 뷰어가 연결 해제 — 방은 유지하고 다시 뷰어 대기 상태로
          case PeerDisconnectedMessage():
            state = state.copyWith(
              connectionState: CameraConnectionState.waitingForViewer,
            );

          // 서버에서 에러 응답 (방 없음, 방이 꽉 참 등)
          case RoomErrorMessage(:final message):
            state = state.copyWith(
              connectionState: CameraConnectionState.error,
              errorMessage: message,
            );

          // offer, unknown 등은 카메라 폰에서 처리할 필요 없음
          default:
            break;
        }
      },
      onError: (Object e) {
        state = state.copyWith(
          connectionState: CameraConnectionState.error,
          errorMessage: '시그널링 오류: $e',
        );
      },
    );
  }

  /// SDP Offer를 생성하고 시그널링 서버로 전송.
  ///
  /// Offer = "내가 보낼 수 있는 영상 형식(코덱, 해상도 등)을 제안하는 SDP 메시지"
  /// createOffer() → setLocalDescription() 순서로 호출해야 ICE 수집이 시작된다.
  Future<void> _createAndSendOffer() async {
    // WebRTCService.createOffer()는 내부에서 setLocalDescription()까지 처리
    final offer = await _webRTCService.createOffer();

    _signalingService.send(
      OfferMessage(
        roomId: _roomId!,
        sdp: {
          'type': offer.type, // 'offer'
          'sdp': offer.sdp, // SDP 본문 (코덱, 포트 등)
        },
      ),
    );
  }

  /// WebRTC가 찾은 ICE Candidate를 시그널링 서버로 전송.
  ///
  /// ICE Candidate = "내가 연결 가능한 네트워크 주소/경로"
  /// 예: 192.168.0.10:5000 (LAN IP), 203.0.113.5:5000 (공인 IP via STUN)
  ///
  /// 수집된 Candidate는 상대방에게 전달해야 P2P 연결이 가능하다.
  /// 시그널링 서버가 중계 역할을 한다.
  void _listenToIceCandidates() {
    _iceCandidateSubscription = _webRTCService.onIceCandidate.listen(
      (candidate) {
        if (_roomId == null) return;
        _signalingService.send(
          CandidateMessage(
            roomId: _roomId!,
            candidate: {
              'candidate': candidate.candidate, // 실제 경로 문자열
              'sdpMid': candidate.sdpMid, // 미디어 스트림 식별자
              'sdpMLineIndex': candidate.sdpMLineIndex, // SDP 내 미디어 라인 인덱스
            },
          ),
        );
      },
    );
  }

  /// WebRTC PeerConnection 상태 변화를 감지하여 UI 상태에 반영.
  ///
  /// RTCPeerConnectionState 주요 값:
  ///   - connecting: ICE 협상 진행 중
  ///   - connected: P2P 연결 완료 → 스트리밍 시작
  ///   - disconnected: 일시적 연결 끊김
  ///   - failed: 연결 실패 (ICE 협상 실패 등)
  void _listenToConnectionState() {
    _connectionStateSubscription = _webRTCService.onConnectionState.listen(
      (rtcState) {
        switch (rtcState) {
          case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
            // P2P 연결 성공 → 영상 스트리밍 중
            state = state.copyWith(
              connectionState: CameraConnectionState.streaming,
            );
          case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
            // 연결 끊김 → 다시 뷰어 대기 (방 ID는 유지)
            state = state.copyWith(
              connectionState: CameraConnectionState.waitingForViewer,
            );
          // no_default_cases 규칙: default 대신 모든 케이스를 명시
          // → 나중에 enum에 새 값이 추가되면 컴파일 오류로 알 수 있어 안전하다
          case RTCPeerConnectionState.RTCPeerConnectionStateNew:
          case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
          case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
            break;
        }
      },
    );
  }

  /// 모든 비동기 리소스를 정리.
  Future<void> _cleanup() async {
    // Stream 구독 취소 — 취소하지 않으면 객체가 GC되지 않는다
    await _signalingSubscription?.cancel();
    await _iceCandidateSubscription?.cancel();
    await _connectionStateSubscription?.cancel();
    _signalingSubscription = null;
    _iceCandidateSubscription = null;
    _connectionStateSubscription = null;

    _signalingService.dispose();
    await _webRTCService.dispose();
    _roomId = null;
  }

  /// StateNotifier.dispose(): Provider가 소멸될 때 Riverpod이 자동 호출.
  ///
  /// autoDispose Provider를 사용하면 구독 위젯이 모두 사라질 때 자동으로 호출된다.
  @override
  Future<void> dispose() async {
    await _cleanup();
    super.dispose();
  }
}
