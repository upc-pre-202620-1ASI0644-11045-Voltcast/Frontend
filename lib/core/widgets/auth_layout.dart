import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Page shell shared by all auth screens: 28px gutters, scrolls when the
/// keyboard is open, and keeps [footer] at the bottom when there is room.
class AuthLayout extends StatelessWidget {
  const AuthLayout({
    super.key,
    required this.children,
    this.footer,
    this.backLabel,
    this.onBack,
    this.centered = false,
  });

  final List<Widget> children;
  final Widget? footer;

  /// Shows the "← Volver" row when set.
  final String? backLabel;
  final VoidCallback? onBack;

  /// Vertically centres the content (success screens).
  final bool centered;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        // Width cap keeps the form readable on tablets and the Windows/web
        // builds. It sits outside the scroll view so the minHeight below
        // reaches IntrinsicHeight and the Spacers can pin the footer down.
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (backLabel != null) _BackRow(label: backLabel!, onBack: onBack),
                          if (centered) const Spacer(),
                          if (!centered && backLabel == null) const SizedBox(height: 40),
                          ...children,
                          const Spacer(),
                          ?footer,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BackRow extends StatelessWidget {
  const _BackRow({required this.label, this.onBack});

  final String label;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 24),
      child: Align(
        alignment: Alignment.centerLeft,
        child: InkWell(
          onTap: onBack ?? () => Navigator.of(context).maybePop(),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.arrow_back, size: 20, color: AppColors.muted),
                const SizedBox(width: 10),
                Text(label, style: const TextStyle(fontSize: 16, color: AppColors.muted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Large heading + grey subtitle used by every auth screen.
class AuthHeading extends StatelessWidget {
  const AuthHeading({super.key, required this.title, this.subtitle, this.subtitleWidget, this.center = false});

  final String title;
  final String? subtitle;
  final Widget? subtitleWidget;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final align = center ? TextAlign.center : TextAlign.start;
    return Column(
      crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTheme.title, textAlign: align),
        if (subtitle != null || subtitleWidget != null) const SizedBox(height: 14),
        if (subtitleWidget != null)
          subtitleWidget!
        else if (subtitle != null)
          Text(subtitle!, style: AppTheme.subtitle, textAlign: align),
      ],
    );
  }
}
