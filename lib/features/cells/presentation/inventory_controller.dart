import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../data/cell.dart';
import '../data/component.dart';
import '../data/inventory_repository.dart';

/// Shared state of the Celdas, Componentes and Código de barras screens, which
/// all derive from the same two lists. Mutations refresh both lists afterwards
/// because one action can touch several rows (disabling a cell frees its
/// components; a swap moves two).
class InventoryController extends ChangeNotifier {
  InventoryController(this._repository);

  final InventoryRepository _repository;

  List<Cell> _cells = [];
  List<Component> _components = [];
  bool _loading = false;
  bool _loadedOnce = false;
  String? _loadError;
  final Set<String> _busy = {};

  bool get loading => _loading;
  bool get hasLoaded => _loadedOnce;
  String? get loadError => _loadError;

  List<Cell> get cells => ([..._cells]..sort(compareCells));
  List<Cell> get activeCells => cells.where((c) => c.isActive).toList();
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

  // ── Stats ────────────────────────────────────────────────────────────────

  int get cellsWithComponents => _cells.where((c) => c.isActive && componentsOf(c.id).isNotEmpty).length;
  int get inactiveCells => _cells.where((c) => !c.isActive).length;
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
      await _fetch();
      _loadedOnce = true;
    } on ApiException catch (e) {
      _loadError = e.message;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _fetch() async {
    final results = await Future.wait([_repository.listCells(), _repository.listComponents()]);
    _cells = results[0] as List<Cell>;
    _components = results[1] as List<Component>;
  }

  // ── Cells ────────────────────────────────────────────────────────────────

  Future<void> createCell(String name) => _mutate([], () => _repository.createCell(name));

  Future<void> renameCell(Cell cell, String name) =>
      _mutate(['cell:${cell.id}'], () => _repository.updateCell(cell.id, name));

  /// Releases the cell's components first when it has any.
  Future<void> disableCell(Cell cell) => _mutate(
        ['cell:${cell.id}', for (final c in componentsOf(cell.id)) 'comp:${c.id}'],
        () => _repository.disableCell(cell.id, releaseComponents: componentsOf(cell.id).isNotEmpty),
      );

  Future<void> generateBarcode(Cell cell) =>
      _mutate(['cell:${cell.id}'], () => _repository.generateBarcode(cell.id));

  // ── Components ───────────────────────────────────────────────────────────

  Future<void> createComponent({
    required ComponentType type,
    required String serialCode,
    Cell? cell,
  }) =>
      _mutate([], () => _repository.createComponent(type: type, serialCode: serialCode, cellId: cell?.id));

  Future<void> editComponent(Component component, {required ComponentType type, required String serialCode}) =>
      _mutate(
        ['comp:${component.id}'],
        () => _repository.updateComponent(component.id, type: type, serialCode: serialCode),
      );

  Future<void> disableComponent(Component component) =>
      _mutate(['comp:${component.id}'], () => _repository.disableComponent(component.id));

  Future<void> assignComponent(Component component, Cell cell) =>
      _mutate(['comp:${component.id}'], () => _repository.assignComponent(component.id, cell.id));

  Future<void> swapComponents(Component a, Component b) =>
      _mutate(['comp:${a.id}', 'comp:${b.id}'], () => _repository.swapComponents(a.id, b.id));

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
