# Architecture

> WiFi CCTV 프로젝트 아키텍처 설계 문서

## Overview

WiFi CCTV는 스마트폰 2대를 활용하여 하나는 카메라(송신), 하나는 뷰어(수신) 역할을 하는 실시간 영상 스트리밍 앱이다.
같은 WiFi 네트워크(LAN) 환경에서 WebRTC를 통한 P2P 영상 전송이 핵심 기능이다.
Flutter + Riverpod 기반의 MVVM 아키텍처를 따른다.

### 핵심 동작 방식: WebRTC P2P 스트리밍

- 카메라 폰이 카메라 영상을 캡처하여 WebRTC로 스트리밍
- 뷰어 폰이 WebRTC로 영상을 수신하여 화면에 표시
- 자체 WebSocket 시그널링 서버로 초기 연결 수립

```
┌─────────────────────────────┐
│  카메라 폰 (송신)             │
│  - 카메라 영상 캡처           │
│  - WebRTC PeerConnection    │
│  - 영상/오디오 스트림 전송     │
└──────────┬──────────────────┘
           │ WebRTC P2P (LAN)
           │
┌──────────▼──────────────────┐
│  시그널링 서버 (WebSocket)    │
│  - SDP Offer/Answer 교환     │
│  - ICE Candidate 교환        │
│  - 방 생성/참여 관리          │
└──────────┬──────────────────┘
           │
┌──────────▼──────────────────┐
│  뷰어 폰 (수신)              │
│  - WebRTC PeerConnection    │
│  - 영상 수신 및 화면 표시     │
│  - RTCVideoRenderer         │
└─────────────────────────────┘
```

### WebRTC 연결 흐름

```
1. 카메라 폰: 방 생성 → 시그널링 서버에 등록
2. 뷰어 폰: 방 참여 → 시그널링 서버에서 카메라 폰 정보 수신
3. SDP Offer/Answer 교환 (세션 협상)
4. ICE Candidate 교환 (네트워크 경로 탐색)
5. P2P 연결 수립 → 영상 스트리밍 시작
```

### SDP (Session Description Protocol)

**"나는 어떤 영상/음성 형식을 지원하고, 어떻게 인코딩할 수 있어?"**

두 기기가 영상을 주고받으려면 먼저 공통으로 지원하는 코덱, 해상도, 포맷을 협상해야 한다.
카메라 폰이 먼저 제안(Offer)하고 뷰어 폰이 수락(Answer)하는 방식으로 교환한다.

```
카메라 폰 → Offer SDP:  "나는 H.264, VP8 지원해. 720p 보낼게."
뷰어 폰   → Answer SDP: "나도 H.264 지원해. OK."
```

실제 SDP는 코덱, 대역폭, 암호화 방식 등을 담은 텍스트 형식이다:

```
v=0
o=- 461234 2 IN IP4 127.0.0.1
m=video 9 UDP/TLS/RTP/SAVPF 96
a=rtpmap:96 VP8/90000
...
```

### ICE (Interactive Connectivity Establishment)

**"나한테 연결하려면 이 주소/경로로 와."**

같은 WiFi 안에 있어도 기기마다 IP가 다르고 방화벽·NAT 환경도 다르다.
ICE는 실제로 연결 가능한 네트워크 경로(Candidate)를 찾아서 양쪽이 교환한 뒤, 가장 적합한 경로로 P2P 연결을 수립한다.

```
카메라 폰이 찾은 Candidate 목록:
  - 192.168.0.10:5000  (로컬 WiFi IP)
  - 203.0.113.5:5000   (공인 IP, STUN 서버가 알려줌)

뷰어 폰이 찾은 Candidate 목록:
  - 192.168.0.20:5001
  - 203.0.113.5:5001
```

LAN 환경에서는 로컬 IP(192.168.x.x)로 바로 연결되므로 STUN/TURN 없이도 동작한다.
STUN은 외부 인터넷 접속 시 공인 IP를 알아내기 위해 필요하다.

### 향후 확장 (외부 접속)

- STUN 서버 추가 (공인 IP 확인)
- TURN 서버 추가 (NAT 뒤에서 영상 중계)
- 인증/보안 레이어 추가

## Tech Stack

| 영역 | 기술 | 비고 |
|------|------|------|
| Language | Dart | |
| Framework | Flutter | 크로스 플랫폼 (Android/iOS) |
| Architecture | MVVM | ViewModel + State |
| State Management | Riverpod | 타입 안전, 테스트 용이 |
| WebRTC | flutter_webrtc | P2P 영상 전송 |
| Signaling | WebSocket (Node.js 서버) | ws 패키지 |
| Camera | camera 패키지 | Flutter 공식 카메라 플러그인 (필요 시) |

## MVVM Architecture

```
┌─────────────────────────────────────────┐
│  View (Flutter Widget)                  │
│  - 카메라 화면 / 뷰어 화면              │
│  - RTCVideoRenderer 표시                │
│  - ref.watch()로 상태 구독              │
└──────────────┬──────────────────────────┘
               │ StateNotifier / AsyncNotifier
               │ 사용자 이벤트 (방 생성, 참여 등)
┌──────────────▼──────────────────────────┐
│  ViewModel (Riverpod Provider)          │
│  - 연결 상태, 스트리밍 상태 관리         │
│  - WebRTC 세션 제어                     │
│  - 비즈니스 로직 조합                    │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│  Service / Repository                   │
│  - SignalingService (WebSocket 통신)     │
│  - WebRTCService (PeerConnection 관리)  │
│  - CameraService (카메라 제어)           │
└─────────────────────────────────────────┘
```

## Key Design Patterns

- **MVVM + Riverpod**: Provider로 ViewModel 역할, StateNotifier/AsyncNotifier로 상태 관리
- **단방향 데이터 흐름(UDF)**: View → Event → Provider → State → View
- **Service Pattern**: WebRTC, Signaling, Camera 등을 독립된 서비스로 분리
- **역할 기반 UI**: 같은 앱에서 카메라 모드 / 뷰어 모드 선택

## Project Structure

```
lib/
├── main.dart
├── app.dart                    # MaterialApp, 라우팅 설정
├── models/                     # 데이터 모델
│   ├── room.dart               # 방 정보 모델
│   └── signaling_message.dart  # 시그널링 메시지 모델
├── services/                   # 외부 서비스 연동
│   ├── signaling_service.dart  # WebSocket 시그널링
│   └── webrtc_service.dart     # WebRTC PeerConnection 관리
├── viewmodels/                 # 비즈니스 로직 (Riverpod Provider)
│   ├── camera_viewmodel.dart   # 카메라 모드 상태 관리
│   ├── viewer_viewmodel.dart   # 뷰어 모드 상태 관리
│   └── connection_viewmodel.dart # 연결 상태 관리
├── views/                      # UI 위젯
│   ├── home_view.dart          # 모드 선택 (카메라/뷰어)
│   ├── camera_view.dart        # 카메라 화면
│   └── viewer_view.dart        # 뷰어 화면
└── utils/                      # 유틸리티
    └── constants.dart          # 상수 정의
```

## Signaling Server

Node.js + ws 패키지로 시그널링 서버를 구현한다. 영상 데이터는 전달하지 않고, WebRTC 연결 수립에 필요한 시그널링 메시지만 중계한다.

- **포트**: 9090 (환경변수 `PORT`로 변경 가능, 8080은 다른 서비스 사용 중)

### 프로젝트 구조

```
signaling_server/
├── package.json
├── server.js              # 진입점 (서버 시작)
├── room-manager.js        # 방 생성/참여/제거 로직
├── message-handler.js     # 메시지 타입별 처리
└── test/
    └── server.test.js
```

### 방(Room) 관리

```
Room = { id: string, camera: WebSocket | null, viewer: WebSocket | null }
```

- **create_room**: 6자리 랜덤 숫자 ID 생성, camera 슬롯에 소켓 등록
- **join_room**: 해당 roomId의 viewer 슬롯에 등록. 방 없으면 room_error
- **1:1 전용**: 방당 카메라 1 + 뷰어 1. 이미 뷰어가 있으면 거부
- **연결 해제 시**: 해당 슬롯 비우고 상대방에게 peer_disconnected 전송. 둘 다 나가면 방 삭제

### 시그널링 프로토콜 (JSON over WebSocket)

| 방향             | type                 | 페이로드         | 설명                            
|-----------------|----------------------|-----------------|-------------------------------|
| Client → Server | `create_room`        | —               | 방 생성 요청 (카메라 폰)           
| Server → Client | `room_created`       | `{ roomId }`    | 생성된 방 ID 전달                 
| Client → Server | `join_room`          | `{ roomId }`    | 방 참여 요청 (뷰어 폰)           
| Server → Client | `room_joined`        | `{ roomId }`    | 참여 성공 알림 (양쪽 모두)         
| Server → Client | `room_error`         | `{ message }`   | 방 없음, 꽉 참 등 에러             
| Client → Server | `offer`              | `{ sdp }`       | SDP Offer (카메라 → 뷰어로 중계)   
| Client → Server | `answer`             | `{ sdp }`       | SDP Answer (뷰어 → 카메라로 중계)  
| Client → Server | `candidate`          | `{ candidate }` | ICE Candidate (상대방에게 중계)    
| Server → Client | `peer_disconnected`  | —               | 상대방 연결 끊김 알림              

### 메시지 중계 흐름

```
카메라 폰                   서버                    뷰어 폰
    |-- create_room -------->|                         |
    |<-- room_created -------|                         |
    |                        |<-- join_room -----------|
    |<-- room_joined --------|-- room_joined --------->|
    |-- offer -------------->|-- offer --------------->|
    |                        |<-- answer --------------|
    |<-- answer -------------|                         |
    |-- candidate ---------->|-- candidate ----------->|
    |<-- candidate ----------|<-- candidate -----------|
    |        (WebRTC P2P 연결 수립 완료)                 |
```

### 설계 포인트

- 서버는 offer, answer, candidate 메시지를 해석하지 않고 **상대방에게 그대로 중계**
- 방 ID는 6자리 숫자 — 같은 LAN에서 수동 입력하기 편하게
- 에러 케이스: 존재하지 않는 방, 이미 가득 찬 방, 상대방 없는 상태에서 메시지 전송
- 테스트: Node 내장 `node:test` + ws 클라이언트로 메시지 라우팅 검증
