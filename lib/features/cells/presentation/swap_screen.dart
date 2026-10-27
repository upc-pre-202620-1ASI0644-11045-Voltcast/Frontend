import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_header.dart' show AppCard;
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/screen_header.dart';
import '../data/cell.dart';
import '../data/component.dart';
import 'cell_screen.dart' show CellModelView;
import 'inventory_controller.dart';

/// What the user does with changes not saved yet when leaving or picking another cell.
enum _Unsaved { save, discard }

/// Swaps components between two cells picked from the whole list, so a swap
/// between A1 and A150 needs no scrolling past 149 cards. "Intercambiar" only
/// stages the swap; nothing reaches the backend until "Guardar cambios".
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

  /// The type the toggle and the "Intercambiar" button work on.
  ComponentType _type = ComponentType.anode;

  bool get _dirty => _swapped.isNotEmpty;

  /// The component of [type] shown on [side]: the other cell's while staged as swapped.
  Component? _shown(InventoryController inventory, int side, ComponentType type) {
    final from = _swapped.contains(type) ? 1 - side : side;
    final cell = inventory.cellById(_cells[from]);
    return cell == null ? null : inventory.occupantOf(cell, type);
  }

  /// Stages (or, when already staged, undoes) the swap of [type] between the two cells.
  void _stage(InventoryController inventory, ComponentType type) {
    // The backend swaps two installed components: both cells need one of that type.
    if (_shown(inventory, 0, type) == null || _shown(inventory, 1, type) == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('El intercambio no se puede realizar porque no hay un componente disponible.')),
        );
      return;
    }
    setState(() => _swapped.contains(type) ? _swapped.remove(type) : _swapped.add(type));
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
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BrandHeader(
              eyebrow: 'Celdas · Componentes',
              title: 'Intercambiar componentes',
              onBack: _saving ? null : _leave,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(16, 20, 16, 24 + MediaQuery.paddingOf(context).bottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(child: _pickerFor(inventory, 0, 'Primera celda')),
                        const Padding(
                          padding: EdgeInsets.fromLTRB(8, 0, 8, 16),
                          child: Icon(Icons.swap_horiz, color: AppColors.muted),
                        ),
                        Expanded(child: _pickerFor(inventory, 1, 'Segunda celda')),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _typeToggle(),
                    const SizedBox(height: 20),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _side(inventory, 0)),
                        const SizedBox(width: 12),
                        Expanded(child: _side(inventory, 1)),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _status(),
                    const SizedBox(height: 10),
                    _swapButton(inventory),
                    const SizedBox(height: 12),
                    _saveButton(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeToggle() {
    Widget option(ComponentType type) {
      final selected = _type == type;
      return Expanded(
        child: GestureDetector(
          key: ValueKey('swap-type-${type.name}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _type = type),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(22),
              boxShadow: selected ? AppCard.shadow : null,
            ),
            child: Text(
              type.label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.blue : AppColors.muted,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(26)),
      child: Row(children: [option(ComponentType.anode), option(ComponentType.cathode)]),
    );
  }

  Widget _status() {
    final n = _swapped.length;
    return Row(
      children: [
        Expanded(
          child: Text(
            n == 0 ? 'Sin cambios pendientes' : '$n ${n == 1 ? 'intercambio pendiente' : 'intercambios pendientes'}',
            style: const TextStyle(fontSize: 13, color: AppColors.muted),
          ),
        ),
        IconButton(
          key: const ValueKey('swap-undo'),
          tooltip: 'Deshacer cambios',
          onPressed: _dirty && !_saving ? () => setState(_swapped.clear) : null,
          icon: const Icon(Icons.restore, size: 20),
          color: AppColors.ink,
        ),
      ],
    );
  }

  Widget _swapButton(InventoryController inventory) {
    final ready = inventory.cellById(_cells[0]) != null && inventory.cellById(_cells[1]) != null && !_saving;
    bool lit(Set<WidgetState> states) => states.contains(WidgetState.hovered) || states.contains(WidgetState.pressed);
    return SizedBox(
      height: 52,
      child: OutlinedButton.icon(
        key: const ValueKey('swap-stage'),
        onPressed: ready ? () => _stage(inventory, _type) : null,
        icon: const Icon(Icons.swap_horiz, size: 20),
        label: Text('Intercambiar ${_type.label.toLowerCase()}s'),
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll(StadiumBorder()),
          textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          // Lime while hovered or pressed, outlined blue otherwise.
          backgroundColor: WidgetStateProperty.resolveWith((s) => lit(s) ? AppColors.lime : Colors.transparent),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? AppColors.disabledFg : (lit(s) ? AppColors.ink : AppColors.blue),
          ),
          side: WidgetStateProperty.resolveWith(
            (s) => BorderSide(
              color: s.contains(WidgetState.disabled)
                  ? AppColors.border
                  : (lit(s) ? AppColors.lime : AppColors.blue.withValues(alpha: 0.35)),
            ),
          ),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
    );
  }

  Widget _pickerFor(InventoryController inventory, int side, String label) {
    final cell = inventory.cellById(_cells[side]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
        ),
        _pickerField(inventory, side, cell),
      ],
    );
  }

  Widget _pickerField(InventoryController inventory, int side, Cell? cell) {
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

    Widget part(ComponentType type) {
      final c = _shown(inventory, side, type);
      final selected = _type == type;
      final changed = _swapped.contains(type);
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: InkWell(
          key: ValueKey('swap-part-${type.name}-$side'),
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _type = type),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? AppColors.blueSoft : AppColors.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(type.label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                Text(
                  c?.serialCode ?? '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: selected ? AppColors.blue : (changed ? AppColors.orange : AppColors.ink),
                  ),
                ),
              ],
            ),
          ),
        ),
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
              slot: (type, size, bar) => _slot(side, type, bar),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Celda ${cell.name}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink),
          ),
          part(ComponentType.anode),
          part(ComponentType.cathode),
        ],
      ),
    );
  }

  /// A slot of [side], outlined while its type is staged as swapped.
  Widget _slot(int side, ComponentType type, Widget bar) {
    return DecoratedBox(
      key: ValueKey('swap-${type.name}-$side'),
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: _swapped.contains(type) ? Border.all(color: AppColors.orange, width: 1.5) : null,
      ),
      child: bar,
    );
  }

  Widget _saveButton() {
    return SizedBox(
      height: 52,
      child: FilledButton.icon(
        onPressed: _dirty && !_saving ? _save : null,
        icon: _saving
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
              )
            : const Icon(Icons.check, size: 20),
        label: const Text('Guardar cambios'),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.blue,
          foregroundColor: Colors.white,
          // Faded blue until there is something to save (while saving it stays solid).
          disabledBackgroundColor: _saving ? AppColors.blue : AppColors.blue.withValues(alpha: 0.5),
          disabledForegroundColor: Colors.white,
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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
