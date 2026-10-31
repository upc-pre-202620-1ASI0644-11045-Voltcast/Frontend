import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/submit_state.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_header.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/auth_visuals.dart';
import '../../../core/widgets/load_error.dart';
import '../../../core/widgets/screen_header.dart';
import '../../cells/data/cell.dart';
import '../../cells/presentation/inventory_controller.dart';
import '../data/alert_rule.dart';
import '../data/forecasting_repository.dart';
import 'forecast_widgets.dart';

/// Allowed voltage (supervisors only): the general limit and, optionally, one per cell.
class AlertRulesScreen extends StatefulWidget {
  const AlertRulesScreen({super.key});

  @override
  State<AlertRulesScreen> createState() => _AlertRulesScreenState();
}

class _AlertRulesScreenState extends State<AlertRulesScreen> with SubmitState {
  final _general = TextEditingController();
  final _perCell = TextEditingController();
  List<AlertRule>? _rules;
  String? _loadError;
  String? _generalError;
  String? _cellError;
  Cell? _cell;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _general.dispose();
    _perCell.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repository = context.read<ForecastingRepository>();
    setState(() => _loadError = null);
    try {
      final rules = (await repository.alertRules())
          .where((r) => r.isActive)
          .toList();
      if (mounted) setState(() => _rules = rules);
    } on ApiException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    }
  }

  /// The typed voltage, or null (with the field's error set) when it is not above zero.
  double? _parse(TextEditingController field, void Function(String?) setError) {
    final value = double.tryParse(field.text.trim().replaceAll(',', '.'));
    final ok = value != null && value > 0;
    setState(() => setError(ok ? null : 'Ingresa un voltaje mayor que cero.'));
    return ok ? value : null;
  }

  Future<void> _save({required bool general}) async {
    final repository = context.read<ForecastingRepository>();
    final messenger = ScaffoldMessenger.of(context);
    final cell = _cell;
    if (!general && cell == null) {
      setState(() => _cellError = 'Elige una celda.');
      return;
    }
    final value = general
        ? _parse(_general, (e) => _generalError = e)
        : _parse(_perCell, (e) => _cellError = e);
    if (value == null) return;

    final ok = await submit(() async {
      await repository.setLimit(value, cellId: general ? null : cell!.id);
      await _load();
    });
    if (ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            general
                ? 'Límite general guardado.'
                : 'Límite de la celda ${cell!.name} guardado.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cells = context.watch<InventoryController>().cells;
    final names = {for (final c in cells) c.id: c.name};
    final rules = _rules;
    final general = rules?.where((r) => r.cellId == null).firstOrNull;
    final byCell = rules?.where((r) => r.cellId != null).toList() ?? [];

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: 'Límite de voltaje',
              subtitle: 'Configuración · Supervisor',
              onBack: () =>
                  context.canPop() ? context.pop() : context.go('/model'),
            ),
            Expanded(
              child: rules == null
                  ? (_loadError != null
                        ? LoadErrorView(message: _loadError!, onRetry: _load)
                        : const Center(child: CircularProgressIndicator()))
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (error != null) ...[
                          ErrorBanner(error!),
                          const SizedBox(height: 12),
                        ],
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'Límite general',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                general == null
                                    ? 'Aún no hay un límite general.'
                                    : 'Actual: ${volts(general.maxVoltage, 2)}. Se aplica a todas las celdas sin límite propio.',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.muted,
                                ),
                              ),
                              const SizedBox(height: 16),
                              _VoltageField(
                                label: 'Voltaje máximo (V)',
                                controller: _general,
                                error: _generalError,
                              ),
                              const SizedBox(height: 16),
                              PrimaryButton(
                                label: 'Guardar límite general',
                                loading: loading,
                                onPressed: () => _save(general: true),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'Límite por celda',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Reemplaza al límite general solo para esa celda.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.muted,
                                ),
                              ),
                              const SizedBox(height: 16),
                              AppDropdown<Cell>(
                                label: 'Celda',
                                value: _cell,
                                hint: 'Elige una celda',
                                items: {
                                  for (final c in cells) c: 'Celda ${c.name}',
                                },
                                onChanged: (c) => setState(() {
                                  _cell = c;
                                  _cellError = null;
                                }),
                              ),
                              const SizedBox(height: 16),
                              _VoltageField(
                                label: 'Voltaje máximo (V)',
                                controller: _perCell,
                                error: _cellError,
                              ),
                              const SizedBox(height: 16),
                              PrimaryButton(
                                label: 'Guardar límite de la celda',
                                loading: loading,
                                onPressed: () => _save(general: false),
                              ),
                            ],
                          ),
                        ),
                        if (byCell.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          SectionTitle(
                            'Límites por celda',
                            trailing: '${byCell.length}',
                          ),
                          const SizedBox(height: 10),
                          for (final r in byCell)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: AppCard(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Celda ${names[r.cellId] ?? '#${r.cellId}'}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      volts(r.maxVoltage, 2),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoltageField extends StatelessWidget {
  const _VoltageField({
    required this.label,
    required this.controller,
    required this.error,
  });

  final String label;
  final TextEditingController controller;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          label: label,
          controller: controller,
          hint: 'Ej. 3.50',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 16,
                  color: AppColors.error,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    error!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
