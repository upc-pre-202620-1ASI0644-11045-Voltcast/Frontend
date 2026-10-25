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

const _tileExtent = 250.0;

/// Every cell from the backend on one vertical production line. A cell with
/// both components is shown closed; once opened, its anode and cathode can be
/// dragged onto another open cell to swap them, or tapped to fly into a view
/// of that bar with the component as the backend has it now.
class ProductionLineScreen extends StatefulWidget {
  const ProductionLineScreen({super.key, this.userName, this.onLogout});

  /// First name for the greeting; the home tab passes the signed-in user's.
  final String? userName;
  final VoidCallback? onLogout;

  @override
  State<ProductionLineScreen> createState() => _ProductionLineScreenState();
}

class _ProductionLineScreenState extends State<ProductionLineScreen> with TickerProviderStateMixin {
  final _scroll = ScrollController();
  final _stackKey = GlobalKey();
  final _listKey = GlobalKey();
  final _headerKey = GlobalKey();
  final _tileKeys = <int, GlobalKey>{};

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
    super.dispose();
  }

  GlobalKey _barKey(int cellId, ComponentType type) => _barKeys.putIfAbsent('$cellId-${type.name}', GlobalKey.new);

  Rect? _rectOf(GlobalKey? key) {
    final box = key?.currentContext?.findRenderObject() as RenderBox?;
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || stack == null || !box.attached) return null;
    return box.localToGlobal(Offset.zero, ancestor: stack) & box.size;
  }

  Rect? _originOf(int cellId, ComponentType type) => _rectOf(_barKey(cellId, type)) ?? _rectOf(_tileKeys[cellId]);

  Future<void> _open(Cell cell) async {
    final ok = await confirmDialog(
      context,
      title: '¿Desea abrir la celda ${cell.name}?',
      message: 'Podrás intercambiar su ánodo y su cátodo.',
      action: 'Abrir',
      actionColor: AppColors.teal,
    );
    if (ok && mounted) setState(() => _opened.add(cell.id));
  }

  Future<void> _enter(int index, Cell cell, ComponentType focus) async {
    if (_cellId != null || _zoom.isAnimating) return;

    // Travel along the line until the cell is centred, then dive into the bar.
    if (_scroll.hasClients) {
      final position = _scroll.position;
      final header = _headerKey.currentContext?.size?.height ?? 0;
      final target = (header + index * _tileExtent + _tileExtent / 2 - position.viewportDimension / 2).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      await _scroll.animateTo(target, duration: const Duration(milliseconds: 350), curve: Curves.easeInOutCubic);
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
  /// it so the drop can reach any of the cells. Fed by a listener around the
  /// list, not by the dragged tile: that tile is disposed once scrolled away.
  void _autoScroll(Offset globalPosition) {
    final list = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (!_dragging || list == null || !_scroll.hasClients) return;
    const edge = 90.0, step = 24.0;
    final y = list.globalToLocal(globalPosition).dy;
    final delta = y < edge ? -step : (y > list.size.height - edge ? step : 0.0);
    if (delta == 0) return;
    final position = _scroll.position;
    _scroll.jumpTo((position.pixels + delta).clamp(position.minScrollExtent, position.maxScrollExtent));
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
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: SafeArea(
          child: Column(
            children: [
              ScreenHeader(
                // The home tab: the line is what the user lands on after signing in.
                title: 'Celdas',
                subtitle: [
                  ?widget.userName,
                  inventory.hasLoaded ? '${inventory.cells.length} celdas' : 'Línea de producción',
                ].join(' · '),
                onBack: selected != null ? _exit : null,
                action: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HeaderAction(
                      label: 'Nueva',
                      onPressed: inventory.hasLoaded && selected == null
                          ? () => showCellSheet(context, inventory)
                          : null,
                    ),
                    if (widget.onLogout != null)
                      IconButton(
                        tooltip: 'Cerrar sesión',
                        onPressed: widget.onLogout,
                        icon: const Icon(Icons.logout, color: AppColors.muted),
                      ),
                  ],
                ),
              ),
              Expanded(child: _body(inventory, selected)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(InventoryController inventory, Cell? selected) {
    if (!inventory.hasLoaded) {
      if (inventory.loading) {
        return const Center(child: CircularProgressIndicator(color: AppColors.blue));
      }
      return LoadErrorView(message: inventory.loadError ?? 'No se pudo cargar.', onRetry: inventory.load);
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
    final header = Padding(
      key: _headerKey,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (inventory.loadError != null) ...[ErrorBanner(inventory.loadError!), const SizedBox(height: 16)],
          const SyncStatusBanner(),
          StatRow(
            tiles: [
              StatTile(label: 'Registradas', value: cells.length),
              StatTile(label: 'Activas', value: inventory.activeCount, color: AppColors.blue),
              StatTile(label: 'Inactivas', value: inventory.inactiveCount, color: AppColors.muted),
            ],
          ),
          const SizedBox(height: 14),
          if (cells.isEmpty)
            const InfoBox(text: 'Aún no hay celdas registradas. Crea la primera con "Nueva".')
          else
            const Text(
              'Visualiza las celdas aquí',
              style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.muted),
            ),
        ],
      ),
    );

    return Listener(
      onPointerMove: (e) => _autoScroll(e.position),
      onPointerUp: (_) => _dragging = false,
      onPointerCancel: (_) => _dragging = false,
      child: RefreshIndicator(
        color: AppColors.blue,
        onRefresh: inventory.load,
        child: Scrollbar(
          controller: _scroll,
          thumbVisibility: true,
          interactive: true,
          child: CustomScrollView(
            key: _listKey,
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: header),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                // Fixed extent: tiles are laid out and culled without measuring
                // them, so only the cells near the screen exist, even with 150.
                sliver: SliverFixedExtentList(
                  itemExtent: _tileExtent,
                  delegate: SliverChildBuilderDelegate(childCount: cells.length, (context, i) {
                    final cell = cells[i];
                    final anode = parts[cell.id]?[ComponentType.anode];
                    final cathode = parts[cell.id]?[ComponentType.cathode];
                    final complete = anode != null && cathode != null;
                    final opened = _opened.contains(cell.id);
                    // Inactive cells are edited and removed too: only a busy one waits.
                    final actionable = !inventory.isCellBusy(cell.id);
                    return RepaintBoundary(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _CellTile(
                          key: _tileKeys.putIfAbsent(cell.id, GlobalKey.new),
                          cell: cell,
                          anode: anode,
                          cathode: cathode,
                          closed: complete && !opened,
                          busy: [anode, cathode].any((c) => c != null && inventory.isComponentBusy(c.id)),
                          barKey: (type) => _barKey(cell.id, type),
                          onOpen: () => _open(cell),
                          onClose: complete && opened ? () => setState(() => _opened.remove(cell.id)) : null,
                          onTap: (type) => _enter(i, cell, type),
                          onSwap: _swap,
                          flying: {for (final f in _flights) f.component.id},
                          onDragStarted: () => _dragging = true,
                          onCode: () => context.push('/barcodes?cell=${cell.id}'),
                          onEdit: actionable ? () => showCellSheet(context, inventory, cell: cell) : null,
                          onDisable: actionable ? () => removeCellWithChecks(context, cell) : null,
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
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

  /// Rename / disable the cell; null when it is inactive or busy.
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
    String serial(Component? c) => c?.serialCode ?? '—';

    Widget lockButton(String label, IconData icon, VoidCallback onPressed) => TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.teal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        visualDensity: VisualDensity.compact,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );

    // A cell is active while it has a cathode and an anode (the backend's rule).
    final active = widget.anode != null && widget.cathode != null;

    // The model on the left, the cell's data and actions beside it.
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 5,
            child: Center(
              child: AspectRatio(aspectRatio: _Model.aspectRatio, child: _model()),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Celda ${cell.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink),
                      ),
                    ),
                    if (widget.onEdit != null)
                      IconButton(
                        tooltip: 'Editar celda',
                        onPressed: widget.onEdit,
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        color: AppColors.blue,
                        visualDensity: VisualDensity.compact,
                      )
                    else
                      const SizedBox(width: 8),
                    StatusPill.of(active ? 'Activa' : 'Inactiva', active ? StatusPill.green : StatusPill.grey),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Á: ${serial(widget.anode)} · C: ${serial(widget.cathode)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, height: 1.4, fontWeight: FontWeight.w600, color: AppColors.ink),
                ),
                const SizedBox(height: 12),
                _CodeChip(cellId: cell.id, code: cell.barcodeValue, onTap: widget.onCode),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Flexible(
                      child: widget.onClose != null
                          ? lockButton('Cerrar celda', Icons.lock_outline, widget.onClose!)
                          : widget.closed
                          ? lockButton('Abrir celda', Icons.lock_open_outlined, widget.onOpen)
                          : const SizedBox.shrink(),
                    ),
                    if (widget.onDisable != null)
                      IconButton(
                        tooltip: 'Eliminar celda',
                        onPressed: widget.onDisable,
                        icon: const Icon(Icons.delete_outline, size: 18),
                        color: AppColors.error,
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
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

/// Small tag with the cell's barcode (or "Generar código"); opens the
/// barcode screen, which already generates, shows and downloads it.
class _CodeChip extends StatelessWidget {
  const _CodeChip({required this.cellId, required this.code, required this.onTap});

  final int cellId;
  final String? code;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: code == null ? 'Generar código de barras' : 'Código de barras $code',
      child: InkWell(
        key: ValueKey('line-code-$cellId'),
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFEEF1F4),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.qr_code_2, size: 16, color: AppColors.ink),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  code ?? 'Generar código de barras',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
    // Frosted white over the line, so the line still shows faintly behind.
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: ColoredBox(
        color: Colors.white.withValues(alpha: 0.86),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 20, 0),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: onBack,
                    icon: const Icon(Icons.zoom_out_map, size: 20),
                    label: const Text('Volver a la línea'),
                    style: TextButton.styleFrom(foregroundColor: AppColors.ink),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Celda ${cell.name}',
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink),
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 2, 20, 0),
              child: Text('Vista del componente', style: TextStyle(fontSize: 13, color: AppColors.muted)),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Column(
                  children: [
                    Text(
                      focus.label.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                        color: AppColors.muted,
                      ),
                    ),
                    Expanded(
                      child: component == null
                          ? Center(
                              child: AspectRatio(
                                aspectRatio: 0.3,
                                child: const CustomPaint(painter: _EmptyBarPainter()),
                              ),
                            )
                          : RotatableBar(key: const ValueKey('detail-bar'), type: focus, serial: component.serialCode),
                    ),
                    if (component != null)
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.threesixty, size: 16, color: AppColors.muted),
                          SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Desliza el dedo para girarlo',
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
            ),
            _ComponentPanel(
              cell: cell,
              type: focus,
              component: component,
              loading: loading,
              error: error,
              refreshedAt: refreshedAt,
              onFocus: onFocus,
              onRefresh: onRefresh,
              actions: component == null
                  ? [
                      // One way in for an empty slot: pick a free one or register a new one there.
                      SmallActionButton(
                        label: 'Asignar componente',
                        color: AppColors.teal,
                        onPressed: () => onAssignFree(focus),
                      ),
                    ]
                  : [
                      SmallActionButton(
                        label: 'Editar',
                        onPressed: isBusy(component.id) ? null : () => onEdit(component),
                      ),
                      // Always enabled: for a component in use the answer is the
                      // "está en uso" message (US013 E02).
                      SmallActionButton(
                        label: 'Deshabilitar',
                        color: AppColors.error,
                        onPressed: isBusy(component.id) ? null : () => onDisable(component),
                      ),
                    ],
            ),
          ],
        ),
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

class _ComponentPanel extends StatelessWidget {
  const _ComponentPanel({
    required this.cell,
    required this.type,
    required this.component,
    required this.loading,
    required this.error,
    required this.refreshedAt,
    required this.onFocus,
    required this.onRefresh,
    required this.actions,
  });

  final Cell cell;
  final ComponentType type;
  final Component? component;
  final bool loading;
  final String? error;
  final DateTime? refreshedAt;
  final ValueChanged<ComponentType> onFocus;
  final VoidCallback onRefresh;
  final List<Widget> actions;

  static String _time(DateTime t) => [t.hour, t.minute, t.second].map((n) => n.toString().padLeft(2, '0')).join(':');

  @override
  Widget build(BuildContext context) {
    final c = component;
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 14, color: AppColors.muted)),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink),
            ),
          ),
        ],
      ),
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.large,
        border: Border.all(color: AppColors.border),
        boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 24, offset: Offset(0, 8))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in const [ComponentType.anode, ComponentType.cathode])
                      ChoiceChip(label: Text(t.label), selected: t == type, onSelected: (_) => onFocus(t)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Actualizar',
                onPressed: loading ? null : onRefresh,
                icon: const Icon(Icons.refresh),
                color: AppColors.blue,
              ),
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
            Text(
              '${c.type.label} · ${c.serialCode}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink),
            ),
            row('ID', '#${c.id}'),
            row('Estado', !c.isActive ? 'Inactivo' : (c.isInUse ? 'En uso' : 'Libre')),
            row('Celda', 'Celda ${cell.name}'),
            row('Código de la celda', cell.barcodeValue ?? 'Pendiente'),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: actions),
          ],
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(error!, style: const TextStyle(fontSize: 13, color: AppColors.error)),
          ],
          if (refreshedAt != null) ...[
            const SizedBox(height: 10),
            Text(
              'Actualizado a las ${_time(refreshedAt!)}',
              style: const TextStyle(fontSize: 12, color: AppColors.hint),
            ),
          ],
        ],
      ),
    );
  }
}
