import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/dialogs.dart';
import '../../../core/submit_state.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/validators.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/auth_visuals.dart';
import '../data/cell.dart';
import '../data/component.dart';
import 'inventory_controller.dart';

/// A component in use is refused with a message (US013 E02); a free one is
/// disabled after a confirmation.
Future<void> disableComponentWithChecks(BuildContext context, Component component) async {
  final inventory = context.read<InventoryController>();

  if (component.isInUse) {
    final cell = inventory.cellById(component.cellId);
    await showInfoDialog(
      context,
      title: 'El componente está en uso',
      message:
          '${component.serialCode} está asignado a la celda ${cell?.name ?? '#${component.cellId}'}, '
          'por lo que no se puede deshabilitar. Libera la celda o asígnalo a otra antes de hacerlo.',
    );
    return;
  }

  final ok = await confirmDialog(
    context,
    title: '¿Deshabilitar ${component.type.label.toLowerCase()}?',
    message: '${component.serialCode} quedará fuera de uso y se conservará su historial.',
    action: 'Deshabilitar',
  );
  if (ok && context.mounted) {
    await runAction(context, () => inventory.disableComponent(component), '${component.serialCode} deshabilitado.');
  }
}

/// Register a component (optionally with its [type] and [cell] chosen) or
/// edit [component]. With [lockType] only [type] is offered: registering for
/// an empty anode slot cannot turn into a cathode.
Future<void> showComponentSheet(
  BuildContext context,
  InventoryController inventory, {
  Component? component,
  ComponentType? type,
  Cell? cell,
  bool lockType = false,
}) => showAppSheet<void>(
  context,
  (_) => _ComponentSheet(
    inventory: inventory,
    component: component,
    initialType: type,
    initialCell: cell,
    lockType: lockType && type != null,
  ),
);

/// Move [component] to a cell with room for it.
Future<void> showAssignSheet(BuildContext context, InventoryController inventory, Component component) =>
    showAppSheet<void>(context, (_) => _AssignSheet(inventory: inventory, component: component));

/// Two-tile cathode / anode picker.
class _TypeSelector extends StatelessWidget {
  const _TypeSelector({required this.value, required this.onChanged, this.types = ComponentType.values});

  final ComponentType value;
  final ValueChanged<ComponentType>? onChanged;
  final List<ComponentType> types;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('TIPO', style: AppTheme.label),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final type in types) ...[
              if (type != types.first) const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  borderRadius: AppRadius.medium,
                  onTap: onChanged == null ? null : () => onChanged!(type),
                  child: Container(
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: AppRadius.medium,
                      color: value == type ? const Color(0xFFEEF3FF) : Colors.white,
                      border: Border.all(
                        color: value == type ? AppColors.blue : AppColors.border,
                        width: value == type ? 1.5 : 1,
                      ),
                    ),
                    child: Text(
                      type.label,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: value == type ? AppColors.blue : AppColors.muted,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Create (component == null) or edit a component.
class _ComponentSheet extends StatefulWidget {
  const _ComponentSheet({
    required this.inventory,
    this.component,
    this.initialType,
    this.initialCell,
    this.lockType = false,
  });

  final InventoryController inventory;
  final Component? component;
  final ComponentType? initialType;
  final Cell? initialCell;
  final bool lockType;

  @override
  State<_ComponentSheet> createState() => _ComponentSheetState();
}

class _ComponentSheetState extends State<_ComponentSheet> with SubmitState {
  final _formKey = GlobalKey<FormState>();

  /// Only the digits are typed; the type letter is put in front (C-001, A-001).
  /// Older codes (CAT-001) keep just their digits when edited.
  late final _serial = TextEditingController(text: widget.component?.serialCode.replaceAll(RegExp(r'\D'), '') ?? '');

  String get _serialCode => '${_type.letter}-${_serial.text.trim()}';
  late ComponentType _type = widget.component?.type ?? widget.initialType ?? ComponentType.cathode;
  late Cell? _cell = widget.initialCell;

  bool get _editing => widget.component != null;

  @override
  void dispose() {
    _serial.dispose();
    super.dispose();
  }

  /// Creating is always allowed so an empty form is answered with the
  /// "required field" message; editing needs an actual change.
  bool get _canSave {
    if (!_editing) return true;
    return _serialCode != widget.component!.serialCode || _type != widget.component!.type;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final serial = _serialCode;

    final ok = await submit(
      () => _editing
          ? widget.inventory.editComponent(widget.component!, type: _type, serialCode: serial)
          : widget.inventory.createComponent(type: _type, serialCode: serial, cell: _cell),
    );
    if (ok) {
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text(_editing ? 'Componente actualizado.' : '${_type.label} $serial registrado.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // One cathode and one anode per cell: only cells with room for this type.
    final cells = widget.inventory.cellsAccepting(_type);
    if (_cell != null && !cells.contains(_cell)) _cell = null;

    return SheetFrame(
      title: _editing ? 'Editar componente' : 'Nuevo componente',
      children: [
        _TypeSelector(
          value: _type,
          types: widget.lockType ? [_type] : ComponentType.values,
          onChanged: loading || widget.lockType ? null : (t) => setState(() => _type = t),
        ),
        const SizedBox(height: 20),
        Form(
          key: _formKey,
          child: AppTextField(
            label: 'Código de serie',
            hint: '001',
            prefixText: '${_type.letter}-',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            controller: _serial,
            textInputAction: TextInputAction.done,
            validator: Validators.serialNumber,
            onSubmitted: (_) => _canSave ? _save() : null,
            enabled: !loading,
          ),
        ),
        if (!_editing) ...[
          const SizedBox(height: 20),
          AppDropdown<Cell?>(
            label: 'Asignar a celda (opcional)',
            value: _cell,
            hint: 'Sin asignar',
            items: {for (final c in cells) c: 'Celda ${c.name}'},
            onChanged: loading ? null : (c) => setState(() => _cell = c),
          ),
          if (cells.isEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Todas las celdas activas ya tienen un ${_type.label.toLowerCase()} asignado.',
              style: const TextStyle(fontSize: 13, color: AppColors.muted),
            ),
          ],
        ],
        const SizedBox(height: 20),
        if (error != null) ...[ErrorBanner(error!), const SizedBox(height: 16)],
        ListenableBuilder(
          listenable: _serial,
          builder: (context, _) => PrimaryButton(
            color: AppColors.teal,
            label: _editing ? 'Guardar cambios' : 'Registrar componente',
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

/// Pick the active cell a component goes to.
class _AssignSheet extends StatefulWidget {
  const _AssignSheet({required this.inventory, required this.component});

  final InventoryController inventory;
  final Component component;

  @override
  State<_AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends State<_AssignSheet> with SubmitState {
  Cell? _selected;

  Future<void> _assign() async {
    final cell = _selected!;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final ok = await submit(() => widget.inventory.assignComponent(widget.component, cell));
    if (ok) {
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('${widget.component.serialCode} asignado a la celda ${cell.name}.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // The component's current cell is not an option, and neither is a cell
    // that already has one of this type (use "Intercambiar" for those).
    final cells = widget.inventory
        .cellsAccepting(widget.component.type, exceptComponentId: widget.component.id)
        .where((c) => c.id != widget.component.cellId)
        .toList();

    return SheetFrame(
      title: 'Asignar ${widget.component.serialCode}',
      children: [
        if (cells.isEmpty)
          InfoBox(
            text:
                'No hay celdas con espacio para un ${widget.component.type.label.toLowerCase()}: '
                'cada celda admite uno solo. Para moverlo entre celdas usa "Intercambiar".',
          )
        else
          AppDropdown<Cell>(
            label: 'Celda',
            value: _selected,
            hint: 'Selecciona una celda',
            items: {for (final c in cells) c: 'Celda ${c.name}'},
            onChanged: loading ? null : (c) => setState(() => _selected = c),
          ),
        const SizedBox(height: 20),
        if (error != null) ...[ErrorBanner(error!), const SizedBox(height: 16)],
        PrimaryButton(
          color: AppColors.teal,
          label: 'Asignar',
          loading: loading,
          onPressed: _selected == null ? null : _assign,
        ),
        const SizedBox(height: 12),
        SecondaryButton(label: 'Cancelar', onPressed: loading ? null : () => Navigator.pop(context)),
      ],
    );
  }
}
