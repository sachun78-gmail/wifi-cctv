import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:wifi_cctv/models/connection_error.dart';
import 'package:wifi_cctv/models/signaling_message.dart';
import 'package:wifi_cctv/services/signaling_service.dart';
import 'package:wifi_cctv/services/webrtc_service.dart';
import 'package:wifi_cctv/viewmodels/camera_viewmodel.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Fake 구현체
//
// flutter_webrtc는 네이티브 바인딩(Android/iOS)이 필요해서 유닛 테스트에서
// 직접 사용할 수 없다. 대신 Fake 클래스를 만들어 네이티브 호출 없이
// 동일한 인터페이스를 흉내 낸다.
//
// Fake (package:test): noSuchMethod를 throw로 오버라이드하여,
// 명시적으로 override하지 않은 메서드 호출 시 UnimplementedError를 발생시킨다.
// ══════════════════════════════════════════════════════════════════════════════

class _FakeWebRTCService extends Fake implements WebRTCService {
  final _iceCandidateCtrl = StreamController<RTCIceCandidate>.broadcast();
  final _connectionStateCtrl =
      StreamController<RTCPeerConnectionState>.broadcast();
  // Phase 7 추가: ICE 연결 상태 스트림 — failed 이벤트로 restartIce() 검증에 사용
  final _iceConnectionStateCtrl =
      StreamController<RTCIceConnectionState>.broadcast();

  var initializeCalled = false;
  var startLocalStreamCalled = false;
  RTCSessionDescription? lastSetRemoteDescription;
  final List<RTCIceCandidate> addedCandidates = [];
  // Phase 7 추가: 호출 여부 검증용 카운터
  var restartIceCalled = false;
  var resetPeerConnectionCalled = 0; // 횟수로 검증 (peer_disconnected 후 재연결 등)

  @override
  Stream<RTCIceCandidate> get onIceCandidate => _iceCandidateCtrl.stream;

  @override
  Stream<RTCPeerConnectionState> get onConnectionState =>
      _connectionStateCtrl.stream;

  @override
  Stream<MediaStream> get onRemoteStream =>
      StreamController<MediaStream>.broadcast().stream;

  // Phase 7 추가: ICE 연결 상태 스트림
  @override
  Stream<RTCIceConnectionState> get onIceConnectionState =>
      _iceConnectionStateCtrl.stream;

  @override
  MediaStream? get localStream => null;

  @override
  Future<void> initialize() async {
    initializeCalled = true;
  }

  @override
  Future<void> startLocalStream({bool frontCamera = false}) async {
    startLocalStreamCalled = true;
  }

  @override
  Future<RTCSessionDescription> createOffer() async {
    return RTCSessionDescription('v=0\r\no=- 0 0 IN IP4 127.0.0.1\r\n', 'offer');
  }

  @override
  Future<void> setRemoteDescription(RTCSessionDescription description) async {
    lastSetRemoteDescription = description;
  }

  @override
  Future<void> addIceCandidate(RTCIceCandidate candidate) async {
    addedCandidates.add(candidate);
  }

  // Phase 7 추가: ICE 재시작 — restartIceCalled로 호출 여부 검증
  @override
  Future<void> restartIce() async {
    restartIceCalled = true;
  }

  // Phase 7 추가: PeerConnection만 재초기화 (StreamController 유지)
  // resetPeerConnectionCalled 횟수로 peer_disconnected 처리 및 재연결 검증
  @override
  Future<void> resetPeerConnection() async {
    resetPeerConnectionCalled++;
    // 재초기화 후에는 initializeCalled가 다시 true가 될 준비
    initializeCalled = false;
    startLocalStreamCalled = false;
  }

  @override
  Future<void> dispose() async {
    await _iceCandidateCtrl.close();
    await _connectionStateCtrl.close();
    await _iceConnectionStateCtrl.close();
  }

  void emitIceCandidate(RTCIceCandidate candidate) {
    _iceCandidateCtrl.add(candidate);
  }

  void emitConnectionState(RTCPeerConnectionState state) {
    _connectionStateCtrl.add(state);
  }

  // Phase 7 추가: ICE 연결 상태 이벤트 주입
  void emitIceConnectionState(RTCIceConnectionState state) {
    _iceConnectionStateCtrl.add(state);
  }
}

class _FakeSignalingService extends Fake implements SignalingService {
  final _messageCtrl = StreamController<SignalingMessage>.broadcast();
  // Phase 7 추가: onClosed 스트림 — 서버 연결 종료 시뮬레이션용
  final _closedCtrl = StreamController<void>.broadcast();

  final List<SignalingMessage> sentMessages = [];

  // Phase 7 추가: true로 설정하면 connect()가 TimeoutException을 던진다
  var simulateTimeout = false;
  // Phase 7 추가: true로 설정하면 connect()가 일반 예외를 던진다
  var simulateError = false;

  bool _isClosed = false; // 이중 dispose 방지

  @override
  Stream<SignalingMessage> get messages => _messageCtrl.stream;

  // Phase 7 추가: onClosed 스트림 노출
  @override
  Stream<void> get onClosed => _closedCtrl.stream;

  @override
  bool get isConnected => true;

  // timeout 파라미터 추가 — Phase 7에서 SignalingService에 추가된 named parameter
  @override
  Future<void> connect(
    String url, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (simulateTimeout) throw TimeoutException('Simulated timeout', timeout);
    if (simulateError) throw Exception('Simulated network error');
  }

  @override
  void send(SignalingMessage message) {
    sentMessages.add(message);
  }

  @override
  void disconnect() {}

  @override
  void dispose() {
    if (!_isClosed) {
      _isClosed = true;
      _messageCtrl.close();
      _closedCtrl.close();
    }
  }

  void pushMessage(SignalingMessage message) {
    _messageCtrl.add(message);
  }

  // Phase 7 추가: 서버 연결 종료 시뮬레이션
  void simulateServerClose() {
    _closedCtrl.add(null);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 테스트 헬퍼
// ══════════════════════════════════════════════════════════════════════════════

({
  ProviderContainer container,
  _FakeWebRTCService fakeWebRTC,
  _FakeSignalingService fakeSignaling,
}) makeContainer() {
  final fakeWebRTC = _FakeWebRTCService();
  final fakeSignaling = _FakeSignalingService();

  final container = ProviderContainer(
    overrides: [
      cameraViewModelProvider.overrideWith(
        (ref) => CameraViewModel(
          webRTCService: fakeWebRTC,
          signalingService: fakeSignaling,
        ),
      ),
    ],
  );
  return (
    container: container,
    fakeWebRTC: fakeWebRTC,
    fakeSignaling: fakeSignaling,
  );
}

Future<void> setupRoomCreated(
  CameraViewModel viewModel,
  _FakeSignalingService fakeSignaling, {
  String roomId = '123456',
}) async {
  await viewModel.startCamera('192.168.0.1');
  fakeSignaling.pushMessage(RoomCreatedMessage(roomId: roomId));
  await Future<void>.delayed(Duration.zero);
}

// ══════════════════════════════════════════════════════════════════════════════
// 테스트
// ══════════════════════════════════════════════════════════════════════════════

void main() {
  // ── CameraState 테스트 ──────────────────────────────────────────────────────
  group('CameraState', () {
    test('기본 생성자 — 초기값 확인', () {
      const state = CameraState();
      expect(state.connectionState, CameraConnectionState.idle);
      expect(state.roomId, isNull);
      // errorMessage는 error getter에서 파생 — error가 null이면 null
      expect(state.errorMessage, isNull);
      expect(state.error, isNull);
    });

    test('copyWith — connectionState만 변경', () {
      const state = CameraState();
      final updated = state.copyWith(
        connectionState: CameraConnectionState.connecting,
      );
      expect(updated.connectionState, CameraConnectionState.connecting);
      expect(updated.roomId, isNull);
      expect(updated.error, isNull);
    });

    test('copyWith — roomId만 변경', () {
      const state = CameraState(
        connectionState: CameraConnectionState.waitingForViewer,
      );
      final updated = state.copyWith(roomId: '654321');
      expect(updated.connectionState, CameraConnectionState.waitingForViewer);
      expect(updated.roomId, '654321');
    });

    // Phase 7: errorMessage → error(ConnectionError)로 변경
    // copyWith에 error: ConnectionError? 파라미터 추가
    test('copyWith — error만 변경', () {
      const state = CameraState();
      final updated = state.copyWith(error: const ServerClosed());
      expect(updated.error, isA<ServerClosed>());
      // errorMessage getter가 ServerClosed를 한국어 문자열로 변환
      expect(updated.errorMessage, isNotNull);
      expect(updated.connectionState, CameraConnectionState.idle);
    });

    test('copyWith — 인자 없으면 동일한 값 유지', () {
      const state = CameraState(
        connectionState: CameraConnectionState.streaming,
        roomId: '999999',
      );
      final updated = state.copyWith();
      expect(updated.connectionState, state.connectionState);
      expect(updated.roomId, state.roomId);
    });

    // Phase 7: errorMessage getter — sealed class switch expression 검증
    test('errorMessage getter — ConnectionError 타입별 한국어 문자열 반환', () {
      expect(
        const CameraState(error: ConnectionTimeout()).errorMessage,
        contains('시간'),
      );
      expect(
        const CameraState(error: RoomNotFound()).errorMessage,
        contains('방'),
      );
      expect(
        const CameraState(error: UnknownConnectionError('raw error'))
            .errorMessage,
        contains('raw error'),
      );
    });
  });

  // ── CameraViewModel 테스트 ──────────────────────────────────────────────────
  group('CameraViewModel', () {
    late ProviderContainer container;
    late _FakeWebRTCService fakeWebRTC;
    late _FakeSignalingService fakeSignaling;
    late CameraViewModel viewModel;

    setUp(() {
      final result = makeContainer();
      container = result.container;
      fakeWebRTC = result.fakeWebRTC;
      fakeSignaling = result.fakeSignaling;
      viewModel = container.read(cameraViewModelProvider.notifier);

      // autoDispose 방지: container.listen()으로 더미 리스너를 붙여 Provider를 살려둔다
      container.listen(cameraViewModelProvider, (_, __) {});
    });

    tearDown(() {
      container.dispose();
    });

    // ── 초기 상태 ─────────────────────────────────────────────────────────────

    test('초기 상태 — idle, roomId/error는 null', () {
      final state = container.read(cameraViewModelProvider);
      expect(state.connectionState, CameraConnectionState.idle);
      expect(state.roomId, isNull);
      expect(state.error, isNull);
      expect(state.errorMessage, isNull);
    });

    // ── startCamera ───────────────────────────────────────────────────────────

    test('startCamera — WebRTCService.initialize/startLocalStream 호출', () async {
      await viewModel.startCamera('192.168.0.1');
      expect(fakeWebRTC.initializeCalled, isTrue);
      expect(fakeWebRTC.startLocalStreamCalled, isTrue);
    });

    test('startCamera — CreateRoomMessage를 시그널링 서버로 전송', () async {
      await viewModel.startCamera('192.168.0.1');
      expect(
        fakeSignaling.sentMessages.whereType<CreateRoomMessage>(),
        hasLength(1),
      );
    });

    test('startCamera — 상태가 waitingForViewer로 전환', () async {
      await viewModel.startCamera('192.168.0.1');
      expect(
        container.read(cameraViewModelProvider).connectionState,
        CameraConnectionState.waitingForViewer,
      );
    });

    test('startCamera 중복 호출 — 두 번째 호출 무시', () async {
      await viewModel.startCamera('192.168.0.1');
      await viewModel.startCamera('192.168.0.1');
      expect(
        fakeSignaling.sentMessages.whereType<CreateRoomMessage>(),
        hasLength(1),
      );
    });

    // Phase 7: 시그널링 연결 타임아웃
    test('startCamera — TimeoutException → error: ConnectionTimeout', () async {
      fakeSignaling.simulateTimeout = true;
      await viewModel.startCamera('192.168.0.1');

      final state = container.read(cameraViewModelProvider);
      expect(state.connectionState, CameraConnectionState.error);
      expect(state.error, isA<ConnectionTimeout>());
    });

    // ── 시그널링 메시지 처리 ──────────────────────────────────────────────────

    test('RoomCreatedMessage 수신 — roomId 저장 및 상태 유지', () async {
      await viewModel.startCamera('192.168.0.1');
      fakeSignaling.pushMessage(const RoomCreatedMessage(roomId: '111111'));
      await Future<void>.delayed(Duration.zero);

      final state = container.read(cameraViewModelProvider);
      expect(state.roomId, '111111');
      expect(state.connectionState, CameraConnectionState.waitingForViewer);
    });

    test('RoomJoinedMessage 수신 — OfferMessage 전송', () async {
      await setupRoomCreated(viewModel, fakeSignaling);

      fakeSignaling.pushMessage(const RoomJoinedMessage(roomId: '123456'));
      await Future<void>.delayed(Duration.zero);

      final offerMessages = fakeSignaling.sentMessages.whereType<OfferMessage>();
      expect(offerMessages, hasLength(1));
      expect(offerMessages.first.roomId, '123456');
      expect(offerMessages.first.sdp['type'], 'offer');
    });

    test('AnswerMessage 수신 — setRemoteDescription 호출', () async {
      await setupRoomCreated(viewModel, fakeSignaling);

      fakeSignaling.pushMessage(
        const AnswerMessage(
          roomId: '123456',
          sdp: {'type': 'answer', 'sdp': 'v=0\r\n'},
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(fakeWebRTC.lastSetRemoteDescription, isNotNull);
      expect(fakeWebRTC.lastSetRemoteDescription!.type, 'answer');
    });

    test('CandidateMessage 수신 — addIceCandidate 호출', () async {
      await setupRoomCreated(viewModel, fakeSignaling);

      fakeSignaling.pushMessage(
        const CandidateMessage(
          roomId: '123456',
          candidate: {
            'candidate': 'candidate:abc123',
            'sdpMid': '0',
            'sdpMLineIndex': 0,
          },
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(fakeWebRTC.addedCandidates, hasLength(1));
      expect(fakeWebRTC.addedCandidates.first.candidate, 'candidate:abc123');
    });

    // Phase 7: peer_disconnected 수신 시 PeerConnection 재초기화
    test('PeerDisconnectedMessage 수신 — PeerConnection 재초기화 후 waitingForViewer 복귀',
        () async {
      await setupRoomCreated(viewModel, fakeSignaling);

      fakeSignaling.pushMessage(const PeerDisconnectedMessage());
      await Future<void>.delayed(Duration.zero);

      final state = container.read(cameraViewModelProvider);
      expect(state.connectionState, CameraConnectionState.waitingForViewer);
      // roomId는 유지 — 같은 번호로 뷰어가 재참여할 수 있어야 한다
      expect(state.roomId, '123456');
      // resetPeerConnection()이 호출되어 PeerConnection이 재초기화됐는지 검증
      expect(fakeWebRTC.resetPeerConnectionCalled, equals(1));
      // 재초기화 후 initialize + startLocalStream 재호출
      expect(fakeWebRTC.initializeCalled, isTrue);
      expect(fakeWebRTC.startLocalStreamCalled, isTrue);
    });

    // Phase 7: RoomErrorMessage → ConnectionError 타입으로 변환
    test('RoomErrorMessage(존재하지 않는 방) 수신 — error: RoomNotFound', () async {
      await viewModel.startCamera('192.168.0.1');
      fakeSignaling.pushMessage(
        const RoomErrorMessage(message: '존재하지 않는 방입니다.'),
      );
      await Future<void>.delayed(Duration.zero);

      final state = container.read(cameraViewModelProvider);
      expect(state.connectionState, CameraConnectionState.error);
      // 서버 메시지 '존재하지 않는 방입니다.'가 RoomNotFound 타입으로 매핑됐는지 확인
      expect(state.error, isA<RoomNotFound>());
    });

    test('RoomErrorMessage(이미 뷰어 연결) 수신 — error: RoomFull', () async {
      await viewModel.startCamera('192.168.0.1');
      fakeSignaling.pushMessage(
        const RoomErrorMessage(message: '이미 뷰어가 연결된 방입니다.'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(cameraViewModelProvider).error,
        isA<RoomFull>(),
      );
    });

    // ── WebRTC 연결 상태 변화 ─────────────────────────────────────────────────

    test('WebRTC connected — streaming 상태로 전환', () async {
      await setupRoomCreated(viewModel, fakeSignaling);

      fakeWebRTC.emitConnectionState(
        RTCPeerConnectionState.RTCPeerConnectionStateConnected,
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(cameraViewModelProvider).connectionState,
        CameraConnectionState.streaming,
      );
    });

    test('WebRTC disconnected — waitingForViewer로 복귀', () async {
      await setupRoomCreated(viewModel, fakeSignaling);
      fakeWebRTC.emitConnectionState(
        RTCPeerConnectionState.RTCPeerConnectionStateConnected,
      );
      await Future<void>.delayed(Duration.zero);

      fakeWebRTC.emitConnectionState(
        RTCPeerConnectionState.RTCPeerConnectionStateDisconnected,
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(cameraViewModelProvider).connectionState,
        CameraConnectionState.waitingForViewer,
      );
    });

    test('WebRTC failed — waitingForViewer로 복귀', () async {
      await setupRoomCreated(viewModel, fakeSignaling);

      fakeWebRTC.emitConnectionState(
        RTCPeerConnectionState.RTCPeerConnectionStateFailed,
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(cameraViewModelProvider).connectionState,
        CameraConnectionState.waitingForViewer,
      );
    });

    // Phase 7: ICE failed → restartIce() 호출
    test('ICE failed — restartIce() 호출', () async {
      await setupRoomCreated(viewModel, fakeSignaling);

      fakeWebRTC.emitIceConnectionState(
        RTCIceConnectionState.RTCIceConnectionStateFailed,
      );
      await Future<void>.delayed(Duration.zero);

      expect(fakeWebRTC.restartIceCalled, isTrue);
    });

    // ── ICE Candidate 전송 ────────────────────────────────────────────────────

    test('WebRTC ICE Candidate 생성 — CandidateMessage로 전송', () async {
      await setupRoomCreated(viewModel, fakeSignaling);

      fakeWebRTC.emitIceCandidate(RTCIceCandidate('candidate:xyz', '0', 0));
      await Future<void>.delayed(Duration.zero);

      final candidateMessages =
          fakeSignaling.sentMessages.whereType<CandidateMessage>().toList();
      expect(candidateMessages, hasLength(1));
      expect(candidateMessages.first.candidate['candidate'], 'candidate:xyz');
      expect(candidateMessages.first.roomId, '123456');
    });

    test('roomId 없을 때 ICE Candidate 발생 — 전송 안 함', () async {
      await viewModel.startCamera('192.168.0.1');

      fakeWebRTC.emitIceCandidate(RTCIceCandidate('candidate:xyz', '0', 0));
      await Future<void>.delayed(Duration.zero);

      expect(
        fakeSignaling.sentMessages.whereType<CandidateMessage>(),
        isEmpty,
      );
    });

    // ── stopCamera ────────────────────────────────────────────────────────────

    test('stopCamera — idle 상태로 초기화', () async {
      await setupRoomCreated(viewModel, fakeSignaling);

      await viewModel.stopCamera();

      final state = container.read(cameraViewModelProvider);
      expect(state.connectionState, CameraConnectionState.idle);
      expect(state.roomId, isNull);
      expect(state.error, isNull);
      expect(state.errorMessage, isNull);
    });

    test('stopCamera 후 startCamera — 재시작 가능', () async {
      await viewModel.startCamera('192.168.0.1');
      await viewModel.stopCamera();

      await viewModel.startCamera('192.168.0.2');

      expect(
        container.read(cameraViewModelProvider).connectionState,
        CameraConnectionState.waitingForViewer,
      );
    });

    // Phase 7: 서버 연결 종료 → 재연결 스케줄링
    test('시그널링 서버 연결 종료 — connecting 상태로 전환 (재연결 대기)', () async {
      await setupRoomCreated(viewModel, fakeSignaling);

      // simulateServerClose(): signalingService.onClosed 이벤트 발행
      fakeSignaling.simulateServerClose();
      await Future<void>.delayed(Duration.zero);

      // 재연결 시도 중: connecting 상태여야 한다
      expect(
        container.read(cameraViewModelProvider).connectionState,
        CameraConnectionState.connecting,
      );
    });
  });
}
