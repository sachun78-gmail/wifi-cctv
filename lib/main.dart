import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'views/home_view.dart';
import 'views/camera_view.dart';
import 'views/viewer_view.dart';

final _router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomeView()),
    GoRoute(path: '/camera', builder: (context, state) => const CameraView()),
    GoRoute(path: '/viewer', builder: (context, state) => const ViewerView()),
  ],
);

void main() {
  runApp(
    const ProviderScope(
      child: WifiCctvApp(),
    ),
  );
}

class WifiCctvApp extends StatelessWidget {
  const WifiCctvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'WiFi CCTV',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      routerConfig: _router,
    );
  }
}
