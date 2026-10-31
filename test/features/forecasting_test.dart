import 'dart:typed_data';

import 'package:actualvoltcast/core/format.dart';
import 'package:actualvoltcast/core/network/api_client.dart';
import 'package:actualvoltcast/core/network/api_exception.dart';
import 'package:actualvoltcast/core/network/backend_messages.dart';
import 'package:actualvoltcast/core/theme/app_theme.dart';
import 'package:actualvoltcast/core/widgets/electric_border.dart';
import 'package:actualvoltcast/features/forecasting/data/forecast.dart';
import 'package:actualvoltcast/features/forecasting/data/forecast_cache.dart';
import 'package:actualvoltcast/features/forecasting/data/forecasting_repository.dart';
import 'package:actualvoltcast/features/forecasting/presentation/cell_forecast_screen.dart';
import 'package:actualvoltcast/features/forecasting/presentation/forecast_chart.dart';
import 'package:actualvoltcast/features/forecasting/presentation/forecast_export.dart';
import 'package:actualvoltcast/features/forecasting/presentation/forecasts_controller.dart';
import 'package:actualvoltcast/features/forecasting/presentation/forecasts_screen.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../helpers/fake_forecasting_backend.dart';
import '../helpers/memory_tokens.dart';

ForecastingRepository _repo(
  FakeForecastingBackend b, [
  MemoryForecastCacheStore? store,
]) => ForecastingRepository(
  ApiClient(
    tokenStorage: MemoryTokens(access: 'token'),
    httpClient: b.client,
  ),
  cache: ForecastCache(store: store ?? MemoryForecastCacheStore()),
);

ForecastItem _item(
  int cell,
  DateTime day, {
  double voltage = 3.2,
  double? max = 4.5,
}) => ForecastItem(
  cellId: cell,
  cellName: 'A$cell',
  date: day,
  voltage: voltage,
  maxVoltage: max,
  exceeds: max != null && voltage > max,
);

ForecastResult _result(List<ForecastItem> items) => ForecastResult(
  items: items,
  model: const ModelInfo(),
  availableFrom: DateTime(2026, 11, 1),
  availableTo: DateTime(2027, 4, 29),
);

Future<GoRouter> _pumpScreen(
  WidgetTester tester,
  ForecastingRepository repo, {
  required Widget home,
  List<String>? pushed,
  // The electric border never stops moving, which pumpAndSettle cannot wait for.
  bool animations = false,
}) async {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      FakeAccessibilityFeatures(disableAnimations: !animations);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  tester.view.physicalSize = const Size(420, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => home),
      GoRoute(
        path: '/forecasts/cell/:id',
        builder: (_, s) {
          pushed?.add(s.uri.toString());
          return const Text('detalle de celda');
        },
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    Provider<ForecastingRepository>.value(
      value: repo,
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ),
  );
  if (animations) {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  } else {
    await tester.pumpAndSettle();
  }
  return router;
}

ForecastsController _controller(WidgetTester tester) =>
    tester.element(find.byType(Scaffold).first).read<ForecastsController>();

void main() {
  group('formats', () {
    test('API timestamps without a zone are UTC', () {
      expect(
        parseApiDateTime('2026-10-28T10:00:00').toUtc(),
        DateTime.utc(2026, 10, 28, 10),
      );
      expect(
        parseApiDateTime('2026-10-28T10:00:00-05:00').toUtc(),
        DateTime.utc(2026, 10, 28, 15),
      );
    });

    test('dates', () {
      expect(apiDate(DateTime(2026, 3, 4)), '2026-03-04');
      expect(parseApiDate('2026-03-04'), DateTime(2026, 3, 4));
    });

    test('days over the limit are grouped into runs of consecutive days', () {
      ForecastItem day(int d, bool over) => ForecastItem(
        cellId: 1,
        cellName: 'A1',
        date: DateTime(2026, 11, d),
        voltage: over ? 4.6 : 3.2,
        maxVoltage: 4.5,
        exceeds: over,
      );
      final ranges = exceedRanges([
        day(1, true),
        day(2, true),
        day(3, false),
        day(4, true),
        // 5 is missing: a gap ends the run
        day(6, true),
      ]);

      expect(ranges, [
        (from: DateTime(2026, 11, 1), to: DateTime(2026, 11, 2), days: 2),
        (from: DateTime(2026, 11, 4), to: DateTime(2026, 11, 4), days: 1),
        (from: DateTime(2026, 11, 6), to: DateTime(2026, 11, 6), days: 1),
      ]);
    });

    test('backend messages of these screens are translated', () {
      expect(
        translateBackendMessage('The file is empty'),
        'El archivo está vacío.',
      );
      expect(
        translateBackendMessage('The file exceeds the 100 MB limit'),
        'El archivo supera el límite de 100 MB.',
      );
      expect(
        translateBackendMessage(
          "Unsupported file format '.csv'. Upload an Excel file (.xlsm, .xlsx)",
        ),
        contains('.xlsx o .xlsm'),
      );
      expect(
        translateBackendMessage(
          'The dataset is not ready to train (status: raw)',
        ),
        contains('aún no está listo'),
      );
      expect(
        translateBackendMessage('The end date cannot be before the start date'),
        'La fecha final no puede ser anterior a la inicial.',
      );
      expect(
        translateBackendMessage('Cell not found: 9'),
        'La celda no existe.',
      );
    });
  });

  group('ForecastCache', () {
    final day1 = DateTime(2026, 11, 1), day2 = DateTime(2026, 11, 2);

    test(
      'a whole day is kept by day and cell; a partial one does not complete it',
      () async {
        final cache = ForecastCache(store: MemoryForecastCacheStore());
        final saved = DateTime(2026, 10, 30, 9);

        await cache.save(_result([_item(1, day1), _item(2, day1)]), now: saved);
        await cache.save(_result([_item(1, day2)]), cellId: 1, now: saved);

        final whole = await cache.day(day1);
        expect(whole!.items.map((i) => i.cellId), unorderedEquals([1, 2]));
        expect(whole.savedAt, saved);
        expect(
          await cache.day(day2),
          isNull,
        ); // only one cell of that day was seen
        expect(await cache.dates(), [day1]);
        expect((await cache.cell(1))!.items.map((i) => i.date), [day1, day2]);
        expect(await cache.cell(9), isNull);
      },
    );

    test('the exceeds filter works on the saved day', () async {
      final cache = ForecastCache(store: MemoryForecastCacheStore());
      await cache.save(_result([_item(1, day1), _item(2, day1, voltage: 4.8)]));

      final only = await cache.day(day1, exceeds: true);
      expect(only!.items.map((i) => i.cellId), [2]);
    });

    test('survives a restart and a corrupted copy', () async {
      final store = MemoryForecastCacheStore();
      await ForecastCache(store: store).save(_result([_item(1, day1)]));

      expect(
        (await ForecastCache(store: store).day(day1))!.items,
        hasLength(1),
      );

      store.value = '{not json';
      expect(await ForecastCache(store: store).day(day1), isNull);
    });

    test('the oldest days are dropped past the size limit', () async {
      final cache = ForecastCache(store: MemoryForecastCacheStore());
      List<ForecastItem> many(DateTime day) => [
        for (var i = 1; i <= 7000; i++) _item(i, day),
      ];

      await cache.save(_result(many(day1)), now: DateTime(2026, 10, 1));
      await cache.save(_result(many(day2)), now: DateTime(2026, 10, 2));

      expect(await cache.dates(), [day2]);
    });
  });

  group('ForecastingRepository', () {
    test('asks the API with the dates, cell and filter it was given', () async {
      final backend = FakeForecastingBackend();
      final repo = _repo(backend);

      await repo.forecasts();
      await repo.forecasts(from: DateTime(2026, 11, 3));
      await repo.forecasts(
        from: DateTime(2026, 11, 1),
        to: DateTime(2026, 11, 2),
        cellId: 2,
        exceeds: true,
      );

      expect(backend.requests[0].url.query, isEmpty);
      expect(backend.requests[1].url.queryParameters, {
        'date_from': '2026-11-03',
      });
      expect(backend.requests[2].url.queryParameters, {
        'date_from': '2026-11-01',
        'date_to': '2026-11-02',
        'cell_id': '2',
        'exceeds': 'true',
      });
    });

    test('a range before the start is a 400 explained in Spanish', () async {
      final repo = _repo(FakeForecastingBackend());
      await expectLater(
        repo.forecasts(from: DateTime(2026, 11, 5), to: DateTime(2026, 11, 1)),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('fecha final'),
          ),
        ),
      );
    });

    test('a cell over the whole horizon is 180 rows', () async {
      final r = await _repo(FakeForecastingBackend()).forecasts(
        from: DateTime(2026, 11, 1),
        to: DateTime(2027, 4, 29),
        cellId: 2,
      );
      expect(r.items, hasLength(180));
    });
  });

  group('ForecastsScreen', () {
    testWidgets(
      'opens on the first available day; cells over the limit are highlighted and first',
      (tester) async {
        final backend = FakeForecastingBackend();
        await _pumpScreen(
          tester,
          _repo(backend),
          home: const ForecastsScreen(),
        );

        expect(find.text('Voltaje estimado · 01 nov 2026'), findsOneWidget);
        expect(backend.requests.single.url.query, isEmpty);
        expect(find.text('Sección A · 2 celdas'), findsOneWidget);
        expect(find.text('1 supera'), findsOneWidget);
        expect(find.text('Sección B · 2 celdas'), findsOneWidget);
        // The alert is not colour only: icon + word.
        expect(find.text('Supera'), findsOneWidget);
        expect(find.byIcon(Icons.warning_amber_rounded), findsWidgets);
        expect(find.text('4.710 V'), findsOneWidget);
        expect(find.text('Límite 4.50 V'), findsNWidgets(3));
        expect(
          find.text('Sin límite'),
          findsNWidgets(2),
        ); // the stat label and the cell without limit
      },
    );

    testWidgets(
      'each section stacks two cards per column, the one over the limit first',
      (tester) async {
        await _pumpScreen(
          tester,
          _repo(FakeForecastingBackend()),
          home: const ForecastsScreen(),
        );

        final a7 = tester.getRect(find.text('Celda A7'));
        final a1 = tester.getRect(find.text('Celda A1'));
        final b1 = tester.getRect(find.text('Celda B1'));
        // A7 (over the limit) leads; A1 sits right under it, in the same column.
        expect(a7.left, a1.left);
        expect(a1.top, greaterThan(a7.top));
        // Section B starts below section A.
        expect(b1.top, greaterThan(a1.top));
      },
    );

    testWidgets('a section slides sideways to reach the rest of its cells', (
      tester,
    ) async {
      final backend = FakeForecastingBackend();
      for (var n = 2; n <= 8; n++) {
        if (n != 7) backend.cells['A$n'] = 10 + n;
      }
      await _pumpScreen(tester, _repo(backend), home: const ForecastsScreen());

      // 8 cells = 4 columns of 2: the last one is far to the right, not even built yet.
      expect(find.text('Celda A8'), findsNothing);
      await tester.drag(find.byType(GridView).first, const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(find.text('Celda A8'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Celda A8')).dx, lessThan(420));
    });

    testWidgets('only the cell over the limit gets the electric border', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        _repo(FakeForecastingBackend()),
        home: const ForecastsScreen(),
      );

      expect(find.byType(ElectricBorder), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ElectricBorder),
          matching: find.text('Celda A7'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the border moves, and stands still with animations off', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        _repo(FakeForecastingBackend()),
        home: const ForecastsScreen(),
        animations: true,
      );
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);

      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('searches by cell name', (tester) async {
      await _pumpScreen(
        tester,
        _repo(FakeForecastingBackend()),
        home: const ForecastsScreen(),
      );

      await tester.enterText(find.byType(TextField), 'b1');
      await tester.pumpAndSettle();
      expect(find.text('Celda B1'), findsOneWidget);
      expect(find.text('Celda B12'), findsOneWidget);
      expect(find.text('Celda A1'), findsNothing);

      await tester.enterText(find.byType(TextField), 'zz');
      await tester.pumpAndSettle();
      expect(
        find.text('Ninguna celda coincide con la búsqueda'),
        findsOneWidget,
      );
    });

    testWidgets('the quick filter asks the API for the cells over the limit', (
      tester,
    ) async {
      final backend = FakeForecastingBackend();
      await _pumpScreen(tester, _repo(backend), home: const ForecastsScreen());

      await tester.tap(find.text('Solo las que superan el límite'));
      await tester.pumpAndSettle();

      expect(backend.requests.last.url.queryParameters['exceeds'], 'true');
      expect(find.text('Celda A7'), findsOneWidget);
      expect(find.text('Celda A1'), findsNothing);
    });

    testWidgets(
      'changing the date asks for that single date and shows only it',
      (tester) async {
        final backend = FakeForecastingBackend();
        await _pumpScreen(
          tester,
          _repo(backend),
          home: const ForecastsScreen(),
        );

        await _controller(tester).setDate(DateTime(2026, 11, 8));
        await tester.pumpAndSettle();

        expect(backend.requests.last.url.queryParameters, {
          'date_from': '2026-11-08',
        });
        expect(_controller(tester).items.map((i) => i.date).toSet(), {
          DateTime(2026, 11, 8),
        });
        expect(find.text('Voltaje estimado · 08 nov 2026'), findsOneWidget);
      },
    );

    testWidgets('the picker only offers days inside the available range', (
      tester,
    ) async {
      final repo = _repo(FakeForecastingBackend());
      await _pumpScreen(
        tester,
        repo,
        home: ChangeNotifierProvider(
          // "Today" is the first available day, so Hoy..En 7 días are all inside.
          create: (_) =>
              ForecastsController(repo, clock: () => DateTime(2026, 11, 1))
                ..load(),
          child: const Scaffold(body: SizedBox()),
        ),
      );
      final c = _controller(tester);
      await tester.pumpAndSettle();

      expect(c.isSelectable(DateTime(2026, 11, 1)), isTrue);
      expect(c.isSelectable(DateTime(2027, 4, 29)), isTrue);
      expect(c.isSelectable(DateTime(2026, 10, 31)), isFalse);
      expect(c.isSelectable(DateTime(2027, 4, 30)), isFalse);
    });

    testWidgets('the retraining banner is shown, and the data stays', (
      tester,
    ) async {
      final backend = FakeForecastingBackend()..retraining = true;
      await _pumpScreen(tester, _repo(backend), home: const ForecastsScreen());

      expect(
        find.textContaining('Se está reentrenando el modelo'),
        findsOneWidget,
      );
      expect(find.text('Celda A7'), findsOneWidget);
    });

    testWidgets('without a model it says so', (tester) async {
      final backend = FakeForecastingBackend()..noModel = true;
      await _pumpScreen(tester, _repo(backend), home: const ForecastsScreen());

      expect(find.text('Aún no hay un modelo entrenado'), findsOneWidget);
    });

    testWidgets('a cell opens its detail with the whole available range', (
      tester,
    ) async {
      final pushed = <String>[];
      await _pumpScreen(
        tester,
        _repo(FakeForecastingBackend()),
        home: const ForecastsScreen(),
        pushed: pushed,
      );

      await tester.tap(find.text('Celda A7'));
      await tester.pumpAndSettle();

      expect(find.text('detalle de celda'), findsOneWidget);
      expect(Uri.parse(pushed.single).queryParameters, {
        'name': 'A7',
        'from': '2026-11-01',
        'to': '2027-04-29',
      });
    });

    testWidgets('a server error offers a retry', (tester) async {
      final backend = FakeForecastingBackend()..failStatus = 500;
      await _pumpScreen(tester, _repo(backend), home: const ForecastsScreen());

      expect(
        find.text('Error del servidor. Inténtalo más tarde.'),
        findsOneWidget,
      );

      backend.failStatus = null;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.text('Celda A7'), findsOneWidget);
    });

    group('without a connection', () {
      testWidgets(
        'shows what was saved, with its date, and only lets pick days seen before',
        (tester) async {
          final backend = FakeForecastingBackend();
          final store = MemoryForecastCacheStore();
          // Opened online first: the day is saved.
          await _pumpScreen(
            tester,
            _repo(backend, store),
            home: const ForecastsScreen(),
          );
          await _controller(tester).setDate(DateTime(2026, 11, 8));
          await tester.pumpAndSettle();

          // A new session without network, same device.
          backend.offline = true;
          await tester.pumpWidget(const SizedBox());
          await _pumpScreen(
            tester,
            _repo(backend, store),
            home: const ForecastsScreen(),
          );

          expect(
            find.textContaining('Sin conexión. Datos guardados el'),
            findsOneWidget,
          );
          expect(find.text('Voltaje estimado · 08 nov 2026'), findsOneWidget);
          expect(find.text('Celda A7'), findsOneWidget);

          final c = _controller(tester);
          expect(c.isSelectable(DateTime(2026, 11, 8)), isTrue);
          expect(
            c.isSelectable(DateTime(2026, 11, 1)),
            isTrue,
          ); // seen in the first load
          expect(c.isSelectable(DateTime(2026, 11, 9)), isFalse);

          await c.setDate(DateTime(2026, 11, 20));
          await tester.pumpAndSettle();
          expect(
            find.text(
              'No existen pronósticos disponibles para consulta sin conexión',
            ),
            findsOneWidget,
          );
        },
      );

      testWidgets('with nothing saved it says there is nothing to show', (
        tester,
      ) async {
        final backend = FakeForecastingBackend()..offline = true;
        await _pumpScreen(
          tester,
          _repo(backend),
          home: const ForecastsScreen(),
        );

        expect(
          find.text(
            'No existen pronósticos disponibles para consulta sin conexión',
          ),
          findsOneWidget,
        );
      });
    });
  });

  group('CellForecastScreen', () {
    CellForecastScreen detail() => CellForecastScreen(
      cellId: 2,
      name: 'A7',
      from: DateTime(2026, 11, 1),
      to: DateTime(2027, 4, 29),
    );

    testWidgets(
      'draws the 180 days, reads a day on touch and flags the days over the limit',
      (tester) async {
        final backend = FakeForecastingBackend();
        await _pumpScreen(tester, _repo(backend), home: detail());

        expect(find.text('Celda A7'), findsOneWidget);
        expect(find.text('Pronóstico a 180 días'), findsOneWidget);
        expect(backend.requests.single.url.queryParameters['cell_id'], '2');
        expect(find.text('Días que superan el límite'), findsOneWidget);
        expect(find.text('180'), findsOneWidget);

        await tester.tapAt(
          tester.getTopLeft(
                find
                    .descendant(
                      of: find.byType(ForecastChart),
                      matching: find.byType(CustomPaint),
                    )
                    .last,
              ) +
              const Offset(200, 100),
        );
        await tester.pump();
        expect(find.textContaining('4.710 V'), findsWidgets);
        expect(find.text('Supera el límite'), findsOneWidget);
      },
    );

    testWidgets('lists the dates over the limit as one run of days', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        _repo(FakeForecastingBackend()),
        home: detail(),
      );

      expect(find.text('Fechas que superan el límite'), findsOneWidget);
      expect(find.text('01 nov 2026 – 29 abr 2027'), findsOneWidget);
      expect(find.text('180 días'), findsOneWidget);
    });

    testWidgets('a cell under its limit has no list of dates', (tester) async {
      await _pumpScreen(
        tester,
        _repo(FakeForecastingBackend()),
        home: const CellForecastScreen(cellId: 1, name: 'A1'),
      );

      expect(find.text('Fechas que superan el límite'), findsNothing);
    });

    testWidgets('downloads the data as Excel', (tester) async {
      String? name;
      Uint8List? bytes;
      await _pumpScreen(
        tester,
        _repo(FakeForecastingBackend()),
        home: CellForecastScreen(
          cellId: 2,
          name: 'A7',
          from: DateTime(2026, 11, 1),
          to: DateTime(2027, 4, 29),
          saveFile: (fileName, data, mime) async {
            name = fileName;
            bytes = data;
          },
        ),
      );

      await tester.tap(find.text('Descargar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Datos (Excel)'));
      await tester.pumpAndSettle();

      expect(name, 'pronostico_A7_2026-11-01_2027-04-29.xlsx');
      final sheet = Excel.decodeBytes(bytes!).tables['Pronóstico']!;
      expect(sheet.rows.length, 181); // header + 180 days
      expect(sheet.rows[0].map((c) => c?.value.toString()), [
        'Fecha',
        'Voltaje (V)',
        'Límite (V)',
        'Supera el límite',
      ]);
      expect(sheet.rows[1][0]!.value.toString(), '2026-11-01');
      expect(sheet.rows[1][3]!.value.toString(), 'Sí');
    });

    testWidgets('downloads the chart as a PNG', (tester) async {
      String? name;
      String? mime;
      await _pumpScreen(
        tester,
        _repo(FakeForecastingBackend()),
        home: CellForecastScreen(
          cellId: 2,
          name: 'A7',
          from: DateTime(2026, 11, 1),
          to: DateTime(2027, 4, 29),
          // Images cannot be encoded on the test clock; forecastPng has its own test.
          buildPng: ({required cellName, required items}) async =>
              Uint8List.fromList([1, 2, 3]),
          saveFile: (fileName, data, type) async {
            name = fileName;
            mime = type;
          },
        ),
      );

      await tester.tap(find.text('Descargar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Imagen del gráfico (PNG)'));
      await tester.pumpAndSettle();

      expect(find.text('No se pudo generar el archivo.'), findsNothing);
      expect(name, 'pronostico_A7_2026-11-01_2027-04-29.png');
      expect(mime, 'image/png');
    });

    testWidgets('forecastPng draws a real PNG', (tester) async {
      final items = [
        for (var i = 0; i < 5; i++)
          ForecastItem(
            cellId: 1,
            cellName: 'A1',
            date: DateTime(2026, 11, 1 + i),
            voltage: 3.2 + i * 0.1,
            maxVoltage: 3.4,
            exceeds: i > 2,
          ),
      ];
      final bytes = await tester.runAsync(
        () => forecastPng(cellName: 'A1', items: items),
      );

      expect(bytes!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]); // PNG signature
    });

    testWidgets('without the range it asks for it first', (tester) async {
      final backend = FakeForecastingBackend();
      await _pumpScreen(
        tester,
        _repo(backend),
        home: const CellForecastScreen(cellId: 2, name: 'A7'),
      );

      expect(backend.requests, hasLength(2));
      expect(backend.requests.first.url.queryParameters, {'cell_id': '2'});
      expect(find.text('Pronóstico a 180 días'), findsOneWidget);
    });

    testWidgets('offline it uses the days saved for that cell', (tester) async {
      final backend = FakeForecastingBackend();
      final store = MemoryForecastCacheStore();
      await _pumpScreen(tester, _repo(backend, store), home: detail());

      backend.offline = true;
      await tester.pumpWidget(const SizedBox());
      await _pumpScreen(tester, _repo(backend, store), home: detail());

      expect(
        find.textContaining('Sin conexión. Datos guardados el'),
        findsOneWidget,
      );
      expect(find.text('Pronóstico a 180 días'), findsOneWidget);
    });

    testWidgets('offline with nothing saved it says so', (tester) async {
      final backend = FakeForecastingBackend()..offline = true;
      await _pumpScreen(tester, _repo(backend), home: detail());

      expect(
        find.text(
          'No existen pronósticos disponibles para consulta sin conexión',
        ),
        findsOneWidget,
      );
    });

    testWidgets('without a model it says so', (tester) async {
      final backend = FakeForecastingBackend()..noModel = true;
      await _pumpScreen(tester, _repo(backend), home: detail());

      expect(find.text('Aún no hay un modelo entrenado'), findsOneWidget);
    });
  });
}
