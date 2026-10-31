import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/format.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_header.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/auth_visuals.dart';
import '../../../core/widgets/load_error.dart';
import '../../../core/widgets/page_header.dart';
import '../data/evaluation.dart';
import '../data/forecast.dart';
import '../data/forecasting_repository.dart';
import 'error_series_chart.dart';
import 'forecast_widgets.dart';
import 'model_controller.dart';

/// Writes [rows] to an Excel file called [fileName] and offers it to the user.
typedef EvaluationExporter = Future<void> Function(
  String fileName,
  List<EvaluationItem> rows,
);

/// Tab "Modelo": how far the forecast is from what was measured, in a sentence,
/// and a table by cell; plus the way into the files.
class ModelScreen extends StatelessWidget {
  /// The Excel button is shown only when an [export] is given.
  const ModelScreen({super.key, this.export});

  final EvaluationExporter? export;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) =>
          ModelController(context.read<ForecastingRepository>())..load(),
      child: _ModelView(export: export),
    );
  }
}

class _ModelView extends StatefulWidget {
  const _ModelView({this.export});

  final EvaluationExporter? export;

  @override
  State<_ModelView> createState() => _ModelViewState();
}

class _ModelViewState extends State<_ModelView> {
  bool _exporting = false;

  Future<void> _pickDate(ModelController c) async {
    final range = c.selectableRange;
    if (range == null) return;
    final picked = await showDatePicker(
      context: context,
      helpText: 'Fecha de la comparación',
      initialDate: c.date != null && c.isSelectable(c.date!)
          ? c.date
          : range.last,
      firstDate: range.first,
      lastDate: range.last,
      selectableDayPredicate: (day) =>
          c.isSelectable(DateTime(day.year, day.month, day.day)),
    );
    if (picked != null) {
      await c.setDate(DateTime(picked.year, picked.month, picked.day));
    }
  }

  Future<void> _export(ModelController c) async {
    final messenger = ScaffoldMessenger.of(context);
    final day = c.evaluation!.date!;
    setState(() => _exporting = true);
    try {
      await widget.export!(
        'comparacion_pronostico_${apiDate(day)}.xlsx',
        await c.allRows(),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ModelController>();

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: RefreshIndicator(
        color: AppColors.blue,
        onRefresh: c.load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
          children: [
            PageHeader(
              eyebrow: 'Validación del pronóstico',
              title: 'Precisión del modelo',
              onBack: () =>
                  context.canPop() ? context.pop() : context.go('/settings'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (c.offline && c.savedAt != null) ...[
                    OfflineBanner(c.savedAt!),
                    const SizedBox(height: 14),
                  ],
                  if (c.retraining) ...[
                    const RetrainingBanner(),
                    const SizedBox(height: 14),
                  ],
                  ..._accuracy(c),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "los últimos 60 días", from the validation range the API reports.
  String _span(ModelController c) {
    final r = c.availableRange;
    if (r == null) return 'los días de validación';
    return 'los últimos ${r.to.difference(r.from).inDays + 1} días';
  }

  List<Widget> _accuracy(ModelController c) {
    if (c.loading && c.metrics == null) {
      return const [
        Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (c.error != null) {
      return [
        SizedBox(
          height: 320,
          child: LoadErrorView(message: c.error!, onRetry: c.load),
        ),
      ];
    }
    if (c.noOfflineData) {
      return const [
        SizedBox(
          height: 320,
          child: EmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'No hay datos de precisión guardados',
            message: 'Conéctate para consultarlos; quedarán guardados en este dispositivo.',
          ),
        ),
      ];
    }
    if (c.noModel) {
      return const [SizedBox(height: 320, child: NoModelState())];
    }
    final m = c.metrics;
    return [
      const Align(
        alignment: Alignment.centerLeft,
        child: StatusPill(
          'Modelo disponible',
          background: Color(0xFFE8F8EE),
          color: AppColors.success,
        ),
      ),
      const SizedBox(height: 14),
      _Summary(m),
      const SizedBox(height: 24),
      const SectionTitle('Pronóstico frente a lo medido'),
      const SizedBox(height: 8),
      Text(
        'Comparación de ${_span(c)}: lo que el modelo pronosticó frente a '
        'lo que realmente se midió. Son días que el modelo no usó para entrenar.',
        style: const TextStyle(
          fontSize: 13,
          height: 1.4,
          color: AppColors.muted,
        ),
      ),
      const SizedBox(height: 12),
      _Comparison(
        controller: c,
        onPickDate: () => _pickDate(c),
        onExport: widget.export == null ? null : () => _export(c),
        exporting: _exporting,
      ),
    ];
  }
}

/// "Error del pronóstico": the mean error in volts, big, with what it means.
class _Summary extends StatelessWidget {
  const _Summary(this.metrics);

  final ModelMetrics? metrics;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    if (m == null || m.mape == null || m.mae == null) {
      return const SizedBox(
        height: 220,
        child: EmptyState(
          icon: Icons.analytics_outlined,
          title: 'Aún no hay métricas de precisión',
          message: 'Aparecerán cuando el modelo tenga días de validación.',
        ),
      );
    }
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Error del pronóstico',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              style: const TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.w800,
                color: AppColors.blue,
              ),
              children: [
                TextSpan(text: decimal(m.mae!, 3)),
                const TextSpan(
                  text: ' V',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Diferencia promedio entre el voltaje real y el pronosticado',
            style: TextStyle(fontSize: 14, height: 1.4, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

/// The chart of the mean error per day, in the card above the date button.
class _SeriesView extends StatelessWidget {
  const _SeriesView({required this.controller});

  final ModelController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final s = c.series;
    const muted = TextStyle(fontSize: 13, color: AppColors.muted);
    final Widget body;
    if (s == null) {
      if (c.seriesError == null) return const SizedBox.shrink();
      body = Row(
        children: [
          Expanded(child: Text(c.seriesError!, style: muted)),
          TextButton(onPressed: c.retrySeries, child: const Text('Reintentar')),
        ],
      );
    } else if (s.items.isEmpty) {
      body = Text(s.message ?? 'Aún no hay datos para graficar.', style: muted);
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Error medio por día',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const Text('Toca un día para ver sus celdas', style: muted),
          const SizedBox(height: 10),
          ErrorSeriesChart(
            points: s.items,
            selected: c.date,
            isSelectable: c.isSelectable,
            onSelect: c.setDate,
          ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: AppCard(child: body),
    );
  }
}

/// Date selector, the summary lines, the table and the Excel button.
class _Comparison extends StatelessWidget {
  const _Comparison({
    required this.controller,
    required this.onPickDate,
    required this.onExport,
    required this.exporting,
  });

  final ModelController controller;
  final VoidCallback onPickDate;
  final VoidCallback? onExport;
  final bool exporting;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final e = c.evaluation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SeriesView(controller: c),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: c.selectableRange == null ? null : onPickDate,
            icon: const Icon(Icons.calendar_today_outlined, size: 18),
            label: Text(
              c.date == null
                  ? 'Elegir fecha'
                  : 'Fecha: ${formatShortDate(c.date!)}',
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (c.evaluationError != null) ...[
          ErrorBanner(c.evaluationError!),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: c.retryEvaluation,
              child: const Text('Reintentar'),
            ),
          ),
        ],
        if (e == null && c.evaluating)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (e == null)
          SizedBox(
            height: 220,
            child: EmptyState(
              icon: c.offline
                  ? Icons.cloud_off_outlined
                  : Icons.compare_arrows_outlined,
              title: c.offline
                  ? 'No hay comparación guardada para consulta sin conexión'
                  : 'No hay datos de comparación para esta fecha',
            ),
          )
        else if (e.items.isEmpty)
          const SizedBox(
            height: 220,
            child: EmptyState(
              icon: Icons.compare_arrows_outlined,
              title: 'No hay datos de comparación para esta fecha',
            ),
          )
        else ...[
          Text(
            'Mostrando ${e.items.length} de ${e.totalCells} celdas',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          if (e.meanErrorPct != null)
            Text(
              'Error promedio de ese día: ${decimal(e.meanErrorPct!, 2)} %',
              style: const TextStyle(fontSize: 14, color: AppColors.ink),
            ),
          const SizedBox(height: 10),
          if (c.evaluating) const LinearProgressIndicator(minHeight: 3),
          // The previous cards stay (dimmed) while the next day loads.
          Opacity(
            opacity: c.evaluating ? 0.5 : 1,
            child: Column(
              children: [
                for (final i in e.items)
                  _CellCard(item: i, mean: e.meanErrorPct),
              ],
            ),
          ),
        ],
        if (onExport != null) ...[
          const SizedBox(height: 16),
          SecondaryButton(
            label: exporting
                ? 'Preparando archivo…'
                : 'Descargar todas las celdas (Excel)',
            onPressed: c.canExport && !exporting ? onExport : null,
          ),
          if (c.offline && !c.canExport)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Sin conexión solo se puede descargar un día que se guardó completo con conexión.',
                style: TextStyle(fontSize: 12.5, color: AppColors.muted),
              ),
            ),
        ],
      ],
    );
  }
}

/// How far above the day's mean error a cell must be to be flagged: past
/// [elevated] times the mean it is amber, past [high] times it is red. The
/// API gives no limit of its own, so the day's mean is the only reference.
const severityBands = (elevated: 1.0, high: 2.0);

enum Severity {
  normal(AppColors.border, AppColors.ink),
  elevated(AppColors.amber, AppColors.amber),
  high(AppColors.error, AppColors.error);

  const Severity(this.bar, this.text);

  final Color bar, text;
}

Severity severityOf(double errorPct, double? mean) {
  if (mean == null || mean <= 0) return Severity.normal;
  final ratio = errorPct / mean;
  if (ratio >= severityBands.high) return Severity.high;
  if (ratio > severityBands.elevated) return Severity.elevated;
  return Severity.normal;
}

/// One cell of the day: name and error up front, the three volts below.
class _CellCard extends StatelessWidget {
  const _CellCard({required this.item, required this.mean});

  final EvaluationItem item;
  final double? mean;

  @override
  Widget build(BuildContext context) {
    final i = item;
    final severity = severityOf(i.errorPct, mean);
    final note = switch (severity) {
      Severity.normal => '',
      Severity.elevated => ', por encima del promedio',
      Severity.high => ', muy por encima del promedio',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        label:
            'Celda ${i.cellName}: error ${decimal(i.errorPct, 2)} por ciento$note. '
            'Real ${decimal(i.real, 3)} voltios, pronosticado ${decimal(i.predicted, 3)} voltios, '
            'diferencia ${decimal(i.errorV, 3)} voltios',
        excludeSemantics: true,
        child: ClipRRect(
          borderRadius: AppRadius.medium,
          child: ColoredBox(
            color: Colors.white,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 5, child: ColoredBox(color: severity.bar)),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    i.cellName,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.ink,
                                    ),
                                  ),
                                ),
                              ),
                              if (severity != Severity.normal) ...[
                                Icon(
                                  Icons.warning_amber_rounded,
                                  size: 18,
                                  color: severity.text,
                                ),
                                const SizedBox(width: 4),
                              ],
                              Text(
                                '${decimal(i.errorPct, 2)} %',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: severity.text,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              _Stat('V. real', decimal(i.real, 3)),
                              _Stat('Pronóstico', decimal(i.predicted, 3)),
                              _Stat('Diferencia (V)', decimal(i.errorV, 3)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label, value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
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
