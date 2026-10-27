import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../data/cell.dart';
import 'inventory_controller.dart';

/// US011, the cell's trash button. A cell without components is removed from
/// view after a confirmation (E01); creating one with the same name brings it
/// back. One that still has components is refused with a message (E02) and the
/// user may choose to release them, which leaves the cell inactive (E03).
Future<void> removeCellWithChecks(BuildContext context, Cell cell) async {
  final inventory = context.read<InventoryController>();

  if (inventory.componentsOf(cell.id).isEmpty) {
    final ok = await confirmDialog(
      context,
      title: '¿Eliminar la celda ${cell.name}?',
      message: 'Dejará de mostrarse. Si vuelves a crear la celda ${cell.name}, se recuperará.',
      action: 'Eliminar',
    );
    if (!ok || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await inventory.hideCell(cell);
      messenger.showSnackBar(SnackBar(content: Text('Celda ${cell.name} eliminada.')));
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
    message:
        'No se puede eliminar la celda ${cell.name} mientras tenga '
        '${serials.isEmpty ? 'componentes' : serials} asignados. Puedes liberarlos: '
        'quedarán disponibles y la celda pasará a inactiva.',
    action: 'Liberar componentes',
  );
  if (release && context.mounted) {
    await runAction(
      context,
      () => inventory.releaseCell(cell),
      'Componentes de la celda ${cell.name} liberados. La celda quedó inactiva.',
    );
  }
}

/// Create (cell == null) or rename a cell.
Future<void> showCellSheet(BuildContext context, InventoryController inventory, {Cell? cell}) =>
    showAppSheet<void>(context, (_) => _CellSheet(inventory: inventory, cell: cell));

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
        const Text('Una letra seguida de un número: A1, B12…', style: TextStyle(fontSize: 13, color: AppColors.muted)),
        const SizedBox(height: 20),
        if (error != null) ...[ErrorBanner(error!), const SizedBox(height: 16)],
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
