import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/load_error.dart';

String volts(double value, [int digits = 3]) =>
    '${value.toStringAsFixed(digits)} V';

/// Permanent while the model is being retrained; the data shown is still valid.
class RetrainingBanner extends StatelessWidget {
  const RetrainingBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppRadius.medium,
      child: const NoticeBanner(
        icon: Icons.autorenew,
        background: AppColors.blueSoft,
        foreground: Color(0xFF1E3A8A),
        text: 'Se está reentrenando el modelo; usas la última versión disponible y pronto habrá una nueva.',
      ),
    );
  }
}

/// Data read from the device because there is no network.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner(this.savedAt, {super.key});

  final DateTime savedAt;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppRadius.medium,
      child: NoticeBanner(
        icon: Icons.cloud_off_outlined,
        text: 'Sin conexión. Datos guardados el ${formatShortDate(savedAt)}.',
      ),
    );
  }
}

class NoModelState extends StatelessWidget {
  const NoModelState({super.key});

  @override
  Widget build(BuildContext context) => const EmptyState(
    icon: Icons.model_training,
    title: 'Aún no hay un modelo entrenado',
    message: 'Sube un archivo histórico y entrena el modelo para ver los pronósticos.',
  );
}

class NoOfflineDataState extends StatelessWidget {
  const NoOfflineDataState({super.key});

  @override
  Widget build(BuildContext context) => const EmptyState(
    icon: Icons.cloud_off_outlined,
    title: 'No existen pronósticos disponibles para consulta sin conexión',
    message:
        'Conéctate para consultarlos; quedarán guardados en este dispositivo.',
  );
}
