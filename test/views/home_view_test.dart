import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:wifi_cctv/views/home_view.dart';

// ══════════════════════════════════════════════════════════════════════════════
// 테스트 헬퍼
// ══════════════════════════════════════════════════════════════════════════════

/// HomeView를 테스트용 앱으로 감싸는 헬퍼.
///
/// 위젯 테스트에서 HomeView를 단독으로 렌더링하려면 아래 요소들이 필요하다:
///   1. MaterialApp: Scaffold, Theme, MediaQuery 등 Material 위젯의 기반 컨텍스트
///   2. GoRouter: context.go()가 내부적으로 GoRouter를 찾으므로, 없으면 오류 발생
///   3. ProviderScope: HomeView는 직접 Riverpod을 쓰지 않지만, 하위 위젯이 쓸 수 있어 안전하게 포함
///
/// 스텁(stub) 경로:
///   - 실제 CameraView/ViewerView 대신 가벼운 Scaffold를 사용해 테스트 속도를 높인다.
///   - 탭 후 해당 텍스트가 화면에 보이는지로 네비게이션 성공 여부를 검증한다.
Widget buildTestApp({GoRouter? router}) {
  final testRouter = router ??
      GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => const HomeView(),
          ),
          GoRoute(
            path: '/camera',
            // 실제 CameraView 대신 가벼운 스텁 — 네이티브 바인딩 없이 테스트 가능
            builder: (_, __) =>
                const Scaffold(body: Center(child: Text('카메라 화면'))),
          ),
          GoRoute(
            path: '/viewer',
            builder: (_, __) =>
                const Scaffold(body: Center(child: Text('뷰어 화면'))),
          ),
        ],
      );

  return ProviderScope(
    child: MaterialApp.router(routerConfig: testRouter),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// 테스트
// ══════════════════════════════════════════════════════════════════════════════

void main() {
  // ── UI 렌더링 ────────────────────────────────────────────────────────────────
  group('HomeView UI 렌더링', () {
    testWidgets('앱 타이틀 "WiFi CCTV" 표시', (tester) async {
      await tester.pumpWidget(buildTestApp());

      // find.text: 화면에서 해당 텍스트를 가진 위젯을 찾는다
      expect(find.text('WiFi CCTV'), findsOneWidget);
    });

    testWidgets('카메라 모드 카드 — 제목 표시', (tester) async {
      await tester.pumpWidget(buildTestApp());

      expect(find.text('카메라'), findsOneWidget);
    });

    testWidgets('뷰어 모드 카드 — 제목 표시', (tester) async {
      await tester.pumpWidget(buildTestApp());

      expect(find.text('뷰어'), findsOneWidget);
    });

    testWidgets('사용 순서 힌트 — 첫 번째 항목 표시', (tester) async {
      await tester.pumpWidget(buildTestApp());

      // 힌트 텍스트의 일부가 화면에 있는지 확인
      expect(
        find.textContaining('카메라 모드'),
        findsOneWidget,
      );
    });

    testWidgets('카메라/뷰어 아이콘 표시', (tester) async {
      await tester.pumpWidget(buildTestApp());

      // find.byIcon: IconData를 가진 Icon 위젯을 찾는다
      expect(find.byIcon(Icons.videocam), findsOneWidget);
      expect(find.byIcon(Icons.tv), findsOneWidget);
    });
  });

  // ── 네비게이션 ───────────────────────────────────────────────────────────────
  group('HomeView 네비게이션', () {
    testWidgets('카메라 카드 탭 → /camera 이동', (tester) async {
      await tester.pumpWidget(buildTestApp());

      // 카메라 카드를 탭
      await tester.tap(find.text('카메라'));

      // pumpAndSettle: 애니메이션과 비동기 작업이 모두 완료될 때까지 기다린다.
      // 단순 pump()는 한 프레임만 처리하므로 화면 전환 애니메이션이 끝나지 않을 수 있다.
      await tester.pumpAndSettle();

      // 스텁 경로에서 /camera로 이동하면 '카메라 화면' 텍스트가 보여야 한다
      expect(find.text('카메라 화면'), findsOneWidget);
      // 홈 화면은 더 이상 표시되지 않아야 한다
      expect(find.text('WiFi CCTV'), findsNothing);
    });

    testWidgets('뷰어 카드 탭 → /viewer 이동', (tester) async {
      await tester.pumpWidget(buildTestApp());

      await tester.tap(find.text('뷰어'));
      await tester.pumpAndSettle();

      expect(find.text('뷰어 화면'), findsOneWidget);
      expect(find.text('WiFi CCTV'), findsNothing);
    });
  });
}
