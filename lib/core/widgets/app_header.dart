import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Top bar of the signed-in screens: [back arrow] + logo + "Voltcast" + actions.
class AppHeader extends StatelessWidget {
  const AppHeader({super.key, this.onBack, this.actions = const []});

  final VoidCallback? onBack;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFF0F1F4))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              tooltip: 'Volver',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, color: AppColors.muted),
            )
          else
            const SizedBox(width: 8),
          Image.asset('assets/logo/logo.png', width: 36, height: 36),
          const SizedBox(width: 12),
          const Text(
            'Voltcast',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.ink),
          ),
          const Spacer(),
          ...actions,
        ],
      ),
    );
  }
}

/// Soft white card used across the signed-in screens.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  static const shadow = [BoxShadow(color: Color(0x140F172A), blurRadius: 18, offset: Offset(0, 6))];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(color: Colors.white, borderRadius: AppRadius.large, boxShadow: AppCard.shadow),
      child: child,
    );
  }
}
