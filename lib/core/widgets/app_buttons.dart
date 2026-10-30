import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

const _buttonHeight = 62.0;

/// Solid button ([color], brand blue by default); renders the light-gray
/// disabled state from the mock-ups when [onPressed] is null, and a spinner
/// while [loading].
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.color = AppColors.blue,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _buttonHeight,
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: AppRadius.medium),
          backgroundColor: color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: loading ? color : AppColors.disabledBg,
          disabledForegroundColor: loading ? Colors.white : AppColors.disabledFg,
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        child: loading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
              )
            : Text(label),
      ),
    );
  }
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _buttonHeight,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: AppRadius.medium),
          side: const BorderSide(color: AppColors.border),
          foregroundColor: const Color(0xFF374151),
          disabledForegroundColor: AppColors.disabledFg,
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
        ),
        child: Text(label),
      ),
    );
  }
}

/// Blue bold inline link, as in "¿No tienes cuenta? **Solicítala aquí**".
class LinkText extends StatelessWidget {
  const LinkText(this.text, {super.key, this.onTap, this.size = 16});

  final String text;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Text(
        text,
        style: TextStyle(fontSize: size, fontWeight: FontWeight.w600, color: AppColors.blue),
      ),
    );
  }
}

/// "¿Pregunta? **Acción**" footer pinned at the bottom of auth screens.
class AuthFooter extends StatelessWidget {
  const AuthFooter({super.key, required this.question, required this.action, required this.onTap});

  final String question;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        children: [
          Text(question, style: const TextStyle(fontSize: 16, color: AppColors.muted)),
          LinkText(action, onTap: onTap),
        ],
      ),
    );
  }
}
