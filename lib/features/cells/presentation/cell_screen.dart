import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/dialogs.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_header.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/auth_visuals.dart';
import '../../../core/widgets/screen_header.dart';
import '../data/cell.dart';
import '../data/component.dart';
import 'cell_sounds.dart';
import 'cell_actions.dart' show LoadErrorView, removeCellWithChecks, showCellSheet, swapWithConfirmation;
import 'component_actions.dart' show disableComponentWithChecks, showComponentSheet;
import 'inventory_controller.dart';
import 'component_rotable_bar.dart';
import 'sync_banner.dart';

const _tileExtent = 212.0;

/// Every cell from the backend, one horizontal row per section (the letter of
/// its name: A1, A2… then B1…). A cell with both components is shown closed;
/// once opened, its anode and cathode can be dragged onto another open cell to
/// swap them, or tapped to fly into a view of that bar with the component as
/// the backend has it now.
class ProductionLineScreen extends StatefulWidget {
  const ProductionLineScreen({super.key, this.userName, this.userRole, this.onLogout});

  /// First name for the greeting; the home tab passes the signed-in user's.
  final String? userName;

  /// "Supervisor", "Ingeniero de Planta": shown above the greeting.
  final String? userRole;
  final VoidCallback? onLogout;

  @override
  State<ProductionLineScreen> createState() => _ProductionLineScreenState();
}

class _ProductionLineScreenState extends State<ProductionLineScreen> with TickerProviderStateMixin {
  final _scroll = ScrollController();
  final _stackKey = GlobalKey();
  final _listKey = GlobalKey();
  final _tileKeys = <String, GlobalKey>{};

  /// Section letter of each cell as last laid out. Part of its keys: a cell
  /// renamed into another section is built anew in that row, not moved there.
  final _sectionOf = <int, String>{};

  /// One horizontal row per section letter, so a drag can scroll it sideways.
  final _rowKeys = <String, GlobalKey>{};
  final _rowPages = <String, PageController>{};

  /// What is typed in the search box, lower-cased.
  String _query = '';

  /// One per bar (`cellId-type`): the zoom starts from and returns to it.
  final _barKeys = <String, GlobalKey>{};
  late final _zoom = AnimationController(vsync: this, duration: const Duration(milliseconds: 750));

  /// Complete cells the user opened. A complete cell not listed here is closed.
  final _opened = <int>{};

  /// Bars travelling between cells after a swap is confirmed.
  List<({Component component, Rect from, Rect to})> _flights = const [];
  late final _flight = AnimationController(vsync: this, duration: const Duration(milliseconds: 750));

  /// A component is being dragged: moving near the list's edges scrolls it.
  bool _dragging = false;

  int? _cellId;
  ComponentType _focus = ComponentType.anode;
  Rect? _origin;
  DateTime? _refreshedAt;

  @override
  void initState() {
    super.initState();
    CellSounds.preload();
  }

  @override
  void dispose() {
    _zoom.dispose();
    _flight.dispose();
    _scroll.dispose();
    for (final c in _rowPages.values) {
      c.dispose();
    }
    super.dispose();
  }

  GlobalKey _barKey(int cellId, ComponentType type) =>
      _barKeys.putIfAbsent('${_sectionOf[cellId]}$cellId-${type.name}', GlobalKey.new);
  GlobalKey _tileKey(int cellId) => _tileKeys.putIfAbsent('${_sectionOf[cellId]}$cellId', GlobalKey.new);

  Rect? _rectOf(GlobalKey? key) {
    final box = key?.currentContext?.findRenderObject() as RenderBox?;
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || stack == null || !box.attached) return null;
    return box.localToGlobal(Offset.zero, ancestor: stack) & box.size;
  }

  Rect? _originOf(int cellId, ComponentType type) => _rectOf(_barKey(cellId, type)) ?? _rectOf(_tileKey(cellId));

  void _open(Cell cell) => setState(() => _opened.add(cell.id));

  Future<void> _enter(Cell cell, ComponentType focus) async {
    if (_cellId != null || _zoom.isAnimating) return;

    // Travel along the line (and its row) until the cell is centred, then dive into the bar.
    final tile = _tileKey(cell.id).currentContext;
    if (tile != null) {
      await Scrollable.ensureVisible(
        tile,
        alignment: 0.5,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOutCubic,
      );
    }
    if (!mounted) return;

    setState(() {
      _cellId = cell.id;
      _focus = focus;
      _origin = _originOf(cell.id, focus);
    });
    _zoom.forward(from: 0);
    _refresh();
  }

  /// There is no per-id endpoint: the lists are fetched again and the panel
  /// reads the component with that id from them.
  Future<void> _refresh() async {
    await context.read<InventoryController>().load();
    if (mounted) setState(() => _refreshedAt = DateTime.now());
  }

  /// While a component is dragged near the top or bottom of the list, scroll
  /// it, and near the sides of a section's row, turn to the next or previous
  /// cell, so the drop can reach any of the cells. Fed by a listener around the list, not by the dragged tile: that
  /// tile is disposed once scrolled away.
  void _autoScroll(Offset globalPosition) {
    if (!_dragging) return;
    const step = 24.0;
    void nudge(ScrollController controller, double at, double extent, double edge) {
      final delta = at < edge ? -step : (at > extent - edge ? step : 0.0);
      if (delta == 0 || !controller.hasClients) return;
      final position = controller.position;
      controller.jumpTo((position.pixels + delta).clamp(position.minScrollExtent, position.maxScrollExtent));
    }

    RenderBox? boxOf(GlobalKey key) => key.currentContext?.findRenderObject() as RenderBox?;
    final list = boxOf(_listKey);
    if (list != null) nudge(_scroll, list.globalToLocal(globalPosition).dy, list.size.height, 90);
    for (final MapEntry(key: section, value: key) in _rowKeys.entries) {
      final row = boxOf(key);
      if (row == null || !row.attached) continue;
      final at = row.globalToLocal(globalPosition);
      if (at.dy < 0 || at.dy > row.size.height) continue;
      final pages = _rowPages[section]!;
      // One cell per page: wait for a turn to finish before taking the next.
      // Narrow edges: the anode of a card sits close to the left one.
      if (!pages.hasClients || pages.position.isScrollingNotifier.value) continue;
      const turn = Duration(milliseconds: 300);
      if (at.dx > row.size.width - 32) pages.nextPage(duration: turn, curve: Curves.easeOutCubic);
      if (at.dx < 32) pages.previousPage(duration: turn, curve: Curves.easeOutCubic);
    }
  }

  /// Once the swap is confirmed, each bar flies over to the other's slot while
  /// the request runs; afterwards they show in their new cells.
  void _swap(Component dragged, Component? target) {
    if (target == null) {
      // Same type onto an empty slot: there is nothing to exchange it with.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El intercambio no se puede realizar porque no hay un componente disponible.')),
      );
      return;
    }
    swapWithConfirmation(
      context,
      dragged,
      target,
      onConfirmed: () {
        final from = _rectOf(_barKey(dragged.cellId!, dragged.type));
        final to = _rectOf(_barKey(target.cellId!, target.type));
        if (from == null || to == null) return; // a cell scrolled away: just swap
        setState(() {
          _flights = [(component: dragged, from: from, to: to), (component: target, from: to, to: from)];
        });
        _flight.forward(from: 0).whenComplete(() {
          if (mounted) setState(() => _flights = const []);
        });
      },
    );
  }

  Widget _flyingBar(({Component component, Rect from, Rect to}) flight, int index) {
    return AnimatedBuilder(
      animation: _flight,
      builder: (context, _) {
        final t = Curves.easeInOutCubic.transform(_flight.value);
        // Up out of the bath, over to the other cell and down into its slot;
        // the two bars curve to opposite sides so they pass each other.
        final arc = sin(pi * t);
        final side = index == 0 ? 1.0 : -1.0;
        final rect = Rect.lerp(flight.from, flight.to, t)!.shift(Offset(side * arc * 70, -arc * 30));
        return Positioned.fromRect(
          rect: rect,
          child: IgnorePointer(
            child: Transform.rotate(
              key: ValueKey('flying-${flight.component.id}'),
              angle: -side * 0.25 * arc,
              child: Transform.scale(
                scale: 1 + 0.1 * arc,
                child: _ShadowedBar(
                  type: flight.component.type,
                  serial: flight.component.serialCode,
                  size: flight.from.size,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _exit() async {
    if (_cellId == null || _zoom.status == AnimationStatus.reverse) return;
    _origin = _originOf(_cellId!, _focus) ?? _origin;
    await _zoom.reverse();
    if (mounted) setState(() => _cellId = null);
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryController>();
    final selected = _cellId == null || !inventory.hasLoaded ? null : inventory.cellById(_cellId);

    return PopScope(
      canPop: selected == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exit();
      },
      child: Scaffold(backgroundColor: AppColors.surface, body: _body(inventory, selected)),
    );
  }

  /// Blue greeting with the cell figures; the first thing in the scroll view.
  Widget _header(InventoryController inventory) {
    final name = widget.userName;
    return BrandHeader(
      eyebrow: [
        ?widget.userRole,
        inventory.hasLoaded ? '${inventory.cells.length} celdas' : 'Línea de producción',
      ].join(' · '),
      // The home tab: the line is what the user lands on after signing in.
      title: name == null ? 'Celdas' : 'Hola, $name',
      onLogout: widget.onLogout,
      action: HeaderAction(
        label: 'Nueva',
        onPressed: inventory.hasLoaded ? () => showCellSheet(context, inventory) : null,
      ),
      bottom: inventory.hasLoaded
          ? StatRow(
              tiles: [
                StatTile(label: 'Registradas', value: inventory.cells.length),
                StatTile(label: 'Activas', value: inventory.activeCount, color: AppColors.success),
                StatTile(label: 'Inactivas', value: inventory.inactiveCount, color: AppColors.muted),
              ],
            )
          : null,
    );
  }

  Widget _body(InventoryController inventory, Cell? selected) {
    if (!inventory.hasLoaded) {
      return Column(
        children: [
          _header(inventory),
          Expanded(
            child: inventory.loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.blue))
                : LoadErrorView(message: inventory.loadError ?? 'No se pudo cargar.', onRetry: inventory.load),
          ),
        ],
      );
    }

    final cells = inventory.cells;

    // One pass over the components instead of a search per tile.
    final parts = <int, Map<ComponentType, Component>>{};
    for (final c in inventory.components) {
      if (c.isInUse) parts.putIfAbsent(c.cellId!, () => {})[c.type] ??= c;
    }
    // A cell that lost a component forgets it was opened, so it closes again
    // (with its animation) as soon as both are assigned once more.
    _opened.removeWhere((id) => parts[id]?.length != 2);

    return LayoutBuilder(
      builder: (context, box) {
        final full = Offset.zero & box.biggest;
        // Clipped: the line is scaled up during the zoom and must not cover the
        // header (a Stack alone only clips layout overflow, not transforms).
        return ClipRect(
          child: Stack(
            key: _stackKey,
            children: [
              AnimatedBuilder(
                animation: _zoom,
                builder: (context, child) {
                  final t = Curves.easeInOutCubic.transform(_zoom.value);
                  // The line rushes past the camera while we dive into the bar.
                  return Opacity(
                    opacity: 1 - 0.85 * t,
                    child: Transform.scale(scale: 1 + 1.5 * t, alignment: _alignmentOf(_origin, full), child: child),
                  );
                },
                child: IgnorePointer(ignoring: selected != null, child: _line(inventory, cells, parts)),
              ),
              for (var i = 0; i < _flights.length; i++) _flyingBar(_flights[i], i),
              if (selected != null)
                AnimatedBuilder(
                  animation: _zoom,
                  builder: (context, child) => _flyIn(full, child!),
                  child: _ComponentDetail(
                    cell: selected,
                    anode: parts[selected.id]?[ComponentType.anode],
                    cathode: parts[selected.id]?[ComponentType.cathode],
                    focus: _focus,
                    loading: inventory.loading,
                    error: inventory.loadError,
                    refreshedAt: _refreshedAt,
                    onFocus: (type) => setState(() => _focus = type),
                    onRefresh: _refresh,
                    onBack: _exit,
                    isBusy: inventory.isComponentBusy,
                    onEdit: (c) => showComponentSheet(context, inventory, component: c),
                    onDisable: (c) => disableComponentWithChecks(context, c),
                    onAssignFree: (type) => _pickFree(selected, type),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  static Alignment _alignmentOf(Rect? rect, Rect full) {
    if (rect == null || full.isEmpty) return Alignment.center;
    return Alignment(rect.center.dx / full.width * 2 - 1, rect.center.dy / full.height * 2 - 1);
  }

  Widget _flyIn(Rect full, Widget child) {
    final t = Curves.easeInOutCubic.transform(_zoom.value);
    final rect = Rect.lerp(_origin ?? full.deflate(full.shortestSide / 3), full, t)!;
    return Positioned.fromRect(
      rect: rect,
      child: IgnorePointer(
        ignoring: _zoom.isAnimating,
        child: Opacity(
          opacity: (t * 1.6).clamp(0.0, 1.0),
          child: Transform(
            alignment: Alignment.center,
            // Starts tilted like a bar seen from the aisle and straightens up on arrival.
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..rotateX((1 - t) * 0.5),
            child: ClipRect(
              child: FittedBox(
                fit: BoxFit.fill,
                child: SizedBox.fromSize(size: full.size, child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _line(InventoryController inventory, List<Cell> cells, Map<int, Map<ComponentType, Component>> parts) {
    // By code: the cell's name or barcode, or the serial of a bar in it.
    final shown = _query.isEmpty
        ? cells
        : cells.where((cell) {
            final codes = [
              cell.name,
              ?cell.barcodeValue,
              for (final c in parts[cell.id]?.values ?? const <Component>[]) c.serialCode,
            ];
            return codes.any((code) => code.toLowerCase().contains(_query));
          }).toList();
    // Cells come sorted (A1, A2… B1…), so each section is one run of the list.
    final sections = <String, List<Cell>>{};
    for (final cell in shown) {
      final letter = cell.name.isEmpty ? '?' : cell.name[0].toUpperCase();
      _sectionOf[cell.id] = letter;
      sections.putIfAbsent(letter, () => []).add(cell);
    }

    final top = Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (inventory.loadError != null) ...[ErrorBanner(inventory.loadError!), const SizedBox(height: 16)],
          const SyncStatusBanner(),
          if (cells.isEmpty)
            const InfoBox(text: 'Aún no hay celdas registradas. Crea la primera con "Nueva".')
          else ...[
            SearchField(onChanged: (text) => setState(() => _query = text.trim().toLowerCase())),
            if (shown.isEmpty) ...[
              const SizedBox(height: 16),
              const InfoBox(text: 'Ninguna celda coincide con la búsqueda.'),
            ],
          ],
        ],
      ),
    );

    Widget tile(Cell cell) {
      final anode = parts[cell.id]?[ComponentType.anode];
      final cathode = parts[cell.id]?[ComponentType.cathode];
      final complete = anode != null && cathode != null;
      final opened = _opened.contains(cell.id);
      // Inactive cells are edited and removed too: only a busy one waits.
      final actionable = !inventory.isCellBusy(cell.id);
      return RepaintBoundary(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: _CellTile(
            key: _tileKey(cell.id),
            cell: cell,
            anode: anode,
            cathode: cathode,
            closed: complete && !opened,
            busy: [anode, cathode].any((c) => c != null && inventory.isComponentBusy(c.id)),
            barKey: (type) => _barKey(cell.id, type),
            onOpen: () => _open(cell),
            onClose: complete && opened ? () => setState(() => _opened.remove(cell.id)) : null,
            onTap: (type) => _enter(cell, type),
            onSwap: _swap,
            flying: {for (final f in _flights) f.component.id},
            onDragStarted: () => _dragging = true,
            onCode: () => context.push('/barcodes?cell=${cell.id}'),
            onEdit: actionable ? () => showCellSheet(context, inventory, cell: cell) : null,
            onDisable: actionable ? () => removeCellWithChecks(context, cell) : null,
          ),
        ),
      );
    }

    return Listener(
      onPointerMove: (e) => _autoScroll(e.position),
      onPointerUp: (_) => _dragging = false,
      onPointerCancel: (_) => _dragging = false,
      child: RefreshIndicator(
        color: AppColors.blue,
        onRefresh: inventory.load,
        child: CustomScrollView(
          key: _listKey,
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _header(inventory)),
            SliverToBoxAdapter(child: top),
            for (final MapEntry(key: letter, value: row) in sections.entries) ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                sliver: SliverToBoxAdapter(
                  child: SectionTitle(
                    'EL $letter',
                    trailing: row.length == 1 ? '1 celda' : '${row.length} celdas · desliza →',
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  key: _rowKeys.putIfAbsent(letter, GlobalKey.new),
                  height: _tileExtent + 14,
                  // One centred cell per page: only the one on screen is built
                  // (and its neighbour while turning), even with 150.
                  child: PageView.builder(
                    controller: _rowPages.putIfAbsent(letter, PageController.new),
                    itemCount: row.length,
                    itemBuilder: (context, i) => Center(
                      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: tile(row[i])),
                    ),
                  ),
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  /// Fills an empty slot with a free component of that type, or registers a new one there.
  Future<void> _pickFree(Cell cell, ComponentType type) {
    final inventory = context.read<InventoryController>();
    final free = inventory.components.where((c) => c.isFree && c.type == type).toList();
    final plural = '${type.label.toLowerCase()}s';
    return showAppSheet<void>(
      context,
      (sheetContext) => SheetFrame(
        title: 'Asignar ${type.label.toLowerCase()} a la celda ${cell.name}',
        children: [
          if (free.isEmpty)
            InfoBox(text: 'No hay $plural libres. Registra uno nuevo.')
          else
            for (final c in free)
              ListTile(
                key: ValueKey('free-${c.id}'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.inventory_2_outlined, color: AppColors.teal),
                title: Text(c.serialCode, style: const TextStyle(fontWeight: FontWeight.w600)),
                trailing: const Icon(Icons.chevron_right, color: AppColors.muted),
                onTap: () {
                  Navigator.pop(sheetContext);
                  runAction(
                    context,
                    () => inventory.assignComponent(c, cell),
                    '${c.serialCode} asignado a la celda ${cell.name}.',
                  );
                },
              ),
          const SizedBox(height: 16),
          SecondaryButton(
            label: 'Registrar nuevo',
            onPressed: () {
              Navigator.pop(sheetContext);
              showComponentSheet(context, inventory, type: type, cell: cell, lockType: true);
            },
          ),
        ],
      ),
    );
  }
}

/// The cell's jar with its anode and cathode, as on the line, for other
/// screens. [slot] wraps each slot (its bar, or an empty space) so it can be
/// dragged or take a drop; [size] is the slot's size.
class CellModelView extends StatelessWidget {
  const CellModelView({super.key, this.anode, this.cathode, this.slot});

  /// Serials shown in each slot; null leaves it empty (hatched).
  final String? anode;
  final String? cathode;
  final Widget Function(ComponentType type, Size size, Widget bar)? slot;

  /// A bar lifted off its slot, with a shadow: the feedback of a drag.
  static Widget liftedBar(ComponentType type, String serial, Size size) =>
      _LiftedBar(type: type, serial: serial, size: size);

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: _Model.aspectRatio,
      child: LayoutBuilder(
        builder: (context, box) {
          final size = box.biggest;
          Widget zone(ComponentType type, Rect fraction, String? serial) {
            final rect = _placeIn(size, fraction);
            final bar = serial == null ? const SizedBox.expand() : _Bar(type: type, serial: serial);
            return Positioned.fromRect(rect: rect, child: slot?.call(type, rect.size, bar) ?? bar);
          }

          return Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _JarBackPainter(hasAnode: anode != null, hasCathode: cathode != null),
                ),
              ),
              zone(ComponentType.anode, _Model.anodeSlot, anode),
              zone(ComponentType.cathode, _Model.cathodeSlot, cathode),
              const Positioned.fill(
                child: IgnorePointer(child: CustomPaint(painter: _JarFrontPainter())),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Layout of the cell model as fractions of its box, shared by the painters
/// and the widgets on top so both always line up.
abstract final class _Model {
  static const aspectRatio = 0.85;
  static const rail = Rect.fromLTRB(0.14, 0.04, 0.86, 0.075);
  static const jar = Rect.fromLTRB(0.10, 0.30, 0.86, 0.97);
  static const liquidTop = 0.44;
  static const membraneX = 0.48;
  static const anodeSlot = Rect.fromLTRB(0.22, 0.14, 0.38, 0.90);
  static const cathodeSlot = Rect.fromLTRB(0.58, 0.14, 0.74, 0.90);
  static const lid = Rect.fromLTRB(0.07, 0.10, 0.93, 0.99);

  /// Depth of a bar's top and side faces, as a fraction of its width.
  static const barDepth = 0.22;
}

class _CellTile extends StatefulWidget {
  const _CellTile({
    super.key,
    required this.cell,
    required this.anode,
    required this.cathode,
    required this.closed,
    required this.busy,
    required this.barKey,
    required this.onOpen,
    required this.onClose,
    required this.onTap,
    required this.onSwap,
    required this.flying,
    required this.onDragStarted,
    required this.onCode,
    required this.onEdit,
    required this.onDisable,
  });

  final Cell cell;
  final Component? anode;
  final Component? cathode;
  final bool closed;
  final bool busy;
  final GlobalKey Function(ComponentType type) barKey;
  final VoidCallback onOpen;

  /// Puts the lid back on an opened complete cell; null otherwise.
  final VoidCallback? onClose;
  final ValueChanged<ComponentType> onTap;

  /// [target] is null when dropped on an empty slot of the same type.
  final void Function(Component dragged, Component? target) onSwap;

  /// Ids of components drawn by the swap overlay right now, not in their slot.
  final Set<int> flying;
  final VoidCallback onDragStarted;
  final VoidCallback onCode;

  /// Rename / remove the cell; null while it is busy.
  final VoidCallback? onEdit;
  final VoidCallback? onDisable;

  @override
  State<_CellTile> createState() => _CellTileState();
}

class _CellTileState extends State<_CellTile> with SingleTickerProviderStateMixin {
  /// 1 = lid on, 0 = open. A tile built already closed shows the lid at once;
  /// only a change while on screen is animated.
  late final _lid = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
    value: widget.closed ? 1 : 0,
  );

  @override
  void didUpdateWidget(_CellTile old) {
    super.didUpdateWidget(old);
    if (old.closed == widget.closed) return;
    if (widget.closed) {
      // The lock sounds as the lid starts coming down, whatever closed it.
      HapticFeedback.mediumImpact();
      CellSounds.close();
      _lid.forward();
    } else {
      HapticFeedback.mediumImpact();
      CellSounds.open();
      _lid.reverse();
    }
  }

  @override
  void dispose() {
    _lid.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cell = widget.cell;
    // A cell is active while it has a cathode and an anode (the backend's rule).
    final active = widget.anode != null && widget.cathode != null;

    Widget part(ComponentType type, Component? c) => Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: _barTint(type), shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(type.label, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            c?.serialCode ?? '—',
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink),
          ),
        ),
      ],
    );

    Widget lockButton(String label, IconData icon, VoidCallback onPressed) => SizedBox(
      height: 40,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 17),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        style: TextButton.styleFrom(
          backgroundColor: AppColors.blueSoft,
          foregroundColor: AppColors.blue,
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppCard.shadow,
      ),
      child: Column(
        children: [
          // The model on the left, the cell's data beside it.
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 14, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 118,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFFEFF4FC), Color(0xFFDCE6F5)],
                      ),
                    ),
                    child: Center(
                      child: AspectRatio(aspectRatio: _Model.aspectRatio, child: _model()),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Celda ${cell.name}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink),
                              ),
                            ),
                            StatusPill.of(active ? 'Activa' : 'Inactiva', active ? StatusPill.green : StatusPill.grey),
                          ],
                        ),
                        const SizedBox(height: 12),
                        part(ComponentType.anode, widget.anode),
                        const SizedBox(height: 6),
                        part(ComponentType.cathode, widget.cathode),
                        const SizedBox(height: 10),
                        InkWell(
                          onTap: () => widget.onTap(ComponentType.anode),
                          borderRadius: BorderRadius.circular(6),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    'Ver componentes',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.blue),
                                  ),
                                ),
                                Icon(Icons.chevron_right, size: 18, color: AppColors.blue),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF0F1F4)),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: widget.onClose != null
                        ? lockButton('Cerrar celda', Icons.lock_outline, widget.onClose!)
                        : widget.closed
                        ? lockButton('Abrir celda', Icons.lock_open_outlined, widget.onOpen)
                        : const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(width: 8),
                // The barcode screen already generates, shows and downloads it.
                CircleAction(
                  key: ValueKey('line-code-${cell.id}'),
                  tooltip: cell.barcodeValue == null ? 'Generar código de barras' : 'Código ${cell.barcodeValue}',
                  icon: Icons.qr_code_2,
                  onPressed: widget.onCode,
                ),
                const SizedBox(width: 8),
                CircleAction(tooltip: 'Editar celda', icon: Icons.edit_outlined, onPressed: widget.onEdit),
                const SizedBox(width: 8),
                CircleAction(
                  tooltip: 'Eliminar celda',
                  icon: Icons.delete_outline,
                  color: AppColors.error,
                  background: AppColors.errorSoft,
                  onPressed: widget.onDisable,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _model() {
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;
        Rect place(Rect f) =>
            Rect.fromLTRB(f.left * size.width, f.top * size.height, f.right * size.width, f.bottom * size.height);
        final lidRect = place(_Model.lid);

        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _JarBackPainter(hasAnode: widget.anode != null, hasCathode: widget.cathode != null),
              ),
            ),
            _zone(ComponentType.anode, place(_Model.anodeSlot), widget.anode),
            _zone(ComponentType.cathode, place(_Model.cathodeSlot), widget.cathode),
            // The bath in front of the bars, so they read as dipped into it.
            const Positioned.fill(
              child: IgnorePointer(child: CustomPaint(painter: _JarFrontPainter())),
            ),
            AnimatedBuilder(
              animation: _lid,
              builder: (context, child) {
                final v = Curves.easeInOutCubic.transform(_lid.value);
                if (v == 0) return const SizedBox.shrink();
                // Hinged at the top: it swings up and back while fading out.
                return Positioned.fromRect(
                  rect: lidRect,
                  child: IgnorePointer(
                    ignoring: _lid.isAnimating,
                    child: Opacity(
                      opacity: v,
                      child: Transform.translate(
                        offset: Offset(0, -(1 - v) * lidRect.height * 0.25),
                        child: Transform(
                          alignment: Alignment.topCenter,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.002)
                            ..rotateX(-(1 - v) * 1.1),
                          child: child,
                        ),
                      ),
                    ),
                  ),
                );
              },
              child: _Lid(cellId: widget.cell.id, name: widget.cell.name, onTap: widget.onOpen),
            ),
          ],
        );
      },
    );
  }

  /// A bar slot: tap to see the component, long-press to drag it, and a drop
  /// target for the same type from another cell.
  Widget _zone(ComponentType type, Rect rect, Component? component) {
    final cell = widget.cell;
    final tappable = GestureDetector(
      key: ValueKey('line-${type.name}-${cell.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onTap(type),
      child: KeyedSubtree(
        key: widget.barKey(type),
        // A bar in flight during a swap is drawn by the screen's overlay instead.
        child: component == null || widget.flying.contains(component.id)
            ? const SizedBox.expand()
            : _Bar(type: type, serial: component.serialCode),
      ),
    );

    // Red over an empty slot: the drop is taken only to say why it cannot swap.
    final hoverColor = component == null ? AppColors.error : AppColors.orange;
    final target = DragTarget<Component>(
      // Only a component of the same type from another cell, onto one that is
      // there: the backend swaps two assigned components.
      // Same type from another cell. An empty slot takes the drop too, only to
      // explain why the swap cannot happen (the backend needs two components).
      onWillAcceptWithDetails: (d) => !widget.busy && d.data.type == type && d.data.cellId != cell.id,
      onAcceptWithDetails: (d) => widget.onSwap(d.data, component),
      builder: (context, hovering, _) => DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          color: hovering.isEmpty ? null : hoverColor.withValues(alpha: 0.18),
          border: hovering.isEmpty ? null : Border.all(color: hoverColor, width: 2.5),
        ),
        // The bar under the dragged one rises a little: it is about to come out.
        child: AnimatedSlide(
          offset: hovering.isEmpty ? Offset.zero : const Offset(0, -0.2),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: component == null
              ? tappable
              : LongPressDraggable<Component>(
                  data: component,
                  maxSimultaneousDrags: widget.busy ? 0 : 1,
                  onDragStarted: widget.onDragStarted,
                  // Pulled out of the bath: the slot is left empty while it travels.
                  feedback: _LiftedBar(type: type, serial: component.serialCode, size: rect.size),
                  childWhenDragging: const Opacity(opacity: 0.6, child: CustomPaint(painter: _EmptyBarPainter())),
                  child: tappable,
                ),
        ),
      ),
    );

    final name = '${type.label} de la celda ${cell.name}';
    return Positioned.fromRect(
      rect: rect,
      child: Semantics(
        button: true,
        label: component == null ? '$name: sin asignar' : '$name: ${component.serialCode}',
        child: MouseRegion(cursor: SystemMouseCursors.click, child: target),
      ),
    );
  }
}

/// Cover of a cell with both components: tapping it asks to open the cell.
class _Lid extends StatelessWidget {
  const _Lid({required this.cellId, required this.name, required this.onTap});

  final int cellId;
  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Celda $name tapada. Toca para abrirla.',
      child: GestureDetector(
        key: ValueKey('line-lid-$cellId'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: CustomPaint(
          painter: const _LidPainter(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 22, 22, 10),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                  const SizedBox(height: 6),
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_outline, size: 14, color: Colors.white70),
                      SizedBox(width: 4),
                      Text('Toca para abrir', style: TextStyle(fontSize: 11, color: Colors.white70)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dot colour of each kind of bar, as painted: bronze anode, steel cathode.
Color _barTint(ComponentType type) => type == ComponentType.anode ? const Color(0xFFB08D4A) : const Color(0xFF6E7A86);

/// A metal bar (anode or cathode) with its serial engraved near the top.
class _Bar extends StatelessWidget {
  const _Bar({required this.type, required this.serial});

  final ComponentType type;
  final String serial;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final d = box.maxWidth * _Model.barDepth;
        return Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(painter: _BarPainter(type)),
            Positioned(
              left: 0,
              right: d,
              top: d + 4,
              height: (box.maxHeight - d) * 0.4,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: RotatedBox(
                  quarterTurns: 3,
                  child: Text(
                    serial,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The bar that follows the finger: it starts where it sat and is pulled up
/// out of the bath, leaning and casting a shadow as it lifts.
class _LiftedBar extends StatefulWidget {
  const _LiftedBar({required this.type, required this.serial, required this.size});

  final ComponentType type;
  final String serial;
  final Size size;

  @override
  State<_LiftedBar> createState() => _LiftedBarState();
}

class _LiftedBarState extends State<_LiftedBar> with SingleTickerProviderStateMixin {
  late final _lift = AnimationController(vsync: this, duration: const Duration(milliseconds: 220))..forward();

  @override
  void dispose() {
    _lift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _lift,
      builder: (context, child) {
        final v = Curves.easeOutBack.transform(_lift.value);
        return Transform.translate(
          offset: Offset(0, -widget.size.height * 0.25 * v),
          child: Transform.rotate(
            angle: -0.12 * v,
            child: Transform.scale(scale: 1 + 0.08 * v, child: child),
          ),
        );
      },
      child: _ShadowedBar(type: widget.type, serial: widget.serial, size: widget.size),
    );
  }
}

/// A bar off its slot (dragged or flying during a swap), with a drop shadow.
class _ShadowedBar extends StatelessWidget {
  const _ShadowedBar({required this.type, required this.serial, required this.size});

  final ComponentType type;
  final String serial;
  final Size size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.fromSize(
      size: size,
      // Material: the dragged copy lives in the overlay, outside the page's text style.
      child: Material(
        type: MaterialType.transparency,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            boxShadow: [BoxShadow(color: Color(0x40000000), blurRadius: 14, offset: Offset(4, 10))],
          ),
          child: _Bar(type: type, serial: serial),
        ),
      ),
    );
  }
}

Rect _placeIn(Size size, Rect f) =>
    Rect.fromLTRB(f.left * size.width, f.top * size.height, f.right * size.width, f.bottom * size.height);

/// Diagonal hatching for an empty slot, as in the "celda vacía" sketch.
void _paintEmptySlot(Canvas canvas, Rect rect) {
  final stroke = Paint()
    ..color = const Color(0xFF8D9BA6)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2;
  canvas.save();
  canvas.clipRect(rect);
  for (var x = rect.left - rect.height; x < rect.right; x += 8) {
    canvas.drawLine(Offset(x, rect.bottom), Offset(x + rect.height, rect.top), stroke);
  }
  canvas.restore();
  canvas.drawRect(rect, stroke..strokeWidth = 1.5);
}

/// Bus rail, the back of the jar, the bath, the membrane and empty slots.
class _JarBackPainter extends CustomPainter {
  const _JarBackPainter({required this.hasAnode, required this.hasCathode});

  final bool hasAnode;
  final bool hasCathode;

  static const _rail = Color(0xFF3B4650);

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint();
    final rail = _placeIn(size, _Model.rail);
    canvas.drawRRect(RRect.fromRectAndRadius(rail, const Radius.circular(2)), fill..color = _rail);

    final jar = _placeIn(size, _Model.jar);
    final d = size.width * 0.04;
    final lead = Paint()
      ..color = _rail
      ..strokeWidth = 2;
    for (final (present, slotFraction) in [(hasAnode, _Model.anodeSlot), (hasCathode, _Model.cathodeSlot)]) {
      final slot = _placeIn(size, slotFraction);
      if (present) {
        // Lead from the rail down to the bar.
        final x = slot.left + slot.width * (1 - _Model.barDepth) / 2;
        canvas.drawLine(Offset(x, rail.bottom), Offset(x, slot.top + slot.width * _Model.barDepth / 2), lead);
      }
    }

    // Rim and right side of the jar, then its inside and the bath.
    canvas.drawPath(
      Path()
        ..moveTo(jar.left, jar.top)
        ..lineTo(jar.left + d, jar.top - d)
        ..lineTo(jar.right + d, jar.top - d)
        ..lineTo(jar.right, jar.top)
        ..close(),
      fill..color = const Color(0xFFD5E1E8),
    );
    canvas.drawPath(
      Path()
        ..moveTo(jar.right, jar.top)
        ..lineTo(jar.right + d, jar.top - d)
        ..lineTo(jar.right + d, jar.bottom - d)
        ..lineTo(jar.right, jar.bottom)
        ..close(),
      fill..color = const Color(0xFFB7C7D1),
    );
    canvas.drawRect(jar, fill..color = const Color(0xFFF1F5F8));
    final bath = Rect.fromLTRB(jar.left, _Model.liquidTop * size.height, jar.right, jar.bottom);
    canvas.drawRect(
      bath,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFA9CFE0), Color(0xFF7FAFC6)],
        ).createShader(bath),
    );

    // Membrane between the two halves.
    final x = _Model.membraneX * size.width;
    final membrane = Path()..moveTo(x, jar.top + 4);
    var right = true;
    for (var y = jar.top + 10; y < jar.bottom - 2; y += 7) {
      membrane.lineTo(x + (right ? 2.5 : -2.5), y);
      right = !right;
    }
    canvas.drawPath(
      membrane,
      Paint()
        ..color = const Color(0xFF5D7686)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    for (final (present, slotFraction) in [(hasAnode, _Model.anodeSlot), (hasCathode, _Model.cathodeSlot)]) {
      if (present) continue;
      final slot = _placeIn(size, slotFraction);
      _paintEmptySlot(
        canvas,
        Rect.fromLTRB(slot.left, jar.top + 6, slot.right - slot.width * _Model.barDepth, slot.bottom),
      );
    }
  }

  @override
  bool shouldRepaint(_JarBackPainter old) => old.hasAnode != hasAnode || old.hasCathode != hasCathode;
}

/// Front of the bath and the glass, drawn over the bars.
class _JarFrontPainter extends CustomPainter {
  const _JarFrontPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final jar = _placeIn(size, _Model.jar);
    final top = _Model.liquidTop * size.height;
    canvas.drawRect(Rect.fromLTRB(jar.left, top, jar.right, jar.bottom), Paint()..color = const Color(0x4D5E93AD));
    canvas.drawLine(
      Offset(jar.left, top),
      Offset(jar.right, top),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.7)
        ..strokeWidth = 1.2,
    );
    canvas.drawRect(
      Rect.fromLTRB(jar.left + 5, jar.top + 6, jar.left + 9, jar.bottom - 8),
      Paint()..color = Colors.white.withValues(alpha: 0.35),
    );
    canvas.drawRect(
      jar,
      Paint()
        ..color = const Color(0xFF7B93A2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    canvas.drawRect(
      Rect.fromLTRB(jar.left - 2, jar.bottom - 3, jar.right + 2, jar.bottom + 1),
      Paint()..color = const Color(0xFF4A5A66),
    );
  }

  @override
  bool shouldRepaint(_JarFrontPainter old) => false;
}

/// Brushed metal bar with a top and a side face: bronze anode, steel cathode.
class _BarPainter extends CustomPainter {
  const _BarPainter(this.type);

  final ComponentType type;

  static const _anode = [Color(0xFF6E5B34), Color(0xFFC9A964), Color(0xFF7D6738)];
  static const _cathode = [Color(0xFF3B434B), Color(0xFF9AA4AE), Color(0xFF47515A)];

  @override
  void paint(Canvas canvas, Size size) {
    final colors = type == ComponentType.anode ? _anode : _cathode;
    final w = size.width, h = size.height;
    final d = w * _Model.barDepth;
    final front = Rect.fromLTRB(0, d, w - d, h);

    canvas.drawRect(
      front,
      Paint()..shader = LinearGradient(colors: colors, stops: const [0, 0.45, 1]).createShader(front),
    );
    final brushed = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..strokeWidth = 1;
    for (var y = front.top + 6; y < front.bottom; y += 7) {
      canvas.drawLine(Offset(front.left + 1, y), Offset(front.right - 1, y), brushed);
    }
    canvas.drawPath(
      Path()
        ..moveTo(0, d)
        ..lineTo(d, 0)
        ..lineTo(w, 0)
        ..lineTo(w - d, d)
        ..close(),
      Paint()..color = Color.lerp(colors[1], Colors.white, 0.35)!,
    );
    canvas.drawPath(
      Path()
        ..moveTo(w - d, d)
        ..lineTo(w, 0)
        ..lineTo(w, h - d)
        ..lineTo(w - d, h)
        ..close(),
      Paint()..color = Color.lerp(colors[2], Colors.black, 0.35)!,
    );
  }

  @override
  bool shouldRepaint(_BarPainter old) => old.type != type;
}

/// Steel cover with a top and side face, a rim seam and rivets.
class _LidPainter extends CustomPainter {
  const _LidPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final d = w * 0.05;
    final front = Rect.fromLTRB(0, d, w - d, h);
    canvas.drawPath(
      Path()
        ..moveTo(0, d)
        ..lineTo(d, 0)
        ..lineTo(w, 0)
        ..lineTo(w - d, d)
        ..close(),
      Paint()..color = const Color(0xFF8C9BA7),
    );
    canvas.drawPath(
      Path()
        ..moveTo(w - d, d)
        ..lineTo(w, 0)
        ..lineTo(w, h - d)
        ..lineTo(w - d, h)
        ..close(),
      Paint()..color = const Color(0xFF333F48),
    );
    canvas.drawRect(
      front,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF62727F), Color(0xFF46545F)],
        ).createShader(front),
    );
    final seamY = front.top + front.height * 0.16;
    canvas.drawLine(
      Offset(front.left, seamY),
      Offset(front.right, seamY),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.3)
        ..strokeWidth = 1.5,
    );
    final rivet = Paint()..color = const Color(0xFF9AA7B1);
    for (final c in [
      Offset(front.left + 8, front.top + 8),
      Offset(front.right - 8, front.top + 8),
      Offset(front.left + 8, front.bottom - 8),
      Offset(front.right - 8, front.bottom - 8),
    ]) {
      canvas.drawCircle(c, 2.5, rivet);
    }
  }

  @override
  bool shouldRepaint(_LidPainter old) => false;
}

/// Inside view of one component: just its bar, plus a floating panel with
/// the component's data.
class _ComponentDetail extends StatelessWidget {
  const _ComponentDetail({
    required this.cell,
    required this.anode,
    required this.cathode,
    required this.focus,
    required this.loading,
    required this.error,
    required this.refreshedAt,
    required this.onFocus,
    required this.onRefresh,
    required this.onBack,
    required this.isBusy,
    required this.onEdit,
    required this.onDisable,
    required this.onAssignFree,
  });

  final Cell cell;
  final Component? anode;
  final Component? cathode;
  final ComponentType focus;
  final bool loading;
  final String? error;
  final DateTime? refreshedAt;
  final ValueChanged<ComponentType> onFocus;
  final VoidCallback onRefresh;
  final VoidCallback onBack;
  final bool Function(int componentId) isBusy;
  final ValueChanged<Component> onEdit;
  final ValueChanged<Component> onDisable;
  final ValueChanged<ComponentType> onAssignFree;

  @override
  Widget build(BuildContext context) {
    final component = focus == ComponentType.anode ? anode : cathode;
    final busy = component != null && isBusy(component.id);
    // Frosted over the line, so the line still shows faintly behind.
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: ColoredBox(
        color: AppColors.surface.withValues(alpha: 0.94),
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    CircleAction(
                      tooltip: 'Volver a la línea',
                      icon: Icons.chevron_left,
                      background: Colors.white,
                      size: 44,
                      onPressed: onBack,
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          const Text('Celda', style: TextStyle(fontSize: 13, color: AppColors.muted)),
                          Text(
                            cell.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink),
                          ),
                        ],
                      ),
                    ),
                    CircleAction(
                      tooltip: 'Actualizar',
                      icon: Icons.refresh,
                      background: Colors.white,
                      size: 44,
                      onPressed: loading ? null : onRefresh,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Center(
                child: _TypeSwitch(selected: focus, onSelected: onFocus),
              ),
              Expanded(
                child: Stack(
                  children: [
                    // Soft blue glow behind the bar.
                    const Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(radius: 0.6, colors: [Color(0x332563EB), Color(0x002563EB)]),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                      child: Column(
                        children: [
                          Expanded(
                            child: component == null
                                ? Center(
                                    child: AspectRatio(
                                      aspectRatio: 0.3,
                                      child: const CustomPaint(painter: _EmptyBarPainter()),
                                    ),
                                  )
                                : RotatableBar(
                                    key: const ValueKey('detail-bar'),
                                    type: focus,
                                    serial: component.serialCode,
                                  ),
                          ),
                          if (component != null)
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.threesixty, size: 16, color: AppColors.muted),
                                SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    'Desliza para girar',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _ComponentPanel(
                key: const ValueKey('component-panel'),
                cell: cell,
                type: focus,
                component: component,
                loading: loading,
                error: error,
                refreshedAt: refreshedAt,
                // A cell far along the line is picked there instead of dragged to.
                footer: component == null
                    ? null
                    : TextButton.icon(
                        key: const ValueKey('swap-elsewhere'),
                        onPressed: () => context.push('/swap?cell=${cell.id}'),
                        icon: const Icon(Icons.swap_horiz, size: 20),
                        label: const Text('Intercambiar con otra celda'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.blue,
                          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                      ),
                actions: component == null
                    ? [
                        // One way in for an empty slot: pick a free one or register a new one there.
                        _PanelButton(
                          label: 'Asignar componente',
                          background: AppColors.blue,
                          foreground: Colors.white,
                          onPressed: () => onAssignFree(focus),
                        ),
                      ]
                    : [
                        _PanelButton(
                          label: 'Editar',
                          background: AppColors.blue,
                          foreground: Colors.white,
                          onPressed: busy ? null : () => onEdit(component),
                        ),
                        // Always enabled: for a component in use the answer is the
                        // "está en uso" message (US013 E02).
                        _PanelButton(
                          label: 'Deshabilitar',
                          background: AppColors.errorSoft,
                          foreground: AppColors.error,
                          onPressed: busy ? null : () => onDisable(component),
                        ),
                      ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Ánodo | Cátodo" segmented switch of the component view.
class _TypeSwitch extends StatelessWidget {
  const _TypeSwitch({required this.selected, required this.onSelected});

  final ComponentType selected;
  final ValueChanged<ComponentType> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(22)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final type in const [ComponentType.anode, ComponentType.cathode])
            Semantics(
              button: true,
              selected: type == selected,
              child: GestureDetector(
                key: ValueKey('focus-${type.name}'),
                onTap: () => onSelected(type),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 9),
                  decoration: BoxDecoration(
                    color: type == selected ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: type == selected ? AppCard.shadow : null,
                  ),
                  child: Text(
                    type.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: type == selected ? AppColors.ink : AppColors.muted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Wide rounded button of the component sheet ("Editar", "Deshabilitar").
class _PanelButton extends StatelessWidget {
  const _PanelButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onPressed,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          disabledBackgroundColor: AppColors.disabledBg,
          disabledForegroundColor: AppColors.disabledFg,
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        child: Text(label),
      ),
    );
  }
}

/// The outline of a missing bar.
class _EmptyBarPainter extends CustomPainter {
  const _EmptyBarPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final d = size.width * _Model.barDepth;
    _paintEmptySlot(canvas, Rect.fromLTRB(0, d, size.width - d, size.height));
  }

  @override
  bool shouldRepaint(_EmptyBarPainter old) => false;
}

/// White sheet at the bottom of the component view with its data and actions.
class _ComponentPanel extends StatelessWidget {
  const _ComponentPanel({
    super.key,
    required this.cell,
    required this.type,
    required this.component,
    required this.loading,
    required this.error,
    required this.refreshedAt,
    required this.actions,
    this.footer,
  });

  final Cell cell;
  final ComponentType type;
  final Component? component;
  final bool loading;
  final String? error;
  final DateTime? refreshedAt;
  final List<Widget> actions;

  /// Under the actions: the way to the swap screen.
  final Widget? footer;

  static String _time(DateTime t) => [t.hour, t.minute, t.second].map((n) => n.toString().padLeft(2, '0')).join(':');

  @override
  Widget build(BuildContext context) {
    final c = component;
    final state = c == null ? null : (!c.isActive ? 'Inactivo' : (c.isInUse ? 'En uso' : 'Libre'));

    Widget info(String label, String value, {Color color = AppColors.ink}) => Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );

    Widget pair(Widget a, Widget b) => Row(
      children: [
        Expanded(child: a),
        const SizedBox(width: 10),
        Expanded(child: b),
      ],
    );

    return Container(
      padding: EdgeInsets.fromLTRB(20, 10, 20, 16 + MediaQuery.paddingOf(context).bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [BoxShadow(color: Color(0x1A0F172A), blurRadius: 24, offset: Offset(0, -6))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(type.label, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                    Text(
                      c?.serialCode ?? 'Sin asignar',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.ink),
                    ),
                  ],
                ),
              ),
              if (state != null)
                StatusPill.of(state, switch (state) {
                  'En uso' => StatusPill.blue,
                  'Libre' => StatusPill.green,
                  _ => StatusPill.grey,
                }),
            ],
          ),
          SizedBox(height: 3, child: loading ? const LinearProgressIndicator(color: AppColors.orange) : null),
          const SizedBox(height: 10),
          if (c == null)
            Text(
              'Esta celda no tiene ${type.label.toLowerCase()} asignado.',
              style: const TextStyle(fontSize: 15, color: AppColors.muted),
            )
          else ...[
            pair(info('ID', '#${c.id}'), info('Celda', cell.name)),
            const SizedBox(height: 10),
            pair(
              info('Estado', state!),
              info(
                'Código',
                cell.barcodeValue ?? 'Pendiente',
                color: cell.hasBarcode ? AppColors.ink : AppColors.amber,
              ),
            ),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(child: actions[i]),
                ],
              ],
            ),
          ],
          if (footer != null) ...[const SizedBox(height: 4), footer!],
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(error!, style: const TextStyle(fontSize: 13, color: AppColors.error)),
          ],
          if (refreshedAt != null) ...[
            const SizedBox(height: 10),
            Text(
              'Actualizado a las ${_time(refreshedAt!)}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
        ],
      ),
    );
  }
}
