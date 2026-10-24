import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/validators.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/auth_layout.dart';
import '../../../../core/widgets/auth_visuals.dart';
import '../../data/auth_repository.dart';
import '../../../../core/submit_state.dart';
import 'reset_args.dart';

class ForgotNewPasswordScreen extends StatefulWidget {
  const ForgotNewPasswordScreen({super.key, required this.args});

  final ResetArgs args;

  @override
  State<ForgotNewPasswordScreen> createState() => _ForgotNewPasswordScreenState();
}

class _ForgotNewPasswordScreenState extends State<ForgotNewPasswordScreen> with SubmitState {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _valid =>
      Validators.newPassword(_password.text) == null && _confirm.text == _password.text;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final repository = context.read<AuthRepository>();
    final ok = await submit(
      () => repository.confirmPasswordReset(
        email: widget.args.email,
        code: widget.args.code,
        newPassword: _password.text,
      ),
    );
    if (ok && mounted) context.go('/forgot/success');
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      backLabel: 'Volver',
      children: [
        const IconTile(icon: Icons.shield_outlined),
        const SizedBox(height: 40),
        const AuthHeading(
          title: 'Nueva contraseña',
          subtitle: 'Crea una contraseña segura para tu cuenta',
        ),
        const SizedBox(height: 36),
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(
                label: 'Nueva contraseña',
                hint: 'Mínimo 8 caracteres',
                controller: _password,
                obscure: true,
                textInputAction: TextInputAction.next,
                validator: Validators.newPassword,
                enabled: !loading,
              ),
              const SizedBox(height: 12),
              ValueListenableBuilder(
                valueListenable: _password,
                builder: (context, value, _) =>
                    PasswordStrengthBar(score: Validators.passwordStrength(value.text)),
              ),
              const SizedBox(height: 24),
              AppTextField(
                label: 'Confirmar contraseña',
                hint: 'Repite tu contraseña',
                controller: _confirm,
                obscure: true,
                textInputAction: TextInputAction.done,
                validator: Validators.confirmPassword(() => _password.text),
                onSubmitted: (_) => _valid ? _save() : null,
                enabled: !loading,
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        if (error != null) ...[
          ErrorBanner(error!),
          const SizedBox(height: 16),
        ],
        ListenableBuilder(
          listenable: Listenable.merge([_password, _confirm]),
          builder: (context, _) => PrimaryButton(
            label: 'Cambiar contraseña',
            loading: loading,
            onPressed: _valid ? _save : null,
          ),
        ),
      ],
    );
  }
}
