import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The VoltCast logo square (assets/logo/logo.png) at the top of login/register.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 64});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Image.asset('assets/logo/logo.png', width: size, height: size, fit: BoxFit.cover),
    );
  }
}

/// Pale square with an outlined blue icon (lock / shield screens).
class IconTile extends StatelessWidget {
  const IconTile({super.key, required this.icon, this.size = 64});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: const Color(0xFFF0F1F4)),
        ),
        child: Icon(icon, color: AppColors.blue, size: size * 0.42),
      ),
    );
  }
}

/// Solid blue square with a white icon (mail / success check).
class SolidIconTile extends StatelessWidget {
  const SolidIconTile({super.key, required this.icon, this.size = 96});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: size,
        height: size,
        color: AppColors.blue,
        child: Icon(icon, color: Colors.white, size: size * 0.45),
      ),
    );
  }
}

/// Grey notice box with a leading icon ("Si no ves el correo…").
class InfoBox extends StatelessWidget {
  const InfoBox({super.key, required this.text, this.icon = Icons.info_outline});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: const Color(0xFFF0F1F4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.muted),
          const SizedBox(width: 14),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 14, height: 1.45, color: AppColors.muted)),
          ),
        ],
      ),
    );
  }
}

/// Inline error shown above the submit button when the API call fails.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 20, color: AppColors.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 14, height: 1.4, color: Color(0xFF991B1B)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Four-segment strength meter under the "Nueva contraseña" field.
class PasswordStrengthBar extends StatelessWidget {
  const PasswordStrengthBar({super.key, required this.score});

  /// 0..4
  final int score;

  static const _colors = [
    AppColors.border,
    AppColors.error,
    Color(0xFFF59E0B),
    Color(0xFF84CC16),
    AppColors.success,
  ];

  @override
  Widget build(BuildContext context) {
    final active = _colors[score.clamp(0, 4)];
    return Row(
      children: [
        for (var i = 0; i < 4; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Container(height: 4, color: i < score ? active : AppColors.border),
          ),
        ],
      ],
    );
  }
}
