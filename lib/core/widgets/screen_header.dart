import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Header of the module screens: back arrow (none on the root of a tab),
/// title + subtitle, optional action.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.onBack,
    this.action,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onBack;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFF0F1F4))),
      ),
      padding: const EdgeInsets.fromLTRB(8, 14, 20, 14),
      child: Row(
        children: [
          if (onBack != null) ...[
            IconButton(
              tooltip: 'Volver',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, color: AppColors.muted),
            ),
            const SizedBox(width: 4),
          ] else
            const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.ink),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, color: AppColors.muted),
                ),
              ],
            ),
          ),
          if (action != null) ...[const SizedBox(width: 12), action!],
        ],
      ),
    );
  }
}

/// "+ Nueva" style button on the right of a [ScreenHeader].
class HeaderAction extends StatelessWidget {
  const HeaderAction({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.add, size: 20),
        label: Text(label),
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: AppRadius.medium),
          backgroundColor: AppColors.teal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
