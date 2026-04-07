import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class HomeView extends StatelessWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WiFi CCTV')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('모드를 선택하세요', style: TextStyle(fontSize: 20)),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => context.go('/camera'),
              icon: const Icon(Icons.videocam),
              label: const Text('카메라 모드'),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => context.go('/viewer'),
              icon: const Icon(Icons.tv),
              label: const Text('뷰어 모드'),
            ),
          ],
        ),
      ),
    );
  }
}
