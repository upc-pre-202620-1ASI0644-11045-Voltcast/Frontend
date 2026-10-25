import 'package:actualvoltcast/core/network/api_client.dart';
import 'package:actualvoltcast/core/theme/app_theme.dart';
import 'package:actualvoltcast/features/cells/data/inventory_repository.dart';
import 'package:actualvoltcast/features/cells/data/pending_swap.dart';
import 'package:actualvoltcast/features/cells/presentation/cell_sounds.dart';
import 'package:actualvoltcast/features/cells/presentation/inventory_controller.dart';
import 'package:actualvoltcast/features/cells/presentation/cell_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../helpers/fake_inventory_backend.dart';
import '../helpers/memory_tokens.dart';

Future<FakeInventoryBackend> _pump(
  WidgetTester tester, {
  FakeInventoryBackend? backend,
  double height = 800,
  ProductionLineScreen screen = const ProductionLineScreen(),
}) async {
  CellSounds.enabled = false; // no audio backend in widget tests
  tester.view.physicalSize = Size(400, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  backend ??= FakeInventoryBackend();
  final repository = InventoryRepository(
    ApiClient(
      tokenStorage: MemoryTokens(access: 'token'),
      httpClient: backend.client,
    ),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: ChangeNotifierProvider(
        create: (_) =>
            InventoryController(repository, store: MemoryPendingSwapStore(), retryEvery: const Duration(hours: 1))
              ..load(),
        child: screen,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return backend;
}

/// Scrolls the line until [key] is built (tiles off screen do not exist) and taps it.
Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  if (finder.evaluate().isEmpty) {
    await tester.dragUntilVisible(finder, find.byType(CustomScrollView), const Offset(0, -200));
  }
  // Only scroll when needed: ensureVisible would also move what is already on screen.
  final screen = Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);
  if (!screen.contains(tester.getCenter(finder))) {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Opens a closed (complete) cell through its lid and the confirmation.
Future<void> _openCell(WidgetTester tester, int id) async {
  await _tapKey(tester, 'line-lid-$id');
  expect(find.textContaining('¿Desea abrir la celda'), findsOneWidget);
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
}

InventoryController _inventory(WidgetTester tester) =>
    Provider.of<InventoryController>(tester.element(find.byType(ProductionLineScreen)), listen: false);

void main() {
  testWidgets('greets the user by name and can sign out', (tester) async {
    var signedOut = false;
    await _pump(
      tester,
      screen: ProductionLineScreen(userName: 'Oscar', onLogout: () => signedOut = true),
    );

    expect(find.text('Celdas'), findsOneWidget);
    expect(find.text('Oscar · 4 celdas'), findsOneWidget);
    expect(find.byTooltip('Volver'), findsNothing); // the home tab has nowhere to go back to

    await tester.tap(find.byTooltip('Cerrar sesión'));
    expect(signedOut, isTrue);
  });

  testWidgets('lays out 150 cells from the backend but only builds the visible ones', (tester) async {
    final backend = FakeInventoryBackend();
    backend.cells.addAll([
      for (var i = 5; i <= 150; i++) {'id': i, 'name': 'L$i', 'barcode_value': null, 'is_visible': true},
    ]);
    await _pump(tester, backend: backend);

    expect(find.text('150 celdas'), findsOneWidget);
    expect(find.textContaining('Celda '), findsWidgets);
    expect(find.textContaining('Celda ').evaluate().length, lessThan(10));

    await tester.dragUntilVisible(find.text('Celda L150'), find.byType(CustomScrollView), const Offset(0, -2000));
    expect(find.text('Celda L150'), findsOneWidget);
    expect(find.text('Celda A1'), findsNothing); // scrolled out and disposed
  });

  testWidgets('a cell with both components starts closed and only opens after confirming', (tester) async {
    await _pump(tester);

    // A1 has an anode and a cathode: the lid covers them, so a tap asks first.
    expect(find.byKey(const ValueKey('line-lid-1')), findsOneWidget);
    await _tapKey(tester, 'line-lid-1');
    expect(find.text('¿Desea abrir la celda A1?'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('line-lid-1')), findsOneWidget);

    await _openCell(tester, 1);
    expect(find.byKey(const ValueKey('line-lid-1')), findsNothing);

    // And it can be closed again.
    await tester.tap(find.text('Cerrar celda'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('line-lid-1')), findsOneWidget);
  });

  testWidgets('a cell closes by itself once it gets both components', (tester) async {
    final backend = FakeInventoryBackend();
    backend.components.add({
      'id': 50,
      'type': 'ANODE',
      'serial_code': 'ANO-050',
      'is_active': true,
      'is_visible': true,
      'cell_id': null,
    });
    await _pump(tester, backend: backend, height: 1400);
    expect(find.byKey(const ValueKey('line-lid-3')), findsNothing); // B3 is empty

    final inventory = _inventory(tester);
    final b3 = inventory.cellById(3)!;
    for (final id in [5, 50]) {
      final done = inventory.assignComponent(inventory.components.firstWhere((c) => c.id == id), b3);
      await tester.pumpAndSettle();
      await done;
    }
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('line-lid-3')), findsOneWidget);
  });

  testWidgets('tapping an anode flies into a view of that bar with its current data', (tester) async {
    final backend = await _pump(tester);
    await _openCell(tester, 1);
    final before = backend.requests.length;

    await _tapKey(tester, 'line-anode-1');

    expect(find.text('Volver a la línea'), findsOneWidget);
    expect(find.text('Vista del componente'), findsOneWidget);
    expect(find.text('Ánodo · ANO-001'), findsOneWidget);
    expect(find.text('#2'), findsOneWidget);
    expect(find.text('CELL-00001'), findsNWidgets(2)); // the tile's code tag (under the view) + panel
    expect(find.textContaining('Actualizado a las'), findsOneWidget);
    expect(backend.requests.length, greaterThan(before)); // fetched again on entering

    await tester.tap(find.text('Cátodo'));
    await tester.pumpAndSettle();
    expect(find.text('Cátodo · CAT-001'), findsOneWidget);

    await tester.tap(find.text('Volver a la línea'));
    await tester.pumpAndSettle();
    expect(find.text('Vista del componente'), findsNothing);
    expect(find.text('Celda A1'), findsOneWidget);
  });

  testWidgets('swiping turns the bar around its vertical axis only', (tester) async {
    await _pump(tester);
    await _openCell(tester, 1);
    await _tapKey(tester, 'line-cathode-1');

    final bar = find.byKey(const ValueKey('detail-bar'));
    dynamic painter() =>
        tester.widget<CustomPaint>(find.descendant(of: bar, matching: find.byType(CustomPaint))).painter;
    final yaw = painter().yaw as double, pitch = painter().pitch as double;

    await tester.drag(bar, const Offset(120, 0));
    await tester.pumpAndSettle();
    final spun = painter().yaw as double;
    expect(spun, isNot(yaw)); // spun

    await tester.drag(bar, const Offset(0, -60));
    await tester.pumpAndSettle();
    expect(painter().pitch as double, pitch); // a vertical swipe does not tilt it
    expect(painter().yaw as double, spun);
    expect(find.text('Vista del componente'), findsOneWidget); // still in the view
  });

  testWidgets('an empty slot says the component is missing', (tester) async {
    await _pump(tester);

    await _tapKey(tester, 'line-cathode-3'); // B3 has neither, so it is open

    expect(find.text('Esta celda no tiene cátodo asignado.'), findsOneWidget);
  });

  testWidgets('system back zooms out instead of leaving the screen', (tester) async {
    await _pump(tester);
    await _openCell(tester, 2);

    await _tapKey(tester, 'line-anode-2');
    expect(find.text('Vista del componente'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Vista del componente'), findsNothing);
    expect(find.text('Celdas'), findsOneWidget);
  });

  testWidgets('each cell has a code tag: its barcode or "Generar código"', (tester) async {
    await _pump(tester);

    expect(
      find.descendant(of: find.byKey(const ValueKey('line-code-1')), matching: find.text('CELL-00001')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byKey(const ValueKey('line-code-2')), matching: find.text('Generar código de barras')),
      findsOneWidget,
    );
  });

  testWidgets('dragging a cathode onto another open cell\'s cathode swaps them after confirming', (tester) async {
    final backend = await _pump(tester, height: 1400);
    await _openCell(tester, 1);
    await _openCell(tester, 2);

    await _drag(tester, from: 'line-cathode-1', to: 'line-cathode-2');
    expect(find.text('¿Intercambiar componentes?'), findsOneWidget);
    await tester.tap(find.text('Intercambiar'));
    await tester.pumpAndSettle();

    expect(backend.component(1)['cell_id'], 2);
    expect(backend.component(3)['cell_id'], 1);
    expect(find.text('CAT-001 y CAT-014 intercambiados.'), findsOneWidget);
    expect(find.text('Vista del componente'), findsNothing); // a drag does not enter the cell
    expect(find.byKey(const ValueKey('line-lid-1')), findsNothing); // both stay open after a swap
  });

  testWidgets('a swap pulls the bar out, then both bars fly to each other\'s slot', (tester) async {
    await _pump(tester, height: 1400);
    await _openCell(tester, 1);
    await _openCell(tester, 2);
    Finder serialIn(String slot, String serial) =>
        find.descendant(of: find.byKey(ValueKey(slot)), matching: find.text(serial));
    expect(serialIn('line-cathode-1', 'CAT-001'), findsOneWidget);

    final gesture = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('line-cathode-1'))));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));
    // Out of its slot and in the hand.
    expect(serialIn('line-cathode-1', 'CAT-001'), findsNothing);
    expect(find.text('CAT-001'), findsOneWidget);

    await gesture.moveTo(tester.getCenter(find.byKey(const ValueKey('line-cathode-2'))));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Intercambiar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('flying-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('flying-3')), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('flying-1')), findsNothing);
    expect(serialIn('line-cathode-2', 'CAT-001'), findsOneWidget);
    expect(serialIn('line-cathode-1', 'CAT-014'), findsOneWidget);
  });

  testWidgets('dropping on an empty slot of the same type explains why it cannot swap', (tester) async {
    final backend = await _pump(tester, height: 1400);
    await _openCell(tester, 1);

    await _drag(tester, from: 'line-cathode-1', to: 'line-cathode-3'); // B3 has no cathode

    expect(find.text('El intercambio no se puede realizar porque no hay un componente disponible.'), findsOneWidget);
    expect(find.text('¿Intercambiar componentes?'), findsNothing);
    expect(backend.swapRequests, 0);
  });

  testWidgets('the "Abrir celda" button opens a closed cell like its lid', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Abrir celda').first);
    await tester.pumpAndSettle();
    expect(find.text('¿Desea abrir la celda A1?'), findsOneWidget);
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('line-lid-1')), findsNothing);
    expect(find.text('Cerrar celda'), findsOneWidget);
  });

  testWidgets('a closed cell does not take a drop', (tester) async {
    final backend = await _pump(tester, height: 1400);
    await _openCell(tester, 1);

    await _drag(tester, from: 'line-cathode-1', to: 'line-lid-2');

    expect(find.text('¿Intercambiar componentes?'), findsNothing);
    expect(backend.swapRequests, 0);
  });

  testWidgets('a component cannot be dropped on one of the other type', (tester) async {
    final backend = await _pump(tester, height: 1400);
    await _openCell(tester, 1);
    await _openCell(tester, 2);

    await _drag(tester, from: 'line-cathode-1', to: 'line-anode-2');

    expect(find.text('¿Intercambiar componentes?'), findsNothing);
    expect(backend.swapRequests, 0);
  });

  testWidgets('dragging near the bottom edge scrolls the line to reach a distant cell', (tester) async {
    final backend = FakeInventoryBackend();
    backend.cells.addAll([
      for (var i = 5; i <= 12; i++) {'id': i, 'name': 'L$i', 'barcode_value': null, 'is_visible': true},
    ]);
    backend.components.add({
      'id': 100,
      'type': 'CATHODE',
      'serial_code': 'CAT-900',
      'is_active': true,
      'is_visible': true,
      'cell_id': 12,
    });
    await _pump(tester, backend: backend);
    await _openCell(tester, 1);

    final gesture = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('line-cathode-1'))));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    final target = find.byKey(const ValueKey('line-cathode-12'));
    // Keep the finger at the bottom edge until the far cell scrolls into view
    // (the cell the drag started from is disposed on the way).
    // Built is not enough: tiles just below the screen are already built.
    for (var i = 0; i < 400 && (target.evaluate().isEmpty || tester.getCenter(target).dy > 650); i++) {
      await gesture.moveTo(Offset(200, i.isEven ? 790 : 789));
      await tester.pump();
    }
    await gesture.moveTo(tester.getCenter(target));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Intercambiar'));
    await tester.pumpAndSettle();
    expect(backend.component(1)['cell_id'], 12);
    expect(backend.component(100)['cell_id'], 1);
  });

  group('replaces the cells and components screens', () {
    testWidgets('"Nueva" creates a cell', (tester) async {
      final backend = await _pump(tester);

      await tester.tap(find.text('Nueva'));
      await tester.pumpAndSettle();
      expect(find.text('Nueva celda'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'D5');
      await tester.tap(find.text('Crear celda'));
      await tester.pumpAndSettle();

      expect(backend.cells.any((c) => c['name'] == 'D5'), isTrue);
    });

    testWidgets('the pencil renames a cell', (tester) async {
      final backend = await _pump(tester);

      await tester.tap(find.byTooltip('Editar celda').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Z9');
      await tester.pump(); // "Guardar cambios" enables once the name differs
      await tester.tap(find.text('Guardar cambios'));
      await tester.pumpAndSettle();

      expect(backend.cell(1)['name'], 'Z9');
    });

    testWidgets('a cell without components is removed from the line', (tester) async {
      final backend = await _pump(tester, height: 1400);

      await tester.tap(find.byTooltip('Eliminar celda').at(2)); // B3
      await tester.pumpAndSettle();
      expect(find.text('¿Eliminar la celda B3?'), findsOneWidget);
      await tester.tap(find.text('Eliminar'));
      await tester.pumpAndSettle();

      expect(backend.cell(3)['is_visible'], isFalse);
      expect(find.text('Celda B3'), findsNothing);
    });

    testWidgets('the component view edits the component and explains why it cannot be disabled', (tester) async {
      await _pump(tester);
      await _openCell(tester, 1);
      await _tapKey(tester, 'line-anode-1');

      await tester.tap(find.text('Editar'));
      await tester.pumpAndSettle();
      expect(find.text('Editar componente'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Deshabilitar'));
      await tester.pumpAndSettle();
      expect(find.text('El componente está en uso'), findsOneWidget);
    });

    testWidgets('an empty slot is filled with a free component from its view', (tester) async {
      final backend = await _pump(tester);

      await _tapKey(tester, 'line-cathode-3'); // B3 has no cathode; CAT-099 is free
      await tester.tap(find.text('Asignar componente'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('free-5')));
      await tester.pumpAndSettle();

      expect(backend.component(5)['cell_id'], 3);
      expect(find.text('Cátodo · CAT-099'), findsOneWidget);
    });
  });
}

/// Long-presses the zone [from] and drops it on the zone [to].
Future<void> _drag(WidgetTester tester, {required String from, required String to}) async {
  final gesture = await tester.startGesture(tester.getCenter(find.byKey(ValueKey(from))));
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
  await gesture.moveTo(tester.getCenter(find.byKey(ValueKey(to))));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}
