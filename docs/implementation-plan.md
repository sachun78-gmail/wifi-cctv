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
  - [ ] 실제 기기 2대에서 E2E 테스트
  - [ ] 에러 처리 (연결 끊김, 재연결, 타임아웃)
  - [ ] UI/UX 개선 (로딩 상태, 에러 메시지)
  - [ ] 카메라 전환 (전면/후면)

---

## 향후 확장 (미정)
- 외부 접속 지원 (STUN/TURN 서버) + Docker Compose로 서버 구성 (시그널링 + TURN 통합)
- 모션 감지 및 알림
- 녹화 저장
- 양방향 오디오
- 야간 모드 (플래시 활용)
