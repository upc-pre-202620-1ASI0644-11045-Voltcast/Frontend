import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/dialogs.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_header.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/auth_visuals.dart';
import '../../../core/widgets/screen_header.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/component.dart';
import 'cell_actions.dart' show LoadErrorView;
import 'cell_screen.dart' show FreeComponentScreen;
import 'component_actions.dart';
import 'inventory_controller.dart';
import 'component_rotable_bar.dart';
import '../../home/settings_menu.dart';

enum _Filter { all, free, disabled, anode, cathode }

/// Anodes and cathodes outside the cells: the freed ones, ready to assign, and
/// the disabled ones (kept for their history). Each is shown as its bar.
class StorageScreen extends StatefulWidget {
  const StorageScreen({super.key});

  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  _Filter _filter = _Filter.all;

  /// What is typed in the search box, lower-cased.
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryController>();
    // Absent in screen tests that mount the storage alone.
    final auth = Provider.of<AuthController?>(context, listen: false);

    final header = BrandHeader(
      eyebrow: 'Ánodos y cátodos',
      title: 'Inventario',
      onLogout: auth?.logout,
      onSettings: settingsAction(context),
      action: HeaderAction(
        label: 'Nuevo',
        onPressed: inventory.hasLoaded ? () => showComponentSheet(context, inventory) : null,
      ),
      bottom: inventory.hasLoaded
          ? StatRow(
              tiles: [
                StatTile(label: 'Registrados', value: inventory.components.length),
                StatTile(label: 'Libres', value: inventory.componentsFree, color: AppColors.success),
                StatTile(
                  label: 'Deshabilitados',
                  value: inventory.components.where((c) => !c.isActive).length,
                  color: AppColors.muted,
                ),
              ],
            )
          : null,
    );

    return Scaffold(backgroundColor: AppColors.surface, body: _body(context, inventory, header));
  }

  Widget _body(BuildContext context, InventoryController inventory, Widget header) {
    if (!inventory.hasLoaded) {
      return Column(
        children: [
          header,
          Expanded(
            child: inventory.loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.blue))
                : LoadErrorView(message: inventory.loadError ?? 'No se pudo cargar.', onRetry: inventory.load),
          ),
        ],
      );
    }

    // In use, a component lives in its cell: the storage has the rest.
    final stored = inventory.components.where((c) => !c.isInUse).toList();
    int count(_Filter f) => stored.where((c) => _matches(c, f)).length;
    final shown = stored
        .where((c) => _matches(c, _filter) && (_query.isEmpty || c.serialCode.toLowerCase().contains(_query)))
        .toList();

    final chips = [
      (_Filter.all, 'Todos'),
      (_Filter.free, 'Libres · ${count(_Filter.free)}'),
      (_Filter.disabled, 'Deshabilitados · ${count(_Filter.disabled)}'),
      (_Filter.anode, 'Ánodos · ${count(_Filter.anode)}'),
      (_Filter.cathode, 'Cátodos · ${count(_Filter.cathode)}'),
    ];

    return RefreshIndicator(
      color: AppColors.blue,
      onRefresh: inventory.load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: header),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (inventory.loadError != null) ...[ErrorBanner(inventory.loadError!), const SizedBox(height: 16)],
                  if (stored.isEmpty)
                    const InfoBox(text: 'Todos los componentes están en sus celdas. Registra uno nuevo con "Nuevo".')
                  else
                    SearchField(onChanged: (text) => setState(() => _query = text.trim().toLowerCase())),
                ],
              ),
            ),
          ),
          if (stored.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: SizedBox(
                height: 60,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  itemCount: chips.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => _FilterChip(
                    label: chips[i].$2,
                    selected: _filter == chips[i].$1,
                    onTap: () => setState(() => _filter = chips[i].$1),
                  ),
                ),
              ),
            ),
            if (shown.isEmpty)
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                sliver: SliverToBoxAdapter(child: InfoBox(text: 'Ningún componente coincide con el filtro.')),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              // Built lazily: only the bars on screen are painted.
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisExtent: 268,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: shown.length,
                itemBuilder: (context, i) => _StoredComponent(
                  key: ValueKey('storage-${shown[i].id}'),
                  component: shown[i],
                  busy: inventory.isComponentBusy(shown[i].id),
                ),
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  static bool _matches(Component c, _Filter f) => switch (f) {
    _Filter.all => true,
    _Filter.free => c.isFree,
    _Filter.disabled => !c.isActive,
    _Filter.anode => c.type == ComponentType.anode,
    _Filter.cathode => c.type == ComponentType.cathode,
  };
}

/// Rounded filter pill: dark when selected.
class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppColors.ink : Colors.white,
        shape: const StadiumBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : AppColors.ink,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One stored component: its bar (turned with the finger), state, type,
/// serial and its actions.
class _StoredComponent extends StatelessWidget {
  const _StoredComponent({super.key, required this.component, required this.busy});

  final Component component;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final inventory = context.read<InventoryController>();
    final c = component;

    // A free one opens its detail; a disabled one only offers its two buttons.
    return GestureDetector(
      onTap: c.isFree && !busy
          ? () =>
                Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => FreeComponentScreen(componentId: c.id)))
          : null,
      child: AppCard(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFEFF4FC), Color(0xFFDCE6F5)],
                  ),
                ),
                child: Stack(
                  children: [
                    // Faded when disabled; its actions stay at full strength.
                    Positioned.fill(
                      child: Opacity(
                        opacity: c.isActive ? 1 : 0.55,
                        child: RotatableBar(key: ValueKey('storage-bar-${c.id}'), type: c.type, serial: c.serialCode),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: c.isActive
                          ? StatusPill.of('Libre', StatusPill.green)
                          : StatusPill.of('Deshabilitado', StatusPill.grey),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.type.label.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                      color: AppColors.muted,
                    ),
                  ),
                  Text(
                    c.serialCode,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: c.isActive
                        ? [
                            CircleAction(
                              tooltip: 'Editar componente',
                              icon: Icons.edit_outlined,
                              size: 36,
                              onPressed: busy ? null : () => showComponentSheet(context, inventory, component: c),
                            ),
                            const SizedBox(width: 8),
                            CircleAction(
                              tooltip: 'Deshabilitar componente',
                              icon: Icons.delete_outline,
                              color: AppColors.error,
                              background: AppColors.errorSoft,
                              size: 36,
                              onPressed: busy ? null : () => disableComponentWithChecks(context, c),
                            ),
                          ]
                        : [
                            Expanded(
                              child: SizedBox(
                                height: 36,
                                child: TextButton(
                                  onPressed: busy
                                      ? null
                                      : () => runAction(
                                          context,
                                          () => inventory.reactivateComponent(c),
                                          '${c.serialCode} reactivado.',
                                        ),
                                  style: TextButton.styleFrom(
                                    backgroundColor: AppColors.blueSoft,
                                    foregroundColor: AppColors.blue,
                                    shape: const StadiumBorder(),
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                                  ),
                                  child: const Text('Reactivar', maxLines: 1, overflow: TextOverflow.ellipsis),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            CircleAction(
                              tooltip: 'Eliminar componente',
                              icon: Icons.delete_outline,
                              color: AppColors.error,
                              background: AppColors.errorSoft,
                              size: 36,
                              onPressed: busy ? null : () => _remove(context, inventory),
                            ),
                          ],
                  ),
                ],
              ),
            ),
          ],
        ),
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
