import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/dialogs.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/backend_messages.dart';
import '../../../core/submit_state.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/validators.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/auth_visuals.dart';
import '../../../core/widgets/screen_header.dart';
import '../data/cell.dart';
import '../data/component.dart';
import 'inventory_controller.dart';
import 'sync_banner.dart';

class CellsScreen extends StatelessWidget {
  const CellsScreen({super.key});

  /// US011. A cell without components is disabled after a confirmation (E01).
  /// One that still has components is refused with a message (E02) and the user
  /// may choose to release them, which frees the cathode and anode and disables
  /// the cell (E03).
  Future<void> _disable(BuildContext context, Cell cell) async {
    final inventory = context.read<InventoryController>();
    final done = 'Celda ${cell.name} deshabilitada.';

    if (inventory.componentsOf(cell.id).isEmpty) {
      final ok = await confirmDialog(
        context,
        title: '¿Deshabilitar celda ${cell.name}?',
        message: 'La celda quedará fuera de uso.',
        action: 'Deshabilitar',
      );
      if (!ok || !context.mounted) return;

      final messenger = ScaffoldMessenger.of(context);
      try {
        await inventory.disableCell(cell);
        messenger.showSnackBar(SnackBar(content: Text(done)));
        return;
      } on ApiException catch (e) {
        // Anything but "it has components" (e.g. offline) is just reported.
        if (e.message != cellHasComponentsMessage) {
          messenger.showSnackBar(SnackBar(content: Text(e.message)));
          return;
        }
        // Components were assigned from another device: same as E02 below.
      }
    }
    if (!context.mounted) return;

    final serials = inventory.componentsOf(cell.id).map((c) => c.serialCode).join(' y ');
    final release = await confirmDialog(
      context,
      title: 'La celda tiene componentes asignados',
      message: 'No se puede deshabilitar la celda ${cell.name} mientras tenga '
          '${serials.isEmpty ? 'componentes' : serials} asignados. Puedes liberarlos para '
          'dejarlos disponibles y deshabilitar la celda.',
      action: 'Liberar y deshabilitar',
    );
    if (release && context.mounted) {
      await runAction(context, () => inventory.disableCell(cell, release: true), done);
    }
  }

  /// Drop of [dragged] onto [target]: same type, different cells (the box only
  /// accepts those). Asks first because a stray drop would change the inventory.
  Future<void> _swap(BuildContext context, Component dragged, Component target) async {
    final inventory = context.read<InventoryController>();
    final ok = await confirmDialog(
      context,
      title: '¿Intercambiar componentes?',
      action: 'Intercambiar',
      actionColor: AppColors.orange,
    );
    if (!ok || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final outcome = await inventory.swapComponents(dragged, target);
      messenger.showSnackBar(
        outcome == SwapOutcome.queued
            ? const SnackBar(
                duration: Duration(seconds: 7),
                content: Text(
                  'Sin conexión: el intercambio se realizó en tu dispositivo y se sincronizará '
                  'con el servidor cuando se recupere la conexión a internet.',
                ),
              )
            : SnackBar(content: Text('${dragged.serialCode} y ${target.serialCode} intercambiados.')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
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
          const SyncStatusBanner(),
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
              Expanded(child: NavButton(label: 'Componentes', color: AppColors.blue, onPressed: () => context.push('/components'))),
              const SizedBox(width: 12),
              Expanded(child: NavButton(label: 'Códigos', color: AppColors.violet, onPressed: () => context.push('/barcodes'))),
            ],
          ),
          const SizedBox(height: 14),
          if (ordered.isEmpty)
            const InfoBox(text: 'Aún no hay celdas registradas. Crea la primera con "Nueva".')
          else ...[
            if (ordered.where((c) => c.isActive).length > 1)
              const Padding(
                padding: EdgeInsets.only(bottom: 10, left: 4, right: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.swap_horiz, size: 18, color: AppColors.orange),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Mantén pulsado un cátodo o ánodo y suéltalo sobre el del mismo tipo de otra celda para intercambiarlos.',
                        style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.muted),
                      ),
                    ),
                  ],
                ),
              ),
            InventoryCard(
              title: 'Inventario de celdas',
              trailing: '${ordered.length} ${ordered.length == 1 ? 'registro' : 'registros'}',
              children: [
                for (final cell in ordered)
                  _CellTile(
                    cell: cell,
                    cathode: inventory.cathodeOf(cell),
                    anode: inventory.anodeOf(cell),
                    busy: inventory.isCellBusy(cell.id),
                    isComponentBusy: inventory.isComponentBusy,
                    onSwap: (dragged, target) => _swap(context, dragged, target),
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
        ],
      ),
    );
  }
}

class _CellTile extends StatelessWidget {
  Widget _box(String label, Component? component) => _ComponentBox(
        label: label,
        component: component,
        enabled: !busy && (component == null || !isComponentBusy(component.id)),
        onSwap: onSwap,
      );

  const _CellTile({
    required this.cell,
    required this.cathode,
    required this.anode,
    required this.busy,
    required this.isComponentBusy,
    required this.onSwap,
    required this.onBarcode,
    required this.onEdit,
    required this.onDisable,
  });

  final Cell cell;
  final Component? cathode;
  final Component? anode;
  final bool busy;
  final bool Function(int componentId) isComponentBusy;
  final void Function(Component dragged, Component target) onSwap;
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
                  decoration: BoxDecoration(color: const Color(0xFFEEF3FF), borderRadius: AppRadius.medium),
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
                  Expanded(child: _box('Cátodo', cathode)),
                  const SizedBox(width: 12),
                  Expanded(child: _box('Ánodo', anode)),
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
                  SmallActionButton(label: 'Código', color: AppColors.violet, onPressed: busy ? null : onBarcode),
                  IconButton(
                    tooltip: 'Editar',
                    onPressed: actionable ? onEdit : null,
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    color: AppColors.blue,
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
                          color: AppColors.error,
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
  const _ComponentBox({
    required this.label,
    required this.component,
    required this.enabled,
    required this.onSwap,
  });

  final String label;
  final Component? component;
  final bool enabled;
  final void Function(Component dragged, Component target) onSwap;

  Widget _content(String? serial, {Color? background, Color? border}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: background ?? AppColors.surface,
          borderRadius: AppRadius.medium,
          border: Border.all(color: border ?? Colors.transparent, width: 2),
        ),
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

  @override
  Widget build(BuildContext context) {
    final c = component;
    // Empty boxes cannot be swapped: there is nothing to exchange.
    if (c == null) return _content(null);

    return DragTarget<Component>(
      onWillAcceptWithDetails: (d) => enabled && d.data.type == c.type && d.data.cellId != c.cellId,
      onAcceptWithDetails: (d) => onSwap(d.data, c),
      builder: (context, hovering, _) {
        final box = _content(
          c.serialCode,
          background: hovering.isNotEmpty ? AppColors.orangeSoft : null,
          border: hovering.isNotEmpty ? AppColors.orange : null,
        );
        return LongPressDraggable<Component>(
          data: c,
          maxSimultaneousDrags: enabled ? 1 : 0,
          feedback: Material(
            color: Colors.transparent,
            child: SizedBox(
              width: 150,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: AppRadius.medium,
                  boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 14, offset: Offset(0, 6))],
                ),
                child: _content(c.serialCode, background: Colors.white, border: AppColors.orange),
              ),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.35, child: box),
          child: box,
        );
      },
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

  /// Creating is always allowed so an empty form is answered with the
  /// "required field" message; editing needs an actual change.
  bool get _canSave => !_editing || _name.text.trim().toUpperCase() != widget.cell!.name;

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
            color: AppColors.teal,
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
