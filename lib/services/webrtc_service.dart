import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

class WebRTCService {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;

  final _onRemoteStream = StreamController<MediaStream>.broadcast();
  final _onIceCandidate = StreamController<RTCIceCandidate>.broadcast();
  final _onConnectionState =
      StreamController<RTCPeerConnectionState>.broadcast();

  Stream<MediaStream> get onRemoteStream => _onRemoteStream.stream;
  Stream<RTCIceCandidate> get onIceCandidate => _onIceCandidate.stream;
  Stream<RTCPeerConnectionState> get onConnectionState =>
      _onConnectionState.stream;

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
      'offerToReceiveVideo': false, // 카메라 폰은 수신 불필요
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
  }
}
