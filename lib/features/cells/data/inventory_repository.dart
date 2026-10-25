import '../../../core/network/api_client.dart';
import 'cell.dart';
import 'component.dart';

/// `/cells` and `/components` endpoints. Any signed-in user may use them.
class InventoryRepository {
  InventoryRepository(this._api);

  final ApiClient _api;

  // ── Cells ────────────────────────────────────────────────────────────────

  Future<List<Cell>> listCells() async {
    final data = await _api.get('/cells', auth: true) as List;
    return data.map((e) => Cell.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Cell> createCell(String name) async => Cell.fromJson(
        await _api.post('/cells', body: {'name': name.trim()}, auth: true) as Map<String, dynamic>,
      );

  Future<Cell> updateCell(int id, String name) async => Cell.fromJson(
        await _api.put('/cells/$id', body: {'name': name.trim()}, auth: true) as Map<String, dynamic>,
      );

  /// Frees the cell's cathode and anode; the cell becomes inactive.
  Future<Cell> releaseCell(int id) async =>
      Cell.fromJson(await _api.patch('/cells/$id/release', auth: true) as Map<String, dynamic>);

  /// Removes a cell without components from view (it is kept in the database).
  Future<Cell> hideCell(int id) async =>
      Cell.fromJson(await _api.patch('/cells/$id/hide', auth: true) as Map<String, dynamic>);

  /// Idempotent: keeps the value if the cell already has one.
  Future<Cell> generateBarcode(int id) async => Cell.fromJson(
        await _api.post('/cells/$id/barcode', auth: true) as Map<String, dynamic>,
      );

  // ── Components ───────────────────────────────────────────────────────────

  Future<List<Component>> listComponents() async {
    final data = await _api.get('/components', auth: true) as List;
    return data.map((e) => Component.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Component> createComponent({
    required ComponentType type,
    required String serialCode,
    int? cellId,
  }) async =>
      Component.fromJson(
        await _api.post(
          '/components',
          body: {
            'type': type.apiName,
            'serial_code': serialCode.trim(),
            'cell_id': ?cellId,
          },
          auth: true,
        ) as Map<String, dynamic>,
      );

  Future<Component> updateComponent(int id, {ComponentType? type, String? serialCode}) async =>
      Component.fromJson(
        await _api.put(
          '/components/$id',
          body: {
            'type': ?type?.apiName,
            'serial_code': ?serialCode?.trim(),
          },
          auth: true,
        ) as Map<String, dynamic>,
      );

  Future<Component> disableComponent(int id) async => Component.fromJson(
        await _api.patch('/components/$id/disable', auth: true) as Map<String, dynamic>,
      );

  Future<Component> reactivateComponent(int id) async =>
      Component.fromJson(await _api.patch('/components/$id/reactivate', auth: true) as Map<String, dynamic>);

  Future<Component> hideComponent(int id) async =>
      Component.fromJson(await _api.patch('/components/$id/hide', auth: true) as Map<String, dynamic>);

  Future<Component> assignComponent(int id, int cellId) async => Component.fromJson(
        await _api.post('/components/$id/assign', body: {'cell_id': cellId}, auth: true)
            as Map<String, dynamic>,
      );

  /// Same type, both assigned, different cells.
  Future<void> swapComponents(int aId, int bId) async {
    await _api.post(
      '/components/swap',
      body: {'component_a_id': aId, 'component_b_id': bId},
      auth: true,
    );
  }
}
