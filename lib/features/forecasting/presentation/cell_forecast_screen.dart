import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/format.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_header.dart';
import '../../../core/widgets/load_error.dart';
import '../../../core/widgets/screen_header.dart';
import '../data/forecast.dart';
import '../data/forecasting_repository.dart';
import 'forecast_chart.dart';
import 'forecast_export.dart';
import 'forecast_widgets.dart';

/// The whole horizon (up to 180 days) of one cell. [from]/[to] are the range
/// the forecasts list reported as available; without them they are asked first.
class CellForecastScreen extends StatefulWidget {
  const CellForecastScreen({
    super.key,
    required this.cellId,
    this.name,
    this.from,
    this.to,
    this.saveFile = shareForecastFile,
    this.buildPng = forecastPng,
  });

  final int cellId;
  final String? name;
  final DateTime? from;
  final DateTime? to;

  /// Where a downloaded file goes; the share sheet unless a test replaces it.
  final ForecastFileSaver saveFile;

  /// Draws the PNG; replaced in tests, where images cannot be encoded.
  final ForecastPngBuilder buildPng;

  @override
  State<CellForecastScreen> createState() => _CellForecastScreenState();
}

class _CellForecastScreenState extends State<CellForecastScreen> {
  ForecastResult? _result;
  bool _loading = true;
  bool _noOfflineData = false;
  String? _error;
  bool _exporting = false;
  bool _allRanges = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repository = context.read<ForecastingRepository>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var from = widget.from, to = widget.to;
      if (from == null || to == null) {
        final first = await repository.forecasts(cellId: widget.cellId);
        from = first.availableFrom;
        to = first.availableTo;
      }
      final result = await repository.forecasts(
        from: from,
        to: to,
        cellId: widget.cellId,
      );
      _result = result;
      _noOfflineData = false;
    } on ApiException catch (e) {
      if (!e.isOffline) {
        _error = e.message;
      } else {
        _result = await repository.cache.cell(widget.cellId);
        _noOfflineData = _result == null;
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _download(_Format format) async {
    final items = _result!.items;
    final name = widget.name ?? '${widget.cellId}';
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _exporting = true);
    try {
      switch (format) {
        case _Format.png:
          await widget.saveFile(
            forecastFileName(name, items, 'png'),
            await widget.buildPng(cellName: name, items: items),
            pngMime,
          );
        case _Format.xlsx:
          await widget.saveFile(
            forecastFileName(name, items, 'xlsx'),
            forecastXlsx(items),
            xlsxMime,
          );
      }
    } on Object {
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo generar el archivo.')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final title = widget.name == null ? 'Celda' : 'Celda ${widget.name}';
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: title,
              subtitle: result == null || result.items.isEmpty
                  ? 'Pronóstico de voltaje'
                  : 'Pronóstico a ${result.items.length} días',
              onBack: () =>
                  context.canPop() ? context.pop() : context.go('/forecasts'),
            ),
            Expanded(child: _body(result)),
          ],
        ),
      ),
    );
  }

  Widget _body(ForecastResult? result) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_noOfflineData) return const NoOfflineDataState();
    if (_error != null) return LoadErrorView(message: _error!, onRetry: _load);
    if (result == null || result.model == null) return const NoModelState();
    if (result.items.isEmpty) {
      return const EmptyState(
        icon: Icons.show_chart,
        title: 'Sin pronósticos para esta celda',
      );
    }

    final items = result.items;
    final over = items.where((i) => i.exceeds).length;
    final highest = items.reduce((a, b) => a.voltage >= b.voltage ? a : b);
    final lowest = items.reduce((a, b) => a.voltage <= b.voltage ? a : b);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (result.retraining) ...[
          const RetrainingBanner(),
          const SizedBox(height: 12),
        ],
        if (result.savedAt != null) ...[
          OfflineBanner(result.savedAt!),
          const SizedBox(height: 12),
        ],
        AppCard(child: ForecastChart(items: items)),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: MenuAnchor(
            menuChildren: [
              MenuItemButton(
                leadingIcon: const Icon(Icons.image_outlined),
                onPressed: () => _download(_Format.png),
                child: const Text('Imagen del gráfico (PNG)'),
              ),
              MenuItemButton(
                leadingIcon: const Icon(Icons.table_chart_outlined),
                onPressed: () => _download(_Format.xlsx),
                child: const Text('Datos (Excel)'),
              ),
            ],
            builder: (context, menu, _) => OutlinedButton.icon(
              onPressed: _exporting
                  ? null
                  : () => menu.isOpen ? menu.close() : menu.open(),
              icon: const Icon(Icons.download_outlined, size: 18),
              label: Text(_exporting ? 'Preparando…' : 'Descargar'),
            ),
          ),
        ),
        const SizedBox(height: 10),
        AppCard(
          child: Column(
            children: [
              _Fact('Voltaje máximo', volts(highest.voltage)),
              _Fact('Voltaje mínimo', volts(lowest.voltage)),
              _Fact(
                'Días que superan el límite',
                '$over',
                color: over > 0 ? AppColors.error : AppColors.ink,
                icon: over > 0 ? Icons.warning_amber_rounded : null,
              ),
            ],
          ),
        ),
        if (over > 0) ...[
          const SizedBox(height: 12),
          _OverRanges(
            ranges: exceedRanges(items),
            all: _allRanges,
            onToggle: () => setState(() => _allRanges = !_allRanges),
          ),
        ],
      ],
    );
  }
}

enum _Format { png, xlsx }

/// The dates over the limit, as runs of consecutive days.
class _OverRanges extends StatelessWidget {
  const _OverRanges({
    required this.ranges,
    required this.all,
    required this.onToggle,
  });

  final List<ExceedRange> ranges;
  final bool all;
  final VoidCallback onToggle;

  /// Runs shown before "Ver todos".
  static const _shown = 5;

  @override
  Widget build(BuildContext context) {
    final visible = all ? ranges : ranges.take(_shown).toList();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Fechas que superan el límite',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          for (final r in visible)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: AppColors.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      r.days == 1
                          ? formatShortDate(r.from)
                          : '${formatShortDate(r.from)} – ${formatShortDate(r.to)}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  Text(
                    r.days == 1 ? '1 día' : '${r.days} días',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.error,
                    ),
                  ),
                ],
              ),
            ),
          if (ranges.length > _shown)
            TextButton(
              onPressed: onToggle,
              child: Text(
                all ? 'Ver menos' : 'Ver los ${ranges.length} tramos',
              ),
            ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value, {this.color = AppColors.ink, this.icon});

  final String label;
  final String value;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, color: AppColors.muted),
            ),
          ),
          if (icon != null) Icon(icon, size: 18, color: color),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
