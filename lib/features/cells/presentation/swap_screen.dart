import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_header.dart';
import '../../../core/widgets/app_widgets.dart';
import '../data/cell.dart';
import '../data/component.dart';
import 'cell_screen.dart' show CellModelView;
import 'inventory_controller.dart';

/// What the user does with changes not saved yet when leaving or picking another cell.
enum _Unsaved { save, discard }

/// Swaps components between two cells picked from the whole list, so a swap
/// between A1 and A150 needs no dragging past 149 cards. Drops only stage the
/// swap; nothing reaches the backend until "Guardar cambios".
class SwapScreen extends StatefulWidget {
  const SwapScreen({super.key, this.initialCellId});

  /// The cell the screen was opened from, preselected on the left.
  final int? initialCellId;

  @override
  State<SwapScreen> createState() => _SwapScreenState();
}

class _SwapScreenState extends State<SwapScreen> {
  /// Left and right cell ids.
  late final _cells = <int?>[widget.initialCellId, null];

  /// Types whose components are swapped between the two cells, not saved yet.
  final _swapped = <ComponentType>{};
  bool _saving = false;

  bool get _dirty => _swapped.isNotEmpty;

  /// The component of [type] shown on [side]: the other cell's while staged as swapped.
  Component? _shown(InventoryController inventory, int side, ComponentType type) {
    final from = _swapped.contains(type) ? 1 - side : side;
    final cell = inventory.cellById(_cells[from]);
    return cell == null ? null : inventory.occupantOf(cell, type);
  }

  void _drop(InventoryController inventory, ({ComponentType type, int side}) dragged, ComponentType target) {
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    if (dragged.type != target) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Solo puedes intercambiar componentes del mismo tipo: ánodo con ánodo y cátodo con cátodo.'),
        ),
      );
      return;
    }
    // The backend swaps two installed components: both cells need one of that type.
    if (_shown(inventory, 1 - dragged.side, target) == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('El intercambio no se puede realizar porque no hay un componente disponible.')),
      );
      return;
    }
    // Dragging it back undoes the staged swap.
    setState(() => _swapped.contains(target) ? _swapped.remove(target) : _swapped.add(target));
  }

  /// Sends the staged swaps one by one. Offline, the controller applies and
  /// queues them like any other swap.
  Future<bool> _save() async {
    final inventory = context.read<InventoryController>();
    final messenger = ScaffoldMessenger.of(context);
    final left = inventory.cellById(_cells[0]), right = inventory.cellById(_cells[1]);
    if (left == null || right == null) return false;
    setState(() => _saving = true);
    var queued = false;
    try {
      for (final type in [..._swapped]) {
        final a = inventory.occupantOf(left, type), b = inventory.occupantOf(right, type);
        // Each saved swap leaves the staging: what is shown is now the real state.
        if (a != null && b != null) queued |= await inventory.swapComponents(a, b) == SwapOutcome.queued;
        _swapped.remove(type);
      }
      messenger.showSnackBar(
        SnackBar(
          duration: Duration(seconds: queued ? 7 : 4),
          content: Text(
            queued
                ? 'Sin conexión: el intercambio se realizó en tu dispositivo y se sincronizará '
                      'con el servidor cuando se recupere la conexión a internet.'
                : 'Cambios guardados.',
          ),
        ),
      );
      return true;
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// With staged swaps, asks whether to save or discard them. True when the
  /// user may go on (nothing staged, saved, or discarded).
  Future<bool> _settleUnsaved() async {
    if (!_dirty) return true;
    final choice = await showDialog<_Unsaved>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tienes cambios sin guardar', style: TextStyle(fontWeight: FontWeight.w700)),
        content: const Text('¿Deseas guardar o descartar los cambios?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _Unsaved.discard),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Descartar'),
          ),
          TextButton(onPressed: () => Navigator.pop(context, _Unsaved.save), child: const Text('Guardar')),
        ],
      ),
    );
    if (!mounted) return false;
    switch (choice) {
      case _Unsaved.save:
        return _save();
      case _Unsaved.discard:
        setState(_swapped.clear);
        return true;
      case null:
        return false; // dismissed: stay
    }
  }

  Future<void> _leave() async {
    if (await _settleUnsaved() && mounted) Navigator.of(context).pop();
  }

  Future<void> _pick(InventoryController inventory, int side) async {
    if (!await _settleUnsaved() || !mounted) return;
    final other = _cells[1 - side];
    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CellPickerSheet(inventory: inventory, exceptId: other),
    );
    if (picked != null && mounted) setState(() => _cells[side] = picked);
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryController>();

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    CircleAction(
                      tooltip: 'Volver',
                      icon: Icons.chevron_left,
                      background: Colors.white,
                      size: 44,
                      onPressed: _saving ? null : _leave,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Intercambiar componentes',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink),
                      ),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Text(
                  'Elige dos celdas. Mantén pulsado un componente y suéltalo sobre el del mismo tipo en la otra celda.',
                  style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.muted),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                child: Row(
                  children: [
                    Expanded(child: _pickerFor(inventory, 0)),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.swap_horiz, color: AppColors.muted),
                    ),
                    Expanded(child: _pickerFor(inventory, 1)),
                  ],
                ),
              ),
              // Right under the pickers; scrolls on short screens.
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 20, 12, 16),
                  child: Row(
                    children: [
                      Expanded(child: _side(inventory, 0)),
                      SizedBox(
                        width: 96,
                        // Only once something was dropped: until then there is nothing to save.
                        child: _dirty || _saving ? Center(child: _saveButton()) : null,
                      ),
                      Expanded(child: _side(inventory, 1)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pickerFor(InventoryController inventory, int side) {
    final cell = inventory.cellById(_cells[side]);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: ValueKey('swap-pick-$side'),
        borderRadius: BorderRadius.circular(16),
        onTap: _saving || !inventory.hasLoaded ? null : () => _pick(inventory, side),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.search, size: 20, color: AppColors.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  cell?.name ?? 'Elegir celda',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: cell == null ? FontWeight.w400 : FontWeight.w700,
                    color: cell == null ? AppColors.muted : AppColors.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _side(InventoryController inventory, int side) {
    final cell = inventory.cellById(_cells[side]);
    if (cell == null) {
      return InkWell(
        onTap: inventory.hasLoaded ? () => _pick(inventory, side) : null,
        borderRadius: AppRadius.large,
        child: Container(
          height: 220,
          alignment: Alignment.center,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.6),
            borderRadius: AppRadius.large,
            border: Border.all(color: AppColors.border),
          ),
          child: const Text(
            'Elige una celda',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.muted),
          ),
        ),
      );
    }

    final ready = inventory.cellById(_cells[1 - side]) != null && !_saving;
    Widget part(ComponentType type) {
      final c = _shown(inventory, side, type);
      final changed = _swapped.contains(type);
      return Row(
        children: [
          Text(type.label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              c?.serialCode ?? '—',
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: changed ? AppColors.orange : AppColors.ink,
              ),
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: AppRadius.large, boxShadow: AppCard.shadow),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFEFF4FC), Color(0xFFDCE6F5)],
              ),
            ),
            child: CellModelView(
              anode: _shown(inventory, side, ComponentType.anode)?.serialCode,
              cathode: _shown(inventory, side, ComponentType.cathode)?.serialCode,
              slot: (type, size, bar) => _slot(inventory, side, type, size, bar, enabled: ready),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Celda ${cell.name}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink),
          ),
          const SizedBox(height: 4),
          part(ComponentType.anode),
          part(ComponentType.cathode),
        ],
      ),
    );
  }

  /// A slot of [side]: its bar can be dragged to the other cell, and it takes
  /// drops from the other cell of any type (a wrong one is refused with a message).
  Widget _slot(
    InventoryController inventory,
    int side,
    ComponentType type,
    Size size,
    Widget bar, {
    required bool enabled,
  }) {
    final serial = _shown(inventory, side, type)?.serialCode;
    final data = (type: type, side: side);
    final changed = _swapped.contains(type);

    return DragTarget<({ComponentType type, int side})>(
      onWillAcceptWithDetails: (d) => enabled && d.data.side != side,
      onAcceptWithDetails: (d) => _drop(inventory, d.data, type),
      builder: (context, hovering, _) {
        final hoverColor = hovering.isEmpty
            ? null
            : (hovering.first?.type == type ? AppColors.orange : AppColors.error);
        return DecoratedBox(
          key: ValueKey('swap-${type.name}-$side'),
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: hoverColor?.withValues(alpha: 0.18),
            border: hoverColor != null
                ? Border.all(color: hoverColor, width: 2.5)
                : (changed ? Border.all(color: AppColors.orange, width: 1.5) : null),
          ),
          child: serial == null || !enabled
              ? bar
              : LongPressDraggable<({ComponentType type, int side})>(
                  data: data,
                  feedback: CellModelView.liftedBar(type, serial, size),
                  childWhenDragging: const Opacity(opacity: 0.3, child: SizedBox.expand()),
                  child: Semantics(label: '${type.label} $serial. Mantén pulsado para arrastrarlo.', child: bar),
                ),
        );
      },
    );
  }

  Widget _saveButton() {
    return SizedBox(
      width: 84,
      height: 96,
      child: FilledButton(
        onPressed: _saving ? null : _save,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.blue,
          disabledBackgroundColor: AppColors.blue,
          padding: const EdgeInsets.all(8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        child: _saving
            ? const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
              )
            : const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check, size: 22),
                  SizedBox(height: 4),
                  Text(
                    'Guardar cambios',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, height: 1.2),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Bottom sheet listing every cell (but [exceptId]) with a search box; pops the picked id.
class _CellPickerSheet extends StatefulWidget {
  const _CellPickerSheet({required this.inventory, this.exceptId});

  final InventoryController inventory;
  final int? exceptId;

  @override
  State<_CellPickerSheet> createState() => _CellPickerSheetState();
}

class _CellPickerSheetState extends State<_CellPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final inventory = widget.inventory;
    final cells = inventory.cells.where((c) => c.id != widget.exceptId && _matches(inventory, c)).toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Text(
                'Elegir celda',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.ink),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DecoratedBox(
                decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(18)),
                child: SearchField(onChanged: (text) => setState(() => _query = text.trim().toLowerCase())),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: cells.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Ninguna celda coincide.', style: TextStyle(color: AppColors.muted)),
                    )
                  // Built lazily: fine with 300 cells.
                  : ListView.builder(
                      itemCount: cells.length,
                      itemBuilder: (context, i) {
                        final cell = cells[i];
                        String serial(ComponentType t) => inventory.occupantOf(cell, t)?.serialCode ?? '—';
                        return ListTile(
                          key: ValueKey('pick-${cell.id}'),
                          title: Text('Celda ${cell.name}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(
                            'Ánodo ${serial(ComponentType.anode)} · Cátodo ${serial(ComponentType.cathode)}',
                          ),
                          trailing: const Icon(Icons.chevron_right, color: AppColors.muted),
                          onTap: () => Navigator.pop(context, cell.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// By code: the cell's name or barcode, or the serial of a bar in it.
  bool _matches(InventoryController inventory, Cell cell) {
    if (_query.isEmpty) return true;
    final codes = [cell.name, ?cell.barcodeValue, for (final c in inventory.componentsOf(cell.id)) c.serialCode];
    return codes.any((code) => code.toLowerCase().contains(_query));
  }
}
