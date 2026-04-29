import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

class WebRTCService {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;

  final _onRemoteStream = StreamController<MediaStream>.broadcast();
  final _onIceCandidate = StreamController<RTCIceCandidate>.broadcast();
  final _onConnectionState = StreamController<RTCPeerConnectionState>.broadcast();
  // ICE 연결 상태 스트림 — RTCPeerConnectionState보다 세밀한 ICE 레벨 상태를 제공.
  // RTCIceConnectionState.failed 감지 → restartIce() 시도에 사용한다.
  // ICE state와 PeerConnection state는 별개: ICE가 failed여도 Peer state는 아직 connected일 수 있다.
  final _onIceConnectionState =
      StreamController<RTCIceConnectionState>.broadcast();

  Stream<MediaStream> get onRemoteStream => _onRemoteStream.stream;
  Stream<RTCIceCandidate> get onIceCandidate => _onIceCandidate.stream;
  Stream<RTCPeerConnectionState> get onConnectionState =>
      _onConnectionState.stream;
  Stream<RTCIceConnectionState> get onIceConnectionState =>
      _onIceConnectionState.stream;

  MediaStream? get localStream => _localStream;

  static const Map<String, dynamic> _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
    ],
  };

  Future<void> initialize() async {
    _peerConnection = await createPeerConnection(_iceConfig);

    _peerConnection!.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        _onIceCandidate.add(candidate);
      }
    };

    _peerConnection!.onConnectionState = _onConnectionState.add;

    // ICE 연결 상태를 외부 Stream으로 노출.
    // ViewModel에서 failed → restartIce() 호출에 사용한다.
    _peerConnection!.onIceConnectionState = _onIceConnectionState.add;

    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _onRemoteStream.add(event.streams.first);
      }
    };
  }

  /// 카메라 폰: 로컬 스트림 획득 후 PeerConnection에 트랙 추가.
  Future<void> startLocalStream({bool frontCamera = false}) async {
    _localStream = await navigator.mediaDevices.getUserMedia({
      'video': {
        'facingMode': frontCamera ? 'user' : 'environment',
      },
      'audio': false,
    });

    for (final track in _localStream!.getTracks()) {
      await _peerConnection!.addTrack(track, _localStream!);
    }
  }

  /// 카메라 폰이 호출. SDP offer를 생성하고 LocalDescription으로 설정.
  Future<RTCSessionDescription> createOffer() async {
    final offer = await _peerConnection!.createOffer({
      'offerToReceiveVideo': false,
      'offerToReceiveAudio': false,
    });
    await _peerConnection!.setLocalDescription(offer);
    return offer;
  }

  /// 뷰어 폰이 호출. SDP answer를 생성하고 LocalDescription으로 설정.
  Future<RTCSessionDescription> createAnswer() async {
    final answer = await _peerConnection!.createAnswer({});
    await _peerConnection!.setLocalDescription(answer);
    return answer;
  }

  Future<void> setRemoteDescription(RTCSessionDescription description) async {
    await _peerConnection!.setRemoteDescription(description);
  }

  Future<void> addIceCandidate(RTCIceCandidate candidate) async {
    await _peerConnection!.addCandidate(candidate);
  }

  /// ICE 재시작: 기존 PeerConnection에서 새 ICE 후보 수집을 재개.
  ///
  /// SDP 재협상 없이 ICE 레벨만 재시작하므로 영상 끊김이 최소화된다.
  /// restartIce()는 내부적으로 새 ufrag/pwd를 생성하고 re-offer를 트리거한다.
  /// RTCIceConnectionState.failed 감지 후 1회 시도한다.
  Future<void> restartIce() async {
    await _peerConnection?.restartIce();
  }

  /// PeerConnection만 재초기화 (StreamController는 유지).
  ///
  /// 왜 dispose()와 다른가:
  ///   dispose(): StreamController를 닫아 기존 구독이 모두 무효화된다.
  ///   이 메서드: PeerConnection만 폐기하고 StreamController는 살려두므로
  ///     ViewModel의 기존 ICE/ConnectionState 구독이 새 PeerConnection에서도 계속 동작한다.
  ///     initialize() 후 새 PeerConnection의 콜백이 같은 StreamController에 이벤트를 추가하기 때문.
  ///
  /// 사용 시점:
  ///   - peer_disconnected 수신 후 새 뷰어 접속 준비 (방 ID는 유지)
  ///   - 시그널링 서버 재연결 시 PeerConnection 재생성
  Future<void> resetPeerConnection() async {
    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await track.stop();
      }
    }
    await _localStream?.dispose();
    await _peerConnection?.close();
    _localStream = null;
    _peerConnection = null;
  }

  Future<void> dispose() async {
    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await track.stop();
      }
    }
    await _localStream?.dispose();
    await _peerConnection?.close();

    _localStream = null;
    _peerConnection = null;

    await _onRemoteStream.close();
    await _onIceCandidate.close();
    await _onConnectionState.close();
    await _onIceConnectionState.close();
  }
}
