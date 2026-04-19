import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// ══════════════════════════════════════════════════════════════════════════════
// HomeView
// ══════════════════════════════════════════════════════════════════════════════

/// 앱 진입 화면. 카메라 모드와 뷰어 모드 중 하나를 선택한다.
///
/// StatelessWidget 사용 이유:
///   - 이 화면은 관리할 상태(State)가 없다. 사용자 탭 → 화면 전환만 한다.
///   - 상태가 없으면 StatelessWidget이 더 단순하고 효율적이다.
///   - 상태가 필요해지면 StatefulWidget 또는 ConsumerWidget으로 전환한다.
class HomeView extends StatelessWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      // SafeArea: 노치, 상태바, 홈 인디케이터 등 시스템 UI와 겹치지 않도록 패딩을 추가한다.
      body: SafeArea(
        // SingleChildScrollView: 콘텐츠가 화면 높이를 초과할 때 스크롤되도록 한다.
        // 소형 폰이나 가로 모드에서도 힌트 영역이 잘리지 않는다.
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 헤더 ──────────────────────────────────────────────────────
              const SizedBox(height: 48),
              const Icon(
                Icons.wifi_tethering,
                size: 72,
                color: Colors.blue,
              ),
              const SizedBox(height: 16),
              const Text(
                'WiFi CCTV',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                '같은 Wi-Fi 네트워크에서 두 기기를 연결합니다',
                style: TextStyle(color: Colors.white54, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 64),

              // ── 모드 선택 카드 ──────────────────────────────────────────
              // Expanded: 남은 공간을 카드들이 균등하게 차지하도록 한다.
              // Row 안에 두 Expanded를 나란히 두면 화면을 반반 나눈다.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _ModeCard(
                      icon: Icons.videocam,
                      title: '카메라',
                      description: '이 기기의 카메라로\n영상을 촬영해 전송',
                      color: Colors.blue,
                      // context.go(): go_router의 화면 전환 메서드.
                      // Navigator.push()와 달리 URL 기반으로 동작하며,
                      // 뒤로가기 스택 대신 경로를 교체(replace)한다.
                      onTap: () => context.go('/camera'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _ModeCard(
                      icon: Icons.tv,
                      title: '뷰어',
                      description: '방 ID를 입력해\n원격 영상을 수신',
                      color: Colors.teal,
                      onTap: () => context.go('/viewer'),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // ── 연결 안내 ──────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(13), // 약 5% 불투명도
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: const Column(
                  children: [
                    _HintRow(
                      icon: Icons.looks_one_outlined,
                      text: '카메라 폰에서 "카메라 모드" 시작',
                    ),
                    SizedBox(height: 8),
                    _HintRow(
                      icon: Icons.looks_two_outlined,
                      text: '표시된 6자리 방 ID를 뷰어 폰에 입력',
                    ),
                    SizedBox(height: 8),
                    _HintRow(
                      icon: Icons.looks_3_outlined,
                      text: '뷰어 폰에서 "참여하기" 버튼 탭',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 보조 위젯
// ══════════════════════════════════════════════════════════════════════════════

/// 카메라/뷰어 모드를 선택하는 카드 위젯.
///
/// 재사용 가능한 단위로 분리하면 코드 중복을 줄이고 가독성이 높아진다.
/// 프라이빗(_) 클래스로 선언하여 이 파일 외부에서 노출되지 않게 한다.
class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // InkWell: Material 디자인의 터치 피드백(물결 효과)을 제공하는 위젯.
    // GestureDetector는 터치 인식만 하지만, InkWell은 시각적 피드백도 함께 제공한다.
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        decoration: BoxDecoration(
          // color.withAlpha(26): 약 10% 불투명도 — 은은한 배경색
          color: color.withAlpha(26),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withAlpha(80)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: color),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// 사용 순서를 안내하는 한 줄 힌트 위젯.
class _HintRow extends StatelessWidget {
  const _HintRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.white38),
        const SizedBox(width: 12),
        Expanded(
          // Expanded: Row 안에서 남은 가로 공간을 차지하도록 강제.
          // 없으면 텍스트가 길 때 Row 밖으로 넘쳐 overflow 오류가 발생한다.
          child: Text(
            text,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ),
      ],
    );
  }
}
