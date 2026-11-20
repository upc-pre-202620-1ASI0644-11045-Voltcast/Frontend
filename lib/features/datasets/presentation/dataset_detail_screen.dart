import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/format.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/backend_messages.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_header.dart';
import '../../../core/widgets/auth_visuals.dart';
import '../../../core/widgets/load_error.dart';
import '../../../core/widgets/page_header.dart';
import '../data/dataset.dart';
import 'datasets_controller.dart';
import 'datasets_screen.dart';

/// One file: its processing state and, once ready, what it contains.
class DatasetDetailScreen extends StatefulWidget {
  const DatasetDetailScreen({super.key, required this.id});

  final int id;

  @override
  State<DatasetDetailScreen> createState() => _DatasetDetailScreenState();
}

class _DatasetDetailScreenState extends State<DatasetDetailScreen> {
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    // The list has no summary; the detail does.
    final datasets = context.read<DatasetsController>();
    Future.microtask(() => datasets.refresh(widget.id));
  }

  Future<void> _confirm() async {
    final controller = context.read<DatasetsController>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _confirming = true);
    try {
      await controller.confirm(widget.id);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<DatasetsController>();
    final d = c.byId(widget.id);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            PageHeader(
              eyebrow: 'Detalle del archivo',
              title: d?.filename ?? 'Archivo',
              onBack: () =>
                  context.canPop() ? context.pop() : context.go('/datasets'),
            ),
            Expanded(
              child: d == null
                  ? (c.error != null
                        ? LoadErrorView(
                            message: c.error!,
                            onRetry: () => c.refresh(widget.id),
                          )
                        : const Center(child: CircularProgressIndicator()))
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: _content(d),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(Dataset d) {
    return [
      _Hero(dataset: d),
      const SizedBox(height: 16),
      switch (d.status) {
        DatasetStatus.raw || DatasetStatus.cleaning => AppCard(
          child: Text(
            d.status == DatasetStatus.raw
                ? 'El archivo está en cola. Se revisará en cuanto haya capacidad.'
                : 'Procesando el archivo'
                      '${d.rowCount > 0 ? ': ${d.processedRowCount} de ${d.rowCount} filas' : ''}. '
                      'Esta pantalla se actualiza sola.',
            style: const TextStyle(
              fontSize: 14,
              height: 1.4,
              color: AppColors.ink,
            ),
          ),
        ),
        DatasetStatus.failed => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ErrorBanner(
              d.errorMessage == null
                  ? 'No se pudo procesar el archivo.'
                  : translateBackendMessage(d.errorMessage!),
            ),
            const SizedBox(height: 12),
            const Text(
              'El archivo fue rechazado. Revisa su estructura (columnas y celdas) y súbelo de nuevo.',
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: AppColors.muted,
              ),
            ),
          ],
        ),
        DatasetStatus.awaitingConfirmation => _MergeConfirmation(
          dataset: d,
          confirming: _confirming,
          onContinue: _confirm,
          onCancel: () =>
              context.canPop() ? context.pop() : context.go('/datasets'),
        ),
        DatasetStatus.ready => _Summary(dataset: d),
      },
    ];
  }
}

/// Status, upload date and, once ready, what the file contains.
class _Hero extends StatelessWidget {
  const _Hero({required this.dataset});

  final Dataset dataset;

  @override
  Widget build(BuildContext context) {
    final d = dataset;
    final s = d.status == DatasetStatus.ready ? d.summary : null;
    final pill = datasetPill(d.status);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const ExcelIcon(size: 56),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    pill,
                    const SizedBox(height: 6),
                    Text(
                      'Subido el ${formatDateTime(d.createdAt)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (s != null) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Divider(height: 1, color: Color(0xFFF0F1F4)),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _Field(
                    'Secciones',
                    s.sections.entries
                        .map((e) => '${e.key} · ${e.value}')
                        .join(' / '),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: _Field('Celdas', '${s.cellCount}')),
              ],
            ),
            if (s.dateFrom != null && s.dateTo != null) ...[
              const SizedBox(height: 12),
              _Field(
                'Periodo',
                // Non-breaking spaces: a long range wraps only after the dash.
                '${formatShortDate(s.dateFrom!)} – ${formatShortDate(s.dateTo!)}'
                    .replaceAll(' ', ' ')
                    .replaceAll(' – ', ' – '),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
      ],
    );
  }
}

/// What the cleaning did with the records of the uploaded file, as a timeline.
/// Zeros are shown on purpose: they confirm the cleaning ran.
class _Summary extends StatelessWidget {
  const _Summary({required this.dataset});

  final Dataset dataset;

  @override
  Widget build(BuildContext context) {
    final s = dataset.summary;
    if (s == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (!s.hasCleaning) return const SizedBox.shrink();
    final rows = [
      (Icons.checklist_rtl, 'Registros leídos', s.rowsRead),
      (Icons.swap_vert, 'Registros ordenados', s.rowsSorted),
      (Icons.filter_none, 'Duplicados eliminados', s.duplicatesRemoved),
      (Icons.delete_outline, 'Descartados (sin fecha)', s.discardedRows),
    ].where((r) => r.$3 != null).toList();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.auto_awesome_outlined,
                size: 20,
                color: AppColors.blue,
              ),
              SizedBox(width: 8),
              Text(
                'Resumen de limpieza',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
          if (dataset.baseDatasetId != null)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.info_outline,
                      size: 15,
                      color: AppColors.muted,
                    ),
                  ),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Los conteos son solo del archivo subido',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          for (var i = 0; i < rows.length; i++)
            _Step(
              icon: rows[i].$1,
              label: rows[i].$2,
              value: rows[i].$3!,
              first: i == 0,
              last: i == rows.length - 1,
            ),
        ],
      ),
    );
  }
}

/// One timeline row: a dot (blue when the step touched records) joined to its
/// neighbours by a dashed line.
class _Step extends StatelessWidget {
  const _Step({
    required this.icon,
    required this.label,
    required this.value,
    required this.first,
    required this.last,
  });

  final IconData icon;
  final String label;
  final int value;
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 14,
            child: Column(
              children: [
                Expanded(child: first ? const SizedBox() : const _Dashes()),
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: value > 0 ? AppColors.blue : AppColors.border,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(child: last ? const SizedBox() : const _Dashes()),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: AppColors.muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '$value',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dashes extends StatelessWidget {
  const _Dashes();

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _DashesPainter(), size: Size.infinite);
}

class _DashesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1.5;
    final x = size.width / 2;
    for (var y = 2.0; y + 3 <= size.height - 2; y += 6) {
      canvas.drawLine(Offset(x, y), Offset(x, y + 3), paint);
    }
  }

  @override
  bool shouldRepaint(_DashesPainter oldDelegate) => false;
}

/// "El archivo cubre del … al … y complementa uno del … al …" with Continuar / Cancelar.
class _MergeConfirmation extends StatelessWidget {
  const _MergeConfirmation({
    required this.dataset,
    required this.confirming,
    required this.onContinue,
    required this.onCancel,
  });

  final Dataset dataset;
  final bool confirming;
  final VoidCallback onContinue;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final m = dataset.merge;
    if (m == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    const style = TextStyle(fontSize: 14, height: 1.4, color: AppColors.ink);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'El archivo cubre del ${formatShortDate(m.newFrom)} al ${formatShortDate(m.newTo)} '
                'y complementa uno del ${formatShortDate(m.baseFrom)} al ${formatShortDate(m.baseTo)}. '
                'El resultado cubrirá ${m.mergedDays} días.',
                style: style,
              ),
              if (m.gapDays > 0) ...[
                const SizedBox(height: 10),
                Text(
                  'Hay ${m.gapDays} días sin registros entre ambos archivos.',
                  style: style,
                ),
              ],
              if (m.overlapDays > 0) ...[
                const SizedBox(height: 10),
                Text(
                  'Los ${m.overlapDays} días que se solapan se toman del archivo nuevo.',
                  style: style.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        PrimaryButton(
          label: 'Continuar',
          loading: confirming,
          onPressed: onContinue,
        ),
        const SizedBox(height: 10),
        SecondaryButton(
          label: 'Cancelar',
          onPressed: confirming ? null : onCancel,
        ),
      ],
    );
  }
}
