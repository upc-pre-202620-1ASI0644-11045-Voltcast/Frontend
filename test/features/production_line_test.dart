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
  // Wide enough to drag between neighbouring cards of a section's row.
  double width = 400,
  ProductionLineScreen screen = const ProductionLineScreen(),
}) async {
  CellSounds.enabled = false; // no audio backend in widget tests
  tester.view.physicalSize = Size(width, height);
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
    // Off the line's screen, or on a later page of section A's row (A2…).
    final onPage = await _swipeRowUntil(tester, finder);
    if (!onPage) await tester.dragUntilVisible(finder, find.byType(CustomScrollView), const Offset(0, -200));
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

/// Swipes section A's row (one cell per page) towards its end until [finder] is built.
Future<bool> _swipeRowUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 12 && finder.evaluate().isEmpty; i++) {
    await _turnRow(tester, 1);
  }
  return finder.evaluate().isNotEmpty;
}

/// Turns section A's row one cell forwards (1) or back (-1).
Future<void> _turnRow(WidgetTester tester, int pages) async {
  final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
  await tester.drag(find.byType(PageView).first, Offset(-pages * width * 0.6, 0));
  await tester.pumpAndSettle();
}

/// Opens A1 and A2 and comes back to A1, the second one a page away.
Future<void> _openA1A2(WidgetTester tester) async {
  await _openCell(tester, 1);
  await _turnRow(tester, 1);
  await _openCell(tester, 2);
  await _turnRow(tester, -1);
}

/// Opens a closed (complete) cell through its lid.
Future<void> _openCell(WidgetTester tester, int id) => _tapKey(tester, 'line-lid-$id');

/// The component view is open.
final _inView = find.byKey(const ValueKey('component-panel'));

/// [text] on the component view's sheet (the line underneath shows serials too).
Finder _inPanel(String text) => find.descendant(of: _inView, matching: find.text(text));

InventoryController _inventory(WidgetTester tester) =>
    Provider.of<InventoryController>(tester.element(find.byType(ProductionLineScreen)), listen: false);

void main() {
  testWidgets('greets the user by name and can sign out', (tester) async {
    var signedOut = false;
    await _pump(
      tester,
      screen: ProductionLineScreen(userName: 'Oscar', userRole: 'Supervisor', onLogout: () => signedOut = true),
    );

    expect(find.text('Hola, Oscar'), findsOneWidget);
    expect(find.text('Supervisor · 4 celdas'), findsOneWidget);
    expect(find.byTooltip('Volver'), findsNothing); // the home tab has nowhere to go back to

    await tester.tap(find.byTooltip('Cerrar sesión'));
    expect(signedOut, isTrue);
  });

  testWidgets('groups the cells by section, one row each', (tester) async {
    await _pump(tester, height: 1400);

    expect(find.text('EL A'), findsOneWidget);
    expect(find.text('2 celdas · desliza →'), findsOneWidget); // A1, A2
    expect(find.text('EL B'), findsOneWidget);
    expect(find.text('EL C'), findsOneWidget);
    expect(find.text('1 celda'), findsNWidgets(2)); // B3, C4
  });

  testWidgets('lays out 150 cells of a section in a row but only builds the visible ones', (tester) async {
    final backend = FakeInventoryBackend();
    backend.cells.addAll([
      for (var i = 5; i <= 150; i++) {'id': i, 'name': 'L$i', 'barcode_value': null, 'is_visible': true},
    ]);
    await _pump(tester, backend: backend);

    expect(find.text('150 celdas'), findsOneWidget);
    await tester.dragUntilVisible(find.text('Celda L5'), find.byType(CustomScrollView), const Offset(0, -200));
    expect(find.text('146 celdas · desliza →'), findsOneWidget);
    expect(find.textContaining('Celda L'), findsWidgets);
    expect(find.textContaining('Celda L').evaluate().length, lessThan(10));

    // Pinned to the element: the finder through L5 stops matching once L5 is scrolled away.
    final rowElement = find.ancestor(of: find.text('Celda L5'), matching: find.byType(Scrollable)).evaluate().first;
    final row = find.byElementPredicate((e) => e == rowElement);
    await tester.dragUntilVisible(find.text('Celda L150'), row, const Offset(-2000, 0));
    expect(find.text('Celda L150'), findsOneWidget);
    expect(find.text('Celda L5'), findsNothing); // scrolled out and disposed
  });

  testWidgets('the search box filters the cells by code', (tester) async {
    await _pump(tester, height: 1400);

    await tester.enterText(find.byType(TextField), 'cat-014'); // A2's cathode
    await tester.pumpAndSettle();
    expect(find.text('Celda A2'), findsOneWidget);
    expect(find.text('Celda A1'), findsNothing);
    expect(find.text('EL B'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('Ninguna celda coincide con la búsqueda.'), findsOneWidget);
  });

  testWidgets('a cell with both components starts closed and opens with a tap on its lid', (tester) async {
    await _pump(tester);

    // A1 has an anode and a cathode: the lid covers them until it is tapped.
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

    expect(_inView, findsOneWidget);
    expect(_inPanel('ANO-001'), findsOneWidget);
    expect(_inPanel('#2'), findsOneWidget);
    expect(_inPanel('En uso'), findsNWidgets(2)); // pill + state
    expect(_inPanel('CELL-00001'), findsOneWidget);
    expect(find.textContaining('Actualizado a las'), findsOneWidget);
    expect(backend.requests.length, greaterThan(before)); // fetched again on entering

    await tester.tap(find.byKey(const ValueKey('focus-cathode')));
    await tester.pumpAndSettle();
    expect(_inPanel('CAT-001'), findsOneWidget);

    await tester.tap(find.byTooltip('Volver a la línea'));
    await tester.pumpAndSettle();
    expect(_inView, findsNothing);
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
    expect(_inView, findsOneWidget); // still in the view
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
    expect(_inView, findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_inView, findsNothing);
    expect(find.text('Celdas'), findsOneWidget);
  });

  testWidgets('each cell has a code button: its barcode or "Generar código"', (tester) async {
    await _pump(tester);

    expect(
      find.descendant(of: find.byKey(const ValueKey('line-code-1')), matching: find.byTooltip('Código CELL-00001')),
      findsOneWidget,
    );
    await _turnRow(tester, 1);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('line-code-2')),
        matching: find.byTooltip('Generar código de barras'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a section shows one centred cell at a time and swipes to the next', (tester) async {
    await _pump(tester);

    expect(find.text('Celda A1'), findsOneWidget);
    expect(find.text('Celda A2'), findsNothing); // no peek of the next card
    // Centred: the card's first and last controls sit the same distance from
    // the screen's edges (16 gutter + 12 card padding).
    final lock = tester.getRect(find.ancestor(of: find.text('Abrir celda').first, matching: find.byType(TextButton)));
    final delete = tester.getRect(find.byTooltip('Eliminar celda').first);
    expect(lock.left, 28);
    expect(400 - delete.right, 28);

    await _turnRow(tester, 1);
    expect(find.text('Celda A2'), findsOneWidget);
    expect(find.text('Celda A1'), findsNothing);
  });

  testWidgets('"Ver componentes" opens the view on the anode', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Ver componentes').first);
    await tester.pumpAndSettle();
    expect(_inPanel('ANO-001'), findsOneWidget);
  });

  testWidgets('a bar cannot be dragged onto another cell: swaps go through the swap screen', (tester) async {
    final backend = await _pump(tester, height: 1400);
    await _openA1A2(tester);

    expect(find.byWidgetPredicate((w) => w is Draggable), findsNothing);
    await _drag(tester, from: 'line-cathode-1', to: 'line-cathode-2');

    expect(find.text('¿Intercambiar componentes?'), findsNothing);
    expect(backend.swapRequests, 0);
    expect(backend.component(1)['cell_id'], 1);
  });

  testWidgets('the "Abrir celda" button opens a closed cell like its lid', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Abrir celda').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('line-lid-1')), findsNothing);
    expect(find.text('Cerrar celda'), findsOneWidget);
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

      await tester.tap(find.byTooltip('Eliminar celda').at(1)); // B3 (A2 is on the next page)
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

      await tester.tap(_inPanel('Editar'));
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
      expect(_inPanel('CAT-099'), findsOneWidget);
    });
  });
}

/// Long-presses the zone [from] and moves to the zone [to], as a drag would. A
/// zone on a later page of the same row is reached by holding at the right
/// edge until the row turns to it.
Future<void> _drag(WidgetTester tester, {required String from, required String to}) async {
  final start = tester.getCenter(find.byKey(ValueKey(from)));
  final gesture = await tester.startGesture(start);
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
  final target = find.byKey(ValueKey(to));
  final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
  for (var i = 0; i < 200 && (target.evaluate().isEmpty || tester.getCenter(target).dx > width); i++) {
    await gesture.moveTo(Offset(width - 4 - (i % 2), start.dy));
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(milliseconds: 400)); // the last turn settles
  await gesture.moveTo(tester.getCenter(target));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}
