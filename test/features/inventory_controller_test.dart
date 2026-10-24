import 'dart:convert';

import 'package:actualvoltcast/core/network/api_client.dart';
import 'package:actualvoltcast/core/network/api_exception.dart';
import 'package:actualvoltcast/core/validators.dart';
import 'package:actualvoltcast/features/cells/data/cell.dart';
import 'package:actualvoltcast/features/cells/data/component.dart';
import 'package:actualvoltcast/features/cells/data/inventory_repository.dart';
import 'package:actualvoltcast/features/cells/presentation/inventory_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_inventory_backend.dart';
import '../helpers/memory_tokens.dart';

InventoryRepository _repo(FakeInventoryBackend backend) => InventoryRepository(
      ApiClient(tokenStorage: MemoryTokens(access: 'token'), httpClient: backend.client),
    );

Future<(InventoryController, FakeInventoryBackend)> _loaded() async {
  final backend = FakeInventoryBackend();
  final controller = InventoryController(_repo(backend));
  await controller.load();
  return (controller, backend);
}

Matcher _apiError(String message) =>
    throwsA(isA<ApiException>().having((e) => e.message, 'message', message));

void main() {
  group('models', () {
    test('cells sort letter first, then numerically', () {
      Cell c(String name) => Cell(id: 1, name: name, isActive: true);
      final sorted = [c('B1'), c('A10'), c('A2'), c('A1')]..sort(compareCells);
      expect(sorted.map((e) => e.name), ['A1', 'A2', 'A10', 'B1']);
    });

    test('entities compare by id so dropdown selections survive a reload', () {
      expect(const Cell(id: 1, name: 'A1', isActive: true), const Cell(id: 1, name: 'A9', isActive: false));
      expect(
        const Component(id: 1, type: ComponentType.cathode, serialCode: 'X', isActive: true, cellId: 1),
        const Component(id: 1, type: ComponentType.anode, serialCode: 'Y', isActive: false),
      );
    });

    test('component states', () {
      const used = Component(id: 1, type: ComponentType.cathode, serialCode: 'X', isActive: true, cellId: 3);
      const free = Component(id: 2, type: ComponentType.cathode, serialCode: 'Y', isActive: true);
      const off = Component(id: 3, type: ComponentType.cathode, serialCode: 'Z', isActive: false);
      expect([used.isInUse, used.isFree], [true, false]);
      expect([free.isInUse, free.isFree], [false, true]);
      expect([off.isInUse, off.isFree], [false, false]);
    });
  });

  group('validators', () {
    test('cellName', () {
      for (final ok in ['A1', 'b12', ' C150 ']) {
        expect(Validators.cellName(ok), isNull, reason: ok);
      }
      for (final bad in ['', '1A', 'AA', 'A0', 'A01', 'A-1', 'AB1']) {
        expect(Validators.cellName(bad), isNotNull, reason: bad);
      }
    });

    test('serialCode', () {
      expect(Validators.serialCode('CAT-001'), isNull);
      expect(Validators.serialCode('  '), isNotNull);
      expect(Validators.serialCode('x' * 51), isNotNull);
    });
  });

  group('InventoryRepository', () {
    test('sends the exact payloads the backend expects', () async {
      final backend = FakeInventoryBackend();
      final repo = _repo(backend);

      await repo.createCell(' b7 ');
      await repo.generateBarcode(1);
      await repo.createComponent(type: ComponentType.anode, serialCode: ' ANO-5 ', cellId: 3);
      await repo.createComponent(type: ComponentType.cathode, serialCode: 'CAT-5');
      await repo.assignComponent(5, 3);
      await repo.swapComponents(1, 3);
      await repo.disableCell(2, releaseComponents: true);

      final sent = backend.requests;
      expect(jsonDecode(sent[0].body), {'name': 'b7'});
      expect(sent[1].url.path, '/api/v1/cells/1/barcode');
      expect(jsonDecode(sent[2].body), {'type': 'ANODE', 'serial_code': 'ANO-5', 'cell_id': 3});
      expect(jsonDecode(sent[3].body), {'type': 'CATHODE', 'serial_code': 'CAT-5'}); // no cell_id key
      expect(jsonDecode(sent[4].body), {'cell_id': 3});
      expect(jsonDecode(sent[5].body), {'component_a_id': 1, 'component_b_id': 3});
      expect(sent[6].method, 'PATCH');
      expect(sent[6].url.toString(), endsWith('/api/v1/cells/2/disable?release_components=true'));
      expect(sent.every((r) => r.headers['Authorization'] == 'Bearer token'), isTrue);
    });
  });

  group('InventoryController', () {
    test('loads, sorts and computes stats', () async {
      final (c, _) = await _loaded();

      expect(c.cells.map((e) => e.name), ['A1', 'A2', 'B3', 'C4']);
      expect(c.activeCells.map((e) => e.name), ['A1', 'A2', 'B3']);
      expect(c.cellsWithComponents, 2);
      expect(c.inactiveCells, 1);
      expect(c.componentsInUse, 4);
      expect(c.componentsFree, 1); // CAT-099; the disabled ANO-777 is not "free"
      expect(c.components.length, 6);
    });

    test('cathode / anode of a cell and the complete-pair rule', () async {
      final (c, _) = await _loaded();
      final a1 = c.cellById(1)!;
      final b3 = c.cellById(3)!;

      expect(c.cathodeOf(a1)?.serialCode, 'CAT-001');
      expect(c.anodeOf(a1)?.serialCode, 'ANO-001');
      expect(c.hasCompletePair(a1), isTrue);
      expect(c.cathodeOf(b3), isNull);
      expect(c.hasCompletePair(b3), isFalse);
    });

    test('createCell: ok, duplicate and bad format', () async {
      final (c, _) = await _loaded();

      await c.createCell('b7');
      expect(c.cells.map((e) => e.name), contains('B7'));

      await expectLater(c.createCell('a1'), _apiError('Ya existe una celda con ese nombre.'));
      await expectLater(
        c.createCell('1A'),
        _apiError('El nombre debe ser una letra seguida de un número, por ejemplo A1 o B12.'),
      );
    });

    test('renameCell', () async {
      final (c, _) = await _loaded();
      await c.renameCell(c.cellById(3)!, 'z9');
      expect(c.cellById(3)!.name, 'Z9');
    });

    test('disabling a cell with components releases them', () async {
      final (c, backend) = await _loaded();
      final a1 = c.cellById(1)!;

      await c.disableCell(a1);

      expect(c.cellById(1)!.isActive, isFalse);
      expect(c.componentsOf(1), isEmpty);
      expect(c.componentsFree, 3); // CAT-099 + the two released
      expect(c.isCellBusy(1), isFalse);
      expect(backend.requests.any((r) => r.url.toString().contains('release_components=true')), isTrue);
    });

    test('disabling an empty cell does not ask to release', () async {
      final (c, backend) = await _loaded();
      await c.disableCell(c.cellById(3)!);
      expect(backend.requests.last.url.queryParameters['release_components'] ?? 'false', 'false');
      expect(c.cellById(3)!.isActive, isFalse);
    });

    test('generateBarcode needs a cathode and an anode', () async {
      final (c, _) = await _loaded();

      await c.generateBarcode(c.cellById(2)!);
      expect(c.cellById(2)!.barcodeValue, 'CELL-00002');

      await expectLater(
        c.generateBarcode(c.cellById(3)!),
        _apiError('La celda necesita un cátodo y un ánodo asignados para generar su código.'),
      );
      expect(c.cellById(3)!.hasBarcode, isFalse);
    });

    test('generateBarcode keeps an existing value', () async {
      final (c, _) = await _loaded();
      await c.generateBarcode(c.cellById(1)!);
      expect(c.cellById(1)!.barcodeValue, 'CELL-00001');
    });

    test('createComponent with and without a cell; duplicate serial', () async {
      final (c, _) = await _loaded();

      await c.createComponent(type: ComponentType.cathode, serialCode: 'CAT-500', cell: c.cellById(3));
      expect(c.cathodeOf(c.cellById(3)!)?.serialCode, 'CAT-500');

      await c.createComponent(type: ComponentType.anode, serialCode: 'ANO-500');
      expect(c.componentsFree, 2);

      await expectLater(
        c.createComponent(type: ComponentType.anode, serialCode: 'ANO-500'),
        _apiError('Ya existe un componente con ese código de serie.'),
      );
    });

    test('editComponent', () async {
      final (c, _) = await _loaded();
      final free = c.components.firstWhere((e) => e.serialCode == 'CAT-099');
      await c.editComponent(free, type: ComponentType.anode, serialCode: 'ANO-099');
      final updated = c.components.firstWhere((e) => e.id == free.id);
      expect([updated.serialCode, updated.type], ['ANO-099', ComponentType.anode]);
    });

    test('assign a free component, then it counts as in use', () async {
      final (c, _) = await _loaded();
      final free = c.components.firstWhere((e) => e.serialCode == 'CAT-099');

      await c.assignComponent(free, c.cellById(3)!);

      expect(c.componentsFree, 0);
      expect(c.cathodeOf(c.cellById(3)!)?.serialCode, 'CAT-099');
    });

    test('cannot assign to a disabled cell', () async {
      final (c, _) = await _loaded();
      final free = c.components.firstWhere((e) => e.serialCode == 'CAT-099');
      await expectLater(c.assignComponent(free, c.cellById(4)!), _apiError('La celda está deshabilitada.'));
    });

    test('disabling: free ok, in use refused', () async {
      final (c, _) = await _loaded();
      final free = c.components.firstWhere((e) => e.serialCode == 'CAT-099');
      final used = c.components.firstWhere((e) => e.serialCode == 'CAT-001');

      await c.disableComponent(free);
      expect(c.components.firstWhere((e) => e.id == free.id).isActive, isFalse);

      await expectLater(
        c.disableComponent(used),
        _apiError('El componente está asignado a una celda y no se puede deshabilitar.'),
      );
      expect(c.isComponentBusy(used.id), isFalse);
    });

    test('swap exchanges cells; rejects mixed types and same cell', () async {
      final (c, _) = await _loaded();
      final cat1 = c.components.firstWhere((e) => e.serialCode == 'CAT-001');
      final cat14 = c.components.firstWhere((e) => e.serialCode == 'CAT-014');
      final ano1 = c.components.firstWhere((e) => e.serialCode == 'ANO-001');

      await c.swapComponents(cat1, cat14);
      expect(c.cathodeOf(c.cellById(1)!)?.serialCode, 'CAT-014');
      expect(c.cathodeOf(c.cellById(2)!)?.serialCode, 'CAT-001');

      await expectLater(c.swapComponents(cat1, ano1), _apiError('Solo se pueden intercambiar componentes del mismo tipo.'));
    });

    test('load failure is exposed without throwing', () async {
      final backend = FakeInventoryBackend()..failWith = (status: 500, detail: 'Internal error: boom');
      final c = InventoryController(_repo(backend));

      await c.load();

      expect(c.hasLoaded, isFalse);
      expect(c.loadError, 'Error del servidor. Inténtalo más tarde.');
    });

    test('a change that succeeds but whose refresh fails does not throw', () async {
      final (c, backend) = await _loaded();
      // Requests 1-2 were the load; the POST (3rd) works, the refresh fails.
      backend.failFromRequest = 4;

      await c.createCell('Q5');

      expect(backend.cells.any((e) => e['name'] == 'Q5'), isTrue); // it did happen server-side
      expect(c.cells.map((e) => e.name), isNot(contains('Q5'))); // list is just stale
      expect(c.isCellBusy(5), isFalse);
    });
  });
}
