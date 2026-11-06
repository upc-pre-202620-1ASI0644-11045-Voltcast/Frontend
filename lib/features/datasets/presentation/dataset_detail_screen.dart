import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/dialogs.dart';
import '../../../core/format.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/backend_messages.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_header.dart';
import '../../../core/widgets/auth_visuals.dart';
import '../../../core/widgets/load_error.dart';
import '../../../core/widgets/page_header.dart';
import '../../forecasting/data/forecasting_repository.dart';
import '../data/dataset.dart';
import 'datasets_controller.dart';
import 'datasets_screen.dart';

/// One file: its processing state and, once ready, what it contains and the
/// button to train the model with it.
class DatasetDetailScreen extends StatefulWidget {
  const DatasetDetailScreen({super.key, required this.id});

  final int id;

  @override
  State<DatasetDetailScreen> createState() => _DatasetDetailScreenState();
}

class _DatasetDetailScreenState extends State<DatasetDetailScreen> {
  bool _starting = false;
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    // The list has no summary; the detail does.
    final datasets = context.read<DatasetsController>();
    Future.microtask(() => datasets.refresh(widget.id));
  }

  Future<void> _train() async {
    final repository = context.read<ForecastingRepository>();
    setState(() => _starting = true);
    try {
      // A 400 (one already running, file not ready) is explained in a SnackBar.
      await runAction(
        context,
        () => repository.startTraining(widget.id),
        'Entrenamiento iniciado.',
      );
    } finally {
      if (mounted) setState(() => _starting = false);
    }
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
      Row(
        children: [
          const ExcelIcon(size: 56),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                datasetPill(d.status),
                const SizedBox(height: 6),
                Text(
                  'Subido el ${formatDateTime(d.createdAt)}',
                  style: const TextStyle(fontSize: 13, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
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
        DatasetStatus.ready => _Summary(
          dataset: d,
          starting: _starting,
          onTrain: _train,
        ),
      },
    ];
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.dataset,
    required this.starting,
    required this.onTrain,
  });

  final Dataset dataset;
  final bool starting;
  final VoidCallback onTrain;

  @override
  Widget build(BuildContext context) {
    final s = dataset.summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (s == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          AppCard(
            child: Column(
              children: [
                _Row(
                  'Secciones',
                  s.sections.entries
                      .map((e) => '${e.key} · ${e.value}')
                      .join(' / '),
                ),
                _Row('Celdas', '${s.cellCount}'),
                if (s.dateFrom != null && s.dateTo != null)
                  _Row(
                    'Periodo',
                    '${formatShortDate(s.dateFrom!)} – ${formatShortDate(s.dateTo!)}',
                  ),
                _Row('Días', '${s.days}'),
                _Row('Celdas nuevas', '${s.newCells}', last: true),
              ],
            ),
          ),
        if (s != null && s.hasCleaning) ...[
          const SizedBox(height: 16),
          _CleaningSummary(summary: s, merged: dataset.baseDatasetId != null),
        ],
        const SizedBox(height: 16),
        const Text(
          'El entrenamiento arranca solo cuando el archivo queda listo. '
          'Usa el botón solo si necesitas reintentarlo.',
          style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.muted),
        ),
        const SizedBox(height: 12),
        SecondaryButton(
          label: starting ? 'Iniciando…' : 'Reintentar entrenamiento',
          onPressed: starting ? null : onTrain,
        ),
      ],
    );
  }
}

/// What the cleaning did with the records of the uploaded file. Zeros are shown
/// on purpose: they confirm the cleaning ran.
class _CleaningSummary extends StatelessWidget {
  const _CleaningSummary({required this.summary, required this.merged});

  final DatasetSummary summary;

  /// The file complements another: the counts are only of the uploaded one.
  final bool merged;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final rows = <(String, int?)>[
      ('Registros leídos', s.rowsRead),
      ('Registros ordenados', s.rowsSorted),
      ('Duplicados eliminados', s.duplicatesRemoved),
      ('Datos descartados (filas sin fecha)', s.discardedRows),
      ('Columnas descartadas', s.discardedColumns),
    ].where((r) => r.$2 != null).toList();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Resumen de limpieza',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          if (merged)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Los conteos son solo del archivo que subiste, no del conjunto unido.',
                style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.muted),
              ),
            ),
          const SizedBox(height: 4),
          for (var i = 0; i < rows.length; i++)
            _Row(rows[i].$1, '${rows[i].$2}', last: i == rows.length - 1),
        ],
      ),
    );
  }
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

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.last = false});

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: Color(0xFFF0F1F4))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, color: AppColors.muted),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
