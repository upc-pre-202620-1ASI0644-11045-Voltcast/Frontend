import 'package:actualvoltcast/core/network/api_client.dart';
import 'package:actualvoltcast/core/theme/app_theme.dart';
import 'package:actualvoltcast/features/cells/data/inventory_repository.dart';
import 'package:actualvoltcast/features/cells/data/pending_swap.dart';
import 'package:actualvoltcast/features/cells/presentation/barcode_export.dart';
import 'package:actualvoltcast/features/cells/presentation/barcode_screen.dart';
import 'package:actualvoltcast/features/cells/presentation/cell_sounds.dart';
import 'package:actualvoltcast/features/cells/presentation/inventory_controller.dart';
import 'package:actualvoltcast/features/cells/presentation/cell_screen.dart';
import 'package:actualvoltcast/features/cells/presentation/storage_screen.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../helpers/fake_inventory_backend.dart';
import '../helpers/memory_tokens.dart';

class _Harness {
  _Harness(this.backend, this.downloads);

  final FakeInventoryBackend backend;

  /// File names handed to the downloader.
  final List<String> downloads;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  String location = '/line',
  FakeInventoryBackend? backend,
  bool failDownload = false,
}) async {
  CellSounds.enabled = false; // no audio backend in widget tests
  // Tall phone-width screen so every tile is built and reachable.
  tester.view.physicalSize = const Size(420, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  backend ??= FakeInventoryBackend();
  final downloads = <String>[];
  final repository = InventoryRepository(
    ApiClient(
      tokenStorage: MemoryTokens(access: 'token'),
      httpClient: backend.client,
    ),
  );

  final router = GoRouter(
    initialLocation: location,
    routes: [
      ShellRoute(
        builder: (context, state, child) => ChangeNotifierProvider(
          create: (_) =>
              InventoryController(repository, store: MemoryPendingSwapStore(), retryEvery: const Duration(hours: 1))
                ..load(),
          child: child,
        ),
        routes: [
          GoRoute(path: '/line', builder: (_, _) => const ProductionLineScreen()),
          GoRoute(path: '/storage', builder: (_, _) => const StorageScreen()),
          GoRoute(
            path: '/barcodes',
            builder: (_, state) => BarcodeScreen(
              initialCellId: int.tryParse(state.uri.queryParameters['cell'] ?? ''),
              downloader: ({required boundaryKey, required fileName}) async {
                if (failDownload) throw Exception('no share handler');
                downloads.add(fileName);
              },
            ),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(MaterialApp.router(theme: AppTheme.light(), routerConfig: router));
  await tester.pumpAndSettle();
  return _Harness(backend, downloads);
}

Future<void> _tapText(WidgetTester tester, String text, {int index = 0}) async {
  final finder = find.text(text);
  await tester.ensureVisible(finder.at(index));
  await tester.pumpAndSettle();
  await tester.tap(finder.at(index));
  await tester.pumpAndSettle();
}

Future<void> _tapTooltip(WidgetTester tester, String tooltip, int index) async {
  final finder = find.byTooltip(tooltip).at(index);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Long-press the zone [from] and drop it on the zone [to].
Future<void> _dragKey(WidgetTester tester, {required String from, required String to}) async {
  final gesture = await tester.startGesture(tester.getCenter(find.byKey(ValueKey(from))));
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
  await gesture.moveTo(tester.getCenter(find.byKey(ValueKey(to))));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

/// Opens a closed (complete) cell through its lid and the confirmation.
Future<void> _openCell(WidgetTester tester, int id) async {
  await _tapKey(tester, 'line-lid-$id');
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
}

/// [text] as an option of an open dropdown (the line behind shows the same names).
Finder _menuOption(String text) =>
    find.descendant(of: find.byWidgetPredicate((w) => w is DropdownMenuItem), matching: find.text(text));

/// Goes to the inventory, as its tab in the bottom bar does.
Future<void> _openStorage(WidgetTester tester) async {
  GoRouter.of(tester.element(find.byType(ProductionLineScreen))).go('/storage');
  await tester.pumpAndSettle();
}

/// Opens the dropdown labelled [label] and picks [option].
Future<void> _pick(WidgetTester tester, {required String label, required String option}) async {
  final field = find.ancestor(of: find.text(label.toUpperCase()), matching: find.byType(Column)).first;
  final dropdown = find.descendant(of: field, matching: find.byType(DropdownButtonFormField<Object?>));
  // The generic type differs per use; fall back to any dropdown under the label.
  final target = dropdown.evaluate().isNotEmpty
      ? dropdown.first
      : find.descendant(of: field, matching: find.byWidgetPredicate((w) => w is DropdownButtonFormField)).first;
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

void main() {
  // The production line replaced the cells and components screens: the same
  // sheets and flows, opened from the line, its component view and its storage.
  group('ProductionLineScreen: cells', () {
    testWidgets('shows stats and every cell with its state', (tester) async {
      await _pump(tester);

      expect(find.text('REGISTRADAS'), findsOneWidget);
      expect(find.text('ACTIVAS'), findsOneWidget);
      expect(find.text('4'), findsOneWidget); // registered
      expect(find.text('2'), findsNWidgets(2)); // active and inactive
      for (final name in ['A1', 'A2', 'B3', 'C4']) {
        expect(find.text('Celda $name'), findsOneWidget);
      }
      expect(find.text('Á: ANO-001 · C: CAT-001'), findsOneWidget);
      expect(find.text('Á: — · C: —'), findsNWidgets(2)); // B3 has neither; C4 is disabled
      expect(find.text('CELL-00001'), findsOneWidget);
      expect(find.text('Generar código de barras'), findsNWidgets(3));
      expect(find.text('Activa'), findsNWidgets(2));
      expect(find.text('Inactiva'), findsNWidgets(2));
    });

    testWidgets('cells are listed by name and inactive ones keep their actions', (tester) async {
      await _pump(tester);

      expect(find.byTooltip('Editar celda'), findsNWidgets(4));
      expect(find.byTooltip('Eliminar celda'), findsNWidgets(4));
      final positions = ['A1', 'A2', 'B3', 'C4'].map((n) => tester.getTopLeft(find.text('Celda $n')).dy).toList();
      expect(positions, [...positions]..sort());
    });

    testWidgets('creates a cell, uppercasing the name', (tester) async {
      final h = await _pump(tester);

      await _tapText(tester, 'Nueva');
      await tester.enterText(find.byType(TextFormField), 'd8');
      await tester.pump();
      await _tapText(tester, 'Crear celda');

      expect(find.text('Celda D8'), findsOneWidget);
      expect(find.text('Celda D8 creada.'), findsOneWidget);
      expect(h.backend.cells.last['name'], 'D8');
    });

    testWidgets('rejects a bad name before calling the API', (tester) async {
      final h = await _pump(tester);
      final before = h.backend.requests.length;

      await _tapText(tester, 'Nueva');
      await tester.enterText(find.byType(TextFormField), 'zz');
      await tester.pump();
      await _tapText(tester, 'Crear celda');

      expect(find.text('Valor no válido: usa una letra seguida de un número, por ejemplo A1 o B12.'), findsOneWidget);
      expect(h.backend.requests.length, before);
    });

    testWidgets('US009 E02: an empty form is rejected with the required-field message', (tester) async {
      final h = await _pump(tester);
      final before = h.backend.requests.length;

      await _tapText(tester, 'Nueva');
      // The button is enabled even when empty, so the user is told what is missing.
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Crear celda')).onPressed, isNotNull);
      await _tapText(tester, 'Crear celda');

      expect(find.text('Campo obligatorio: ingresa el nombre de la celda.'), findsOneWidget);
      expect(find.text('Nueva celda'), findsOneWidget); // the sheet stays open
      expect(h.backend.requests.length, before);
    });

    testWidgets('a duplicate name is reported inside the sheet', (tester) async {
      await _pump(tester);

      await _tapText(tester, 'Nueva');
      await tester.enterText(find.byType(TextFormField), 'A1');
      await tester.pump();
      await _tapText(tester, 'Crear celda');

      expect(find.text('Nueva celda'), findsOneWidget);
      expect(find.text('Ya existe una celda con ese nombre.'), findsOneWidget);
    });

    testWidgets('rename needs a change to enable saving', (tester) async {
      final h = await _pump(tester);

      await _tapTooltip(tester, 'Editar celda', 2); // B3
      expect(find.text('Editar celda'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Guardar cambios')).onPressed, isNull);

      await tester.enterText(find.byType(TextFormField), 'k9');
      await tester.pump();
      await _tapText(tester, 'Guardar cambios');

      expect(find.text('Celda K9'), findsOneWidget);
      expect(h.backend.cell(3)['name'], 'K9');
    });

    testWidgets('US011 E01: an empty cell is removed from view after confirming', (tester) async {
      final h = await _pump(tester);

      await _tapTooltip(tester, 'Eliminar celda', 2); // B3, no components
      expect(find.text('¿Eliminar la celda B3?'), findsOneWidget);
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Eliminar')));
      await tester.pumpAndSettle();

      expect(h.backend.cell(3)['is_visible'], isFalse);
      expect(find.text('Celda B3 eliminada.'), findsOneWidget);
      expect(find.text('Celda B3'), findsNothing);
    });

    testWidgets('creating a removed cell again brings it back', (tester) async {
      final h = await _pump(tester);
      h.backend.cell(3)['is_visible'] = false;

      await _tapText(tester, 'Nueva');
      await tester.enterText(find.byType(TextFormField), 'b3');
      await tester.pump();
      await _tapText(tester, 'Crear celda');

      expect(h.backend.cell(3)['is_visible'], isTrue);
      expect(h.backend.cells.length, 4); // no new record
      expect(find.text('Celda B3'), findsOneWidget);
    });

    testWidgets('US011 E02: a cell with components is refused, with a message', (tester) async {
      final h = await _pump(tester);

      await _tapTooltip(tester, 'Eliminar celda', 0); // A1 has CAT-001 and ANO-001

      // No plain "remove" confirmation: the user is told why it cannot be done.
      expect(find.text('La celda tiene componentes asignados'), findsOneWidget);
      expect(find.textContaining('CAT-001 y ANO-001'), findsOneWidget);
      expect(find.text('¿Eliminar la celda A1?'), findsNothing);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(h.backend.cell(1)['is_visible'], isTrue);
      expect(h.backend.component(1)['cell_id'], 1); // nothing was released
    });

    testWidgets('US011 E03: releasing the components frees them and leaves the cell inactive', (tester) async {
      final h = await _pump(tester);

      await _tapTooltip(tester, 'Eliminar celda', 0); // A1
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Liberar componentes')));
      await tester.pumpAndSettle();

      expect(h.backend.cellJson(1)['is_active'], isFalse);
      expect(h.backend.cell(1)['is_visible'], isTrue); // still on the line
      expect(h.backend.component(1)['cell_id'], isNull);
      expect(h.backend.component(2)['cell_id'], isNull);
      expect(find.text('Componentes de la celda A1 liberados. La celda quedó inactiva.'), findsOneWidget);
      expect(find.text('Inactiva'), findsNWidgets(3));
    });

    testWidgets('cancelling the dialog changes nothing', (tester) async {
      final h = await _pump(tester);

      await _tapTooltip(tester, 'Eliminar celda', 2); // B3, empty
      expect(find.textContaining('Dejará de mostrarse'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(h.backend.cell(3)['is_visible'], isTrue);
    });

    testWidgets('the code tag opens the barcode screen on that cell', (tester) async {
      await _pump(tester);

      await tester.tap(find.byKey(const ValueKey('line-code-2'))); // A2
      await tester.pumpAndSettle();

      expect(find.text('Código de barras'), findsOneWidget);
      expect(find.text('Celda A2'), findsOneWidget); // preselected in the dropdown
      expect(find.text('Pendiente'), findsOneWidget); // A2 has no code yet
    });

    testWidgets('load failure offers a retry that recovers', (tester) async {
      final backend = FakeInventoryBackend()..failWith = (status: 500, detail: 'Internal error: boom');
      await _pump(tester, backend: backend);

      expect(find.text('Error del servidor. Inténtalo más tarde.'), findsOneWidget);
      expect(find.text('Nueva'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Nueva')).onPressed, isNull);

      backend.failWith = null;
      await _tapText(tester, 'Reintentar');
      expect(find.text('Celda A1'), findsOneWidget);
    });
  });

  group('ProductionLineScreen: components', () {
    testWidgets('the storage shows the stats and the components outside the cells', (tester) async {
      await _pump(tester);
      await _openStorage(tester);

      expect(find.text('6'), findsOneWidget); // registered
      expect(find.text('Cátodo · CAT-099'), findsOneWidget);
      expect(find.text('LIBERADOS · 1'), findsOneWidget);
      expect(find.text('Libre'), findsOneWidget);
      expect(find.text('DESHABILITADOS · 1'), findsOneWidget);
      expect(find.text('Ánodo · ANO-777'), findsOneWidget);
      expect(find.text('Deshabilitado'), findsOneWidget);
      expect(find.text('Cátodo · CAT-001'), findsNothing); // in use: lives in its cell
    });

    testWidgets('US013 E01: a component that is not in use is disabled after confirming', (tester) async {
      final h = await _pump(tester);
      await _openStorage(tester);

      // CAT-099 is the only active one in the storage; ANO-777 has no actions.
      await tester.tap(find.byTooltip('Deshabilitar componente'));
      await tester.pumpAndSettle();
      expect(find.text('¿Deshabilitar cátodo?'), findsOneWidget);
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Deshabilitar')));
      await tester.pumpAndSettle();

      expect(h.backend.component(5)['is_active'], isFalse);
      expect(find.text('CAT-099 deshabilitado.'), findsOneWidget);
    });

    testWidgets('US013 E02: a component in use is refused, with a message', (tester) async {
      final h = await _pump(tester);
      await _openCell(tester, 1);
      await _tapKey(tester, 'line-cathode-1');
      final before = h.backend.requests.length;

      // Enabled on purpose: the answer to the attempt is the "en uso" message.
      expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Deshabilitar')).onPressed, isNotNull);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Deshabilitar'));
      await tester.pumpAndSettle();

      expect(find.text('El componente está en uso'), findsOneWidget);
      expect(find.textContaining('CAT-001 está asignado a la celda A1'), findsOneWidget);
      expect(find.text('¿Deshabilitar cátodo?'), findsNothing);

      await tester.tap(find.text('Entendido'));
      await tester.pumpAndSettle();
      expect(h.backend.component(1)['is_active'], isTrue);
      expect(h.backend.requests.length, before);
    });

    testWidgets('registers a component assigned to a cell', (tester) async {
      final h = await _pump(tester);
      await _openStorage(tester);

      await _tapText(tester, 'Nuevo');
      await _tapText(tester, 'Ánodo', index: 0);
      await tester.enterText(find.byType(TextFormField), '500');
      await tester.pump();
      await _pick(tester, label: 'Asignar a celda (opcional)', option: 'Celda B3');
      await _tapText(tester, 'Registrar componente');

      expect(find.text('Ánodo A-500 registrado.'), findsOneWidget);
      final created = h.backend.components.last;
      expect([created['type'], created['serial_code'], created['cell_id']], ['ANODE', 'A-500', 3]);
    });

    testWidgets('an empty slot registers a new component of its type straight into its cell', (tester) async {
      final h = await _pump(tester);
      await _tapKey(tester, 'line-anode-3'); // B3 has no anode

      await tester.tap(find.text('Asignar componente')); // the slot's only action
      await tester.pumpAndSettle();
      await tester.tap(find.text('Registrar nuevo'));
      await tester.pumpAndSettle();
      expect(find.text('Nuevo componente'), findsOneWidget);
      // Locked to the slot's type: the cathode option is not offered.
      expect(find.descendant(of: find.byType(BottomSheet), matching: find.text('Cátodo')), findsNothing);
      await tester.enterText(find.byType(TextFormField), '501');
      await tester.pump();
      await _tapText(tester, 'Registrar componente');

      final created = h.backend.components.last;
      expect([created['type'], created['serial_code'], created['cell_id']], ['ANODE', 'A-501', 3]);
    });

    testWidgets('a duplicate serial is reported inside the sheet', (tester) async {
      final backend = FakeInventoryBackend();
      backend.component(5)['serial_code'] = 'C-099';
      await _pump(tester, backend: backend);
      await _openStorage(tester);

      await _tapText(tester, 'Nuevo');
      await tester.enterText(find.byType(TextFormField), '099');
      await tester.pump();
      await _tapText(tester, 'Registrar componente');

      expect(find.text('Nuevo componente'), findsWidgets); // the sheet stays open
      expect(find.text('Ya existe un componente con ese código de serie.'), findsOneWidget);
    });

    testWidgets('edits the serial code', (tester) async {
      final h = await _pump(tester);
      await _openStorage(tester);

      await _tapTooltip(tester, 'Editar componente', 0); // CAT-099
      expect(find.text('Editar componente'), findsOneWidget);
      expect(find.text('099'), findsOneWidget); // only the digits of CAT-099
      await tester.enterText(find.byType(TextFormField), '100');
      await tester.pump();
      await _tapText(tester, 'Guardar cambios');

      expect(find.text('Cátodo · C-100'), findsOneWidget);
      expect(h.backend.component(5)['serial_code'], 'C-100');
    });

    testWidgets('assigns a free component to a cell', (tester) async {
      final h = await _pump(tester);
      await _openStorage(tester);

      await _tapTooltip(tester, 'Asignar a una celda', 0); // CAT-099
      await _pick(tester, label: 'Celda', option: 'Celda B3');
      await tester.tap(find.widgetWithText(FilledButton, 'Asignar'));
      await tester.pumpAndSettle();

      expect(h.backend.component(5)['cell_id'], 3);
      expect(find.text('CAT-099 asignado a la celda B3.'), findsOneWidget);
    });

    testWidgets('one cathode and one anode per cell: only cells with room are offered', (tester) async {
      await _pump(tester);
      await _openStorage(tester);

      await _tapTooltip(tester, 'Asignar a una celda', 0); // CAT-099, free
      await tester.tap(find.byWidgetPredicate((w) => w is DropdownButtonFormField));
      await tester.pumpAndSettle();

      // A1 and A2 already have a cathode; only B3 has room.
      expect(_menuOption('Celda B3'), findsWidgets);
      expect(_menuOption('Celda A1'), findsNothing);
      expect(_menuOption('Celda A2'), findsNothing);
    });

    testWidgets('when no cell has room the assign sheet says to use "Intercambiar"', (tester) async {
      final backend = FakeInventoryBackend();
      // Give B3 and C4 a cathode too: now every cell has one.
      for (final (id, cell) in [(7, 3), (8, 4)]) {
        backend.components.add({
          'id': id,
          'type': 'CATHODE',
          'serial_code': 'CAT-$id',
          'is_active': true,
          'is_visible': true,
          'cell_id': cell,
        });
      }
      await _pump(tester, backend: backend);
      await _openStorage(tester);

      await _tapTooltip(tester, 'Asignar a una celda', 0); // CAT-099, the only free component
      expect(find.textContaining('No hay celdas con espacio para un cátodo'), findsOneWidget);
      expect(find.textContaining('Intercambiar'), findsWidgets);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Asignar')).onPressed, isNull);
    });

    testWidgets('US012 E02: an empty serial code is rejected with the required-field message', (tester) async {
      final h = await _pump(tester);
      await _openStorage(tester);
      final before = h.backend.requests.length;

      await _tapText(tester, 'Nuevo');
      expect(
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Registrar componente')).onPressed,
        isNotNull,
      );
      await _tapText(tester, 'Registrar componente');

      expect(find.text('Campo obligatorio: ingresa el código de serie.'), findsOneWidget);
      expect(h.backend.requests.length, before);
    });

    testWidgets('the new-component sheet only offers cells with room for that type', (tester) async {
      await _pump(tester);
      await _openStorage(tester);

      await _tapText(tester, 'Nuevo');
      await tester.ensureVisible(find.byWidgetPredicate((w) => w is DropdownButtonFormField));
      await tester.tap(find.byWidgetPredicate((w) => w is DropdownButtonFormField));
      await tester.pumpAndSettle();

      // Default type is cathode: A1 and A2 already have one.
      expect(_menuOption('Celda B3'), findsWidgets);
      expect(_menuOption('Celda A1'), findsNothing);
      expect(_menuOption('Celda A2'), findsNothing);
    });

    testWidgets('the serial code takes only digits and gets the type letter in front', (tester) async {
      final h = await _pump(tester);
      await _openStorage(tester);

      await _tapText(tester, 'Nuevo'); // cathode by default
      expect(find.text('C-'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'C-12x3');
      await tester.pump();
      expect(find.text('123'), findsOneWidget); // letters and dashes are dropped
      await _tapText(tester, 'Registrar componente');

      expect(h.backend.components.last['serial_code'], 'C-123');
    });

    testWidgets('a disabled component is reactivated: it is free again', (tester) async {
      final h = await _pump(tester);
      await _openStorage(tester);

      await _tapText(tester, 'Reactivar'); // ANO-777
      expect(h.backend.component(6)['is_active'], isTrue);
      expect(find.text('ANO-777 reactivado.'), findsOneWidget);
      expect(find.text('Reactivar'), findsNothing); // now listed with the free ones
    });

    testWidgets('a disabled component is removed from view after confirming', (tester) async {
      final h = await _pump(tester);
      await _openStorage(tester);

      await _tapTooltip(tester, 'Eliminar componente', 0); // ANO-777
      expect(find.text('¿Eliminar ANO-777?'), findsOneWidget);
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Eliminar')));
      await tester.pumpAndSettle();

      expect(h.backend.component(6)['is_visible'], isFalse);
      expect(find.byKey(const ValueKey('storage-6')), findsNothing);
    });

    testWidgets('cancelling the swap confirmation leaves the components where they are', (tester) async {
      final h = await _pump(tester);
      await _openCell(tester, 1);
      await _openCell(tester, 2);

      await _dragKey(tester, from: 'line-cathode-1', to: 'line-cathode-2');
      await _tapText(tester, 'Cancelar');

      expect(h.backend.component(1)['cell_id'], 1);
      expect(h.backend.swapRequests, 0);
    });

    testWidgets('US014 E02: without a connection the swap is done locally and queued', (tester) async {
      final h = await _pump(tester);
      await _openCell(tester, 1);
      await _openCell(tester, 2);

      h.backend.offline = true; // the connection drops after the screen was loaded
      await _dragKey(tester, from: 'line-cathode-1', to: 'line-cathode-2');
      await _tapText(tester, 'Intercambiar');

      // Message from the criterion, and the change is already visible.
      expect(find.textContaining('Sin conexión'), findsOneWidget);
      expect(
        find.textContaining('se sincronizará con el servidor cuando se recupere la conexión a internet'),
        findsOneWidget,
      );
      expect(find.textContaining('1 intercambio pendiente de sincronizar'), findsOneWidget);
      expect(h.backend.component(1)['cell_id'], 1); // the server was not reached
      expect(find.text('Á: ANO-014 · C: CAT-001'), findsOneWidget); // A2 shows the moved cathode

      // Connection is back: "Reintentar ahora" sends it.
      h.backend.offline = false;
      await _tapText(tester, 'Reintentar ahora');

      expect(h.backend.component(1)['cell_id'], 2);
      expect(h.backend.component(3)['cell_id'], 1);
      expect(find.textContaining('pendiente de sincronizar'), findsNothing);
      expect(find.text('Se sincronizaron 1 intercambio con el servidor.'), findsOneWidget);

      await tester.tap(find.byTooltip('Cerrar')); // the notice can be dismissed
      await tester.pumpAndSettle();
      expect(find.textContaining('Se sincronizaron'), findsNothing);
    });
  });

  group('BarcodeScreen', () {
    testWidgets('a generated code is drawn and can be downloaded', (tester) async {
      final h = await _pump(tester, location: '/barcodes?cell=1');

      expect(find.byType(BarcodeWidget), findsOneWidget);
      expect(find.text('CELL-00001'), findsOneWidget);
      expect(find.text('Disponible'), findsOneWidget);
      expect(find.text('CAT-001'), findsOneWidget);
      expect(find.text('ANO-001'), findsOneWidget);

      await _tapText(tester, 'Descargar PNG');
      expect(h.downloads, ['codigo-celda-A1.png']);
    });

    testWidgets('a pending cell with both components can generate its code', (tester) async {
      final h = await _pump(tester, location: '/barcodes?cell=2');

      expect(find.byType(BarcodeWidget), findsNothing);
      expect(find.text('Pendiente'), findsOneWidget);
      expect(find.text('Genera el código para poder descargarlo.'), findsOneWidget);

      await _tapText(tester, 'Generar código');

      expect(h.backend.cell(2)['barcode_value'], 'CELL-00002');
      expect(find.byType(BarcodeWidget), findsOneWidget);
      expect(find.text('Descargar PNG'), findsOneWidget);
      expect(find.text('Código generado para la celda A2.'), findsOneWidget);
    });

    testWidgets('US016 E02: a cell without components is refused, with a message', (tester) async {
      final h = await _pump(tester, location: '/barcodes?cell=3');
      final before = h.backend.requests.length;

      // Enabled on purpose: the answer to the attempt is the message.
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Generar código')).onPressed, isNotNull);
      await _tapText(tester, 'Generar código');

      expect(find.textContaining('La celda no tiene componentes asignados'), findsOneWidget);
      expect(h.backend.cell(3)['barcode_value'], isNull);
      expect(h.backend.requests.length, before);
    });

    testWidgets('US016 E02: a cell with only one of the two components is told what is missing', (tester) async {
      final backend = FakeInventoryBackend();
      backend.component(2)['cell_id'] = null; // ANO-001 leaves A1: it keeps only the cathode
      backend.cell(1)['barcode_value'] = null;
      await _pump(tester, location: '/barcodes?cell=1', backend: backend);

      await _tapText(tester, 'Generar código');

      expect(find.text('A la celda le falta un ánodo para generar su código.'), findsOneWidget);
      expect(backend.cell(1)['barcode_value'], isNull);
    });

    testWidgets('US017 E02: downloading before generating says to generate it first', (tester) async {
      final h = await _pump(tester, location: '/barcodes?cell=2');

      await _tapText(tester, 'Descargar PNG');

      expect(find.text('Primero debes generar el código de barras de esta celda.'), findsOneWidget);
      expect(h.downloads, isEmpty);
    });

    testWidgets('switching cell with the dropdown', (tester) async {
      await _pump(tester, location: '/barcodes?cell=1');

      await _pick(tester, label: 'Celda', option: 'Celda B3');

      expect(find.byType(BarcodeWidget), findsNothing);
      expect(find.text('Sin asignar'), findsNWidgets(2));
    });

    testWidgets('defaults to the first cell; inactive cells are offered, removed ones are not', (tester) async {
      final backend = FakeInventoryBackend();
      backend.cell(4)['is_visible'] = false;
      await _pump(tester, location: '/barcodes', backend: backend);
      expect(find.text('Celda A1'), findsOneWidget);

      await tester.tap(find.byWidgetPredicate((w) => w is DropdownButtonFormField));
      await tester.pumpAndSettle();
      expect(find.text('Celda B3'), findsWidgets); // inactive: shows what it is missing
      expect(find.text('Celda C4'), findsNothing);
    });

    testWidgets('a failing share sheet shows a message instead of crashing', (tester) async {
      await _pump(tester, location: '/barcodes?cell=1', failDownload: true);

      await _tapText(tester, 'Descargar PNG');
      expect(find.text('No se pudo exportar el código. Inténtalo de nuevo.'), findsOneWidget);
    });

    testWidgets('capturePng renders the barcode area to a real PNG', (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: RepaintBoundary(
              key: key,
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(20),
                child: BarcodeWidget(barcode: Barcode.code128(), data: 'CELL-00001', width: 260, height: 96),
              ),
            ),
          ),
        ),
      );

      // Image encoding is real async work, outside the fake-async test zone.
      final bytes = await tester.runAsync(() => capturePng(key));

      expect(bytes!.sublist(0, 8), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]); // PNG signature
      expect(bytes.length, greaterThan(1000));
    });

    testWidgets('with no cells it explains what to do', (tester) async {
      final backend = FakeInventoryBackend();
      for (final c in backend.cells) {
        c['is_visible'] = false;
      }
      await _pump(tester, location: '/barcodes', backend: backend);

      expect(find.textContaining('No hay celdas'), findsOneWidget);
    });
  });
}
