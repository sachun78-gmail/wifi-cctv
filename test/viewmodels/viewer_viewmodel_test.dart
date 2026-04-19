import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:wifi_cctv/models/signaling_message.dart';
import 'package:wifi_cctv/services/signaling_service.dart';
import 'package:wifi_cctv/services/webrtc_service.dart';
import 'package:wifi_cctv/viewmodels/viewer_viewmodel.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Fake 구현체
//
// flutter_webrtc는 네이티브 바인딩(Android/iOS)이 필요해서 유닛 테스트에서
// 직접 사용할 수 없다. 대신 Fake 클래스를 만들어 네이티브 호출 없이
// 동일한 인터페이스를 흉내 낸다.
//
// Fake (package:test): noSuchMethod를 UnimplementedError로 오버라이드한다.
// 명시적으로 override하지 않은 메서드를 호출하면 즉시 실패 → 구현 누락을 빠르게 발견할 수 있다.
// ══════════════════════════════════════════════════════════════════════════════

/// WebRTCService를 대체하는 테스트용 Fake.
///
/// 뷰어 역할이므로 CameraViewModel 테스트의 Fake와 달리 createAnswer()가 추가된다.
/// (카메라 폰은 createOffer(), 뷰어 폰은 createAnswer()를 호출)
class _FakeWebRTCService extends Fake implements WebRTCService {
  // StreamController.broadcast(): 여러 리스너가 붙을 수 있는 스트림 생성
  final _iceCandidateCtrl = StreamController<RTCIceCandidate>.broadcast();
  final _connectionStateCtrl =
      StreamController<RTCPeerConnectionState>.broadcast();
  final _remoteStreamCtrl = StreamController<MediaStream>.broadcast();

  // 테스트에서 호출 여부를 검증하기 위한 기록용 변수
  var initializeCalled = false;
  RTCSessionDescription? lastSetRemoteDescription;
  var createAnswerCalled = false;
  final List<RTCIceCandidate> addedCandidates = [];

  // ── WebRTCService 인터페이스 구현 ────────────────────────────────────────

  @override
  Stream<RTCIceCandidate> get onIceCandidate => _iceCandidateCtrl.stream;

  @override
  Stream<RTCPeerConnectionState> get onConnectionState =>
      _connectionStateCtrl.stream;

  @override
  Stream<MediaStream> get onRemoteStream => _remoteStreamCtrl.stream;

  @override
  Future<void> initialize() async {
    initializeCalled = true;
  }

  @override
  Future<void> setRemoteDescription(RTCSessionDescription description) async {
    lastSetRemoteDescription = description;
  }

  /// createAnswer(): 실제 SDP 대신 더미 RTCSessionDescription 반환.
  /// RTCSessionDescription은 순수 Dart 데이터 클래스 — 네이티브 호출 없음.
  @override
  Future<RTCSessionDescription> createAnswer() async {
    createAnswerCalled = true;
    return RTCSessionDescription('v=0\r\no=- 0 0 IN IP4 127.0.0.1\r\n', 'answer');
  }

  @override
  Future<void> addIceCandidate(RTCIceCandidate candidate) async {
    addedCandidates.add(candidate);
  }

  @override
  Future<void> dispose() async {
    await _iceCandidateCtrl.close();
    await _connectionStateCtrl.close();
    await _remoteStreamCtrl.close();
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
/// overrides: 실제 서비스 대신 Fake를 주입하여 네이티브 의존성 없이 테스트 가능하게 한다.
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
      viewerViewModelProvider.overrideWith(
        (ref) => ViewerViewModel(
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

/// joinRoom 호출 후 RoomJoinedMessage까지 주입하는 헬퍼.
///
/// 여러 테스트에서 공통으로 필요한 "방 참여 완료" 상태를 빠르게 만들어준다.
Future<void> setupRoomJoined(
  ViewerViewModel viewModel,
  _FakeSignalingService fakeSignaling, {
  String host = '192.168.0.1',
  String roomId = '123456',
}) async {
  await viewModel.joinRoom(host, roomId);
  fakeSignaling.pushMessage(RoomJoinedMessage(roomId: roomId));
  // Future.delayed(Duration.zero): 현재 microtask/event를 모두 처리한 뒤 다음 이벤트 루프로 넘김.
  // Stream 리스너 콜백이 비동기로 실행되므로, Duration.zero 한 틱을 기다려야 콜백이 처리된다.
  await Future<void>.delayed(Duration.zero);
}

/// joinRoom → RoomJoined → OfferMessage 주입까지 완료하는 헬퍼.
///
/// Offer 수신 이후 동작을 테스트할 때 사용한다.
Future<void> setupOfferReceived(
  ViewerViewModel viewModel,
  _FakeSignalingService fakeSignaling, {
  String roomId = '123456',
}) async {
  await setupRoomJoined(viewModel, fakeSignaling, roomId: roomId);
  fakeSignaling.pushMessage(
    OfferMessage(
      roomId: roomId,
      sdp: const {'type': 'offer', 'sdp': 'v=0\r\n'},
    ),
  );
  await Future<void>.delayed(Duration.zero);
}

// ══════════════════════════════════════════════════════════════════════════════
// 테스트
// ══════════════════════════════════════════════════════════════════════════════

void main() {
  // ── ViewerState 테스트 ───────────────────────────────────────────────────────
  group('ViewerState', () {
    test('기본 생성자 — 초기값 확인', () {
      const state = ViewerState();
      expect(state.connectionState, ViewerConnectionState.idle);
      expect(state.roomId, isNull);
      expect(state.errorMessage, isNull);
    });

    test('copyWith — connectionState만 변경', () {
      const state = ViewerState();
      final updated = state.copyWith(
        connectionState: ViewerConnectionState.connecting,
      );
      expect(updated.connectionState, ViewerConnectionState.connecting);
      expect(updated.roomId, isNull); // 나머지는 유지
      expect(updated.errorMessage, isNull);
    });

    test('copyWith — roomId만 변경', () {
      const state = ViewerState(
        connectionState: ViewerConnectionState.waitingForOffer,
      );
      final updated = state.copyWith(roomId: '654321');
      expect(updated.connectionState, ViewerConnectionState.waitingForOffer); // 유지
      expect(updated.roomId, '654321');
    });

    test('copyWith — errorMessage만 변경', () {
      const state = ViewerState();
      final updated = state.copyWith(errorMessage: '연결 실패');
      expect(updated.errorMessage, '연결 실패');
      expect(updated.connectionState, ViewerConnectionState.idle); // 유지
    });

    test('copyWith — 인자 없으면 동일한 값 유지', () {
      const state = ViewerState(
        connectionState: ViewerConnectionState.streaming,
        roomId: '999999',
      );
      final updated = state.copyWith();
      expect(updated.connectionState, state.connectionState);
      expect(updated.roomId, state.roomId);
    });
  });

  // ── ViewerViewModel 테스트 ───────────────────────────────────────────────────
  group('ViewerViewModel', () {
    late ProviderContainer container;
    late _FakeWebRTCService fakeWebRTC;
    late _FakeSignalingService fakeSignaling;
    late ViewerViewModel viewModel;

    setUp(() {
      final result = makeContainer();
      container = result.container;
      fakeWebRTC = result.fakeWebRTC;
      fakeSignaling = result.fakeSignaling;

      // notifier: StateNotifierProvider에서 ViewModel(StateNotifier) 자체를 읽는 방법
      viewModel = container.read(viewerViewModelProvider.notifier);

      // ★ autoDispose 방지를 위한 활성 리스너 등록 ★
      //
      // 문제: autoDispose Provider는 활성 리스너(watch/listen)가 없으면
      //   이벤트 루프의 다음 턴(await 이후)에 즉시 dispose된다.
      //   container.read()만 하면 리스너가 없어서,
      //   await Future.delayed(Duration.zero) 이후 Provider가 사라진다.
      //
      // 해결: container.listen()으로 더미 리스너를 붙여 Provider를 살려둔다.
      //   tearDown에서 container.dispose()가 이 리스너도 함께 정리한다.
      container.listen(viewerViewModelProvider, (_, __) {});
    });

    tearDown(() {
      // ProviderContainer.dispose(): autoDispose Provider의 dispose()를 호출
      // → ViewerViewModel.dispose() → _cleanup() 호출
      container.dispose();
    });

    // ── 초기 상태 ─────────────────────────────────────────────────────────────

    test('초기 상태 — idle, roomId/errorMessage는 null', () {
      final state = container.read(viewerViewModelProvider);
      expect(state.connectionState, ViewerConnectionState.idle);
      expect(state.roomId, isNull);
      expect(state.errorMessage, isNull);
    });

    // ── joinRoom ──────────────────────────────────────────────────────────────

    test('joinRoom — WebRTCService.initialize 호출 (startLocalStream은 호출 안 함)', () async {
      await viewModel.joinRoom('192.168.0.1', '123456');
      // 뷰어는 영상을 수신만 하므로 로컬 스트림을 시작하지 않는다
      expect(fakeWebRTC.initializeCalled, isTrue);
    });

    test('joinRoom — JoinRoomMessage를 시그널링 서버로 전송', () async {
      await viewModel.joinRoom('192.168.0.1', '123456');
      final joinMessages = fakeSignaling.sentMessages.whereType<JoinRoomMessage>();
      expect(joinMessages, hasLength(1));
      expect(joinMessages.first.roomId, '123456');
    });

    test('joinRoom — roomId가 상태에 저장됨', () async {
      await viewModel.joinRoom('192.168.0.1', '654321');
      expect(container.read(viewerViewModelProvider).roomId, '654321');
    });

    test('joinRoom 중복 호출 — 두 번째 호출 무시', () async {
      await viewModel.joinRoom('192.168.0.1', '123456');
      await viewModel.joinRoom('192.168.0.1', '999999');
      // JoinRoomMessage가 한 번만 전송되어야 함
      expect(
        fakeSignaling.sentMessages.whereType<JoinRoomMessage>(),
        hasLength(1),
      );
    });

    // ── 시그널링 메시지 처리 ──────────────────────────────────────────────────

    test('RoomJoinedMessage 수신 — waitingForOffer 상태로 전환', () async {
      await viewModel.joinRoom('192.168.0.1', '123456');
      fakeSignaling.pushMessage(const RoomJoinedMessage(roomId: '123456'));
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(viewerViewModelProvider).connectionState,
        ViewerConnectionState.waitingForOffer,
      );
    });

    test('OfferMessage 수신 — setRemoteDescription 호출', () async {
      await setupRoomJoined(viewModel, fakeSignaling);

      fakeSignaling.pushMessage(
        const OfferMessage(
          roomId: '123456',
          sdp: {'type': 'offer', 'sdp': 'v=0\r\n'},
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(fakeWebRTC.lastSetRemoteDescription, isNotNull);
      expect(fakeWebRTC.lastSetRemoteDescription!.type, 'offer');
      expect(fakeWebRTC.lastSetRemoteDescription!.sdp, 'v=0\r\n');
    });

    test('OfferMessage 수신 — createAnswer 호출', () async {
      await setupRoomJoined(viewModel, fakeSignaling);

      fakeSignaling.pushMessage(
        const OfferMessage(
          roomId: '123456',
          sdp: {'type': 'offer', 'sdp': 'v=0\r\n'},
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(fakeWebRTC.createAnswerCalled, isTrue);
    });

    test('OfferMessage 수신 — AnswerMessage를 시그널링 서버로 전송', () async {
      await setupRoomJoined(viewModel, fakeSignaling);

      fakeSignaling.pushMessage(
        const OfferMessage(
          roomId: '123456',
          sdp: {'type': 'offer', 'sdp': 'v=0\r\n'},
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final answerMessages = fakeSignaling.sentMessages.whereType<AnswerMessage>();
      expect(answerMessages, hasLength(1));
      expect(answerMessages.first.roomId, '123456');
      // createAnswer()가 반환한 더미 SDP type이 'answer'인지 확인
      expect(answerMessages.first.sdp['type'], 'answer');
    });

    test('CandidateMessage 수신 — addIceCandidate 호출', () async {
      await setupRoomJoined(viewModel, fakeSignaling);

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

    test('PeerDisconnectedMessage 수신 — idle 상태, 에러 메시지 설정', () async {
      await setupRoomJoined(viewModel, fakeSignaling);

      fakeSignaling.pushMessage(const PeerDisconnectedMessage());
      await Future<void>.delayed(Duration.zero);

      final state = container.read(viewerViewModelProvider);
      // 카메라와 달리 뷰어는 idle로 복귀 (카메라가 사라졌으므로 재입력 필요)
      expect(state.connectionState, ViewerConnectionState.idle);
      expect(state.errorMessage, isNotNull);
    });

    test('RoomErrorMessage 수신 — error 상태, errorMessage 설정', () async {
      await viewModel.joinRoom('192.168.0.1', '000000');
      fakeSignaling.pushMessage(
        const RoomErrorMessage(message: '존재하지 않는 방입니다.'),
      );
      await Future<void>.delayed(Duration.zero);

      final state = container.read(viewerViewModelProvider);
      expect(state.connectionState, ViewerConnectionState.error);
      expect(state.errorMessage, '존재하지 않는 방입니다.');
    });

    // ── WebRTC 연결 상태 변화 ─────────────────────────────────────────────────

    test('WebRTC connected — streaming 상태로 전환', () async {
      await setupOfferReceived(viewModel, fakeSignaling);

      fakeWebRTC.emitConnectionState(
        RTCPeerConnectionState.RTCPeerConnectionStateConnected,
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(viewerViewModelProvider).connectionState,
        ViewerConnectionState.streaming,
      );
    });

    test('WebRTC disconnected — idle 상태로 복귀, 에러 메시지 설정', () async {
      await setupOfferReceived(viewModel, fakeSignaling);
      fakeWebRTC.emitConnectionState(
        RTCPeerConnectionState.RTCPeerConnectionStateConnected,
      );
      await Future<void>.delayed(Duration.zero);

      fakeWebRTC.emitConnectionState(
        RTCPeerConnectionState.RTCPeerConnectionStateDisconnected,
      );
      await Future<void>.delayed(Duration.zero);

      final state = container.read(viewerViewModelProvider);
      expect(state.connectionState, ViewerConnectionState.idle);
      expect(state.errorMessage, isNotNull);
    });

    test('WebRTC failed — idle 상태로 복귀', () async {
      await setupOfferReceived(viewModel, fakeSignaling);

      fakeWebRTC.emitConnectionState(
        RTCPeerConnectionState.RTCPeerConnectionStateFailed,
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(viewerViewModelProvider).connectionState,
        ViewerConnectionState.idle,
      );
    });

    // ── ICE Candidate 전송 ────────────────────────────────────────────────────

    test('WebRTC ICE Candidate 생성 — CandidateMessage로 전송', () async {
      await setupRoomJoined(viewModel, fakeSignaling);

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

    // ── stopViewer ────────────────────────────────────────────────────────────

    test('stopViewer — idle 상태로 초기화', () async {
      await setupRoomJoined(viewModel, fakeSignaling);

      await viewModel.stopViewer();

      final state = container.read(viewerViewModelProvider);
      expect(state.connectionState, ViewerConnectionState.idle);
      expect(state.roomId, isNull);
      expect(state.errorMessage, isNull);
    });

    test('stopViewer 후 joinRoom — 재시작 가능', () async {
      await viewModel.joinRoom('192.168.0.1', '123456');
      await viewModel.stopViewer();

      // idle 상태이므로 다시 시작 가능
      await viewModel.joinRoom('192.168.0.1', '654321');

      expect(
        container.read(viewerViewModelProvider).connectionState,
        ViewerConnectionState.connecting,
      );
    });

    test('error 상태에서 joinRoom — 재시작 가능', () async {
      await viewModel.joinRoom('192.168.0.1', '000000');
      fakeSignaling.pushMessage(
        const RoomErrorMessage(message: '존재하지 않는 방입니다.'),
      );
      await Future<void>.delayed(Duration.zero);

      // error 상태에서도 다시 joinRoom 호출 가능
      await viewModel.joinRoom('192.168.0.1', '111111');

      expect(
        container.read(viewerViewModelProvider).connectionState,
        ViewerConnectionState.connecting,
      );
    });
  });
}
