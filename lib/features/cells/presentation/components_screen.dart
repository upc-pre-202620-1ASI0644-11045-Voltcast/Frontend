import 'package:flutter/material.dart';
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
import '../data/component.dart';
import 'cells_screen.dart' show LoadErrorView;
import 'inventory_controller.dart';

class ComponentsScreen extends StatefulWidget {
  const ComponentsScreen({super.key});

  @override
  State<ComponentsScreen> createState() => _ComponentsScreenState();
}

class _ComponentsScreenState extends State<ComponentsScreen> {
  /// null = all.
  ComponentType? _filter;

  Future<void> _disable(Component component) async {
    final inventory = context.read<InventoryController>();
    final ok = await confirmDialog(
      context,
      title: '¿Deshabilitar ${component.type.label.toLowerCase()}?',
      message: '${component.serialCode} quedará fuera de uso y se conservará su historial.',
      action: 'Deshabilitar',
    );
    if (ok && mounted) {
      await runAction(context, () => inventory.disableComponent(component), '${component.serialCode} deshabilitado.');
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
              title: 'Componentes',
              subtitle: 'Cátodos y ánodos',
              onBack: () => context.canPop() ? context.pop() : context.go('/cells'),
              action: HeaderAction(
                label: 'Nuevo',
                onPressed: inventory.hasLoaded
                    ? () => showAppSheet<void>(context, (_) => _ComponentSheet(inventory: inventory))
                    : null,
              ),
            ),
            Expanded(child: _body(inventory)),
          ],
        ),
      ),
    );
  }

  Widget _body(InventoryController inventory) {
    if (!inventory.hasLoaded) {
      if (inventory.loading) {
        return const Center(child: CircularProgressIndicator(color: AppColors.blue));
      }
      return LoadErrorView(message: inventory.loadError ?? 'No se pudo cargar.', onRetry: inventory.load);
    }

    final all = inventory.components;
    final visible = all.where((c) => _filter == null || c.type == _filter).toList();
    // Active first; disabled ones stay listed (history is kept).
    final ordered = [...visible.where((c) => c.isActive), ...visible.where((c) => !c.isActive)];

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
              StatTile(label: 'Registrados', value: all.length),
              StatTile(label: 'En uso', value: inventory.componentsInUse, color: AppColors.blue),
              StatTile(label: 'Libres', value: inventory.componentsFree),
            ],
          ),
          const SizedBox(height: 14),
          _TypeFilter(value: _filter, onChanged: (v) => setState(() => _filter = v)),
          const SizedBox(height: 14),
          if (ordered.isEmpty)
            InfoBox(
              text: all.isEmpty
                  ? 'Aún no hay componentes registrados. Crea el primero con "Nuevo".'
                  : 'No hay componentes de este tipo.',
            )
          else
            InventoryCard(
              title: 'Inventario',
              trailing: '${ordered.length} ${ordered.length == 1 ? 'componente' : 'componentes'}',
              children: [
                for (final component in ordered)
                  _ComponentTile(
                    component: component,
                    cell: inventory.cellById(component.cellId),
                    busy: inventory.isComponentBusy(component.id),
                    onEdit: () => showAppSheet<void>(
                      context,
                      (_) => _ComponentSheet(inventory: inventory, component: component),
                    ),
                    onAssign: () => showAppSheet<void>(
                      context,
                      (_) => _AssignSheet(inventory: inventory, component: component),
                    ),
                    onDisable: () => _disable(component),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _TypeFilter extends StatelessWidget {
  const _TypeFilter({required this.value, required this.onChanged});

  final ComponentType? value;
  final ValueChanged<ComponentType?> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, ComponentType? type) {
      final selected = value == type;
      return Expanded(
        child: InkWell(
          borderRadius: AppRadius.medium,
          onTap: () => onChanged(type),
          child: Container(
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: AppRadius.medium,
              color: selected ? AppColors.ink : Colors.white,
              border: Border.all(color: selected ? AppColors.ink : const Color(0xFFF0F1F4)),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppColors.muted,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip('Todos', null),
        const SizedBox(width: 8),
        chip('Cátodos', ComponentType.cathode),
        const SizedBox(width: 8),
        chip('Ánodos', ComponentType.anode),
      ],
    );
  }
}

class _ComponentTile extends StatelessWidget {
  const _ComponentTile({
    required this.component,
    required this.cell,
    required this.busy,
    required this.onEdit,
    required this.onAssign,
    required this.onDisable,
  });

  final Component component;
  final Cell? cell;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onAssign;
  final VoidCallback onDisable;

  @override
  Widget build(BuildContext context) {
    final isCathode = component.type == ComponentType.cathode;
    final subtitle = !component.isActive
        ? 'Deshabilitado'
        : component.isInUse
            ? 'Asignado a celda ${cell?.name ?? '#${component.cellId}'}'
            : 'Disponible para asignar';
    final pill = !component.isActive
        ? StatusPill.of('Inactivo', StatusPill.grey)
        : component.isInUse
            ? StatusPill.of('En uso', StatusPill.blue)
            : StatusPill.of('Libre', StatusPill.green);

    return Opacity(
      opacity: component.isActive ? 1 : 0.55,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isCathode ? const Color(0xFFEEF3FF) : AppColors.violetSoft,
                    borderRadius: AppRadius.medium,
                  ),
                  child: Text(
                    component.type.letter,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: isCathode ? AppColors.blue : const Color(0xFF9333EA),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${component.type.label} · ${component.serialCode}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.ink),
                      ),
                      const SizedBox(height: 2),
                      Text(subtitle, style: const TextStyle(fontSize: 14, color: AppColors.muted)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                pill,
              ],
            ),
            if (component.isActive) ...[
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.blue),
                      )
                    : Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.end,
                        children: [
                          SmallActionButton(label: 'Editar', onPressed: onEdit),
                          SmallActionButton(
                            label: component.isInUse ? 'Reasignar' : 'Asignar',
                            color: AppColors.teal,
                            onPressed: onAssign,
                          ),
                          // A component in use must be moved or its cell disabled
                          // first: the backend refuses to disable it.
                          SmallActionButton(
                            label: 'Deshabilitar',
                            color: AppColors.error,
                            onPressed: component.isInUse ? null : onDisable,
                          ),
                        ],
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Two-tile cathode / anode picker.
class _TypeSelector extends StatelessWidget {
  const _TypeSelector({required this.value, required this.onChanged});

  final ComponentType value;
  final ValueChanged<ComponentType>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('TIPO', style: AppTheme.label),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final type in ComponentType.values) ...[
              if (type.index > 0) const SizedBox(width: 12),
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
  const _ComponentSheet({required this.inventory, this.component});

  final InventoryController inventory;
  final Component? component;

  @override
  State<_ComponentSheet> createState() => _ComponentSheetState();
}

class _ComponentSheetState extends State<_ComponentSheet> with SubmitState {
  final _formKey = GlobalKey<FormState>();
  late final _serial = TextEditingController(text: widget.component?.serialCode ?? '');
  late ComponentType _type = widget.component?.type ?? ComponentType.cathode;
  Cell? _cell;

  bool get _editing => widget.component != null;

  @override
  void dispose() {
    _serial.dispose();
    super.dispose();
  }

  bool get _canSave {
    final serial = _serial.text.trim();
    if (serial.isEmpty) return false;
    if (!_editing) return true;
    return serial != widget.component!.serialCode || _type != widget.component!.type;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final serial = _serial.text.trim();

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
    final cells = widget.inventory.activeCells;

    return SheetFrame(
      title: _editing ? 'Editar componente' : 'Nuevo componente',
      children: [
        _TypeSelector(value: _type, onChanged: loading ? null : (t) => setState(() => _type = t)),
        const SizedBox(height: 20),
        Form(
          key: _formKey,
          child: AppTextField(
            label: 'Código de serie',
            hint: _type == ComponentType.cathode ? 'CAT-001' : 'ANO-001',
            controller: _serial,
            textInputAction: TextInputAction.done,
            validator: Validators.serialCode,
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
        ],
        const SizedBox(height: 20),
        if (error != null) ...[
          ErrorBanner(error!),
          const SizedBox(height: 16),
        ],
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
    final cells = widget.inventory.activeCells;

    return SheetFrame(
      title: 'Asignar ${widget.component.serialCode}',
      children: [
        if (cells.isEmpty)
          const InfoBox(text: 'No hay celdas activas. Crea una celda primero.')
        else
          AppDropdown<Cell>(
            label: 'Celda',
            value: _selected,
            hint: 'Selecciona una celda',
            items: {
              for (final c in cells)
                c: c.id == widget.component.cellId ? 'Celda ${c.name} (actual)' : 'Celda ${c.name}',
            },
            onChanged: loading ? null : (c) => setState(() => _selected = c),
          ),
        const SizedBox(height: 20),
        if (error != null) ...[
          ErrorBanner(error!),
          const SizedBox(height: 16),
        ],
        PrimaryButton(
          color: AppColors.teal,
          label: 'Asignar',
          loading: loading,
          onPressed: _selected == null || _selected!.id == widget.component.cellId ? null : _assign,
        ),
        const SizedBox(height: 12),
        SecondaryButton(label: 'Cancelar', onPressed: loading ? null : () => Navigator.pop(context)),
      ],
    );
  }
}
