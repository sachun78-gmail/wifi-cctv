import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:wifi_cctv/views/camera_view.dart';
import 'package:wifi_cctv/views/home_view.dart';
import 'package:wifi_cctv/views/viewer_view.dart';

// ══════════════════════════════════════════════════════════════════════════════
// 라우팅 설정 (go_router)
// ══════════════════════════════════════════════════════════════════════════════

/// 앱 전체 라우팅을 담당하는 GoRouter 인스턴스.
///
/// go_router란?
///   - Flutter 공식 권장 라우팅 패키지(flutter.dev).
///   - URL 기반으로 화면을 관리하며, 웹/딥링크도 동일한 방식으로 처리한다.
///   - Navigator 2.0 API를 감싼 고수준 API라 코드가 단순하다.
///
/// GoRoute:
///   - path: URL 경로 (예: '/camera')
///   - builder: 해당 경로로 이동할 때 생성할 위젯
///
/// context.go(path): 현재 경로를 교체 (뒤로가기 스택에 쌓이지 않음)
/// context.push(path): 스택에 추가 (뒤로가기 가능)
/// → 이 앱에서는 홈 ↔ 카메라/뷰어가 동등한 관계이므로 go()를 사용한다.
final _router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomeView()),
    GoRoute(path: '/camera', builder: (context, state) => const CameraView()),
    GoRoute(path: '/viewer', builder: (context, state) => const ViewerView()),
  ],
);

// ══════════════════════════════════════════════════════════════════════════════
// 앱 진입점
// ══════════════════════════════════════════════════════════════════════════════

void main() {
  // runApp: Flutter 앱을 시작하는 함수.
  // 전달한 위젯이 위젯 트리의 루트가 된다.
  runApp(
    // ProviderScope: Riverpod의 루트 위젯.
    // - 이 위젯 아래의 모든 Provider가 여기서 관리된다.
    // - 앱 전체에서 Provider를 사용하려면 반드시 최상단에 위치해야 한다.
    // - ProviderScope 없이 ref.watch/read를 호출하면 런타임 오류가 발생한다.
    const ProviderScope(
      child: WifiCctvApp(),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// 루트 위젯
// ══════════════════════════════════════════════════════════════════════════════

/// 앱 전체 설정(테마, 라우팅)을 담당하는 루트 위젯.
///
/// StatelessWidget: 테마와 라우터는 앱 생명주기 동안 변하지 않으므로 상태 불필요.
class WifiCctvApp extends StatelessWidget {
  const WifiCctvApp({super.key});

  @override
  Widget build(BuildContext context) {
    // MaterialApp.router: go_router와 함께 사용하는 MaterialApp 변형.
    // - 일반 MaterialApp은 Navigator를 직접 사용할 때 적합하다.
    // - go_router처럼 외부 라우터를 쓸 때는 .router 생성자를 사용해야 한다.
    // - routerConfig에 GoRouter 인스턴스를 전달하면 라우팅이 연결된다.
    return MaterialApp.router(
      title: 'WiFi CCTV',
      // ThemeData: 앱 전체의 색상, 폰트, 컴포넌트 스타일을 일괄 정의.
      // ColorScheme.fromSeed: 씨앗 색상(seedColor)으로 Material 3 색상 팔레트를 자동 생성.
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      routerConfig: _router,
    );
  }
}
