import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/auth_layout.dart';
import '../../../../core/widgets/auth_visuals.dart';

class ForgotSuccessScreen extends StatelessWidget {
  const ForgotSuccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      centered: true,
      children: [
        const SolidIconTile(icon: Icons.check, size: 104),
        const SizedBox(height: 44),
        const AuthHeading(
          center: true,
          title: '¡Contraseña\nactualizada!',
          subtitle: 'Tu contraseña fue cambiada exitosamente. Ya puedes iniciar '
              'sesión con tu nueva contraseña.',
        ),
        const SizedBox(height: 48),
        PrimaryButton(
          label: 'Volver al inicio de sesión',
          onPressed: () => context.go('/login'),
        ),
      ],
    );
  }
}
