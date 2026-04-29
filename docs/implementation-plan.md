# Implementation Plan

> 구현 계획을 단계별로 기록합니다.

---

## Phase 1: 프로젝트 초기 설정
- **상태**: ✅ 완료 (2026-04-06)
- **목표**: Flutter 프로젝트 생성 및 기본 의존성 설정
- **프로젝트 위치**: `D:/_work/Study/Android/wifiCtrl/` (루트에 직접 생성)
- **작업 목록**:
  - [x] Flutter 프로젝트 생성 (`flutter create --org com.wificctv --project-name wifi_cctv .`)
  - [x] pubspec.yaml 의존성 추가
    - flutter_riverpod ^2.6.1 (상태 관리)
    - flutter_webrtc ^0.12.5 (WebRTC)
    - web_socket_channel ^3.0.1 (WebSocket 통신)
    - go_router ^14.8.1 (라우팅)
    - freezed_annotation + json_annotation (모델 어노테이션)
    - dev: freezed, json_serializable, build_runner (코드 생성)
  - [x] MVVM 패키지 구조 생성 (models, services, viewmodels, views, utils)
  - [x] Riverpod ProviderScope 설정
  - [x] Android 설정 (카메라/마이크/인터넷 퍼미션)
  - [x] go_router 라우팅 설정 (/, /camera, /viewer)
  - [x] HomeView, CameraView, ViewerView 스켈레톤 생성
  - [x] 빌드 및 에뮬레이터 실행 확인

---

## Phase 2: 시그널링 서버 구현
- **상태**: ✅ 완료 (2026-04-06)
- **목표**: WebSocket 기반 시그널링 서버 구현 (방 생성/참여, SDP/ICE 교환)
- **포트**: 9090 (환경변수 `PORT`로 변경 가능)
- **상세 설계**: [architecture.md → Signaling Server 섹션](architecture.md#signaling-server) 참조
- **작업 목록**:
  - [x] Node.js 서버 프로젝트 생성 (`signaling_server/`, `npm init`, `ws` 패키지 설치)
  - [x] room-manager.js 구현 (방 생성/참여/제거, 6자리 랜덤 ID)
  - [x] message-handler.js 구현 (메시지 타입별 처리 및 상대방 중계)
  - [x] server.js 구현 (WebSocket 서버 시작, 연결/해제 처리)
  - [x] 테스트 작성 (node:test + ws 클라이언트, 메시지 라우팅 검증) — 10/10 통과

---

## Phase 3: WebRTC 서비스 구현
- **상태**: ✅ 완료 (2026-04-10)
- **목표**: WebRTC PeerConnection 생성, 미디어 스트림 관리
- **작업 목록**:
  - [x] WebRTCService 구현 (`lib/services/webrtc_service.dart`)
    - RTCPeerConnection 생성/관리
    - Local/Remote MediaStream 관리
    - SDP Offer/Answer 생성
    - ICE Candidate 처리
  - [x] SignalingService 구현 (`lib/services/signaling_service.dart`)
    - WebSocket 연결 관리
    - 메시지 송수신 (JSON 직렬화/역직렬화)
    - channelFactory 주입으로 테스트 가능하게 리팩토링
  - [x] 시그널링 메시지 모델 정의 (`lib/models/signaling_message.dart`) — Dart 3 sealed class (codegen 불필요)
  - [x] Room 모델 정의 (`lib/models/room.dart`)
  - [x] 상수 정의 (`lib/utils/constants.dart`) — `AppConstants.signalingUrl(host)`
  - [x] 테스트 작성 — 24개 통과 (SignalingMessage 16개 + SignalingService 8개)
    - WebRTCService: flutter_webrtc 네이티브 바인딩 필요 → Phase 7 통합 테스트로 분류

---

## Phase 4: 카메라 모드 구현
- **상태**: ✅ 완료 (2026-04-15)
- **목표**: 카메라 폰에서 영상 캡처 → WebRTC로 스트리밍
- **작업 목록**:
  - [x] CameraViewModel 구현 (`lib/viewmodels/camera_viewmodel.dart`)
    - `CameraConnectionState` 열거형 (idle/connecting/waitingForViewer/streaming/error)
    - `CameraState` 불변 상태 클래스 + copyWith 패턴
    - `StateNotifierProvider.autoDispose`로 Provider 등록
    - 방 생성 → 뷰어 대기 → Offer 생성/전송 → Answer 수신 → ICE 교환 흐름
    - 모든 Stream 구독 cleanup (메모리 누수 방지)
  - [x] CameraView 구현 (`lib/views/camera_view.dart`)
    - `ConsumerStatefulWidget` (RTCVideoRenderer 생명주기 관리)
    - 로컬 카메라 미리보기 (RTCVideoView + RTCVideoRenderer)
    - 방 ID 오버레이 표시 (뷰어 대기 중 크게 표시)
    - 연결 상태 배지 (_StatusBadge)
    - 서버 IP 입력 + 시작/중지 버튼
  - [x] 카메라 권한 처리 — Phase 1에서 AndroidManifest.xml 설정 완료,
        flutter_webrtc가 getUserMedia() 호출 시 런타임 권한 자동 요청
  - [x] 테스트 작성 (`test/viewmodels/camera_viewmodel_test.dart`) — 23개 통과
    - CameraState: 5개 (초기값, copyWith 패턴)
    - CameraViewModel: 18개 (시그널링 흐름, WebRTC 상태, ICE, stopCamera)
    - Fake 패턴: _FakeWebRTCService(Fake implements), _FakeSignalingService(Fake implements)
    - autoDispose 주의: container.listen()으로 Provider 유지 (학습 포인트)

---

## Phase 5: 뷰어 모드 구현
- **상태**: ✅ 완료 (2026-04-17)
- **목표**: 뷰어 폰에서 WebRTC로 영상 수신 및 표시
- **설계 결정**:
  - UI는 Phase 4 CameraView 패턴과 동일하게 구성 (하단 컨트롤 패널 + 영상 영역)
  - 시그널링 메시지는 기존 모델(`JoinRoomMessage`, `RoomJoinedMessage`, `OfferMessage`, `AnswerMessage`, `CandidateMessage`, `PeerDisconnectedMessage`, `RoomErrorMessage`) 재사용 — 신규 정의 불필요
- **작업 목록**:
  - [x] ViewerViewModel 구현 (`lib/viewmodels/viewer_viewmodel.dart`)
    - `ViewerConnectionState` 열거형 (idle/connecting/waitingForOffer/streaming/error)
    - `ViewerState` 불변 상태 클래스 + copyWith 패턴 (roomId, connectionState, errorMessage)
    - `StateNotifierProvider.autoDispose`로 Provider 등록 (Phase 4 대칭)
    - 방 참여 흐름: `joinRoom(host, roomId)` → `JoinRoomMessage` 전송 → `RoomJoinedMessage` 수신 → `OfferMessage` 수신 → `setRemoteDescription` → Answer 생성/전송 → ICE 교환 → remote stream 수신
    - 모든 Stream 구독 cleanup (메모리 누수 방지)
  - [x] ViewerView 구현 (`lib/views/viewer_view.dart`) — Phase 4 CameraView와 동일 패턴
    - `ConsumerStatefulWidget` (RTCVideoRenderer 생명주기 관리)
    - 상단: 원격 영상 영역 (RTCVideoView, `mirror: false`) + 상태 배지 오버레이
    - 하단 컨트롤 패널:
      - 에러 메시지 영역
      - 시작 전: 서버 IP TextField + 방 ID TextField (6자리 숫자)
      - 시작 후: 방 ID/상태 텍스트 표시
      - 참여/중지 버튼 (연결 중에는 비활성 + 스피너)
    - `_serverHostController` 기본값 `'192.168.0.'` (CameraView와 동일)
    - `_roomIdController` 6자리 숫자 입력
  - [x] 테스트 작성 (`test/viewmodels/viewer_viewmodel_test.dart`) — 24개 통과
    - ViewerState: 5개 (초기값, copyWith 패턴)
    - ViewerViewModel: 19개 (join 흐름, Offer→Answer, ICE, PeerDisconnected, error, stopViewer, 재시작)
    - Fake 패턴: `_FakeWebRTCService`(createAnswer 추가), `_FakeSignalingService` 재활용
    - autoDispose 방지: `container.listen()`으로 Provider 유지 (Phase 4 동일 패턴)

---

## Phase 6: 홈 화면 및 라우팅
- **상태**: ✅ 완료 (2026-04-17)
- **목표**: 모드 선택 화면 + 화면 전환
- **작업 목록**:
  - [x] HomeView 구현 (카메라/뷰어 모드 선택)
    - 다크 테마, 모드 선택 카드(_ModeCard), 사용 순서 힌트(_HintRow)
    - SingleChildScrollView로 소형 폰/가로 모드 오버플로우 대응
    - StatelessWidget 사용 이유, go_router context.go(), SafeArea, InkWell 주석 추가
  - [x] go_router 라우팅 설정 — main.dart에 이미 구현됨 (Phase 1)
    - / → HomeView, /camera → CameraView, /viewer → ViewerView
    - main.dart에 GoRouter, ProviderScope, MaterialApp.router 학습 주석 추가
  - [x] 테스트 작성 (`test/views/home_view_test.dart`) — 7개 통과
    - UI 렌더링 5개 (타이틀, 카드 제목, 아이콘, 힌트)
    - 네비게이션 2개 (카메라/뷰어 카드 탭 → 경로 이동 검증)
    - 스텁 GoRouter로 네이티브 의존성 없이 화면 전환 테스트

---

## Phase 7: 통합 테스트 및 안정화
- **상태**: 미시작
- **목표**: 전체 플로우 통합 및 안정화
- **작업 목록**:
  - [ ] **실제 기기 2대에서 E2E 테스트** (선행 필수)
    - **담당**: 사용자 직접 수행. Sonnet은 보조 (로그 수집 스크립트, 결함 분류, 재현 절차 정리).
    - **왜 먼저인가**: 단위 테스트는 Fake로 통과시켰지만 `flutter_webrtc` 네이티브 바인딩(권한, ICE candidate 수집, P2P 협상)은 실기기에서만 검증 가능. 후속 작업(에러 처리, UI/UX, 카메라 전환)에서 다뤄야 할 실제 결함을 여기서 먼저 발굴한다.
    - **사전 준비**:
      - [✅] Android 폰 2대 (또는 Android 1 + iOS 1) 준비, 두 폰을 동일 WiFi에 연결
      - [✅] 시그널링 서버 호스트 PC도 같은 WiFi 연결, IP 확인 (`ipconfig` / `ifconfig`)
      - [✅] PC 방화벽 9090 인바운드 허용 (Windows Defender 방화벽 규칙 추가)
      - [✅] `cd signaling_server && npm start` → 포트 9090 LISTEN 확인
      - [✅] iOS 사용 시 `ios/Runner/Info.plist`의 카메라/마이크/로컬 네트워크 권한 문구 확인
    - **기본 흐름 검증 (Happy Path)**:
      - [✅] 폰A=카메라 시작 → 권한 다이얼로그 수락 → 6자리 방 ID 표시
      - [✅] 폰B=뷰어, 서버 IP + 방 ID 입력 → "참여" → 영상 수신 확인
      - [✅] 연결 수립까지 소요 시간 측정 (목표: 3초 이내)
      - [✅] 영상 끊김/지연/해상도 주관 평가 (5분 이상 연속 시청)
      - [⚠️] 음성 송수신 동작 여부 (현재 비디오 전용이면 N/A로 기록)
    - **권한/네트워크 케이스**:
      - [✅ ] 권한 거부 → 카메라 모드 진입 시 사용자에게 어떤 메시지가 보이는가(권한 오류 메시지 표시됨)
      - [✅] 시그널링 서버 미기동 상태에서 시작 → 에러 노출 방식 확인
      - [❌] 잘못된 IP 입력 → 타임아웃까지 시간/메시지 확인 (현재 무한 대기 가능성 있음 → 트랙 B 작업 근거)
      - [✅] 잘못된 방 ID 입력 → `room_error` 처리 확인
      - [⚠️] 같은 방에 뷰어 1명 더 참여 시도 → "방 가득 참" 처리 확인
    - **세션 라이프사이클**:
      - [✅] 카메라 폰 백그라운드 전환(홈 버튼) → 복귀 시 스트림 재개 여부
      - [✅] 뷰어 폰 백그라운드 전환 → 복귀 시 영상 재개 여부
      - [✅] 카메라 폰 화면 잠금 → 복구 동작
      - [✅] 카메라 폰 앱 강제 종료 → 뷰어가 받는 신호 (peer_disconnected 표시 여부)
      - [❌] 뷰어 폰 앱 강제 종료 → 카메라가 다시 대기 상태로 돌아오는지
      - [⚠️] 두 번째 뷰어 재참여 시 정상 재연결 가능한지
    - **네트워크 변동**:
      - [❌] 스트리밍 중 카메라 폰 WiFi OFF → ON 복구 → 자동 재연결 여부
      - [❌] 시그널링 서버 종료 후 재기동 → 클라이언트 동작
      - [⚠️] 라우터 재부팅 시나리오 (장시간 안정성)
    - **장시간 안정성**:
      - [⚠️] 30분 연속 스트리밍 → 메모리 사용량/배터리/발열 관찰
      - [⚠️] 1시간 연속 → 스트림 끊김 여부, 시그널링 keepalive 필요성 판단
    - **로그 수집 가이드** (Sonnet이 보조):
      - [ ] `flutter logs` 또는 `adb logcat | grep -i "webrtc\|flutter"` 명령 정리
      - [ ] 시그널링 서버 stdout 로그 → 파일로 저장 (`npm start > server.log 2>&1`)
      - [ ] 결함 발견 시 양쪽 폰 + 서버 로그를 같은 시각으로 묶어 보관
    - **산출물**:
      - [ ] `docs/e2e-test-log.md` 신규 작성 — 시나리오별 결과(✅/⚠️/❌), 재현 절차, 로그 발췌
      - [ ] 발견된 결함을 Phase 7의 후속 작업 항목(에러 처리/UI/카메라 전환)에 반영하거나 신규 하위 항목으로 추가
  - [ ] **에러 처리 (연결 끊김, 재연결, 타임아웃)**
    - **담당**: Sonnet (코딩 전 사용자에게 설계 확인 필수)
    - **근거**: E2E 테스트에서 발견된 ❌ 4건 + ⚠️ 안정성 항목을 해소한다.
      - ❌ 잘못된 IP 입력 → 무한 대기
      - ❌ 뷰어 폰 강제 종료 → 카메라가 대기 상태로 복귀 실패
      - ❌ WiFi OFF/ON 시 자동 재연결 미동작
      - ❌ 시그널링 서버 재기동 시 클라이언트 미복구
      - ⚠️ 30분/1시간 장시간 스트리밍 안정성 (keepalive 미정)
    - **공통 설계 원칙**:
      - 모든 `Timer` / `StreamSubscription`은 ViewModel `dispose()`에서 cancel — 메모리 누수/Zombie 콜백 방지 (학습 주석 필수)
      - 재연결 로직은 ViewModel 내부에서 별도 메서드로 분리 (`_attemptReconnect(int attempt)`) — 단위 테스트 용이성 확보
      - 에러 분류는 `CameraError` / `ViewerError` sealed class로 추상화 (UI/UX 트랙 C와 공유 — 트랙 C 시작 전 본 트랙에서 정의)
      - `flutter_webrtc` API는 플랫폼별 차이가 있을 수 있으니 Android 우선 검증 후 iOS 확인
    - **세부 작업**:
      - [ ] **(1) 시그널링 연결 타임아웃** — ❌ "잘못된 IP 입력 무한 대기" 해소
        - [ ] `SignalingService.connect(host)`에 `Duration timeout` 파라미터 추가 (기본 10초)
        - [ ] WebSocket 핸드셰이크/첫 메시지 수신까지 타이머 → 만료 시 `TimeoutException` 발생
        - [ ] `CameraViewModel.startCamera`/`ViewerViewModel.joinRoom`에서 catch → `error` 상태 + 한글 메시지
        - [ ] 단위 테스트: `_FakeSignalingService.simulateNeverConnect()` 추가, `fake_async`로 시간 진행
      - [ ] **(2) 방 참여/협상 단계별 타임아웃** — Offer/Answer 미수신 케이스
        - [ ] 카메라: `waitingForViewer` 진입 후 일정 시간(예: 5분) 동안 `JoinRoomMessage` 미수신 시 안내 (에러 아님, 재시작 유도)
        - [ ] 뷰어: `waitingForOffer` 진입 후 30초 동안 `OfferMessage` 미수신 시 timeout 에러
        - [ ] ViewModel에 `Timer? _negotiationTimeout` 필드 — 상태 전이 시 cancel/start 일관 처리
      - [ ] **(3) WebSocket onDone/onError 핸들링** — ❌ "서버 재기동 시 미복구" 해소
        - [ ] `SignalingService` 내부에 `Stream<SignalingConnectionState>` 노출 (connecting/open/closed/error)
        - [ ] ViewModel에서 구독 → 비정상 종료 감지 시 `error` 상태 + 자동 재연결 진입
        - [ ] cleanup 검증: 기존 PeerConnection은 유지할지 폐기할지 결정 → "폐기 후 재협상" 권장 (ICE 상태 꼬임 방지)
      - [ ] **(4) 자동 재연결 (지수 백오프)** — ❌ "WiFi OFF/ON 미동작" 해소
        - [ ] 재시도 정책: 최대 3회, 지연 1s → 2s → 4s (지수 백오프)
        - [ ] 사용자가 "중지" 버튼을 누르면 재연결 즉시 취소
        - [ ] 재연결 시도 횟수/남은 시간을 상태에 노출 (UI/UX 트랙 C에서 표시)
        - [ ] 모든 시도 실패 시 최종 `error` 상태로 전이
        - [ ] 단위 테스트: `_FakeSignalingService`에 `simulateDisconnect()` 추가, 백오프 타이밍 검증
      - [ ] **(5) ICE 연결 실패 감지** — P2P 경로 단절 케이스
        - [ ] `WebRTCService`에서 `RTCPeerConnection.onIceConnectionState`를 외부 Stream으로 노출 (현재 노출 여부 점검)
        - [ ] `RTCIceConnectionState.failed` 수신 → `peerConnection.restartIce()` 호출 (1회 시도)
        - [ ] `disconnected` 수신 → 짧은 대기(5초) 후 자동 복구되지 않으면 재협상 트리거
        - [ ] 학습 포인트: ICE state 전이도(`new → checking → connected → disconnected → failed`) 주석으로 정리
      - [ ] **(6) peer_disconnected 처리 보강** — ❌ "뷰어 강제 종료 시 카메라 미복귀" 해소
        - [ ] 카메라 ViewModel: `PeerDisconnectedMessage` 수신 시 → 기존 PeerConnection 폐기 → 새 PeerConnection 생성 → `waitingForViewer` 상태로 복귀 (방 ID는 유지)
        - [ ] 뷰어 ViewModel: 수신 시 → 사용자에게 "카메라가 연결을 끊었습니다" 안내 후 `idle` 또는 `waitingForOffer` 상태로 복귀 (정책 결정 필요)
        - [ ] 단위 테스트: `_FakeSignalingService.emit(PeerDisconnectedMessage())` 후 상태 검증
      - [ ] **(7) WebSocket keepalive (ping/pong)** — ⚠️ "장시간 안정성" 대응
        - [ ] 시그널링 서버(`signaling_server/server.js`)에서 `ws.ping()` 주기 전송 (예: 30초)
        - [ ] 일정 시간 pong 미수신 시 서버가 클라이언트 연결 종료 → 클라이언트는 (4) 자동 재연결로 복구
        - [ ] 클라이언트 측은 `web_socket_channel`이 ping/pong을 자동 처리 → 추가 코드 불필요한지 확인
        - [ ] Phase 2 테스트(`signaling_server/test/`)에 ping 관련 케이스 추가
      - [ ] **(8) 에러 분류 sealed class 정의** (트랙 C와 공유)
        - [ ] `lib/models/connection_error.dart` 신규 생성
        - [ ] `sealed class ConnectionError` + 하위 케이스:
          `NetworkUnreachable`, `ConnectionTimeout`, `RoomNotFound`, `RoomFull`,
          `MediaPermissionDenied`, `IceFailed`, `PeerDisconnected`, `ServerClosed`, `Unknown(String)`
        - [ ] ViewModel의 `errorMessage: String?` → `error: ConnectionError?` 로 교체
        - [ ] View는 Dart 3 `switch expression`으로 한글 메시지/액션 매핑 (트랙 C에서 UI 적용)
    - **테스트 보강**:
      - [ ] `_FakeSignalingService` 확장: `simulateDisconnect()`, `simulateError(Object)`, `simulateNeverConnect()`
      - [ ] `_FakeWebRTCService` 확장: `emitIceConnectionState(RTCIceConnectionState)`, `restartIceCalls` 카운터
      - [ ] `fake_async` 패키지 의존성 추가 (`pubspec.yaml` dev_dependencies)
      - [ ] 카메라/뷰어 ViewModel 각각에 재연결/타임아웃/peer_disconnected 시나리오 테스트 ≥ 6개씩 추가
    - **검증 방법** (트랙 A 재실행):
      - [ ] 잘못된 IP 입력 → 10초 내 한글 에러 메시지 노출
      - [ ] 카메라 폰 WiFi OFF 5초 후 ON → 자동 재연결 후 스트리밍 재개
      - [ ] 시그널링 서버 kill → 재기동 → 클라이언트 자동 복구
      - [ ] 뷰어 강제 종료 → 카메라가 `waitingForViewer` 상태로 복귀 + 같은 방 ID 유지
      - [ ] 30분 연속 스트리밍 → 끊김 없음
    - **산출물**:
      - [ ] `docs/design-decisions.md`에 결정 추가:
        - 재연결 정책 (최대 횟수, 백오프 간격)
        - 협상 타임아웃 값 (시그널링 10s, 뷰어 Offer 대기 30s 등 — 실험 후 조정)
        - keepalive 주기 (서버측 ping 30s)
        - 에러 분류 체계 (sealed class)
      - [ ] `docs/architecture.md`에 "에러/재연결 흐름" 섹션 신설 (선택)
  - [ ] UI/UX 개선 (로딩 상태, 에러 메시지)
  - [ ] 카메라 전환 (전면/후면)

---

## 향후 확장 (미정)
- 외부 접속 지원 (STUN/TURN 서버) + Docker Compose로 서버 구성 (시그널링 + TURN 통합)
- 모션 감지 및 알림
- 녹화 저장
- 양방향 오디오
- 야간 모드 (플래시 활용)
