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

class ForgotEmailScreen extends StatefulWidget {
  const ForgotEmailScreen({super.key});

  @override
  State<ForgotEmailScreen> createState() => _ForgotEmailScreenState();
}

class _ForgotEmailScreenState extends State<ForgotEmailScreen> with SubmitState {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    final repository = context.read<AuthRepository>();
    final email = _email.text.trim();
    final ok = await submit(() => repository.requestPasswordReset(email));
    // The backend answers the same whether or not the email exists, so we
    // always continue to the code screen.
    if (ok && mounted) context.push('/forgot/code', extra: email);
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      backLabel: 'Volver',
      onBack: () => context.canPop() ? context.pop() : context.go('/login'),
      footer: AuthFooter(
        question: '¿Recordaste tu contraseña?',
        action: 'Inicia sesión',
        onTap: () => context.go('/login'),
      ),
      children: [
        const IconTile(icon: Icons.lock_outline),
        const SizedBox(height: 40),
        const AuthHeading(
          title: 'Recuperar\ncontraseña',
          subtitle: 'Ingresa tu correo y te enviaremos un código de verificación '
              'válido por 15 minutos.',
        ),
        const SizedBox(height: 36),
        Form(
          key: _formKey,
          child: AppTextField(
            label: 'Correo electrónico',
            hint: 'nombre@voltcast.io',
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.email],
            validator: Validators.email,
            onSubmitted: (_) => _send(),
            enabled: !loading,
          ),
        ),
        const SizedBox(height: 28),
        if (error != null) ...[
          ErrorBanner(error!),
          const SizedBox(height: 16),
        ],
        ListenableBuilder(
          listenable: _email,
          builder: (context, _) => PrimaryButton(
            label: 'Enviar código',
            loading: loading,
            onPressed: _email.text.trim().isEmpty ? null : _send,
          ),
        ),
      ],
    );
  }
}
