import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/validators.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/auth_layout.dart';
import '../../../../core/widgets/auth_visuals.dart';
import '../../data/auth_repository.dart';
import '../../../../core/submit_state.dart';
import 'package:provider/provider.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> with SubmitState {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _sent = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    final repository = context.read<AuthRepository>();
    final ok = await submit(
      () => repository.register(
        fullName: _name.text,
        email: _email.text,
        password: _password.text,
      ),
    );
    if (ok && mounted) setState(() => _sent = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_sent) return _SentView(email: _email.text.trim());

    return AuthLayout(
      footer: AuthFooter(
        question: '¿Ya tienes cuenta?',
        action: 'Inicia sesión',
        onTap: () => context.go('/login'),
      ),
      children: [
        const BrandMark(),
        const SizedBox(height: 56),
        const AuthHeading(
          title: 'Solicitar cuenta',
          subtitle: 'Tu solicitud quedará pendiente de aprobación',
        ),
        const SizedBox(height: 36),
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(
                label: 'Nombre completo',
                hint: 'María García',
                controller: _name,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                validator: Validators.fullName,
                enabled: !loading,
              ),
              const SizedBox(height: 24),
              AppTextField(
                label: 'Correo electrónico',
                hint: 'nombre@ejemplo.com',
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                validator: Validators.email,
                enabled: !loading,
              ),
              const SizedBox(height: 24),
              AppTextField(
                label: 'Contraseña',
                hint: 'Mínimo 8 caracteres',
                controller: _password,
                obscure: true,
                textInputAction: TextInputAction.next,
                validator: Validators.newPassword,
                enabled: !loading,
              ),
              const SizedBox(height: 24),
              AppTextField(
                label: 'Confirmar contraseña',
                hint: 'Repite tu contraseña',
                controller: _confirm,
                obscure: true,
                textInputAction: TextInputAction.done,
                validator: Validators.confirmPassword(() => _password.text),
                onSubmitted: (_) => _register(),
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
        // Always enabled: submitting an incomplete form is answered with a
        // message under each missing field (US023 E02).
        PrimaryButton(label: 'Solicitar cuenta', loading: loading, onPressed: _register),
      ],
    );
  }
}

class _SentView extends StatelessWidget {
  const _SentView({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      centered: true,
      children: [
        const SolidIconTile(icon: Icons.check),
        const SizedBox(height: 40),
        const AuthHeading(
          center: true,
          title: 'Solicitud\nenviada',
          subtitle: 'Un supervisor revisará tu solicitud. Podrás iniciar sesión '
              'cuando sea aprobada.',
        ),
        const SizedBox(height: 40),
        PrimaryButton(
          label: 'Volver al inicio de sesión',
          onPressed: () => context.go('/login'),
        ),
      ],
    );
  }
}
