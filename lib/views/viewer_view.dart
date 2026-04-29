import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';

import 'package:wifi_cctv/models/connection_error.dart';
import 'package:wifi_cctv/viewmodels/viewer_viewmodel.dart';

// ══════════════════════════════════════════════════════════════════════════════
// ViewerView
// ══════════════════════════════════════════════════════════════════════════════

/// 뷰어 모드 화면.
///
/// ConsumerStatefulWidget 사용 이유:
///   - RTCVideoRenderer는 initialize()/dispose()로 네이티브 리소스를 직접 관리해야 한다.
///   - StatefulWidget 계열이 아니면 initState/dispose를 사용할 수 없다.
///   - ConsumerState는 State에 ref(Riverpod 접근자)가 추가된 것.
///
/// CameraView와의 차이:
///   - localRenderer 대신 remoteRenderer 사용 (원격 영상 표시)
///   - 방 ID 입력 필드 추가 (_roomIdController)
///   - mirror: false (원격 영상은 좌우 반전 불필요)
class ViewerView extends ConsumerStatefulWidget {
  const ViewerView({super.key});

  @override
  ConsumerState<ViewerView> createState() => _ViewerViewState();
}

class _ViewerViewState extends ConsumerState<ViewerView> {
  // 원격 카메라 영상을 표시할 렌더러.
  // initialize()로 네이티브 리소스 할당, dispose()로 해제 필요하다.
  final _remoteRenderer = RTCVideoRenderer();

  // 서버 IP 입력 — CameraView와 동일한 기본값 사용
  final _serverHostController = TextEditingController(text: '192.168.0.');

  // 참여할 방의 6자리 ID 입력 — 카메라 폰이 알려준 숫자를 여기에 입력
  final _roomIdController = TextEditingController();

  // 렌더러 초기화 완료 여부 — 초기화 전에 RTCVideoView를 빌드하면 오류 발생
  bool _rendererInitialized = false;

  @override
  void initState() {
    super.initState();
    _initRenderer();
  }

  Future<void> _initRenderer() async {
    await _remoteRenderer.initialize();
    // mounted 체크: dispose된 후 setState를 호출하면 오류가 발생할 수 있으므로 확인
    if (mounted) {
      setState(() => _rendererInitialized = true);
    }
  }

  @override
  void dispose() {
    // 화면이 사라질 때 반드시 네이티브 리소스를 해제해야 한다.
    _remoteRenderer.dispose();
    _serverHostController.dispose();
    _roomIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ref.watch: viewerViewModelProvider의 상태(ViewerState)를 구독.
    // 상태가 바뀔 때마다 build()가 다시 실행되어 UI가 자동 갱신된다.
    final viewerState = ref.watch(viewerViewModelProvider);

    // ref.read: 상태를 구독하지 않고 ViewModel 메서드만 호출할 때 사용.
    // 버튼 onPressed 등 이벤트 핸들러에서 ref.watch 대신 ref.read를 써야
    // 불필요한 rebuild가 발생하지 않는다.
    final viewModel = ref.read(viewerViewModelProvider.notifier);

    // ref.listen: 상태 변화 시 사이드 이펙트를 실행할 때 사용 (UI 갱신이 아닌 경우).
    // 원격 스트림이 도착하면 렌더러에 연결하는 작업이 이에 해당한다.
    ref.listen<ViewerState>(viewerViewModelProvider, (previous, next) {
      final stream = viewModel.remoteStream;
      // 원격 스트림이 새로 도착했고 아직 렌더러에 연결되지 않은 경우
      if (stream != null && _remoteRenderer.srcObject == null) {
        // srcObject에 MediaStream을 연결 = 렌더러가 해당 스트림을 화면에 표시
        _remoteRenderer.srcObject = stream;
        setState(() {});
      }
      // 뷰어 중지(idle) 시 렌더러 초기화
      if (next.connectionState == ViewerConnectionState.idle) {
        _remoteRenderer.srcObject = null;
        setState(() {});
      }
    });

    final isActive = viewerState.connectionState != ViewerConnectionState.idle &&
        viewerState.connectionState != ViewerConnectionState.error;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('뷰어 모드'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            await viewModel.stopViewer();
            // await 이후에는 위젯이 dispose 됐을 수 있으므로 context.mounted 확인 필수
            if (context.mounted) context.go('/');
          },
        ),
      ),
      body: Column(
        children: [
          // 원격 영상 영역 (화면의 대부분을 차지)
          Expanded(
            child: _buildVideoArea(viewerState),
          ),
          // 하단 컨트롤 패널 (IP 입력 + 방 ID 입력 + 버튼)
          _buildControlPanel(viewerState, viewModel, isActive),
        ],
      ),
    );
  }

  // ── 영상 영역 ────────────────────────────────────────────────────────────────

  Widget _buildVideoArea(ViewerState viewerState) {
    final isStarted = viewerState.connectionState != ViewerConnectionState.idle &&
        viewerState.connectionState != ViewerConnectionState.error;

    // 미시작 또는 렌더러 초기화 전: 안내 메시지 표시
    if (!_rendererInitialized || !isStarted) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tv, color: Colors.white54, size: 64),
            SizedBox(height: 16),
            Text('방 ID를 입력하고 참여하세요', style: TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // RTCVideoView: RTCVideoRenderer를 Flutter 위젯 트리에 삽입하는 위젯.
        // mirror: false — 원격 영상은 카메라가 이미 올바른 방향으로 보내므로 반전 불필요.
        //                 (CameraView는 전면 카메라 셀카 효과를 위해 mirror: true 사용)
        RTCVideoView(
          _remoteRenderer,
          mirror: false,
        ),

        // 연결 상태 배지 (우측 상단)
        Positioned(
          top: 16,
          right: 16,
          child: _StatusBadge(connectionState: viewerState.connectionState),
        ),
      ],
    );
  }

  // ── 하단 컨트롤 패널 ────────────────────────────────────────────────────────

  Widget _buildControlPanel(
    ViewerState viewerState,
    ViewerViewModel viewModel,
    bool isActive,
  ) {
    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 에러 표시 — ConnectionError sealed class + switch expression 패턴.
          // camera_view.dart와 동일한 패턴. 뷰어 전용 에러(NegotiationTimeout)가 포함된다.
          if (viewerState.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                switch (viewerState.error!) {
                  NetworkUnreachable() =>
                    '서버에 연결할 수 없습니다.\nIP와 방화벽을 확인하세요.',
                  ConnectionTimeout() =>
                    '연결 시간이 초과됐습니다.\n서버 IP를 확인하세요.',
                  NegotiationTimeout() =>
                    '카메라 응답을 기다리다\n시간이 초과됐습니다 (30초).',
                  RoomNotFound() => '존재하지 않는 방 번호입니다.',
                  RoomFull() => '이미 뷰어가 참여 중입니다.',
                  MediaPermissionDenied() => '카메라 또는 마이크\n권한이 필요합니다.',
                  IceFailed() => 'P2P 연결에 실패했습니다.\n같은 WiFi인지 확인하세요.',
                  PeerDisconnected() => '카메라가 연결을 종료했습니다.',
                  ServerClosed() => '서버와의 연결이 끊어졌습니다.',
                  UnknownConnectionError(:final message) => '오류: $message',
                },
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),

          // 스트리밍 중일 때 방 ID를 컨트롤 패널에 표시
          if (viewerState.roomId != null &&
              viewerState.connectionState == ViewerConnectionState.streaming)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                '방 ID: ${viewerState.roomId}  •  수신 중',
                style: const TextStyle(color: Colors.greenAccent, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),

          // 서버 IP + 방 ID 입력 필드 (참여 전에만 표시)
          if (!isActive) ...[
            TextField(
              controller: _serverHostController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: '시그널링 서버 IP',
                labelStyle: TextStyle(color: Colors.white70),
                hintText: '예: 192.168.0.100',
                hintStyle: TextStyle(color: Colors.white30),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white30),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.blue),
                ),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _roomIdController,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                letterSpacing: 6,
              ),
              decoration: const InputDecoration(
                labelText: '방 ID (6자리)',
                labelStyle: TextStyle(color: Colors.white70),
                hintText: '123456',
                hintStyle: TextStyle(color: Colors.white30),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white30),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.blue),
                ),
              ),
              // 숫자만 입력 가능하도록
              keyboardType: TextInputType.number,
              maxLength: 6,
            ),
            const SizedBox(height: 4),
          ],

          // 참여 / 중지 버튼
          ElevatedButton.icon(
            // 연결 중에는 버튼 비활성화 (null을 넘기면 비활성)
            onPressed: viewerState.connectionState ==
                    ViewerConnectionState.connecting
                ? null
                : isActive
                    ? viewModel.stopViewer
                    : () => viewModel.joinRoom(
                          _serverHostController.text.trim(),
                          _roomIdController.text.trim(),
                        ),
            icon: viewerState.connectionState == ViewerConnectionState.connecting
                // 연결 중: 로딩 스피너 표시
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(isActive ? Icons.stop_circle : Icons.play_arrow),
            label: Text(_buttonLabel(viewerState.connectionState)),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  isActive ? Colors.red.shade700 : Colors.blue.shade700,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey.shade800,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  /// 연결 상태에 따른 버튼 레이블.
  String _buttonLabel(ViewerConnectionState connectionState) {
    // Dart 3 switch expression — 각 상태에 맞는 레이블을 값으로 반환
    return switch (connectionState) {
      ViewerConnectionState.idle => '참여하기',
      ViewerConnectionState.connecting => '연결 중...',
      ViewerConnectionState.waitingForOffer => '중지 (영상 대기 중)',
      ViewerConnectionState.streaming => '중지 (수신 중)',
      ViewerConnectionState.error => '다시 시도',
    };
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 보조 위젯
// ══════════════════════════════════════════════════════════════════════════════

/// 연결 상태를 색상으로 표시하는 배지 위젯.
///
/// 프라이빗 클래스(_로 시작)로 선언하여 이 파일 외부에서 사용하지 못하게 한다.
/// 공개 API를 최소화하는 것이 유지보수에 유리하다.
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.connectionState});

  final ViewerConnectionState connectionState;

  @override
  Widget build(BuildContext context) {
    // Dart 3 record 반환 — (label, color)를 한 번에 구조 분해
    final (label, color) = switch (connectionState) {
      ViewerConnectionState.idle => ('대기', Colors.grey),
      ViewerConnectionState.connecting => ('연결 중', Colors.orange),
      ViewerConnectionState.waitingForOffer => ('영상 대기', Colors.amber),
      ViewerConnectionState.streaming => ('수신 중', Colors.green),
      ViewerConnectionState.error => ('에러', Colors.red),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        // withAlpha: 0~255 범위로 투명도 설정. withOpacity(0.0~1.0)보다 성능이 좋다.
        color: color.withAlpha(200),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
