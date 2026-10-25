import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/validators.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/auth_layout.dart';
import '../../../../core/widgets/auth_visuals.dart';
import '../auth_controller.dart';
import '../../../../core/submit_state.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SubmitState {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthController>();
    // On success the router redirects to /home by itself.
    await submit(() => auth.login(email: _email.text, password: _password.text));
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      footer: AuthFooter(
        question: '¿No tienes cuenta?',
        action: 'Solicítala aquí',
        onTap: () => context.go('/register'),
      ),
      children: [
        const BrandMark(),
        const SizedBox(height: 56),
        const AuthHeading(
          title: 'Bienvenido\nde vuelta',
          subtitle: 'Ingresa tus credenciales para continuar',
        ),
        const SizedBox(height: 40),
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              const SizedBox(height: 28),
              AppTextField(
                label: 'Contraseña',
                hint: '••••••••',
                controller: _password,
                obscure: true,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                validator: (v) => Validators.required(v, 'Campo obligatorio: ingresa tu contraseña.'),
                onSubmitted: (_) => _login(),
                enabled: !loading,
                trailingLabel: LinkText(
                  '¿Olvidaste tu contraseña?',
                  size: 14,
                  onTap: loading ? null : () => context.push('/forgot'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        if (error != null) ...[
          ErrorBanner(error!),
          const SizedBox(height: 16),
        ],
        PrimaryButton(label: 'Iniciar sesión', loading: loading, onPressed: _login),
      ],
    );
  }
}
