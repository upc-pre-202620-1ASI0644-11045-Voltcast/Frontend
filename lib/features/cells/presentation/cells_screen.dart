import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/dialogs.dart';
import '../../../core/submit_state.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/validators.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/auth_visuals.dart';
import '../../../core/widgets/screen_header.dart';
import '../data/cell.dart';
import 'inventory_controller.dart';

class CellsScreen extends StatelessWidget {
  const CellsScreen({super.key});

  Future<void> _disable(BuildContext context, Cell cell) async {
    final inventory = context.read<InventoryController>();
    final components = inventory.componentsOf(cell.id);

    final ok = await confirmDialog(
      context,
      title: '¿Deshabilitar celda ${cell.name}?',
      message: components.isEmpty
          ? 'La celda quedará fuera de uso y se conservará su historial.'
          : 'Se liberarán ${components.map((c) => c.serialCode).join(' y ')} para poder '
              'reasignarlos. La celda quedará fuera de uso y se conservará su historial.',
      action: 'Deshabilitar',
    );
    if (ok && context.mounted) {
      await runAction(context, () => inventory.disableCell(cell), 'Celda ${cell.name} deshabilitada.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryController>();

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: 'Celdas',
              subtitle: 'Gestión de celdas eléctricas',
              onBack: () => context.canPop() ? context.pop() : context.go('/home'),
              action: HeaderAction(
                label: 'Nueva',
                onPressed: inventory.hasLoaded
                    ? () => showAppSheet<void>(context, (_) => _CellSheet(inventory: inventory))
                    : null,
              ),
            ),
            Expanded(child: _body(context, inventory)),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, InventoryController inventory) {
    if (!inventory.hasLoaded) {
      if (inventory.loading) {
        return const Center(child: CircularProgressIndicator(color: AppColors.blue));
      }
      return LoadErrorView(message: inventory.loadError ?? 'No se pudo cargar.', onRetry: inventory.load);
    }

    final cells = inventory.cells;
    // Active cells first; disabled ones stay listed (history is kept).
    final ordered = [...cells.where((c) => c.isActive), ...cells.where((c) => !c.isActive)];

    return RefreshIndicator(
      color: AppColors.blue,
      onRefresh: inventory.load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          if (inventory.loadError != null) ...[
            ErrorBanner(inventory.loadError!),
            const SizedBox(height: 16),
          ],
          StatRow(
            tiles: [
              StatTile(label: 'Registradas', value: cells.length),
              StatTile(label: 'Con componentes', value: inventory.cellsWithComponents, color: AppColors.blue),
              StatTile(label: 'Inactivas', value: inventory.inactiveCells, color: AppColors.muted),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: NavButton(label: 'Componentes', onPressed: () => context.push('/components'))),
              const SizedBox(width: 12),
              Expanded(child: NavButton(label: 'Códigos', onPressed: () => context.push('/barcodes'))),
            ],
          ),
          const SizedBox(height: 14),
          if (ordered.isEmpty)
            const InfoBox(text: 'Aún no hay celdas registradas. Crea la primera con "Nueva".')
          else
            InventoryCard(
              title: 'Inventario de celdas',
              trailing: '${ordered.length} ${ordered.length == 1 ? 'registro' : 'registros'}',
              children: [
                for (final cell in ordered)
                  _CellTile(
                    cell: cell,
                    cathode: inventory.cathodeOf(cell)?.serialCode,
                    anode: inventory.anodeOf(cell)?.serialCode,
                    busy: inventory.isCellBusy(cell.id),
                    onBarcode: () => context.push('/barcodes?cell=${cell.id}'),
                    onEdit: () => showAppSheet<void>(
                      context,
                      (_) => _CellSheet(inventory: inventory, cell: cell),
                    ),
                    onDisable: () => _disable(context, cell),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _CellTile extends StatelessWidget {
  const _CellTile({
    required this.cell,
    required this.cathode,
    required this.anode,
    required this.busy,
    required this.onBarcode,
    required this.onEdit,
    required this.onDisable,
  });

  final Cell cell;
  final String? cathode;
  final String? anode;
  final bool busy;
  final VoidCallback onBarcode;
  final VoidCallback onEdit;
  final VoidCallback onDisable;

  @override
  Widget build(BuildContext context) {
    final actionable = cell.isActive && !busy;

    return Opacity(
      opacity: cell.isActive ? 1 : 0.55,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  color: const Color(0xFFEEF3FF),
                  child: Text(
                    cell.name,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.blue),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Celda ${cell.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink),
                  ),
                ),
                StatusPill.of(cell.isActive ? 'Activa' : 'Inactiva', cell.isActive ? StatusPill.green : StatusPill.grey),
              ],
            ),
            if (cell.isActive) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: _ComponentBox(label: 'Cátodo', serial: cathode)),
                  const SizedBox(width: 12),
                  Expanded(child: _ComponentBox(label: 'Ánodo', serial: anode)),
                ],
              ),
            ],
            const SizedBox(height: 14),
            const Divider(height: 1, color: Color(0xFFF0F1F4)),
            const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cell.hasBarcode ? const Color(0xFF22C55E) : const Color(0xFFF5B50A),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    cell.hasBarcode ? 'Código generado' : 'Código pendiente',
                    style: const TextStyle(fontSize: 14, color: AppColors.muted),
                  ),
                ),
                if (cell.isActive) ...[
                  SmallActionButton(label: 'Código', onPressed: busy ? null : onBarcode),
                  IconButton(
                    tooltip: 'Editar',
                    onPressed: actionable ? onEdit : null,
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    color: AppColors.muted,
                  ),
                  busy
                      ? const SizedBox(
                          width: 48,
                          height: 48,
                          child: Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.blue),
                            ),
                          ),
                        )
                      : IconButton(
                          tooltip: 'Deshabilitar',
                          onPressed: onDisable,
                          icon: const Icon(Icons.block_outlined, size: 20),
                          color: AppColors.muted,
                        ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ComponentBox extends StatelessWidget {
  const _ComponentBox({required this.label, required this.serial});

  final String label;
  final String? serial;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
          const SizedBox(height: 6),
          Text(
            serial ?? 'Sin asignar',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: serial == null ? FontWeight.w400 : FontWeight.w600,
              color: serial == null ? AppColors.hint : AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// Retry card shown when the first load fails.
class LoadErrorView extends StatelessWidget {
  const LoadErrorView({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ErrorBanner(message),
            const SizedBox(height: 16),
            PrimaryButton(label: 'Reintentar', onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}

/// Uppercases as you type: cell names are stored uppercase (A1, B12).
class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}

/// Create (cell == null) or rename a cell.
class _CellSheet extends StatefulWidget {
  const _CellSheet({required this.inventory, this.cell});

  final InventoryController inventory;
  final Cell? cell;

  @override
  State<_CellSheet> createState() => _CellSheetState();
}

class _CellSheetState extends State<_CellSheet> with SubmitState {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.cell?.name ?? '');

  bool get _editing => widget.cell != null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _canSave {
    final value = _name.text.trim();
    return value.isNotEmpty && (!_editing || value.toUpperCase() != widget.cell!.name);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final name = _name.text.trim().toUpperCase();

    final ok = await submit(
      () => _editing ? widget.inventory.renameCell(widget.cell!, name) : widget.inventory.createCell(name),
    );
    if (ok) {
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(_editing ? 'Celda actualizada.' : 'Celda $name creada.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SheetFrame(
      title: _editing ? 'Editar celda' : 'Nueva celda',
      children: [
        Form(
          key: _formKey,
          child: AppTextField(
            label: 'Nombre de la celda',
            hint: 'A1',
            controller: _name,
            textInputAction: TextInputAction.done,
            inputFormatters: [_UpperCaseFormatter()],
            validator: Validators.cellName,
            onSubmitted: (_) => _canSave ? _save() : null,
            enabled: !loading,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Una letra seguida de un número: A1, B12…',
          style: TextStyle(fontSize: 13, color: AppColors.muted),
        ),
        const SizedBox(height: 20),
        if (error != null) ...[
          ErrorBanner(error!),
          const SizedBox(height: 16),
        ],
        ListenableBuilder(
          listenable: _name,
          builder: (context, _) => PrimaryButton(
            label: _editing ? 'Guardar cambios' : 'Crear celda',
            loading: loading,
            onPressed: _canSave ? _save : null,
          ),
        ),
        const SizedBox(height: 12),
        SecondaryButton(label: 'Cancelar', onPressed: loading ? null : () => Navigator.pop(context)),
      ],
    );
  }
}
