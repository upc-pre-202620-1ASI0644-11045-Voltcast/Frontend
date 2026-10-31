import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Light top of the screens opened over the tabs: round back button, the
/// "Voltcast" mark, a small eyebrow and a big title, with an optional [trailing]
/// widget under them (a count and an action).
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    this.onBack,
    this.trailing,
  });

  final String eyebrow;
  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (onBack != null)
                IconButton(
                  tooltip: 'Volver',
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back, size: 20),
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.field,
                    foregroundColor: AppColors.ink,
                    fixedSize: const Size.square(40),
                  ),
                ),
              const Spacer(),
              const Icon(Icons.bolt_outlined, size: 18, color: AppColors.blue),
              const SizedBox(width: 2),
              const Text(
                'Voltcast',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            eyebrow,
            style: const TextStyle(fontSize: 14, color: AppColors.muted),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: AppColors.ink,
            ),
          ),
          if (trailing != null) ...[const SizedBox(height: 14), trailing!],
        ],
      ),
    );
  }
}

/// The spreadsheet mark of the file cards: a green sheet with an "X".
class ExcelIcon extends StatelessWidget {
  const ExcelIcon({super.key, this.size = 56});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFE8F8EE),
          borderRadius: BorderRadius.circular(size * 0.28),
        ),
        child: Center(
          child: Container(
            width: size * 0.5,
            height: size * 0.5,
            decoration: BoxDecoration(
              color: const Color(0xFF16A34A),
              borderRadius: BorderRadius.circular(size * 0.1),
            ),
            alignment: Alignment.center,
            child: Text(
              'X',
              style: TextStyle(
                fontSize: size * 0.3,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
