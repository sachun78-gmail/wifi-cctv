import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';

import 'package:wifi_cctv/models/connection_error.dart';
import 'package:wifi_cctv/viewmodels/camera_viewmodel.dart';

// ══════════════════════════════════════════════════════════════════════════════
// CameraView
// ══════════════════════════════════════════════════════════════════════════════

/// 카메라 모드 화면.
///
/// ConsumerStatefulWidget 사용 이유:
///   - ConsumerWidget(StatelessWidget 계열): ref.watch만 있으면 충분할 때
///   - ConsumerStatefulWidget(StatefulWidget 계열): State 객체가 필요할 때
///     → 여기서는 RTCVideoRenderer가 생명주기(initState/dispose) 관리가 필요하므로
///       StatefulWidget 계열을 사용한다.
///
/// ConsumerState vs State:
///   - ConsumerState는 State에 ref(Riverpod 접근자)가 추가된 것
///   - ref.watch(), ref.read(), ref.listen() 사용 가능
class CameraView extends ConsumerStatefulWidget {
  const CameraView({super.key});

  @override
  ConsumerState<CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends ConsumerState<CameraView> {
  // RTCVideoRenderer: flutter_webrtc에서 제공하는 영상 렌더러.
  // - initialize()로 네이티브 리소스 할당, dispose()로 해제 필요
  // - srcObject에 MediaStream을 연결하면 RTCVideoView에 영상이 표시됨
  final _localRenderer = RTCVideoRenderer();

  // 서버 IP 입력 필드 컨트롤러
  final _serverHostController = TextEditingController(text: '192.168.0.');

  // 렌더러 초기화 완료 여부 — 초기화 전에 RTCVideoView를 빌드하면 오류 발생
  bool _rendererInitialized = false;

  @override
  void initState() {
    super.initState();
    // initState는 위젯이 처음 생성될 때 한 번 호출된다
    _initRenderer();
  }

  Future<void> _initRenderer() async {
    // RTCVideoRenderer.initialize(): 네이티브 플랫폼에 렌더러 리소스 요청
    // - 비동기이므로 await 필요
    // - 완료 후 setState()로 rebuild 트리거
    await _localRenderer.initialize();
    // mounted 체크: dispose된 후에 setState를 호출하면 오류가 발생할 수 있으므로
    if (mounted) {
      setState(() => _rendererInitialized = true);
    }
  }

  @override
  void dispose() {
    // 화면이 사라질 때 반드시 해제해야 한다
    // 해제하지 않으면 네이티브 리소스 누수 발생
    _localRenderer.dispose();
    _serverHostController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ref.watch: cameraViewModelProvider의 상태(CameraState)를 구독
    // - 상태가 바뀔 때마다 이 build()가 다시 실행되어 UI가 갱신됨
    // - 이것이 Riverpod의 핵심: 상태 변화 → 자동 UI 재빌드
    final cameraState = ref.watch(cameraViewModelProvider);

    // ref.read: 상태를 구독하지 않고 ViewModel의 메서드만 호출할 때 사용
    // - 버튼 onPressed 등 이벤트 핸들러에서 사용
    // - ref.watch를 이벤트 핸들러에 쓰면 불필요한 rebuild가 발생할 수 있다
    final viewModel = ref.read(cameraViewModelProvider.notifier);

    // ref.listen: 상태 변화 시 사이드 이펙트 실행 (UI 갱신이 아닌 경우에 사용)
    // - 예: 로컬 스트림이 생기면 렌더러에 연결, SnackBar 표시 등
    // - build() 안에서만 호출 가능 (initState에서는 사용 불가)
    ref.listen<CameraState>(cameraViewModelProvider, (previous, next) {
      final stream = viewModel.localStream;
      // 로컬 스트림이 새로 생겼고, 아직 렌더러에 연결되지 않은 경우
      if (stream != null && _localRenderer.srcObject == null) {
        // srcObject에 MediaStream을 연결 = 렌더러가 이 스트림을 화면에 표시
        _localRenderer.srcObject = stream;
        // RTCVideoRenderer의 srcObject 변경은 setState 없이도 반영되지만,
        // 렌더러 상태가 바뀌었으니 rebuild를 명시적으로 요청
        setState(() {});
      }
      // 카메라 중지 시 렌더러 초기화
      if (next.connectionState == CameraConnectionState.idle) {
        _localRenderer.srcObject = null;
        setState(() {});
      }
    });

    final isActive = cameraState.connectionState != CameraConnectionState.idle &&
        cameraState.connectionState != CameraConnectionState.error;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('카메라 모드'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            // 카메라 중지 후 홈으로 이동
            await viewModel.stopCamera();
            // context.mounted: 비동기 작업 후 context가 아직 유효한지 확인
            // await 이후에는 위젯이 dispose 되었을 수 있으므로 반드시 체크
            if (context.mounted) context.go('/');
          },
        ),
      ),
      body: Column(
        children: [
          // 카메라 프리뷰 영역 (화면의 대부분을 차지)
          Expanded(
            child: _buildVideoPreview(cameraState),
          ),
          // 하단 컨트롤 패널 (IP 입력 + 버튼)
          _buildControlPanel(cameraState, viewModel, isActive),
        ],
      ),
    );
  }

  // ── 영상 프리뷰 ─────────────────────────────────────────────────────────────

  Widget _buildVideoPreview(CameraState cameraState) {
    final isStarted = cameraState.connectionState != CameraConnectionState.idle &&
        cameraState.connectionState != CameraConnectionState.error;

    // 카메라 미시작 상태: 안내 메시지 표시
    if (!_rendererInitialized || !isStarted) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off, color: Colors.white54, size: 64),
            SizedBox(height: 16),
            Text('카메라 시작 전', style: TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // RTCVideoView: RTCVideoRenderer를 Flutter 위젯 트리에 삽입하는 위젯.
        // - objectFit: 영상 비율 처리 방식
        //   * RTCVideoViewObjectFitContain: 비율 유지 (레터박스 발생 가능)
        //   * RTCVideoViewObjectFitCover: 화면 꽉 채움 (일부 잘릴 수 있음)
        // - mirror: true → 전면 카메라 영상을 좌우 반전 (셀카 거울 효과)
        RTCVideoView(
          _localRenderer,
          // objectFit 기본값이 RTCVideoViewObjectFitContain이므로 생략
          // (비율 유지, 레터박스 방식)
          mirror: true,
        ),

        // 연결 상태 배지 (우측 상단)
        Positioned(
          top: 16,
          right: 16,
          child: _StatusBadge(connectionState: cameraState.connectionState),
        ),

        // 방 ID 표시 (뷰어 대기 중일 때만 크게 표시)
        // 뷰어에게 이 6자리 숫자를 알려주면 연결된다
        if (cameraState.roomId != null &&
            cameraState.connectionState == CameraConnectionState.waitingForViewer)
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Center(
              child: _RoomIdDisplay(roomId: cameraState.roomId!),
            ),
          ),
      ],
    );
  }

  // ── 하단 컨트롤 패널 ────────────────────────────────────────────────────────

  Widget _buildControlPanel(
    CameraState cameraState,
    CameraViewModel viewModel,
    bool isActive,
  ) {
    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 에러 표시 — ConnectionError sealed class + switch expression 패턴.
          // sealed class의 exhaustive check: 모든 케이스를 다루지 않으면 컴파일 오류 발생.
          // 새 ConnectionError 타입 추가 시 이 switch에도 케이스를 추가해야 한다.
          if (cameraState.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                switch (cameraState.error!) {
                  NetworkUnreachable() =>
                    '서버에 연결할 수 없습니다.\nIP와 방화벽을 확인하세요.',
                  ConnectionTimeout() =>
                    '연결 시간이 초과됐습니다.\n서버 IP를 확인하세요.',
                  NegotiationTimeout() => '카메라 응답을 기다리다\n시간이 초과됐습니다.',
                  RoomNotFound() => '존재하지 않는 방 번호입니다.',
                  RoomFull() => '이미 뷰어가 참여 중입니다.',
                  MediaPermissionDenied() => '카메라 또는 마이크\n권한이 필요합니다.',
                  IceFailed() => 'P2P 연결에 실패했습니다.\n같은 WiFi인지 확인하세요.',
                  PeerDisconnected() => '뷰어가 연결을 종료했습니다.',
                  ServerClosed() => '서버와의 연결이 끊어졌습니다.',
                  UnknownConnectionError(:final message) => '오류: $message',
                },
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),

          // 스트리밍 중일 때 방 ID 컨트롤 패널에도 표시 (프리뷰 위에는 안 보임)
          if (cameraState.roomId != null &&
              cameraState.connectionState == CameraConnectionState.streaming)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                '방 ID: ${cameraState.roomId}  •  스트리밍 중',
                style: const TextStyle(color: Colors.greenAccent, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),

          // 서버 IP 입력 필드 (카메라 시작 전에만 표시)
          if (!isActive) ...[
            TextField(
              controller: _serverHostController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: '시그널링 서버 IP',
                labelStyle: TextStyle(color: Colors.white70),
                hintText: '예: 192.168.0.100',
                hintStyle: TextStyle(color: Colors.white30),
                // 비활성 상태 테두리
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white30),
                ),
                // 포커스 상태 테두리
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.blue),
                ),
              ),
              // 숫자와 . 만 입력 가능하도록
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
          ],

          // 시작 / 중지 버튼
          ElevatedButton.icon(
            // 연결 중에는 버튼 비활성화 (null을 넘기면 비활성)
            onPressed: cameraState.connectionState ==
                    CameraConnectionState.connecting
                ? null
                : isActive
                    ? viewModel.stopCamera
                    : () =>
                        viewModel.startCamera(_serverHostController.text.trim()),
            icon: cameraState.connectionState == CameraConnectionState.connecting
                // 연결 중: 로딩 스피너 표시
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(isActive ? Icons.stop_circle : Icons.videocam),
            label: Text(_buttonLabel(cameraState.connectionState)),
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
  String _buttonLabel(CameraConnectionState connectionState) {
    // Dart 3 switch expression — switch문이 값을 반환하는 표현식 형태
    return switch (connectionState) {
      CameraConnectionState.idle => '카메라 시작',
      CameraConnectionState.connecting => '연결 중...',
      CameraConnectionState.waitingForViewer => '중지 (뷰어 대기 중)',
      CameraConnectionState.streaming => '중지 (스트리밍 중)',
      CameraConnectionState.error => '다시 시작',
    };
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 보조 위젯 — 재사용 가능한 작은 위젯은 별도 클래스로 분리하면 가독성이 높아진다
// ══════════════════════════════════════════════════════════════════════════════

/// 연결 상태를 색상으로 표시하는 배지 위젯.
///
/// 프라이빗 클래스(_로 시작)로 선언하면 이 파일 외부에서 사용 불가.
/// 파일 내부에서만 쓰는 위젯은 프라이빗으로 두어 공개 API를 최소화한다.
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.connectionState});

  final CameraConnectionState connectionState;

  @override
  Widget build(BuildContext context) {
    // 패턴 매칭으로 레이블과 색상을 한 번에 추출 (Dart 3 record 반환)
    final (label, color) = switch (connectionState) {
      CameraConnectionState.idle => ('대기', Colors.grey),
      CameraConnectionState.connecting => ('연결 중', Colors.orange),
      CameraConnectionState.waitingForViewer => ('뷰어 대기', Colors.amber),
      CameraConnectionState.streaming => ('스트리밍', Colors.green),
      CameraConnectionState.error => ('에러', Colors.red),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        // withAlpha: 투명도 설정 (0~255). withOpacity(0~1.0)보다 성능이 좋음
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

/// 뷰어에게 보여줄 방 ID를 크게 표시하는 위젯.
///
/// letterSpacing으로 숫자 간격을 벌려 읽기 쉽게 만든다.
class _RoomIdDisplay extends StatelessWidget {
  const _RoomIdDisplay({required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(180),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '뷰어에게 알려줄 방 ID',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text(
            roomId,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 52,
              fontWeight: FontWeight.bold,
              // letterSpacing: 글자 간격 — 6자리 숫자를 구분하기 쉽게
              letterSpacing: 10,
            ),
          ),
        ],
      ),
    );
  }
}
