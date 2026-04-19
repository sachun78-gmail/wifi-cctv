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

/// 뷰어 모드의 연결 단계를 나타내는 열거형.
///
/// CameraConnectionState와 대칭 구조이지만 역할이 다르다.
/// - 카메라: 방을 만들고 Offer를 보내는 쪽
/// - 뷰어: 방에 참여하고 Answer를 보내는 쪽
enum ViewerConnectionState {
  idle, // 초기 상태 — 방 ID 입력 전
  connecting, // 시그널링 서버에 WebSocket 연결 중
  waitingForOffer, // 방 참여 완료, 카메라의 Offer 대기 중
  streaming, // WebRTC P2P 연결 완료, 영상 수신 중
  error, // 에러 발생
}

/// ViewerViewModel이 관리하는 전체 상태.
///
/// 불변(immutable) 설계 — 값을 바꿀 때는 copyWith()로 새 객체를 생성해 교체한다.
/// 상태가 새 객체로 교체될 때마다 Riverpod이 UI에 변경을 알린다.
class ViewerState {
  const ViewerState({
    this.connectionState = ViewerConnectionState.idle,
    this.roomId,
    this.errorMessage,
  });

  final ViewerConnectionState connectionState;
  final String? roomId; // 참여한 방의 ID — 컨트롤 패널에 표시용
  final String? errorMessage; // 에러 발생 시 사용자에게 보여줄 메시지

  /// 일부 필드만 바꾼 새 ViewerState를 반환.
  ///
  /// Dart에는 built-in copyWith가 없어 직접 구현한다.
  /// null을 명시적으로 지우고 싶은 경우(roomId, errorMessage)는
  /// 직접 `ViewerState(...)` 생성자를 호출하는 방식으로 처리한다.
  ViewerState copyWith({
    ViewerConnectionState? connectionState,
    String? roomId,
    String? errorMessage,
  }) {
    return ViewerState(
      connectionState: connectionState ?? this.connectionState,
      roomId: roomId ?? this.roomId,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Provider 정의
// ══════════════════════════════════════════════════════════════════════════════

/// ViewerViewModel을 Riverpod에 등록하는 Provider.
///
/// autoDispose: ViewerView가 사라질 때 자동으로 dispose()를 호출한다.
/// 뷰어 화면에서 나가면 WebSocket 연결, WebRTC 리소스가 자동 정리된다.
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
///
/// `StateNotifier<ViewerState>`:
///   - state 프로퍼티로 현재 상태를 읽는다.
///   - state = newState 로 상태를 교체하면 Riverpod이 UI를 자동 갱신한다.
///
/// 카메라(CameraViewModel)와 역할이 반대:
///   - 카메라: create_room → Offer 생성 → streaming
///   - 뷰어:  join_room  → Offer 수신 → Answer 생성 → streaming
class ViewerViewModel extends StateNotifier<ViewerState> {
  ViewerViewModel({
    required WebRTCService webRTCService,
    required SignalingService signalingService,
  })  : _webRTCService = webRTCService,
        _signalingService = signalingService,
        super(const ViewerState()); // StateNotifier 생성자에 초기 상태 전달

  final WebRTCService _webRTCService;
  final SignalingService _signalingService;

  // Stream 구독 객체는 반드시 저장해두어야 나중에 cancel()할 수 있다.
  // 취소하지 않으면 위젯이 사라진 후에도 콜백이 계속 실행되어 메모리 누수가 생긴다.
  StreamSubscription<SignalingMessage>? _signalingSubscription;
  StreamSubscription<RTCIceCandidate>? _iceCandidateSubscription;
  StreamSubscription<RTCPeerConnectionState>? _connectionStateSubscription;
  StreamSubscription<MediaStream>? _remoteStreamSubscription;

  String? _roomId; // 참여한 방 ID — ICE Candidate 등 메시지 전송 시 필요

  /// 수신 중인 원격 스트림 — View에서 RTCVideoRenderer에 연결하기 위해 노출.
  MediaStream? get remoteStream => _remoteStream;
  MediaStream? _remoteStream;

  // ── 공개 메서드 ─────────────────────────────────────────────────────────────

  /// 뷰어 모드 시작.
  ///
  /// [serverHost]: 시그널링 서버의 IP 주소 (예: '192.168.0.100')
  /// [roomId]:     참여할 방의 6자리 ID
  ///
  /// 흐름:
  ///   1. WebRTC PeerConnection 초기화 (뷰어는 startLocalStream 불필요 — 수신만)
  ///   2. 시그널링 서버에 WebSocket 연결
  ///   3. 이벤트 리스너 등록
  ///   4. join_room 메시지 전송
  Future<void> joinRoom(String serverHost, String roomId) async {
    // 이미 진행 중이면 중복 실행 방지
    if (state.connectionState != ViewerConnectionState.idle &&
        state.connectionState != ViewerConnectionState.error) {
      return;
    }

    // errorMessage를 null로 초기화하기 위해 새 ViewerState를 직접 생성.
    // copyWith는 null을 ?? 연산자로 넘기므로 기존 errorMessage가 남는다.
    state = ViewerState(
      connectionState: ViewerConnectionState.connecting,
      roomId: roomId,
    );

    try {
      // Step 1: WebRTC PeerConnection 초기화
      // - 뷰어는 영상을 수신만 하므로 startLocalStream()은 호출하지 않는다.
      // - initialize() 내부에서 onTrack 콜백이 설정되어 원격 트랙 수신 준비가 된다.
      await _webRTCService.initialize();

      // Step 2: 시그널링 서버에 WebSocket 연결
      final url = AppConstants.signalingUrl(serverHost);
      await _signalingService.connect(url);

      // Step 3: 이벤트 리스너 등록 (연결 성공 후 등록해야 메시지를 놓치지 않음)
      _listenToSignaling();
      _listenToIceCandidates();
      _listenToConnectionState();
      _listenToRemoteStream();

      // Step 4: 방 참여 요청
      // - 서버는 방이 존재하면 room_joined, 없으면 room_error로 응답한다.
      _roomId = roomId;
      _signalingService.send(JoinRoomMessage(roomId: roomId));
    } on Object catch (e) {
      // on Object: Exception과 Error를 모두 잡는다.
      // catch (e)보다 명시적이고, 타입 추가 시 컴파일러가 알려준다.
      state = ViewerState(
        connectionState: ViewerConnectionState.error,
        errorMessage: '연결 실패: $e',
      );
    }
  }

  /// 뷰어 모드 중지 및 리소스 해제.
  Future<void> stopViewer() async {
    await _cleanup();
    state = const ViewerState();
  }

  // ── 비공개 메서드 ───────────────────────────────────────────────────────────

  /// 시그널링 서버로부터 오는 메시지를 처리.
  ///
  /// Dart 3 sealed class + switch 패턴 매칭으로 타입별 분기.
  /// sealed class의 exhaustive check 덕분에 처리 누락 시 컴파일 오류가 난다.
  void _listenToSignaling() {
    _signalingSubscription = _signalingService.messages.listen(
      (message) async {
        switch (message) {
          // 방 참여 성공 — 카메라 폰의 Offer를 기다리는 상태로 전환
          case RoomJoinedMessage():
            state = state.copyWith(
              connectionState: ViewerConnectionState.waitingForOffer,
            );

          // 카메라가 보낸 SDP Offer 수신
          // Offer = "내가 보낼 영상 코덱/해상도 등을 제안하는 SDP 메시지"
          // 뷰어는 Offer를 RemoteDescription으로 등록한 뒤 Answer를 만들어 응답한다.
          case OfferMessage(:final sdp):
            await _handleOffer(sdp);

          // 상대방(카메라)이 보낸 ICE Candidate 수신
          // - 상대방의 네트워크 경로 정보 → addCandidate()로 PeerConnection에 추가
          case CandidateMessage(:final candidate):
            final iceCandidate = RTCIceCandidate(
              candidate['candidate'] as String,
              candidate['sdpMid'] as String?,
              candidate['sdpMLineIndex'] as int?,
            );
            await _webRTCService.addIceCandidate(iceCandidate);

          // 카메라가 연결 해제
          // - 카메라가 사라졌으므로 뷰어는 idle로 복귀 (재입력 필요)
          // - 카메라와 달리 뷰어는 방 ID를 다시 입력해야 하므로 waiting 상태 유지보다 idle이 적절
          case PeerDisconnectedMessage():
            await _cleanup();
            state = const ViewerState(
              connectionState: ViewerConnectionState.idle,
              errorMessage: '카메라가 연결을 종료했습니다.',
            );

          // 서버에서 에러 응답 (방 없음, 방이 꽉 참 등)
          case RoomErrorMessage(:final message):
            state = ViewerState(
              connectionState: ViewerConnectionState.error,
              errorMessage: message,
            );

          // room_created, answer, unknown 등은 뷰어에서 처리할 필요 없음
          default:
            break;
        }
      },
      onError: (Object e) {
        state = ViewerState(
          connectionState: ViewerConnectionState.error,
          errorMessage: '시그널링 오류: $e',
        );
      },
    );
  }

  /// SDP Offer를 수신해서 처리하고 Answer를 전송.
  ///
  /// WebRTC 협상 흐름:
  ///   1. setRemoteDescription(offer) — 상대방 SDP 등록
  ///   2. createAnswer()              — 내가 지원하는 형식으로 Answer SDP 생성
  ///                                   (내부에서 setLocalDescription()까지 처리)
  ///   3. send(AnswerMessage)         — Answer를 시그널링 서버를 통해 카메라에 전달
  Future<void> _handleOffer(Map<String, dynamic> sdp) async {
    final description = RTCSessionDescription(
      sdp['sdp'] as String,
      sdp['type'] as String, // 'offer'
    );
    await _webRTCService.setRemoteDescription(description);

    // createAnswer()는 내부에서 setLocalDescription()까지 처리
    final answer = await _webRTCService.createAnswer();

    _signalingService.send(
      AnswerMessage(
        roomId: _roomId!,
        sdp: {
          'type': answer.type, // 'answer'
          'sdp': answer.sdp, // SDP 본문
        },
      ),
    );
  }

  /// WebRTC가 찾은 ICE Candidate를 시그널링 서버로 전송.
  ///
  /// ICE Candidate = "내가 연결 가능한 네트워크 주소/경로"
  /// 뷰어의 Candidate를 카메라에 전달해야 P2P 연결이 가능하다.
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

  /// WebRTC PeerConnection 상태 변화를 UI 상태에 반영.
  ///
  /// connected → streaming: 카메라 영상이 수신되기 시작
  /// disconnected/failed → idle: 연결 끊김, 재입력 필요
  void _listenToConnectionState() {
    _connectionStateSubscription = _webRTCService.onConnectionState.listen(
      (rtcState) {
        switch (rtcState) {
          case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
            state = state.copyWith(
              connectionState: ViewerConnectionState.streaming,
            );
          case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
            // 연결이 끊어지면 idle로 복귀 — 뷰어는 카메라와 달리 방 ID를 다시 입력해야 함
            state = ViewerState(
              connectionState: ViewerConnectionState.idle,
              errorMessage: '연결이 끊어졌습니다.',
            );
          // no_default_cases: 모든 케이스를 명시하여 새 enum 값 추가 시 컴파일 오류로 알 수 있음
          case RTCPeerConnectionState.RTCPeerConnectionStateNew:
          case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
          case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
            break;
        }
      },
    );
  }

  /// 카메라에서 보내는 원격 미디어 스트림을 수신.
  ///
  /// WebRTC P2P 연결이 완료되면 onTrack 이벤트가 발생하고,
  /// WebRTCService 내부에서 onRemoteStream에 스트림을 추가한다.
  /// View에서 ref.listen으로 이 스트림을 RTCVideoRenderer에 연결한다.
  void _listenToRemoteStream() {
    _remoteStreamSubscription = _webRTCService.onRemoteStream.listen(
      (stream) {
        _remoteStream = stream;
        // state를 교체해서 View의 ref.listen이 트리거되도록 한다
        state = state.copyWith();
      },
    );
  }

  /// 모든 비동기 리소스를 정리.
  Future<void> _cleanup() async {
    // Stream 구독 취소 — 취소하지 않으면 객체가 GC되지 않아 메모리 누수 발생
    await _signalingSubscription?.cancel();
    await _iceCandidateSubscription?.cancel();
    await _connectionStateSubscription?.cancel();
    await _remoteStreamSubscription?.cancel();
    _signalingSubscription = null;
    _iceCandidateSubscription = null;
    _connectionStateSubscription = null;
    _remoteStreamSubscription = null;

    _signalingService.dispose();
    await _webRTCService.dispose();
    _roomId = null;
    _remoteStream = null;
  }

  /// StateNotifier.dispose(): autoDispose Provider가 소멸될 때 Riverpod이 자동 호출.
  ///
  /// ViewerView가 위젯 트리에서 제거되면 구독자가 없어지고,
  /// autoDispose가 이 dispose()를 호출하여 모든 리소스를 해제한다.
  @override
  Future<void> dispose() async {
    await _cleanup();
    super.dispose();
  }
}
