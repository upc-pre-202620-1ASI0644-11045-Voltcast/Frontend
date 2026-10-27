import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(color: AppColors.blue, strokeWidth: 3),
      ),
    );
  }
}
