import 'package:actualvoltcast/core/network/api_client.dart';
import 'package:actualvoltcast/core/theme/app_theme.dart';
import 'package:actualvoltcast/features/cells/data/inventory_repository.dart';
import 'package:actualvoltcast/features/cells/presentation/barcode_export.dart';
import 'package:actualvoltcast/features/cells/presentation/barcode_screen.dart';
import 'package:actualvoltcast/features/cells/presentation/cells_screen.dart';
import 'package:actualvoltcast/features/cells/presentation/components_screen.dart';
import 'package:actualvoltcast/features/cells/presentation/inventory_controller.dart';
import 'package:barcode_widget/barcode_widget.dart';
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
  String location = '/cells',
  FakeInventoryBackend? backend,
  bool failDownload = false,
}) async {
  // Tall phone-width screen so every tile is built and reachable.
  tester.view.physicalSize = const Size(420, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  backend ??= FakeInventoryBackend();
  final downloads = <String>[];
  final repository = InventoryRepository(
    ApiClient(tokenStorage: MemoryTokens(access: 'token'), httpClient: backend.client),
  );

  final router = GoRouter(
    initialLocation: location,
    routes: [
      ShellRoute(
        builder: (context, state, child) => ChangeNotifierProvider(
          create: (_) => InventoryController(repository)..load(),
          child: child,
        ),
        routes: [
          GoRoute(path: '/cells', builder: (_, _) => const CellsScreen()),
          GoRoute(path: '/components', builder: (_, _) => const ComponentsScreen()),
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
  group('CellsScreen', () {
    testWidgets('shows stats, tiles and barcode state', (tester) async {
      await _pump(tester);

      expect(find.text('Gestión de celdas eléctricas'), findsOneWidget);
      expect(find.text('REGISTRADAS'), findsOneWidget);
      for (final n in ['4', '2', '1']) {
        expect(find.text(n), findsOneWidget, reason: 'stat $n');
      }
      for (final name in ['A1', 'A2', 'B3', 'C4']) {
        expect(find.text('Celda $name'), findsOneWidget);
      }
      expect(find.text('CAT-001'), findsOneWidget);
      expect(find.text('ANO-014'), findsOneWidget);
      expect(find.text('Sin asignar'), findsNWidgets(2)); // B3 has neither
      expect(find.text('Código generado'), findsOneWidget);
      expect(find.text('Código pendiente'), findsNWidgets(3));
      expect(find.text('Activa'), findsNWidgets(3));
      expect(find.text('Inactiva'), findsOneWidget);
      expect(find.text('4 registros'), findsOneWidget);
    });

    testWidgets('disabled cells are listed last and have no actions', (tester) async {
      await _pump(tester);

      expect(find.byTooltip('Editar'), findsNWidgets(3));
      expect(find.byTooltip('Deshabilitar'), findsNWidgets(3));
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

      expect(find.text('Usa una letra seguida de un número, por ejemplo A1 o B12.'), findsOneWidget);
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

      await _tapTooltip(tester, 'Editar', 2); // B3
      expect(find.text('Editar celda'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Guardar cambios')).onPressed, isNull);

      await tester.enterText(find.byType(TextFormField), 'k9');
      await tester.pump();
      await _tapText(tester, 'Guardar cambios');

      expect(find.text('Celda K9'), findsOneWidget);
      expect(h.backend.cell(3)['name'], 'K9');
    });

    testWidgets('disabling a cell lists the components it will release', (tester) async {
      final h = await _pump(tester);

      await _tapTooltip(tester, 'Deshabilitar', 0); // A1
      expect(find.text('¿Deshabilitar celda A1?'), findsOneWidget);
      expect(find.textContaining('CAT-001 y ANO-001'), findsOneWidget);

      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Deshabilitar')));
      await tester.pumpAndSettle();

      expect(h.backend.cell(1)['is_active'], isFalse);
      expect(h.backend.component(1)['cell_id'], isNull);
      expect(find.text('Celda A1 deshabilitada.'), findsOneWidget);
      expect(find.text('Inactiva'), findsNWidgets(2));
    });

    testWidgets('cancelling the dialog changes nothing', (tester) async {
      final h = await _pump(tester);

      await _tapTooltip(tester, 'Deshabilitar', 2); // B3, empty
      expect(find.textContaining('La celda quedará fuera de uso'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(h.backend.cell(3)['is_active'], isTrue);
    });

    testWidgets('"Código" opens the barcode screen on that cell', (tester) async {
      await _pump(tester);

      // Only the buttons say exactly "Código"; active cells are A1, A2, B3.
      await _tapText(tester, 'Código', index: 1);

      expect(find.text('Código de barras'), findsOneWidget);
      expect(find.text('Celda A2'), findsOneWidget); // preselected in the dropdown
      expect(find.text('Pendiente'), findsOneWidget); // A2 has no code yet
    });

    testWidgets('navigation buttons', (tester) async {
      await _pump(tester);

      await _tapText(tester, 'Componentes');
      expect(find.text('Cátodos y ánodos'), findsOneWidget);
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

  group('ComponentsScreen', () {
    testWidgets('shows stats, states and filters by type', (tester) async {
      await _pump(tester, location: '/components');

      expect(find.text('Cátodos y ánodos'), findsOneWidget);
      expect(find.text('6'), findsOneWidget);
      expect(find.text('Cátodo · CAT-001'), findsOneWidget);
      expect(find.text('Asignado a celda A1'), findsNWidgets(2));
      expect(find.text('Disponible para asignar'), findsOneWidget);
      expect(find.text('Deshabilitado'), findsOneWidget);
      expect(find.text('6 componentes'), findsOneWidget);

      await _tapText(tester, 'Cátodos');
      expect(find.text('Ánodo · ANO-001'), findsNothing);
      expect(find.text('Cátodo · CAT-099'), findsOneWidget);
      expect(find.text('3 componentes'), findsOneWidget); // CAT-001, CAT-014, CAT-099
    });

    testWidgets('a component in use cannot be disabled; a free one can', (tester) async {
      final h = await _pump(tester, location: '/components');

      OutlinedButton disable(int i) =>
          tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Deshabilitar').at(i));

      // Order: CAT-001, CAT-014, CAT-099, ANO-001, ANO-014 (active), ANO-777 (inactive, no actions).
      expect(disable(0).onPressed, isNull);
      expect(disable(2).onPressed, isNotNull);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Deshabilitar').at(2));
      await tester.pumpAndSettle();
      expect(find.text('¿Deshabilitar cátodo?'), findsOneWidget);
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Deshabilitar')));
      await tester.pumpAndSettle();

      expect(h.backend.component(5)['is_active'], isFalse);
      expect(find.text('CAT-099 deshabilitado.'), findsOneWidget);
    });

    testWidgets('registers a component assigned to a cell', (tester) async {
      final h = await _pump(tester, location: '/components');

      await _tapText(tester, 'Nuevo');
      await _tapText(tester, 'Ánodo', index: 0);
      await tester.enterText(find.byType(TextFormField), 'ANO-500');
      await tester.pump();
      await _pick(tester, label: 'Asignar a celda (opcional)', option: 'Celda B3');
      await _tapText(tester, 'Registrar componente');

      expect(find.text('Ánodo ANO-500 registrado.'), findsOneWidget);
      final created = h.backend.components.last;
      expect([created['type'], created['serial_code'], created['cell_id']], ['ANODE', 'ANO-500', 3]);
    });

    testWidgets('a duplicate serial is reported inside the sheet', (tester) async {
      await _pump(tester, location: '/components');

      await _tapText(tester, 'Nuevo');
      await tester.enterText(find.byType(TextFormField), 'CAT-001');
      await tester.pump();
      await _tapText(tester, 'Registrar componente');

      expect(find.text('Nuevo componente'), findsOneWidget);
      expect(find.text('Ya existe un componente con ese código de serie.'), findsOneWidget);
    });

    testWidgets('edits the serial code', (tester) async {
      final h = await _pump(tester, location: '/components');

      await _tapText(tester, 'Editar', index: 2); // CAT-099
      expect(find.text('Editar componente'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'CAT-100');
      await tester.pump();
      await _tapText(tester, 'Guardar cambios');

      expect(find.text('Cátodo · CAT-100'), findsOneWidget);
      expect(h.backend.component(5)['serial_code'], 'CAT-100');
    });

    testWidgets('assigns a free component to a cell', (tester) async {
      final h = await _pump(tester, location: '/components');

      await _tapText(tester, 'Asignar'); // only the free one says "Asignar"
      await _pick(tester, label: 'Celda', option: 'Celda B3');
      await tester.tap(find.widgetWithText(FilledButton, 'Asignar'));
      await tester.pumpAndSettle();

      expect(h.backend.component(5)['cell_id'], 3);
      expect(find.text('Asignado a celda B3'), findsOneWidget);
    });

    testWidgets('reassign cannot pick the current cell', (tester) async {
      await _pump(tester, location: '/components');

      await _tapText(tester, 'Reasignar', index: 0); // CAT-001 in A1
      await _pick(tester, label: 'Celda', option: 'Celda A1 (actual)');
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Asignar')).onPressed, isNull);
    });

    testWidgets('swaps two cathodes between cells', (tester) async {
      final h = await _pump(tester, location: '/components');

      await _tapText(tester, 'Intercambiar');
      await _pick(tester, label: 'Primer componente', option: 'Cátodo CAT-001 · celda A1');

      // Only same-type components in other cells are offered as the second.
      await _pick(tester, label: 'Segundo componente', option: 'Cátodo CAT-014 · celda A2');
      await tester.tap(find.widgetWithText(FilledButton, 'Intercambiar'));
      await tester.pumpAndSettle();

      expect(h.backend.component(1)['cell_id'], 2);
      expect(h.backend.component(3)['cell_id'], 1);
      expect(find.text('CAT-001 y CAT-014 intercambiados.'), findsOneWidget);
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

    testWidgets('a cell without components cannot generate a code', (tester) async {
      await _pump(tester, location: '/barcodes?cell=3');

      expect(find.textContaining('Asigna un cátodo y un ánodo'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Generar código')).onPressed, isNull);
    });

    testWidgets('switching cell with the dropdown', (tester) async {
      await _pump(tester, location: '/barcodes?cell=1');

      await _pick(tester, label: 'Celda', option: 'Celda B3');

      expect(find.byType(BarcodeWidget), findsNothing);
      expect(find.text('Sin asignar'), findsNWidgets(2));
    });

    testWidgets('defaults to the first active cell; disabled cells are not offered', (tester) async {
      await _pump(tester, location: '/barcodes');
      expect(find.text('Celda A1'), findsOneWidget);

      await tester.tap(find.byWidgetPredicate((w) => w is DropdownButtonFormField));
      await tester.pumpAndSettle();
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

    testWidgets('with no active cells it explains what to do', (tester) async {
      final backend = FakeInventoryBackend();
      for (final c in backend.cells) {
        c['is_active'] = false;
      }
      await _pump(tester, location: '/barcodes', backend: backend);

      expect(find.textContaining('No hay celdas activas'), findsOneWidget);
    });
  });
}
