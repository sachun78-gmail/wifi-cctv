import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

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
// 실수로 테스트에서 구현되지 않은 메서드를 호출하면 즉시 알 수 있어 안전하다.
// ══════════════════════════════════════════════════════════════════════════════

/// WebRTCService를 대체하는 테스트용 Fake.
///
/// 모든 async 메서드는 즉시 완료(return)되어 네이티브 호출 없이 동작한다.
/// StreamController를 외부에 노출하여 테스트에서 이벤트를 직접 주입할 수 있다.
class _FakeWebRTCService extends Fake implements WebRTCService {
  // StreamController.broadcast(): 여러 리스너가 붙을 수 있는 스트림 생성
  // ViewModel 내부의 _listenToIceCandidates()와 _listenToConnectionState()가 구독한다
  final _iceCandidateCtrl =
      StreamController<RTCIceCandidate>.broadcast();
  final _connectionStateCtrl =
      StreamController<RTCPeerConnectionState>.broadcast();

  // 테스트에서 호출 여부를 검증하기 위한 기록용 변수
  var initializeCalled = false;
  var startLocalStreamCalled = false;
  RTCSessionDescription? lastSetRemoteDescription;
  final List<RTCIceCandidate> addedCandidates = [];

  // ── WebRTCService 인터페이스 구현 ────────────────────────────────────────

  @override
  Stream<RTCIceCandidate> get onIceCandidate => _iceCandidateCtrl.stream;

  @override
  Stream<RTCPeerConnectionState> get onConnectionState =>
      _connectionStateCtrl.stream;

  @override
  Stream<MediaStream> get onRemoteStream =>
      StreamController<MediaStream>.broadcast().stream;

  /// localStream: 카메라 폰에서 실제 스트림이 없으므로 null 반환
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

  /// createOffer(): 실제 SDP 대신 더미 RTCSessionDescription 반환
  @override
  Future<RTCSessionDescription> createOffer() async {
    // RTCSessionDescription은 순수 Dart 데이터 클래스 — 네이티브 호출 없음
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

  @override
  Future<void> dispose() async {
    await _iceCandidateCtrl.close();
    await _connectionStateCtrl.close();
  }

  // ── 테스트 헬퍼 메서드 ───────────────────────────────────────────────────

  /// 테스트에서 ICE Candidate 이벤트를 ViewModel에 주입
  void emitIceCandidate(RTCIceCandidate candidate) {
    _iceCandidateCtrl.add(candidate);
  }

  /// 테스트에서 WebRTC 연결 상태 변화를 ViewModel에 주입
  void emitConnectionState(RTCPeerConnectionState state) {
    _connectionStateCtrl.add(state);
  }
}

/// SignalingService를 대체하는 테스트용 Fake.
///
/// WebSocket 연결 없이 인메모리로 동작한다.
/// [sentMessages]로 ViewModel이 보낸 메시지를 수집하고,
/// [pushMessage]로 서버에서 온 것처럼 메시지를 ViewModel에 주입한다.
class _FakeSignalingService extends Fake implements SignalingService {
  final _messageCtrl = StreamController<SignalingMessage>.broadcast();

  // ViewModel이 send()로 보낸 메시지 목록 — 테스트에서 검증용
  final List<SignalingMessage> sentMessages = [];

  @override
  Stream<SignalingMessage> get messages => _messageCtrl.stream;

  @override
  bool get isConnected => true;

  @override
  Future<void> connect(String url) async {
    // 즉시 연결 성공으로 처리
  }

  @override
  void send(SignalingMessage message) {
    sentMessages.add(message);
  }

  @override
  void disconnect() {}

  @override
  void dispose() {
    _messageCtrl.close();
  }

  // ── 테스트 헬퍼 메서드 ───────────────────────────────────────────────────

  /// 서버에서 온 것처럼 메시지를 ViewModel에 주입
  void pushMessage(SignalingMessage message) {
    _messageCtrl.add(message);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 테스트 헬퍼
// ══════════════════════════════════════════════════════════════════════════════

/// ProviderContainer를 생성하고 Fake 서비스로 ViewModel을 교체한다.
///
/// ProviderContainer: Riverpod Provider를 위젯 트리 없이 순수 Dart로 테스트할 때 사용.
/// overrides: 실제 구현 대신 Fake를 주입할 때 사용.
({
  ProviderContainer container,
  _FakeWebRTCService fakeWebRTC,
  _FakeSignalingService fakeSignaling,
}) makeContainer() {
  final fakeWebRTC = _FakeWebRTCService();
  final fakeSignaling = _FakeSignalingService();

  final container = ProviderContainer(
    overrides: [
      // overrideWith: 이 테스트에서만 다른 ViewModel 인스턴스를 사용하도록 교체
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

/// startCamera 호출 후 RoomCreatedMessage를 주입하여 roomId까지 설정하는 헬퍼.
///
/// 여러 테스트에서 공통으로 필요한 "방 생성 완료" 상태를 만들어준다.
Future<void> setupRoomCreated(
  CameraViewModel viewModel,
  _FakeSignalingService fakeSignaling, {
  String roomId = '123456',
}) async {
  await viewModel.startCamera('192.168.0.1');
  fakeSignaling.pushMessage(RoomCreatedMessage(roomId: roomId));
  // Future.delayed(Duration.zero): 현재 실행 중인 microtask/event 를 모두 처리하고 다음 이벤트 루프 턴으로 넘김
  // Stream 리스너 콜백이 비동기로 실행되므로, 호출 직후 바로 검증하면 아직 처리 안 됨
  // Duration.zero로 한 틱을 기다리면 콜백이 처리된 후 검증할 수 있다
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
      expect(state.errorMessage, isNull);
    });

    test('copyWith — connectionState만 변경', () {
      const state = CameraState();
      final updated = state.copyWith(
        connectionState: CameraConnectionState.connecting,
      );
      expect(updated.connectionState, CameraConnectionState.connecting);
      expect(updated.roomId, isNull); // 나머지는 유지
      expect(updated.errorMessage, isNull);
    });

    test('copyWith — roomId만 변경', () {
      const state = CameraState(
        connectionState: CameraConnectionState.waitingForViewer,
      );
      final updated = state.copyWith(roomId: '654321');
      expect(updated.connectionState, CameraConnectionState.waitingForViewer); // 유지
      expect(updated.roomId, '654321');
    });

    test('copyWith — errorMessage만 변경', () {
      const state = CameraState();
      final updated = state.copyWith(errorMessage: '연결 실패');
      expect(updated.errorMessage, '연결 실패');
      expect(updated.connectionState, CameraConnectionState.idle); // 유지
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

      // notifier: StateNotifierProvider에서 ViewModel(StateNotifier) 자체를 읽는 방법
      viewModel = container.read(cameraViewModelProvider.notifier);

      // ★ autoDispose 방지를 위한 활성 리스너 등록 ★
      //
      // 문제: autoDispose Provider는 활성 리스너(watch/listen)가 없으면
      //   이벤트 루프의 다음 턴(await 이후)에 즉시 dispose된다.
      //   테스트에서 container.read()만 하면 리스너가 없어서,
      //   await Future.delayed(Duration.zero) 이후 Provider가 사라진다.
      //
      // 해결: container.listen()으로 더미 리스너를 붙여 Provider를 살려둔다.
      //   테스트가 끝나면 tearDown의 container.dispose()가 이 리스너도 함께 정리한다.
      container.listen(cameraViewModelProvider, (_, __) {});
    });

    tearDown(() {
      // ProviderContainer.dispose(): autoDispose Provider의 dispose()를 호출
      // → CameraViewModel.dispose() → _cleanup() 호출
      // → container에 붙인 listen 구독도 함께 정리됨
      container.dispose();
    });

    // ── 초기 상태 ─────────────────────────────────────────────────────────────

    test('초기 상태 — idle, roomId/errorMessage는 null', () {
      final state = container.read(cameraViewModelProvider);
      expect(state.connectionState, CameraConnectionState.idle);
      expect(state.roomId, isNull);
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
      // sentMessages: Fake가 수집한 ViewModel이 보낸 메시지 목록
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
      // CreateRoomMessage가 한 번만 전송되어야 함
      expect(
        fakeSignaling.sentMessages.whereType<CreateRoomMessage>(),
        hasLength(1),
      );
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
      // roomId가 설정된 상태여야 offer에 포함할 수 있음
      await setupRoomCreated(viewModel, fakeSignaling);

      fakeSignaling.pushMessage(const RoomJoinedMessage(roomId: '123456'));
      await Future<void>.delayed(Duration.zero);

      final offerMessages = fakeSignaling.sentMessages.whereType<OfferMessage>();
      expect(offerMessages, hasLength(1));
      expect(offerMessages.first.roomId, '123456');
      // SDP type이 'offer'인지 확인
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
      expect(fakeWebRTC.lastSetRemoteDescription!.sdp, 'v=0\r\n');
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
      expect(fakeWebRTC.addedCandidates.first.sdpMid, '0');
    });

    test('PeerDisconnectedMessage 수신 — waitingForViewer 상태로 복귀', () async {
      await setupRoomCreated(viewModel, fakeSignaling);

      fakeSignaling.pushMessage(const PeerDisconnectedMessage());
      await Future<void>.delayed(Duration.zero);

      final state = container.read(cameraViewModelProvider);
      expect(state.connectionState, CameraConnectionState.waitingForViewer);
      // roomId는 유지되어야 뷰어가 다시 참여할 수 있음
      expect(state.roomId, '123456');
    });

    test('RoomErrorMessage 수신 — error 상태, errorMessage 설정', () async {
      await viewModel.startCamera('192.168.0.1');
      fakeSignaling.pushMessage(
        const RoomErrorMessage(message: '존재하지 않는 방입니다.'),
      );
      await Future<void>.delayed(Duration.zero);

      final state = container.read(cameraViewModelProvider);
      expect(state.connectionState, CameraConnectionState.error);
      expect(state.errorMessage, '존재하지 않는 방입니다.');
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
      // 먼저 connected 상태로 만들고
      fakeWebRTC.emitConnectionState(
        RTCPeerConnectionState.RTCPeerConnectionStateConnected,
      );
      await Future<void>.delayed(Duration.zero);

      // 그 다음 disconnected
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

    // ── ICE Candidate 전송 ────────────────────────────────────────────────────

    test('WebRTC ICE Candidate 생성 — CandidateMessage로 전송', () async {
      await setupRoomCreated(viewModel, fakeSignaling);

      // 로컬에서 ICE Candidate가 발견된 것처럼 이벤트 주입
      fakeWebRTC.emitIceCandidate(
        RTCIceCandidate('candidate:xyz', '0', 0),
      );
      await Future<void>.delayed(Duration.zero);

      final candidateMessages =
          fakeSignaling.sentMessages.whereType<CandidateMessage>().toList();
      expect(candidateMessages, hasLength(1));
      expect(candidateMessages.first.candidate['candidate'], 'candidate:xyz');
      expect(candidateMessages.first.roomId, '123456');
    });

    test('roomId 없을 때 ICE Candidate 발생 — 전송 안 함', () async {
      // startCamera만 하고 RoomCreatedMessage는 받지 않은 상태
      await viewModel.startCamera('192.168.0.1');

      fakeWebRTC.emitIceCandidate(
        RTCIceCandidate('candidate:xyz', '0', 0),
      );
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
      expect(state.errorMessage, isNull);
    });

    test('stopCamera 후 startCamera — 재시작 가능', () async {
      await viewModel.startCamera('192.168.0.1');
      await viewModel.stopCamera();

      // idle 상태이므로 다시 시작 가능
      await viewModel.startCamera('192.168.0.2');

      expect(
        container.read(cameraViewModelProvider).connectionState,
        CameraConnectionState.waitingForViewer,
      );
    });
  });
}
