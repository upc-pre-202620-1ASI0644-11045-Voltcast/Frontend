import 'dart:convert';

import 'package:actualvoltcast/core/network/api_client.dart';
import 'package:actualvoltcast/core/network/api_exception.dart';
import 'package:actualvoltcast/core/network/backend_messages.dart';
import 'package:actualvoltcast/core/validators.dart';
import 'package:actualvoltcast/features/cells/data/cell.dart';
import 'package:actualvoltcast/features/cells/data/component.dart';
import 'package:actualvoltcast/features/cells/data/inventory_repository.dart';
import 'package:actualvoltcast/features/cells/data/pending_swap.dart';
import 'package:actualvoltcast/features/cells/presentation/inventory_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_inventory_backend.dart';
import '../helpers/memory_tokens.dart';

InventoryRepository _repo(FakeInventoryBackend backend) => InventoryRepository(
      ApiClient(tokenStorage: MemoryTokens(access: 'token'), httpClient: backend.client),
    );

Future<(InventoryController, FakeInventoryBackend)> _loaded({
  MemoryPendingSwapStore? store,
  FakeInventoryBackend? backend,
  Duration retryEvery = const Duration(minutes: 5),
}) async {
  backend ??= FakeInventoryBackend();
  final controller = InventoryController(
    _repo(backend),
    store: store ?? MemoryPendingSwapStore(),
    retryEvery: retryEvery,
  );
  addTearDown(controller.dispose);
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

    test('US011 E02: a cell with components is refused while they are assigned', () async {
      final (c, backend) = await _loaded();

      await expectLater(c.disableCell(c.cellById(1)!), _apiError(cellHasComponentsMessage));

      expect(c.cellById(1)!.isActive, isTrue);
      expect(c.componentsOf(1), hasLength(2)); // nothing was released
      expect(backend.requests.last.url.queryParameters['release_components'], 'false');
    });

    test('US011 E03: releasing the components frees them and disables the cell', () async {
      final (c, backend) = await _loaded();
      final a1 = c.cellById(1)!;

      await c.disableCell(a1, release: true);

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
        _apiError('El componente está en uso: está asignado a una celda y no se puede deshabilitar.'),
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
      final c = InventoryController(_repo(backend), store: MemoryPendingSwapStore());
      addTearDown(c.dispose);

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

  group('one cathode and one anode per cell', () {
    test('cellsAccepting only lists cells with room for that type', () async {
      final (c, _) = await _loaded();

      // A1 and A2 already hold a cathode and an anode; B3 is empty.
      expect(c.cellsAccepting(ComponentType.cathode).map((e) => e.name), ['B3']);
      expect(c.cellsAccepting(ComponentType.anode).map((e) => e.name), ['B3']);
    });

    test('a component does not block its own cell', () async {
      final (c, _) = await _loaded();
      final cat1 = c.components.firstWhere((e) => e.serialCode == 'CAT-001');

      final names = c.cellsAccepting(ComponentType.cathode, exceptComponentId: cat1.id).map((e) => e.name);
      expect(names, ['A1', 'B3']);
    });

    test('registering a second cathode in a cell is refused', () async {
      final (c, backend) = await _loaded();

      await expectLater(
        c.createComponent(type: ComponentType.cathode, serialCode: 'CAT-200', cell: c.cellById(1)),
        throwsA(isA<ApiException>().having(
          (e) => e.message,
          'message',
          allOf(contains('A1'), contains('CAT-001'), contains('un solo cátodo')),
        )),
      );
      // It never reached the server.
      expect(backend.components.any((e) => e['serial_code'] == 'CAT-200'), isFalse);
    });

    test('assigning to a cell that already has that type is refused, an empty cell is fine', () async {
      final (c, _) = await _loaded();
      final free = c.components.firstWhere((e) => e.serialCode == 'CAT-099');

      await expectLater(c.assignComponent(free, c.cellById(1)!), throwsA(isA<ApiException>()));
      expect(c.cathodeOf(c.cellById(1)!)?.serialCode, 'CAT-001');

      await c.assignComponent(free, c.cellById(3)!);
      expect(c.cathodeOf(c.cellById(3)!)?.serialCode, 'CAT-099');
    });

    test('a cathode and an anode can share a cell', () async {
      final (c, _) = await _loaded();
      await c.createComponent(type: ComponentType.cathode, serialCode: 'CAT-300', cell: c.cellById(3));
      await c.createComponent(type: ComponentType.anode, serialCode: 'ANO-300', cell: c.cellById(3));

      expect(c.hasCompletePair(c.cellById(3)!), isTrue);
      expect(c.componentsOf(3), hasLength(2));
    });

    test('changing the type of an installed component cannot take an occupied slot', () async {
      final (c, _) = await _loaded();
      // CAT-014 sits in A2, which already has an anode.
      final cat14 = c.components.firstWhere((e) => e.serialCode == 'CAT-014');

      await expectLater(
        c.editComponent(cat14, type: ComponentType.anode, serialCode: 'CAT-014'),
        throwsA(isA<ApiException>()),
      );
      expect(c.components.firstWhere((e) => e.id == cat14.id).type, ComponentType.cathode);
    });

    test('swapping keeps the rule: each cell still has one of each', () async {
      final (c, _) = await _loaded();
      final cat1 = c.components.firstWhere((e) => e.serialCode == 'CAT-001');
      final cat14 = c.components.firstWhere((e) => e.serialCode == 'CAT-014');

      await c.swapComponents(cat1, cat14);

      expect(c.componentsOf(1).where((e) => e.type == ComponentType.cathode), hasLength(1));
      expect(c.componentsOf(2).where((e) => e.type == ComponentType.cathode), hasLength(1));
    });
  });

  group('US014 E02: swapping without a connection', () {
    Component find(InventoryController c, String serial) =>
        c.components.firstWhere((e) => e.serialCode == serial);

    test('is applied on the device and queued', () async {
      final store = MemoryPendingSwapStore();
      final (c, backend) = await _loaded(store: store);
      backend.offline = true;

      final outcome = await c.swapComponents(find(c, 'CAT-001'), find(c, 'CAT-014'));

      expect(outcome, SwapOutcome.queued);
      expect(c.pendingCount, 1);
      expect(c.cathodeOf(c.cellById(1)!)?.serialCode, 'CAT-014'); // visible immediately
      expect(c.cathodeOf(c.cellById(2)!)?.serialCode, 'CAT-001');
      expect(backend.component(1)['cell_id'], 1); // the server has not heard about it
      expect(await store.read(), hasLength(1)); // and it survives a restart
      expect(c.isComponentBusy(1), isFalse);
    });

    test('is sent when the connection is back', () async {
      final store = MemoryPendingSwapStore();
      final (c, backend) = await _loaded(store: store);
      backend.offline = true;
      await c.swapComponents(find(c, 'CAT-001'), find(c, 'CAT-014'));

      backend.offline = false;
      await c.syncPending();

      expect(c.pendingCount, 0);
      expect(backend.component(1)['cell_id'], 2);
      expect(backend.component(3)['cell_id'], 1);
      expect(backend.swapRequests, 1);
      expect(c.syncNotice, 'Se sincronizaron 1 intercambio con el servidor.');
      expect(await store.read(), isEmpty);
      expect(c.cathodeOf(c.cellById(1)!)?.serialCode, 'CAT-014'); // not reverted by the refresh
    });

    test('stays queued while there is still no connection', () async {
      final (c, backend) = await _loaded();
      backend.offline = true;
      await c.swapComponents(find(c, 'CAT-001'), find(c, 'CAT-014'));

      await c.syncPending();

      expect(c.pendingCount, 1);
      expect(c.syncNotice, isNull);
      expect(c.cathodeOf(c.cellById(1)!)?.serialCode, 'CAT-014');
    });

    test('is not sent twice when the first attempt had in fact reached the server', () async {
      final (c, backend) = await _loaded();
      backend.offline = true;
      await c.swapComponents(find(c, 'CAT-001'), find(c, 'CAT-014'));
      // The request got through but its answer was lost: the server already swapped them.
      backend.component(1)['cell_id'] = 2;
      backend.component(3)['cell_id'] = 1;

      backend.offline = false;
      await c.syncPending();

      expect(backend.swapRequests, 0); // re-sending would have undone it
      expect(backend.component(1)['cell_id'], 2);
      expect(c.pendingCount, 0);
      expect(c.cathodeOf(c.cellById(1)!)?.serialCode, 'CAT-014');
    });

    test('is dropped with a message if the cells changed on the server meanwhile', () async {
      final (c, backend) = await _loaded();
      backend.offline = true;
      await c.swapComponents(find(c, 'CAT-001'), find(c, 'CAT-014'));
      backend.component(1)['cell_id'] = 3; // someone moved CAT-001 elsewhere

      backend.offline = false;
      await c.syncPending();

      expect(backend.swapRequests, 0);
      expect(c.pendingCount, 0);
      expect(c.syncNotice, allOf(contains('CAT-001'), contains('ya no aplica')));
      expect(c.cathodeOf(c.cellById(3)!)?.serialCode, 'CAT-001'); // shows the server's truth
    });

    test('is dropped with the reason if the server refuses it', () async {
      final (c, backend) = await _loaded();
      backend.offline = true;
      await c.swapComponents(find(c, 'CAT-001'), find(c, 'CAT-014'));

      backend.offline = false;
      backend.failFromRequest = null;
      // The server answers, but refuses the swap itself.
      backend.refuseSwaps = 'Components belong to the same cell';
      await c.syncPending();

      expect(c.pendingCount, 0);
      expect(c.syncNotice, contains('pertenecen a la misma celda'));
    });

    test('a refusal from the server is an error, not something to queue', () async {
      final (c, _) = await _loaded();

      await expectLater(
        c.swapComponents(find(c, 'CAT-001'), find(c, 'ANO-014')), // different types
        _apiError('Solo se pueden intercambiar componentes del mismo tipo.'),
      );
      expect(c.pendingCount, 0);
    });

    test('queued swaps are restored and sent when the app starts again', () async {
      final backend = FakeInventoryBackend();
      final store = MemoryPendingSwapStore([
        const PendingSwap(aId: 1, bId: 3, aCellId: 1, bCellId: 2, aSerial: 'CAT-001', bSerial: 'CAT-014'),
      ]);

      final (c, _) = await _loaded(store: store, backend: backend);

      expect(c.pendingCount, 0);
      expect(backend.component(1)['cell_id'], 2);
      expect(backend.component(3)['cell_id'], 1);
      expect(c.cathodeOf(c.cellById(1)!)?.serialCode, 'CAT-014');
    });

    test('retries by itself while swaps are queued', () async {
      final (c, backend) = await _loaded(retryEvery: const Duration(milliseconds: 30));
      backend.offline = true;
      await c.swapComponents(find(c, 'CAT-001'), find(c, 'CAT-014'));

      backend.offline = false;
      for (var i = 0; i < 40 && c.pendingCount > 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      expect(c.pendingCount, 0);
      expect(backend.component(1)['cell_id'], 2);
    });

    test('the sync notice can be dismissed', () async {
      final (c, backend) = await _loaded();
      backend.offline = true;
      await c.swapComponents(find(c, 'CAT-001'), find(c, 'CAT-014'));
      backend.offline = false;
      await c.syncPending();

      c.dismissSyncNotice();

      expect(c.syncNotice, isNull);
    });
  });
}
