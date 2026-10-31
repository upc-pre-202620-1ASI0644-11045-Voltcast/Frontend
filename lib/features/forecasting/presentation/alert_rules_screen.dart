import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/submit_state.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/auth_visuals.dart';
import '../../../core/widgets/load_error.dart';
import '../../../core/widgets/page_header.dart';
import '../data/alert_rule.dart';
import '../data/forecasting_repository.dart';
import 'forecast_widgets.dart';

/// Allowed voltage (supervisors only): the general limit.
class AlertRulesScreen extends StatefulWidget {
  const AlertRulesScreen({super.key});

  @override
  State<AlertRulesScreen> createState() => _AlertRulesScreenState();
}

class _AlertRulesScreenState extends State<AlertRulesScreen> with SubmitState {
  final _general = TextEditingController();
  List<AlertRule>? _rules;
  String? _loadError;
  String? _generalError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _general.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repository = context.read<ForecastingRepository>();
    setState(() => _loadError = null);
    try {
      final rules = (await repository.alertRules())
          .where((r) => r.isActive)
          .toList();
      if (!mounted) return;
      final general = rules.where((r) => r.cellId == null).firstOrNull;
      // The field starts on the limit in force, ready to be edited.
      if (general != null && _general.text.isEmpty) {
        _general.text = general.maxVoltage.toStringAsFixed(2);
      }
      setState(() => _rules = rules);
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

  Future<void> _save() async {
    final repository = context.read<ForecastingRepository>();
    final messenger = ScaffoldMessenger.of(context);
    final value = _parse(_general, (e) => _generalError = e);
    if (value == null) return;

    final ok = await submit(() async {
      await repository.setLimit(value);
      await _load();
    });
    if (ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Límite general guardado.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final rules = _rules;
    final general = rules?.where((r) => r.cellId == null).firstOrNull;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            PageHeader(
              eyebrow: 'Configuración · Supervisor',
              title: 'Límite de voltaje',
              onBack: () =>
                  context.canPop() ? context.pop() : context.go('/settings'),
            ),
            Expanded(
              child: rules == null
                  ? (_loadError != null
                        ? LoadErrorView(message: _loadError!, onRetry: _load)
                        : const Center(child: CircularProgressIndicator()))
                  : ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        if (error != null) ...[
                          ErrorBanner(error!),
                          const SizedBox(height: 12),
                        ],
                        const SizedBox(height: 8),
                        Center(
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: const BoxDecoration(
                              color: Color(0xFFFFF1D6),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.bolt,
                              size: 30,
                              color: AppColors.amber,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Center(
                          child: Text(
                            'VOLTAJE MÁXIMO (V)',
                            style: AppTheme.label,
                          ),
                        ),
                        _VoltageField(
                          controller: _general,
                          error: _generalError,
                        ),
                        const SizedBox(height: 6),
                        const Center(
                          child: Text(
                            'Aplicable a todas las celdas.',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.muted,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Divider(height: 1, color: Color(0xFFE3E7EE)),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Límite actual',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: AppColors.muted,
                                  ),
                                ),
                              ),
                              Text(
                                general == null
                                    ? 'Sin definir'
                                    : volts(general.maxVoltage, 2),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1, color: Color(0xFFE3E7EE)),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.blueSoft,
                            borderRadius: AppRadius.large,
                          ),
                          child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 20,
                                color: AppColors.blue,
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Umbral de alerta',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.blue,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Las celdas con un pronóstico superior a este máximo se resaltarán en Pronósticos.',
                                      style: TextStyle(
                                        fontSize: 14,
                                        height: 1.4,
                                        color: AppColors.blue,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        PrimaryButton(
                          label: 'Guardar límite',
                          loading: loading,
                          onPressed: _save,
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

class _VoltageField extends StatelessWidget {
  const _VoltageField({required this.controller, required this.error});

  final TextEditingController controller;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: TextField(
            controller: controller,
            textAlign: TextAlign.center,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            style: const TextStyle(
              fontSize: 56,
              fontWeight: FontWeight.w800,
              color: AppColors.blue,
            ),
            decoration: const InputDecoration(
              hintText: '0.00',
              hintStyle: TextStyle(color: AppColors.hint),
              suffixText: 'V',
              suffixStyle: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w500,
                color: AppColors.muted,
              ),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.ink, width: 1),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.blue, width: 2),
              ),
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 16,
                  color: AppColors.error,
                ),
                const SizedBox(width: 6),
                Flexible(
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
