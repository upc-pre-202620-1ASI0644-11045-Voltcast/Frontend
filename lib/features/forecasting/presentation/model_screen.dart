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
import '../../../core/widgets/screen_header.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/evaluation.dart';
import '../data/forecast.dart';
import '../data/forecasting_repository.dart';
import 'forecast_widgets.dart';
import 'model_controller.dart';

/// Writes [rows] to an Excel file called [fileName] and offers it to the user.
typedef EvaluationExporter =
    Future<void> Function(String fileName, List<EvaluationItem> rows);

/// Tab "Modelo": how far the forecast is from what was measured, in a sentence,
/// a collapsed technical detail and a table by cell; plus the way into files and
/// (supervisors) the voltage limit.
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
    final auth = Provider.of<AuthController?>(context, listen: false);
    final model = c.metrics?.model;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: RefreshIndicator(
        color: AppColors.blue,
        onRefresh: c.load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [
            BrandHeader(
              eyebrow: model == null
                  ? 'Precisión del modelo'
                  : '${model.name} · versión ${model.version}',
              title: 'Modelo',
              onLogout: auth?.logout,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 110),
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
                  const SizedBox(height: 24),
                  const SectionTitle('Gestión'),
                  const SizedBox(height: 12),
                  _ManageTile(
                    icon: Icons.table_chart_outlined,
                    title: 'Archivos históricos',
                    subtitle: 'Sube y revisa los datos de voltaje',
                    onTap: () => context.push('/datasets'),
                  ),
                  if (auth?.user?.isAdmin == true)
                    _ManageTile(
                      icon: Icons.bolt,
                      title: 'Límite de voltaje',
                      subtitle: 'Voltaje máximo permitido',
                      onTap: () => context.push('/limit'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
            message:
                'Conéctate para consultarlos; quedarán guardados en este dispositivo.',
          ),
        ),
      ];
    }
    if (c.noModel) {
      return const [SizedBox(height: 320, child: NoModelState())];
    }
    final m = c.metrics;
    return [
      const SectionTitle('Precisión del modelo'),
      const SizedBox(height: 12),
      _Summary(m),
      if (m?.mape != null) ...[
        const SizedBox(height: 10),
        _TechnicalDetail(m!),
      ],
      const SizedBox(height: 24),
      const SectionTitle('Pronóstico frente a lo medido'),
      const SizedBox(height: 8),
      const Text(
        'Comparación de los últimos 60 días: lo que el modelo pronosticó frente a '
        'lo que realmente se midió. Son días que el modelo no usó para entrenar.',
        style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.muted),
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

/// "En promedio, el pronóstico se desvía 0,77 % (0,024 V)".
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
    const base = TextStyle(fontSize: 18, height: 1.35, color: AppColors.ink);
    const strong = TextStyle(fontWeight: FontWeight.w800);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              style: base,
              children: [
                const TextSpan(text: 'En promedio, el pronóstico se desvía '),
                TextSpan(text: '${decimal(m.mape!, 2)} %', style: strong),
                const TextSpan(text: ' ('),
                TextSpan(text: '${decimal(m.mae!, 3)} V', style: strong),
                const TextSpan(text: ')'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Calculado sobre los últimos días de los datos, que el modelo no usó para entrenar.',
            style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

/// The five figures that used to be the screen, collapsed. ExpansionTile is a
/// focusable list tile that announces whether it is expanded.
class _TechnicalDetail extends StatelessWidget {
  const _TechnicalDetail(this.m);

  final ModelMetrics m;

  @override
  Widget build(BuildContext context) {
    String fmt(double? v, int digits) => v == null ? '—' : decimal(v, digits);
    return Material(
      color: Colors.white,
      borderRadius: AppRadius.large,
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: const Text(
            'Ver detalle técnico',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TechRow(
              'MSE',
              '${fmt(m.mse, 4)} V²',
              'Promedio de los errores al cuadrado. Castiga más los errores grandes.',
            ),
            _TechRow(
              'RMSE',
              '${fmt(m.rmse, 3)} V',
              'Raíz del MSE: un error típico, en voltios.',
            ),
            _TechRow(
              'MAE',
              '${fmt(m.mae, 3)} V',
              'Promedio del error sin signo, en voltios.',
            ),
            _TechRow(
              'MAPE',
              '${fmt(m.mape, 2)} %',
              'Error promedio como porcentaje del voltaje real.',
            ),
            _TechRow(
              'R²',
              fmt(m.r2, 3),
              'Qué parte de la variación del voltaje explica el modelo; 1 es perfecto.',
            ),
          ],
        ),
      ),
    );
  }
}

class _TechRow extends StatelessWidget {
  const _TechRow(this.name, this.value, this.help);

  final String name;
  final String value;
  final String help;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$name: $value. $help',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(name, style: AppTheme.label),
                const Spacer(),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
            Text(
              help,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Date and order selectors, the summary lines, the table and the Excel button.
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
        const SizedBox(height: 10),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'worst', label: Text('Mayor error')),
            ButtonSegment(value: 'best', label: Text('Menor error')),
          ],
          selected: {c.order},
          onSelectionChanged: (s) => c.setOrder(s.first),
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
          // The previous table stays (dimmed) while the next one loads.
          Opacity(
            opacity: c.evaluating ? 0.5 : 1,
            child: _Table(result: e, order: c.order),
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

// Column weights of the table; the same ones for the header and every row so
// it fits a phone without sideways scrolling.
const _flex = [2, 3, 3, 3, 3];

Widget _cell(int i, Widget child, {Alignment at = Alignment.centerRight}) =>
    Expanded(
      flex: _flex[i],
      child: Align(alignment: at, child: child),
    );

class _Table extends StatelessWidget {
  const _Table({required this.result, required this.order});

  final EvaluationResult result;
  final String order;

  @override
  Widget build(BuildContext context) {
    final mean = result.meanErrorPct;
    const head = TextStyle(
      fontSize: 11.5,
      height: 1.2,
      fontWeight: FontWeight.w700,
      color: AppColors.muted,
    );
    Widget title(String text) => Text(text, style: head, textAlign: TextAlign.right);

    return Material(
      color: Colors.white,
      borderRadius: AppRadius.large,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          children: [
            Semantics(
              header: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _cell(0, const Text('Celda', style: head), at: Alignment.centerLeft),
                  _cell(1, title('Voltaje real (V)')),
                  _cell(2, title('Voltaje pronosticado (V)')),
                  _cell(3, title('Diferencia (V)')),
                  _cell(
                    4,
                    Semantics(
                      label: order == 'worst'
                          ? 'Error (%), ordenado de mayor a menor'
                          : 'Error (%), ordenado de menor a mayor',
                      excludeSemantics: true,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            order == 'worst' ? Icons.arrow_downward : Icons.arrow_upward,
                            size: 12,
                            color: AppColors.muted,
                          ),
                          const Flexible(
                            child: Text('Error (%)', style: head, textAlign: TextAlign.right),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 16),
            for (final i in result.items) _Row(item: i, mean: mean),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.item, required this.mean});

  final EvaluationItem item;
  final double? mean;

  @override
  Widget build(BuildContext context) {
    final i = item;
    // A day's mean is the only reference the API gives; above it is "alto".
    final high = mean != null && i.errorPct > mean!;
    const body = TextStyle(fontSize: 13, color: AppColors.ink);
    return Semantics(
      label:
          'Celda ${i.cellName}: real ${decimal(i.real, 3)} voltios, '
          'pronosticado ${decimal(i.predicted, 3)} voltios, '
          'diferencia ${decimal(i.errorV, 3)} voltios, '
          'error ${decimal(i.errorPct, 2)} por ciento${high ? ', error alto' : ''}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            _cell(
              0,
              Text(i.cellName, style: body.copyWith(fontWeight: FontWeight.w700)),
              at: Alignment.centerLeft,
            ),
            _cell(1, Text(decimal(i.real, 3), style: body)),
            _cell(2, Text(decimal(i.predicted, 3), style: body)),
            _cell(3, Text(decimal(i.errorV, 3), style: body)),
            _cell(
              4,
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (high) ...[
                    const Icon(Icons.warning_amber_rounded, size: 15, color: AppColors.error),
                    const SizedBox(width: 2),
                  ],
                  Text(
                    decimal(i.errorPct, 2),
                    style: body.copyWith(
                      fontWeight: FontWeight.w800,
                      color: high ? AppColors.error : AppColors.ink,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManageTile extends StatelessWidget {
  const _ManageTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: AppRadius.large,
        child: InkWell(
          borderRadius: AppRadius.large,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.blueSoft,
                  child: Icon(icon, color: AppColors.blue),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(fontSize: 13, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
