import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dialogs.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_header.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/auth_visuals.dart';
import '../../../core/widgets/screen_header.dart';
import '../data/component.dart';
import 'cell_actions.dart' show LoadErrorView;
import 'component_actions.dart';
import 'inventory_controller.dart';
import 'component_rotable_bar.dart';

/// Anodes and cathodes outside the cells: the freed ones, ready to assign, and
/// the disabled ones (kept for their history). Each is shown as its bar.
class StorageScreen extends StatelessWidget {
  const StorageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryController>();

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: 'Inventario',
              subtitle: 'Ánodos y cátodos sin asignar',
              action: HeaderAction(
                label: 'Nuevo',
                onPressed: inventory.hasLoaded ? () => showComponentSheet(context, inventory) : null,
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
      if (inventory.loading) return const Center(child: CircularProgressIndicator(color: AppColors.blue));
      return LoadErrorView(message: inventory.loadError ?? 'No se pudo cargar.', onRetry: inventory.load);
    }

    final freed = inventory.components.where((c) => c.isFree).toList();
    final disabled = inventory.components.where((c) => !c.isActive).toList();

    List<Widget> section(String title, List<Component> components) => [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
        sliver: SliverToBoxAdapter(child: Text('${title.toUpperCase()} · ${components.length}', style: AppTheme.label)),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        // Built lazily: only the bars on screen are painted.
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisExtent: 300,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: components.length,
          itemBuilder: (context, i) => _StoredComponent(
            key: ValueKey('storage-${components[i].id}'),
            component: components[i],
            busy: inventory.isComponentBusy(components[i].id),
          ),
        ),
      ),
    ];

    return RefreshIndicator(
      color: AppColors.blue,
      onRefresh: inventory.load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (inventory.loadError != null) ...[ErrorBanner(inventory.loadError!), const SizedBox(height: 16)],
                  StatRow(
                    tiles: [
                      StatTile(label: 'Registrados', value: inventory.components.length),
                      StatTile(label: 'En uso', value: inventory.componentsInUse, color: AppColors.blue),
                      StatTile(label: 'Libres', value: inventory.componentsFree),
                    ],
                  ),
                  if (freed.isEmpty && disabled.isEmpty) ...[
                    const SizedBox(height: 16),
                    const InfoBox(text: 'Todos los componentes están en sus celdas. Registra uno nuevo con "Nuevo".'),
                  ],
                ],
              ),
            ),
          ),
          if (freed.isNotEmpty) ...section('Liberados', freed),
          if (disabled.isNotEmpty) ...section('Deshabilitados', disabled),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

/// One stored component: its bar (turned with the finger), serial, state and,
/// while active, its actions.
class _StoredComponent extends StatelessWidget {
  const _StoredComponent({super.key, required this.component, required this.busy});

  final Component component;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final inventory = context.read<InventoryController>();
    final c = component;

    Widget action(String tooltip, IconData icon, Color color, VoidCallback onPressed) => IconButton(
      tooltip: tooltip,
      onPressed: busy ? null : onPressed,
      icon: Icon(icon, size: 20),
      color: color,
      visualDensity: VisualDensity.compact,
    );

    return AppCard(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
      child: Column(
        children: [
          // Faded when disabled; its actions stay at full strength.
          Expanded(
            child: Opacity(
              opacity: c.isActive ? 1 : 0.55,
              child: Column(
                children: [
                  Expanded(
                    child: RotatableBar(key: ValueKey('storage-bar-${c.id}'), type: c.type, serial: c.serialCode),
                  ),
                  Text(
                    '${c.type.label} · ${c.serialCode}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink),
                  ),
                  const SizedBox(height: 6),
                  c.isActive
                      ? StatusPill.of('Libre', StatusPill.green)
                      : StatusPill.of('Deshabilitado', StatusPill.grey),
                ],
              ),
            ),
          ),
          if (c.isActive)
            SizedBox(
              height: 44,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  action(
                    'Editar componente',
                    Icons.edit_outlined,
                    AppColors.blue,
                    () => showComponentSheet(context, inventory, component: c),
                  ),
                  action(
                    'Asignar a una celda',
                    Icons.input,
                    AppColors.teal,
                    () => showAssignSheet(context, inventory, c),
                  ),
                  action(
                    'Deshabilitar componente',
                    Icons.delete_outline,
                    AppColors.error,
                    () => disableComponentWithChecks(context, c),
                  ),
                ],
              ),
            )
          else ...[
            const SizedBox(height: 8),
            SmallActionButton(
              label: 'Reactivar',
              color: AppColors.teal,
              onPressed: busy
                  ? null
                  : () => runAction(context, () => inventory.reactivateComponent(c), '${c.serialCode} reactivado.'),
            ),
            action('Eliminar componente', Icons.delete_outline, AppColors.error, () => _remove(context, inventory)),
          ],
        ],
      ),
    );
  }

  /// Hides a disabled component; registering its code again brings it back.
  Future<void> _remove(BuildContext context, InventoryController inventory) async {
    final ok = await confirmDialog(
      context,
      title: '¿Eliminar ${component.serialCode}?',
      message: 'Dejará de mostrarse. Si vuelves a registrar este código, se recuperará.',
      action: 'Eliminar',
    );
    if (ok && context.mounted) {
      await runAction(context, () => inventory.hideComponent(component), '${component.serialCode} eliminado.');
    }
  }
}
