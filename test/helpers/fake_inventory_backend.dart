import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Stateful stand-in for `/cells` and `/components` that enforces the same
/// business rules (and error messages) as the real backend.
class FakeInventoryBackend {
  FakeInventoryBackend() {
    client = MockClient(_handle);
  }

  late final MockClient client;
  final requests = <http.Request>[];

  /// When set, every request fails with this status/detail.
  ({int status, String detail})? failWith;

  /// While true every request fails like a lost connection (no HTTP answer).
  bool offline = false;

  /// Requests that actually reached the swap endpoint (to prove a swap is not re-sent).
  int swapRequests = 0;

  /// When set, the swap endpoint answers 400 with this message (the rest keeps working).
  String? refuseSwaps;

  /// 1-based index of the first request that fails with a 500 (e.g. to make
  /// only the refresh after a mutation fail).
  int? failFromRequest;

  final cells = <Map<String, dynamic>>[
    _cell(1, 'A1', 'CELL-00001', true),
    _cell(2, 'A2', null, true),
    _cell(3, 'B3', null, true),
    _cell(4, 'C4', null, false),
  ];

  final components = <Map<String, dynamic>>[
    _component(1, 'CATHODE', 'CAT-001', 1),
    _component(2, 'ANODE', 'ANO-001', 1),
    _component(3, 'CATHODE', 'CAT-014', 2),
    _component(4, 'ANODE', 'ANO-014', 2),
    _component(5, 'CATHODE', 'CAT-099', null),
    _component(6, 'ANODE', 'ANO-777', null, active: false),
  ];

  static Map<String, dynamic> _cell(int id, String name, String? barcode, bool active) =>
      {'id': id, 'name': name, 'barcode_value': barcode, 'is_active': active};

  static Map<String, dynamic> _component(int id, String type, String serial, int? cellId, {bool active = true}) =>
      {'id': id, 'type': type, 'serial_code': serial, 'is_active': active, 'cell_id': cellId};

  Map<String, dynamic> cell(int id) => cells.firstWhere((c) => c['id'] == id);
  Map<String, dynamic> component(int id) => components.firstWhere((c) => c['id'] == id);

  List<Map<String, dynamic>> _assigned(int cellId) =>
      components.where((c) => c['is_active'] == true && c['cell_id'] == cellId).toList();

  http.Response _json(int status, Object body) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  http.Response _bad(String message) => _json(400, {'detail': message});

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    if (offline) throw http.ClientException('connection lost');
    final fail = failWith;
    if (fail != null) return _json(fail.status, {'detail': fail.detail});
    if (failFromRequest != null && requests.length >= failFromRequest!) {
      return _json(500, {'detail': 'Internal error: boom'});
    }

    final path = request.url.path.replaceFirst('/api/v1', '');
    final body = request.body.isEmpty ? <String, dynamic>{} : jsonDecode(request.body) as Map<String, dynamic>;

    if (request.method == 'GET' && path == '/cells') return _json(200, cells);
    if (request.method == 'GET' && path == '/components') return _json(200, components);

    if (request.method == 'POST' && path == '/cells') {
      final name = (body['name'] as String).trim().toUpperCase();
      if (!RegExp(r'^[A-Z][1-9][0-9]*$').hasMatch(name)) {
        return _bad('Cell name must be a letter followed by a number, e.g. A1, B12');
      }
      if (cells.any((c) => c['name'] == name)) return _bad("Cell '$name' already exists");
      final created = _cell(cells.length + 1, name, null, true);
      cells.add(created);
      return _json(201, created);
    }

    final cellMatch = RegExp(r'^/cells/(\d+)(?:/(disable|barcode))?$').firstMatch(path);
    if (cellMatch != null) {
      final id = int.parse(cellMatch.group(1)!);
      final target = cells.where((c) => c['id'] == id).firstOrNull;
      if (target == null) return _bad('Cell not found: $id');

      switch (cellMatch.group(2)) {
        case 'disable':
          final assigned = _assigned(id);
          final release = request.url.queryParameters['release_components'] == 'true';
          if (assigned.isNotEmpty && !release) {
            return _bad(
              'Cell has assigned cathodes/anodes; release them first or disable with release_components=true',
            );
          }
          for (final c in assigned) {
            c['cell_id'] = null;
          }
          if (target['is_active'] != true) return _bad('Cell is already disabled');
          target['is_active'] = false;
        case 'barcode':
          final types = _assigned(id).map((c) => c['type']).toSet();
          if (!(types.contains('CATHODE') && types.contains('ANODE'))) {
            return _bad('Cell must have an assigned cathode and anode to generate its barcode');
          }
          if (target['is_active'] != true) return _bad('Cannot generate a barcode for a disabled cell');
          target['barcode_value'] ??= 'CELL-${id.toString().padLeft(5, '0')}';
        default: // PUT rename
          final name = (body['name'] as String).trim().toUpperCase();
          if (!RegExp(r'^[A-Z][1-9][0-9]*$').hasMatch(name)) {
            return _bad('Cell name must be a letter followed by a number, e.g. A1, B12');
          }
          if (name != target['name'] && cells.any((c) => c['name'] == name)) {
            return _bad("Cell '$name' already exists");
          }
          target['name'] = name;
      }
      return _json(200, target);
    }

    if (request.method == 'POST' && path == '/components/swap') {
      swapRequests++;
      if (refuseSwaps != null) return _bad(refuseSwaps!);
      final a = component(body['component_a_id'] as int);
      final b = component(body['component_b_id'] as int);
      if (a['type'] != b['type']) {
        return _bad('Can only swap components of the same type (CATHODE with CATHODE, ANODE with ANODE)');
      }
      if (a['cell_id'] == null || b['cell_id'] == null) {
        return _bad('Both components must be assigned to a cell to be swapped');
      }
      if (a['cell_id'] == b['cell_id']) return _bad('Components belong to the same cell');
      final tmp = a['cell_id'];
      a['cell_id'] = b['cell_id'];
      b['cell_id'] = tmp;
      return _json(200, [a, b]);
    }

    if (request.method == 'POST' && path == '/components') {
      final serial = (body['serial_code'] as String).trim();
      if (components.any((c) => c['serial_code'] == serial)) {
        return _bad("Component with serial code '$serial' already exists");
      }
      final created = _component(components.length + 1, body['type'] as String, serial, body['cell_id'] as int?);
      components.add(created);
      return _json(201, created);
    }

    final compMatch = RegExp(r'^/components/(\d+)(?:/(disable|assign))?$').firstMatch(path);
    if (compMatch != null) {
      final id = int.parse(compMatch.group(1)!);
      final target = components.where((c) => c['id'] == id).firstOrNull;
      if (target == null) return _bad('Component not found: $id');

      switch (compMatch.group(2)) {
        case 'disable':
          if (target['is_active'] != true) return _bad('Component is already disabled');
          if (target['cell_id'] != null) return _bad('Component is in use: it is assigned to a cell');
          target['is_active'] = false;
        case 'assign':
          final dest = cell(body['cell_id'] as int);
          if (dest['is_active'] != true) return _bad('Cell is disabled: ${dest['id']}');
          if (target['is_active'] != true) return _bad('Cannot assign a disabled component');
          target['cell_id'] = dest['id'];
        default: // PUT
          final serial = body['serial_code'] as String?;
          if (serial != null &&
              serial != target['serial_code'] &&
              components.any((c) => c['serial_code'] == serial)) {
            return _bad("Component with serial code '$serial' already exists");
          }
          if (serial != null) target['serial_code'] = serial;
          if (body['type'] != null) target['type'] = body['type'];
      }
      return _json(200, target);
    }

    return _json(404, {'detail': 'Not found'});
  }
}
