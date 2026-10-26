import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Header of the module screens: back arrow (none on the root of a tab),
/// title + subtitle, optional action.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({super.key, required this.title, required this.subtitle, this.onBack, this.action});

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
          shape: const StadiumBorder(),
          backgroundColor: AppColors.lime,
          foregroundColor: AppColors.ink,
          disabledBackgroundColor: Colors.white24,
          disabledForegroundColor: Colors.white60,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

/// Blue top of the tab screens: brand row, eyebrow + big title, an optional
/// action, and [bottom] (the stats card) hanging over its lower edge.
/// Draws under the status bar, so it is placed outside any SafeArea.
class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key, required this.eyebrow, required this.title, this.action, this.onLogout, this.bottom});

  final String eyebrow;
  final String title;
  final Widget? action;
  final VoidCallback? onLogout;
  final Widget? bottom;

  static const _overlap = 44.0;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Stack(
      children: [
        Positioned.fill(
          bottom: bottom == null ? 0 : _overlap,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.headerTop, AppColors.headerBottom],
              ),
            ),
            // Decorative ring in the corner, as in the mock-ups.
            child: Align(
              alignment: Alignment.topRight,
              child: Transform.translate(
                offset: const Offset(60, -70),
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.07)),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, top + 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Image.asset('assets/logo/logo-circular.png', width: 34, height: 34),
                  const SizedBox(width: 10),
                  const Text(
                    'Voltcast',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                  const Spacer(),
                  if (onLogout != null)
                    IconButton(
                      tooltip: 'Cerrar sesión',
                      onPressed: onLogout,
                      icon: const Icon(Icons.logout, size: 20),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.16),
                        foregroundColor: Colors.white,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 22),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          eyebrow,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.8)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (action != null) ...[const SizedBox(width: 12), action!],
                ],
              ),
              SizedBox(height: bottom == null ? 28 : 20),
              ?bottom,
            ],
          ),
        ),
      ],
    );
  }
}
