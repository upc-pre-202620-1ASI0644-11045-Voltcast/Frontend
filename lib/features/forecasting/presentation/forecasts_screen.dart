import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/load_error.dart';
import '../../../core/widgets/screen_header.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/forecast.dart';
import '../data/forecasting_repository.dart';
import 'forecast_widgets.dart';
import 'forecasts_controller.dart';

/// Tab "Pronósticos": the voltage forecast of every cell for one day.
class ForecastsScreen extends StatelessWidget {
  const ForecastsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) =>
          ForecastsController(context.read<ForecastingRepository>())..load(),
      child: const _ForecastsView(),
    );
  }
}

class _ForecastsView extends StatelessWidget {
  const _ForecastsView();

  static const _quickDays = [
    ('Hoy', 0),
    ('Mañana', 1),
    ('En 3 días', 3),
    ('En 7 días', 7),
  ];

  Future<void> _pickDate(BuildContext context, ForecastsController c) async {
    final range = c.selectableRange;
    if (range == null) return;
    final picked = await showDatePicker(
      context: context,
      helpText: 'Fecha del pronóstico',
      initialDate: c.date != null && c.isSelectable(c.date!)
          ? c.date
          : range.first,
      firstDate: range.first,
      lastDate: range.last,
      selectableDayPredicate: (day) =>
          c.isSelectable(DateTime(day.year, day.month, day.day)),
    );
    if (picked != null) {
      await c.setDate(DateTime(picked.year, picked.month, picked.day));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ForecastsController>();
    // Absent in screen tests that mount this tab alone.
    final auth = Provider.of<AuthController?>(context, listen: false);
    final items = c.items;
    final exceeding = items.where((i) => i.exceeds).length;

    final header = BrandHeader(
      eyebrow: c.date == null
          ? 'Voltaje estimado'
          : 'Voltaje estimado · ${formatShortDate(c.date!)}',
      title: 'Pronósticos',
      onLogout: auth?.logout,
      bottom: c.result == null || c.noModel
          ? null
          : StatRow(
              tiles: [
                StatTile(label: 'Celdas', value: items.length),
                StatTile(
                  label: 'Superan el límite',
                  value: exceeding,
                  color: AppColors.error,
                ),
                StatTile(
                  label: 'Sin límite',
                  value: items.where((i) => i.maxVoltage == null).length,
                ),
              ],
            ),
    );

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: RefreshIndicator(
        color: AppColors.blue,
        onRefresh: c.load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: header),
            ..._content(context, c),
            const SliverToBoxAdapter(child: SizedBox(height: 110)),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context, ForecastsController c) {
    final result = c.result;
    if (result == null && c.loading) {
      return [
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (c.noOfflineData) {
      return [
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        SliverToBoxAdapter(
          child: _Controls(
            controller: c,
            onPick: () => _pickDate(context, c),
            quickDays: _quickDays,
          ),
        ),
        const SliverFillRemaining(
          hasScrollBody: false,
          child: NoOfflineDataState(),
        ),
      ];
    }
    if (result == null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: LoadErrorView(
            message: c.error ?? 'No se pudo cargar.',
            onRetry: c.load,
          ),
        ),
      ];
    }
    if (c.noModel) {
      return [
        const SliverFillRemaining(hasScrollBody: false, child: NoModelState()),
      ];
    }

    final visible = c.visible;
    final rows = _rows(visible);
    return [
      SliverToBoxAdapter(
        child: _Controls(
          controller: c,
          onPick: () => _pickDate(context, c),
          quickDays: _quickDays,
        ),
      ),
      if (c.loading)
        const SliverToBoxAdapter(child: LinearProgressIndicator(minHeight: 3)),
      if (visible.isEmpty)
        const SliverToBoxAdapter(
          child: EmptyState(
            icon: Icons.search_off,
            title: 'Ninguna celda coincide con la búsqueda',
          ),
        )
      else
        // Virtualised: only the rows on screen are built.
        SliverList.builder(
          itemCount: rows.length,
          itemBuilder: (context, index) => switch (rows[index]) {
            final String title => Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
              child: SectionTitle(title),
            ),
            final ForecastItem item => Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: _CellCard(
                item: item,
                onTap: () => context.push(_detailPath(item, result)),
              ),
            ),
            _ => const SizedBox.shrink(),
          },
        ),
    ];
  }

  /// The headers and cards of the list, the cells over the limit first.
  List<Object> _rows(List<ForecastItem> visible) {
    final over = visible.where((i) => i.exceeds).toList();
    final rest = visible.where((i) => !i.exceeds).toList();
    return [
      if (over.isNotEmpty) ...['Superan el límite · ${over.length}', ...over],
      if (rest.isNotEmpty) ...[
        over.isEmpty
            ? 'Celdas · ${rest.length}'
            : 'Resto de celdas · ${rest.length}',
        ...rest,
      ],
    ];
  }

  String _detailPath(ForecastItem item, ForecastResult result) => Uri(
    path: '/forecasts/cell/${item.cellId}',
    queryParameters: {
      'name': item.cellName,
      if (result.availableFrom != null) 'from': apiDate(result.availableFrom!),
      if (result.availableTo != null) 'to': apiDate(result.availableTo!),
    },
  ).toString();
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.controller,
    required this.onPick,
    required this.quickDays,
  });

  final ForecastsController controller;
  final VoidCallback onPick;
  final List<(String, int)> quickDays;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final result = c.result;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (result != null && result.retraining) ...[
            const RetrainingBanner(),
            const SizedBox(height: 10),
          ],
          if (result?.savedAt != null) ...[
            OfflineBanner(result!.savedAt!),
            const SizedBox(height: 10),
          ],
          if (result == null && c.noOfflineData) ...[
            ClipRRect(
              borderRadius: AppRadius.medium,
              child: const NoticeBanner(
                icon: Icons.cloud_off_outlined,
                text: 'Sin conexión.',
              ),
            ),
            const SizedBox(height: 10),
          ],
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (label, offset) in quickDays) ...[
                  _DayChip(
                    label: label,
                    day: c.today.add(Duration(days: offset)),
                    controller: c,
                  ),
                  const SizedBox(width: 8),
                ],
                ActionChip(
                  avatar: const Icon(Icons.calendar_month_outlined, size: 18),
                  label: const Text('Elegir fecha'),
                  onPressed: c.selectableRange == null ? null : onPick,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SearchField(hint: 'Buscar celda (A1, B12…)', onChanged: c.setQuery),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilterChip(
              avatar: const Icon(Icons.warning_amber_rounded, size: 18),
              label: const Text('Solo las que superan el límite'),
              selected: c.onlyExceeds,
              onSelected: c.setOnlyExceeds,
            ),
          ),
        ],
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.label,
    required this.day,
    required this.controller,
  });

  final String label;
  final DateTime day;
  final ForecastsController controller;

  @override
  Widget build(BuildContext context) {
    final selectable = controller.isSelectable(day);
    return ChoiceChip(
      label: Text(label),
      selected: controller.date == day,
      onSelected: selectable ? (_) => controller.setDate(day) : null,
    );
  }
}

class _CellCard extends StatelessWidget {
  const _CellCard({required this.item, required this.onTap});

  final ForecastItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final max = item.maxVoltage;
    final over = item.exceeds;
    final color = over ? AppColors.error : AppColors.ink;

    return Semantics(
      button: true,
      excludeSemantics: true,
      label:
          'Celda ${item.cellName}, ${over ? 'supera el límite, ' : ''}${volts(item.voltage)}'
          '${max == null ? ', sin límite' : ', límite ${volts(max, 2)}'}',
      child: Material(
        color: over ? AppColors.errorSoft : Colors.white,
        borderRadius: AppRadius.large,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.large,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: AppRadius.large,
              border: Border.all(
                color: over ? AppColors.error : AppColors.border,
                width: over ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: over ? Colors.white : AppColors.blueSoft,
                  child: Text(
                    item.cellName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Celda ${item.cellName}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                          // Colour is not the only cue: the icon and the word say it too.
                          if (over)
                            const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.warning_amber_rounded,
                                  size: 16,
                                  color: AppColors.error,
                                ),
                                SizedBox(width: 3),
                                Text(
                                  'Supera',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.error,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (max != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (item.voltage / max).clamp(0.0, 1.0),
                            minHeight: 6,
                            backgroundColor: AppColors.border,
                            color: over ? AppColors.error : AppColors.blue,
                          ),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        max == null ? 'Sin límite' : 'Límite ${volts(max, 2)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  volts(item.voltage),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
