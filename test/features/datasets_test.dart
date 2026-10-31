import 'dart:typed_data';

import 'package:actualvoltcast/core/network/api_client.dart';
import 'package:actualvoltcast/core/theme/app_theme.dart';
import 'package:actualvoltcast/features/datasets/data/dataset.dart';
import 'package:actualvoltcast/features/datasets/data/datasets_repository.dart';
import 'package:actualvoltcast/features/datasets/presentation/dataset_detail_screen.dart';
import 'package:actualvoltcast/features/datasets/presentation/datasets_controller.dart';
import 'package:actualvoltcast/features/datasets/presentation/datasets_screen.dart';
import 'package:actualvoltcast/features/datasets/presentation/excel_picker.dart';
import 'package:actualvoltcast/features/forecasting/data/forecasting_repository.dart';
import 'package:actualvoltcast/features/forecasting/data/forecast_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../helpers/fake_forecasting_backend.dart';
import '../helpers/memory_tokens.dart';

ApiClient _api(FakeForecastingBackend b) => ApiClient(
  tokenStorage: MemoryTokens(access: 'token'),
  httpClient: b.client,
);

Future<FakeForecastingBackend> _pump(
  WidgetTester tester,
  Widget home, {
  FakeForecastingBackend? backend,
  Duration pollEvery = const Duration(seconds: 10),
}) async {
  tester.view.physicalSize = const Size(420, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final b = backend ?? FakeForecastingBackend();
  final api = _api(b);
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => home),
      GoRoute(
        path: '/datasets/:id',
        builder: (_, s) =>
            DatasetDetailScreen(id: int.parse(s.pathParameters['id']!)),
      ),
    ],
  );
  addTearDown(router.dispose);

  final forecasting = ForecastingRepository(
    api,
    cache: ForecastCache(store: MemoryForecastCacheStore()),
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<ForecastingRepository>.value(value: forecasting),
        // Created by the tree, so disposing the tree also stops their timers.
        ChangeNotifierProvider(
          create: (_) =>
              DatasetsController(DatasetsRepository(api), pollEvery: pollEvery),
        ),
      ],
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return b;
}

Future<PickedFile?> _picks(String name, [int size = 10]) async =>
    (name: name, bytes: Uint8List(size));

void main() {
  group('DatasetsRepository', () {
    test('uploads the file in the multipart field "file"', () async {
      final backend = FakeForecastingBackend();
      final created = await DatasetsRepository(_api(backend))
          .upload('nuevo.xlsx', [1, 2, 3]);

      final sent = backend.requests.single;
      expect(sent.method, 'POST');
      expect(sent.url.path, '/api/v1/datasets');
      expect(sent.headers['content-type'], startsWith('multipart/form-data'));
      expect(sent.body, contains('name="file"'));
      expect(sent.body, contains('filename="nuevo.xlsx"'));
      expect(created.status, DatasetStatus.raw);
    });

    test('reads the summary of a ready file', () async {
      final d = await DatasetsRepository(_api(FakeForecastingBackend())).get(2);
      expect(d.summary!.sections, {'A': 150, 'B': 150});
      expect(d.summary!.newCells, 2);
      expect(d.summary!.dateTo, DateTime(2026, 9, 30));
    });
  });

  group('DatasetsController', () {
    testWidgets(
      'asks for a file every 10 s while it is processing, then stops',
      (tester) async {
        final backend = FakeForecastingBackend()
          ..datasets.insert(
            0,
            FakeForecastingBackend.dataset(3, 'a.xlsx', 'cleaning'),
          );
        await _pump(tester, const Scaffold(body: SizedBox()), backend: backend);
        final controller = tester
            .element(find.byType(Scaffold))
            .read<DatasetsController>();
        await controller.load();
        int gets() => backend.requests
            .where((r) => r.url.path == '/api/v1/datasets/3')
            .length;

        await tester.pump(const Duration(seconds: 10));
        expect(gets(), 1);
        await tester.pump(const Duration(seconds: 10));
        expect(gets(), 2);

        backend.datasets.first['upload_status'] = 'ready';
        await tester.pump(const Duration(seconds: 10));
        expect(controller.byId(3)!.status, DatasetStatus.ready);

        // Everything final: no more requests.
        await tester.pump(const Duration(seconds: 30));
        expect(gets(), 3);
      },
    );
  });

  group('DatasetsScreen', () {
    testWidgets('lists the files newest first with their state in Spanish', (
      tester,
    ) async {
      await _pump(tester, DatasetsScreen(pick: () => _picks('x.xlsx')));

      expect(find.text('historico_oct.xlsx'), findsOneWidget);
      expect(find.text('Listo'), findsOneWidget);
      expect(
        find.text('Con error'),
        findsNWidgets(2),
      ); // the filter chip and the pill
      expect(find.text('Subir Excel'), findsOneWidget);
    });

    testWidgets('the search box and the filters narrow the list', (
      tester,
    ) async {
      await _pump(tester, DatasetsScreen(pick: () => _picks('x.xlsx')));

      await tester.tap(find.text('Listos'));
      await tester.pump();
      expect(find.text('historico_oct.xlsx'), findsOneWidget);
      expect(find.text('Ningún archivo coincide.'), findsNothing);

      await tester.tap(find.text('Todos'));
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump();
      expect(find.text('historico_oct.xlsx'), findsNothing);
      expect(find.text('Ningún archivo coincide.'), findsOneWidget);
    });

    testWidgets('an uploaded file appears "En cola"', (tester) async {
      await _pump(tester, DatasetsScreen(pick: () => _picks('nuevo.xlsx')));

      await tester.tap(find.text('Subir Excel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Elegir archivo'));
      await tester.pumpAndSettle();

      expect(find.text('nuevo.xlsx'), findsOneWidget);
      expect(find.text('En cola'), findsOneWidget);
      // US001 E01: the upload is confirmed.
      expect(find.textContaining('se subió correctamente'), findsOneWidget);
    });

    testWidgets('an unsupported file is explained without leaving the screen', (
      tester,
    ) async {
      final backend = await _pump(
        tester,
        DatasetsScreen(pick: () => _picks('datos.csv')),
      );

      await tester.tap(find.text('Subir Excel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Elegir archivo'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('El formato no es compatible'),
        findsOneWidget,
      );
      expect(find.text('Archivos históricos'), findsOneWidget);
      expect(find.text('datos.csv'), findsNothing);
      // Refused on the device: nothing was sent.
      expect(backend.requests.where((r) => r.method == 'POST'), isEmpty);
    });

    testWidgets('cancelling the picker sends nothing', (tester) async {
      final backend = await _pump(
        tester,
        DatasetsScreen(pick: () async => null),
      );

      await tester.tap(find.text('Subir Excel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Elegir archivo'));
      await tester.pumpAndSettle();

      expect(backend.requests.where((r) => r.method == 'POST'), isEmpty);
    });

    testWidgets(
      'a file can complement a ready one and waits for confirmation',
      (tester) async {
        final backend = await _pump(
          tester,
          DatasetsScreen(pick: () => _picks('nuevo.xlsx')),
        );

        await tester.tap(find.text('Subir Excel'));
        await tester.pumpAndSettle();
        expect(find.text('Este archivo complementa a:'), findsOneWidget);
        await tester.tap(find.text('historico_oct.xlsx').last);
        await tester.tap(find.text('Elegir archivo'));
        await tester.pumpAndSettle();

        final post = backend.requests.lastWhere((r) => r.method == 'POST');
        expect(post.body, contains('name="base_dataset_id"'));
        expect(find.text('Esperando tu confirmación'), findsOneWidget);
      },
    );

    testWidgets('backing out of the chooser uploads nothing', (tester) async {
      final backend = await _pump(
        tester,
        DatasetsScreen(pick: () => _picks('nuevo.xlsx')),
      );

      await tester.tap(find.text('Subir Excel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(backend.requests.where((r) => r.method == 'POST'), isEmpty);
    });

    testWidgets('while a training runs the upload is disabled and says why', (
      tester,
    ) async {
      final backend = FakeForecastingBackend()
        ..trainings.add(FakeForecastingBackend.training(1, 'running'));
      await _pump(
        tester,
        DatasetsScreen(pick: () => _picks('x.xlsx')),
        backend: backend,
      );

      expect(
        find.text(
          'Hay un entrenamiento en curso; espera a que termine para subir un archivo.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Subir Excel'));
      await tester.pumpAndSettle();
      expect(find.text('Este archivo complementa a:'), findsNothing);
      expect(backend.requests.where((r) => r.method == 'POST'), isEmpty);
    });

    testWidgets('a failing list shows the error with a retry', (tester) async {
      final backend = FakeForecastingBackend()..offline = true;
      await _pump(
        tester,
        DatasetsScreen(pick: () => _picks('x.xlsx')),
        backend: backend,
      );

      expect(find.textContaining('No se pudo conectar'), findsOneWidget);
      backend.offline = false;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.text('historico_oct.xlsx'), findsOneWidget);
    });
  });

  group('DatasetDetailScreen', () {
    testWidgets('a ready file shows its summary and trains the model', (
      tester,
    ) async {
      final backend = await _pump(tester, const DatasetDetailScreen(id: 2));

      expect(find.text('A · 150 / B · 150'), findsOneWidget);
      expect(find.text('300'), findsOneWidget);
      expect(find.text('Celdas nuevas'), findsOneWidget);
      expect(find.textContaining('01 ene 2024'), findsOneWidget);

      await tester.tap(find.text('Reintentar entrenamiento'));
      await tester.pumpAndSettle();

      final post = backend.requests.lastWhere((r) => r.method == 'POST');
      expect(post.url.path, '/api/v1/trainings');
      expect(post.body, contains('"dataset_id":2'));
      expect(find.text('Entrenamiento iniciado.'), findsOneWidget);
    });

    testWidgets('a training already in progress is explained in Spanish', (
      tester,
    ) async {
      final backend = FakeForecastingBackend()
        ..trainings.add(FakeForecastingBackend.training(1, 'running'));
      await _pump(tester, const DatasetDetailScreen(id: 2), backend: backend);

      await tester.tap(find.text('Reintentar entrenamiento'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Ya hay un entrenamiento en curso. Espera a que termine para iniciar otro.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a ready file says the training starts by itself', (
      tester,
    ) async {
      await _pump(tester, const DatasetDetailScreen(id: 2));

      expect(find.textContaining('arranca solo'), findsOneWidget);
    });

    testWidgets(
      'a file waiting for confirmation explains the merge and continues',
      (tester) async {
        final backend = FakeForecastingBackend()
          ..datasets.insert(0, {
            ...FakeForecastingBackend.dataset(
              3,
              'nuevo.xlsx',
              'awaiting_confirmation',
            ),
            'base_dataset_id': 2,
          });
        await _pump(tester, const DatasetDetailScreen(id: 3), backend: backend);

        expect(
          find.textContaining(
            'El archivo cubre del 25 jun 2026 al 30 sep 2026',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining('uno del 01 ene 2024 al 30 jun 2026'),
          findsOneWidget,
        );
        expect(find.textContaining('cubrirá 1004 días'), findsOneWidget);
        expect(find.textContaining('6 días que se solapan'), findsOneWidget);

        await tester.tap(find.text('Continuar'));
        await tester.pumpAndSettle();

        expect(
          backend.requests.any(
            (r) =>
                r.method == 'POST' &&
                r.url.path == '/api/v1/datasets/3/confirm',
          ),
          isTrue,
        );
        expect(find.text('En cola'), findsOneWidget);
      },
    );

    testWidgets('Cancelar only closes the message', (tester) async {
      final backend = FakeForecastingBackend()
        ..datasets.insert(0, {
          ...FakeForecastingBackend.dataset(
            3,
            'nuevo.xlsx',
            'awaiting_confirmation',
          ),
          'base_dataset_id': 2,
        });
      await _pump(tester, const DatasetDetailScreen(id: 3), backend: backend);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(
        backend.requests.where((r) => r.url.path.endsWith('/confirm')),
        isEmpty,
      );
      expect(backend.datasets.first['upload_status'], 'awaiting_confirmation');
    });

    testWidgets('a rejection by dates is explained in Spanish', (tester) async {
      final backend = FakeForecastingBackend()
        ..datasets.insert(
          0,
          FakeForecastingBackend.dataset(
            3,
            'x.xlsx',
            'failed',
            error: 'The file has dates after today (2026-12-01); only measured voltages can be uploaded',
          ),
        );
      await _pump(tester, const DatasetDetailScreen(id: 3), backend: backend);

      expect(find.textContaining('fechas posteriores a hoy'), findsOneWidget);
    });

    testWidgets(
      'a failed file shows the cause and asks to review its structure',
      (tester) async {
        await _pump(tester, const DatasetDetailScreen(id: 1));

        expect(find.text('No cell columns were identified'), findsOneWidget);
        expect(find.textContaining('Revisa su estructura'), findsOneWidget);
        expect(find.text('Reintentar entrenamiento'), findsNothing);
      },
    );
  });
}
