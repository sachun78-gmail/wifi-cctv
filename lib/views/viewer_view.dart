import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ViewerView extends StatelessWidget {
  const ViewerView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('뷰어 모드'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
      ),
      body: const Center(child: Text('뷰어 모드 (Phase 5에서 구현)')),
    );
  }
}
