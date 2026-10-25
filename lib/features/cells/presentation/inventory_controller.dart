import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/network/api_exception.dart';
import '../data/cell.dart';
import '../data/component.dart';
import '../data/inventory_repository.dart';
import '../data/pending_swap.dart';

/// How a swap ended: confirmed by the server, or done on the device while
/// offline and waiting to be synced.
enum SwapOutcome { applied, queued }

/// Shared state of the Celdas, Componentes and Código de barras screens, which
/// all derive from the same two lists. Mutations refresh both lists afterwards
/// because one action can touch several rows (disabling a cell frees its
/// components; a swap moves two).
///
/// Business rule enforced here (the backend does not): a cell holds at most
/// one cathode and one anode.
class InventoryController extends ChangeNotifier {
  InventoryController(
    this._repository, {
    required this._store,
    this.retryEvery = const Duration(seconds: 15),
  });

  final InventoryRepository _repository;
  final PendingSwapStore _store;

  /// How often queued swaps are retried while there are any.
  final Duration retryEvery;

  List<Cell> _cells = [];
  List<Component> _components = [];
  List<PendingSwap> _pending = [];
  bool _pendingRead = false;
  bool _loading = false;
  bool _loadedOnce = false;
  bool _syncing = false;
  String? _loadError;
  String? _syncNotice;
  Timer? _retryTimer;
  final Set<String> _busy = {};

  bool get loading => _loading;
  bool get hasLoaded => _loadedOnce;
  String? get loadError => _loadError;

  /// Swaps done offline that the server has not received yet.
  int get pendingCount => _pending.length;
  bool get syncing => _syncing;

  /// Result of the last background sync, shown until dismissed.
  String? get syncNotice => _syncNotice;

  List<Cell> get cells => ([..._cells]..sort(compareCells));

  /// A cell is active while it has a cathode and an anode (the backend's rule,
  /// computed here too so the line and the counts agree right after a change).
  List<Cell> get activeCells => cells.where(hasCompletePair).toList();
  List<Component> get components => ([..._components]..sort(compareComponents));

  Cell? cellById(int? id) {
    for (final c in _cells) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Active components installed in the cell.
  List<Component> componentsOf(int cellId) =>
      _components.where((c) => c.isActive && c.cellId == cellId).toList();

  Component? _firstOf(int cellId, ComponentType type) {
    for (final c in componentsOf(cellId)) {
      if (c.type == type) return c;
    }
    return null;
  }

  Component? cathodeOf(Cell cell) => _firstOf(cell.id, ComponentType.cathode);
  Component? anodeOf(Cell cell) => _firstOf(cell.id, ComponentType.anode);

  /// A barcode can only be generated once the cell has both.
  bool hasCompletePair(Cell cell) => cathodeOf(cell) != null && anodeOf(cell) != null;

  // ── One cathode and one anode per cell ───────────────────────────────────

  /// The component of [type] installed in [cell], ignoring [exceptComponentId].
  Component? occupantOf(Cell cell, ComponentType type, {int? exceptComponentId}) {
    for (final c in componentsOf(cell.id)) {
      if (c.type == type && c.id != exceptComponentId) return c;
    }
    return null;
  }

  /// Cells that still have room for a component of [type] (getting it is what
  /// makes an inactive cell active).
  List<Cell> cellsAccepting(ComponentType type, {int? exceptComponentId}) => cells
      .where((c) => occupantOf(c, type, exceptComponentId: exceptComponentId) == null)
      .toList();

  void _ensureRoom(Cell cell, ComponentType type, {int? exceptComponentId}) {
    final occupant = occupantOf(cell, type, exceptComponentId: exceptComponentId);
    if (occupant == null) return;
    throw ApiException(
      'La celda ${cell.name} ya tiene un ${type.label.toLowerCase()} asignado '
      '(${occupant.serialCode}). Cada celda admite un solo cátodo y un solo ánodo; '
      'usa "Intercambiar" para moverlos entre celdas.',
    );
  }

  // ── Stats ────────────────────────────────────────────────────────────────

  int get activeCount => _cells.where(hasCompletePair).length;
  int get inactiveCount => _cells.length - activeCount;
  int get componentsInUse => _components.where((c) => c.isInUse).length;
  int get componentsFree => _components.where((c) => c.isFree).length;

  bool isCellBusy(int id) => _busy.contains('cell:$id');
  bool isComponentBusy(int id) => _busy.contains('comp:$id');

  // ── Loading ──────────────────────────────────────────────────────────────

  Future<void> load() async {
    _loading = true;
    _loadError = null;
    notifyListeners();
    try {
      await _readPending();
      await _fetch();
      _loadedOnce = true;
    } on ApiException catch (e) {
      _loadError = e.message;
    } finally {
      _loading = false;
      notifyListeners();
    }
    // Online again: send what was done offline.
    if (_loadedOnce && _pending.isNotEmpty) await syncPending();
  }

  Future<void> _readPending() async {
    if (_pendingRead) return;
    _pending = await _store.read();
    _pendingRead = true;
    if (_pending.isNotEmpty) _scheduleRetry();
  }

  Future<void> _fetch() async {
    final results = await Future.wait([_repository.listCells(), _repository.listComponents()]);
    _cells = results[0] as List<Cell>;
    _components = results[1] as List<Component>;
    _reapplyPending();
  }

  // ── Cells ────────────────────────────────────────────────────────────────

  Future<void> createCell(String name) => _mutate([], () => _repository.createCell(name));

  Future<void> renameCell(Cell cell, String name) =>
      _mutate(['cell:${cell.id}'], () => _repository.updateCell(cell.id, name));

  /// Frees the cell's cathode and anode: the cell becomes inactive.
  Future<void> releaseCell(Cell cell) => _mutate(
        ['cell:${cell.id}', for (final c in componentsOf(cell.id)) 'comp:${c.id}'],
        () => _repository.releaseCell(cell.id),
      );

  /// Removes a cell without components from view; creating one with the same
  /// name brings it back.
  Future<void> hideCell(Cell cell) => _mutate(['cell:${cell.id}'], () => _repository.hideCell(cell.id));

  Future<void> generateBarcode(Cell cell) =>
      _mutate(['cell:${cell.id}'], () => _repository.generateBarcode(cell.id));

  // ── Components ───────────────────────────────────────────────────────────

  Future<void> createComponent({
    required ComponentType type,
    required String serialCode,
    Cell? cell,
  }) async {
    if (cell != null) _ensureRoom(cell, type);
    await _mutate([], () => _repository.createComponent(type: type, serialCode: serialCode, cellId: cell?.id));
  }

  Future<void> editComponent(Component component, {required ComponentType type, required String serialCode}) async {
    // Changing the type of an installed component must not take a slot that is already used.
    final cell = cellById(component.cellId);
    if (cell != null && component.isActive && type != component.type) {
      _ensureRoom(cell, type, exceptComponentId: component.id);
    }
    await _mutate(
      ['comp:${component.id}'],
      () => _repository.updateComponent(component.id, type: type, serialCode: serialCode),
    );
  }

  Future<void> disableComponent(Component component) =>
      _mutate(['comp:${component.id}'], () => _repository.disableComponent(component.id));

  /// A disabled component becomes free again.
  Future<void> reactivateComponent(Component component) =>
      _mutate(['comp:${component.id}'], () => _repository.reactivateComponent(component.id));

  /// Removes a disabled component from view; registering its code again brings it back.
  Future<void> hideComponent(Component component) =>
      _mutate(['comp:${component.id}'], () => _repository.hideComponent(component.id));

  Future<void> assignComponent(Component component, Cell cell) async {
    _ensureRoom(cell, component.type, exceptComponentId: component.id);
    await _mutate(['comp:${component.id}'], () => _repository.assignComponent(component.id, cell.id));
  }

  /// Swaps two installed components of the same type between their cells. If the
  /// server cannot be reached the swap is applied on the device and queued, and
  /// [SwapOutcome.queued] is returned; it is sent when the connection is back.
  Future<SwapOutcome> swapComponents(Component a, Component b) async {
    final keys = ['comp:${a.id}', 'comp:${b.id}'];
    _busy.addAll(keys);
    notifyListeners();
    try {
      await _repository.swapComponents(a.id, b.id);
      try {
        await _fetch();
      } on ApiException {
        // The swap went through; the next refresh will catch up.
      }
      return SwapOutcome.applied;
    } on ApiException catch (e) {
      // A status code means the server answered and refused: a real error.
      if (e.statusCode != null || a.cellId == null || b.cellId == null) rethrow;
      await _queueSwap(PendingSwap(
        aId: a.id,
        bId: b.id,
        aCellId: a.cellId!,
        bCellId: b.cellId!,
        aSerial: a.serialCode,
        bSerial: b.serialCode,
      ));
      return SwapOutcome.queued;
    } finally {
      _busy.removeAll(keys);
      notifyListeners();
    }
  }

  // ── Offline queue ────────────────────────────────────────────────────────

  Future<void> _queueSwap(PendingSwap swap) async {
    _pending = [..._pending, swap];
    _swapLocally(swap.aId, swap.bId);
    await _store.write(_pending);
    _scheduleRetry();
  }

  void _swapLocally(int aId, int bId) {
    final a = _components.where((c) => c.id == aId).firstOrNull;
    final b = _components.where((c) => c.id == bId).firstOrNull;
    if (a == null || b == null) return;
    _components = [
      for (final c in _components)
        if (c.id == aId) c.withCell(b.cellId) else if (c.id == bId) c.withCell(a.cellId) else c,
    ];
  }

  /// A refresh brings the server's state, which does not have the queued swaps
  /// yet: put them back on top so the user keeps seeing what they did.
  void _reapplyPending() {
    for (final swap in _pending) {
      final a = _components.where((c) => c.id == swap.aId).firstOrNull;
      final b = _components.where((c) => c.id == swap.bId).firstOrNull;
      if (a == null || b == null) continue;
      if (a.cellId == swap.aCellId && b.cellId == swap.bCellId) _swapLocally(swap.aId, swap.bId);
    }
  }

  void _scheduleRetry() {
    _retryTimer ??= Timer.periodic(retryEvery, (_) => syncPending());
  }

  void _stopRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  /// Sends the queued swaps. Before each one it checks what the server holds:
  /// a swap whose reply was lost may already be applied (sending it again would
  /// undo it), and one whose cells changed meanwhile no longer makes sense.
  Future<void> syncPending() async {
    if (_pending.isEmpty || _syncing) return;
    _syncing = true;
    notifyListeners();

    var synced = 0;
    final problems = <String>[];
    try {
      final server = [...await _repository.listComponents()];
      Component? find(int id) => server.where((c) => c.id == id).firstOrNull;

      for (final swap in [..._pending]) {
        final a = find(swap.aId);
        final b = find(swap.bId);

        if (a == null || b == null || !a.isActive || !b.isActive) {
          _pending.remove(swap);
          problems.add('${swap.label}: alguno de los componentes ya no está disponible.');
        } else if (a.cellId == swap.bCellId && b.cellId == swap.aCellId) {
          _pending.remove(swap); // already applied on the server
          synced++;
        } else if (a.cellId != swap.aCellId || b.cellId != swap.bCellId) {
          _pending.remove(swap);
          problems.add('${swap.label}: la asignación cambió en el servidor y el intercambio ya no aplica.');
        } else {
          try {
            await _repository.swapComponents(swap.aId, swap.bId);
            _pending.remove(swap);
            synced++;
            server
              ..removeWhere((c) => c.id == a.id || c.id == b.id)
              ..addAll([a.withCell(b.cellId), b.withCell(a.cellId)]);
          } on ApiException catch (e) {
            if (e.statusCode == null) rethrow; // still offline: keep the rest queued
            _pending.remove(swap);
            problems.add('${swap.label}: ${e.message}');
          }
        }
      }
    } on ApiException {
      // Still offline: whatever is left stays queued for the next attempt.
    } finally {
      await _store.write(_pending);
      _syncing = false;
    }

    if (_pending.isEmpty) _stopRetry();
    if (synced > 0 || problems.isNotEmpty) {
      _syncNotice = [
        if (synced > 0) 'Se sincronizaron $synced ${synced == 1 ? 'intercambio' : 'intercambios'} con el servidor.',
        ...problems,
      ].join(' ');
    }
    try {
      await _fetch();
    } on ApiException {
      // Offline again between the two requests; keep the local view.
    }
    notifyListeners();
  }

  void dismissSyncNotice() {
    _syncNotice = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _stopRetry();
    super.dispose();
  }

  /// Runs [action] flagging [keys] as busy, then refreshes. Errors from
  /// [action] propagate (the busy flags are always cleared); a failed refresh
  /// afterwards only leaves the lists as they were.
  Future<void> _mutate(List<String> keys, Future<void> Function() action) async {
    _busy.addAll(keys);
    notifyListeners();
    try {
      await action();
      try {
        await _fetch();
      } on ApiException {
        // The change went through; the next pull-to-refresh will catch up.
      }
    } finally {
      _busy.removeAll(keys);
      notifyListeners();
    }
  }
}
