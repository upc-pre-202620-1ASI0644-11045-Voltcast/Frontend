import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
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
  bool _accepted = false;
  bool _sent = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _accepted &&
      _name.text.trim().isNotEmpty &&
      _email.text.trim().isNotEmpty &&
      _password.text.isNotEmpty &&
      _confirm.text.isNotEmpty;

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
                onSubmitted: (_) => _canSubmit ? _register() : null,
                enabled: !loading,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _TermsCheckbox(
          value: _accepted,
          onChanged: loading ? null : (v) => setState(() => _accepted = v),
        ),
        const SizedBox(height: 28),
        if (error != null) ...[
          ErrorBanner(error!),
          const SizedBox(height: 16),
        ],
        ListenableBuilder(
          listenable: Listenable.merge([_name, _email, _password, _confirm]),
          builder: (context, _) => PrimaryButton(
            label: 'Solicitar cuenta',
            loading: loading,
            onPressed: _canSubmit ? _register : null,
          ),
        ),
      ],
    );
  }
}

class _TermsCheckbox extends StatelessWidget {
  const _TermsCheckbox({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    // The terms/privacy documents are not defined yet, so these are styled
    // like the mock-up but have no destination.
    const link = TextStyle(fontWeight: FontWeight.w600, color: AppColors.blue);
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: Checkbox(
              value: value,
              onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
              shape: RoundedRectangleBorder(borderRadius: AppRadius.small),
              side: const BorderSide(color: AppColors.border, width: 2),
              activeColor: AppColors.blue,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text.rich(
                const TextSpan(
                  style: TextStyle(fontSize: 16, height: 1.5, color: AppColors.muted),
                  children: [
                    TextSpan(text: 'Acepto los '),
                    TextSpan(text: 'Términos de servicio', style: link),
                    TextSpan(text: ' y la '),
                    TextSpan(text: 'Política de privacidad', style: link),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
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
