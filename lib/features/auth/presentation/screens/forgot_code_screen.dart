import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/validators.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/auth_layout.dart';
import '../../../../core/widgets/auth_visuals.dart';
import '../../data/auth_repository.dart';
import '../../../../core/submit_state.dart';
import 'reset_args.dart';

class ForgotCodeScreen extends StatefulWidget {
  const ForgotCodeScreen({super.key, required this.email});

  final String email;

  @override
  State<ForgotCodeScreen> createState() => _ForgotCodeScreenState();
}

class _ForgotCodeScreenState extends State<ForgotCodeScreen> with SubmitState {
  static const _resendCooldown = 30;

  final _code = TextEditingController();
  Timer? _timer;
  int _secondsLeft = _resendCooldown;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _secondsLeft = _resendCooldown);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft <= 1) {
        t.cancel();
      }
      if (mounted) setState(() => _secondsLeft--);
    });
  }

  Future<void> _resend() async {
    final repository = context.read<AuthRepository>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await submit(() => repository.requestPasswordReset(widget.email));
    if (!ok || !mounted) return;
    _startCooldown();
    messenger.showSnackBar(const SnackBar(content: Text('Te enviamos un nuevo código.')));
  }

  // There is no "verify only" endpoint: the code is checked by the backend
  // together with the new password on the next screen, which comes back here
  // with a message when the code is wrong or expired.
  Future<void> _continue() async {
    final rejection = await context.push<String>(
      '/forgot/new-password',
      extra: ResetArgs(email: widget.email, code: _code.text),
    );
    if (rejection != null && mounted) {
      _code.clear();
      setState(() => error = rejection);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canResend = _secondsLeft <= 0 && !loading;
    return AuthLayout(
      backLabel: 'Volver al inicio',
      onBack: () => context.go('/login'),
      children: [
        const SolidIconTile(icon: Icons.mail_outline, size: 112),
        const SizedBox(height: 40),
        AuthHeading(
          center: true,
          title: 'Revisa tu correo',
          subtitleWidget: Text.rich(
            textAlign: TextAlign.center,
            TextSpan(
              style: AppTheme.subtitle,
              children: [
                const TextSpan(text: 'Enviamos un código de verificación a '),
                TextSpan(
                  text: widget.email,
                  style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink),
                ),
                const TextSpan(text: '. Válido por '),
                const TextSpan(
                  text: '15 minutos',
                  style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink),
                ),
                const TextSpan(text: '.'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 36),
        AppTextField(
          label: 'Código de verificación',
          hint: '000000',
          controller: _code,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          validator: Validators.verificationCode,
          onSubmitted: (_) => _code.text.length == 6 ? _continue() : null,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w600,
            letterSpacing: 14,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 20),
        if (error != null) ...[
          ErrorBanner(error!),
          const SizedBox(height: 16),
        ],
        ListenableBuilder(
          listenable: _code,
          builder: (context, _) => PrimaryButton(
            label: 'Verificar código',
            onPressed: _code.text.length == 6 ? _continue : null,
          ),
        ),
        const SizedBox(height: 16),
        SecondaryButton(
          label: _secondsLeft > 0 ? 'Reenviar código en ${_secondsLeft}s' : 'Reenviar código',
          onPressed: canResend ? _resend : null,
        ),
        const SizedBox(height: 28),
        const InfoBox(
          text: 'Si no ves el correo, revisa tu carpeta de spam. El código expira en 15 minutos.',
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
