import 'dart:convert';

import 'package:actualvoltcast/core/network/api_client.dart';
import 'package:actualvoltcast/core/format.dart';
import 'package:actualvoltcast/core/theme/app_theme.dart';
import 'package:actualvoltcast/core/widgets/app_buttons.dart';
import 'package:actualvoltcast/features/auth/data/auth_repository.dart';
import 'package:actualvoltcast/features/auth/data/auth_user.dart';
import 'package:actualvoltcast/features/auth/presentation/auth_controller.dart';
import 'package:actualvoltcast/features/cells/data/inventory_repository.dart';
import 'package:actualvoltcast/features/cells/data/pending_swap.dart';
import 'package:actualvoltcast/features/cells/presentation/inventory_controller.dart';
import 'package:actualvoltcast/features/forecasting/data/evaluation.dart';
import 'package:actualvoltcast/features/forecasting/data/evaluation_cache.dart';
import 'package:actualvoltcast/features/forecasting/data/evaluation_series.dart';
import 'package:actualvoltcast/features/forecasting/presentation/error_series_chart.dart';
import 'package:actualvoltcast/features/forecasting/data/forecast_cache.dart';
import 'package:actualvoltcast/features/forecasting/data/forecasting_repository.dart';
import 'package:actualvoltcast/features/forecasting/presentation/alert_rules_screen.dart';
import 'package:actualvoltcast/features/forecasting/presentation/evaluation_export.dart';
import 'package:actualvoltcast/features/forecasting/presentation/model_controller.dart';
import 'package:actualvoltcast/features/forecasting/presentation/model_screen.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:actualvoltcast/features/home/settings_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../helpers/fake_forecasting_backend.dart';
import '../helpers/memory_tokens.dart';

class _SignedIn extends AuthController {
  _SignedIn(this._user, ApiClient api)
    : super(
        AuthRepository(
          api: api,
          tokens: MemoryTokens(access: 'token'),
        ),
      );

  final AuthUser _user;

  @override
  AuthUser? get user => _user;
}

Future<void> _pump(
  WidgetTester tester,
  FakeForecastingBackend backend,
  Widget screen, {
  String role = 'ADMIN',
}) async {
  tester.view.physicalSize = const Size(420, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final api = ApiClient(
    tokenStorage: MemoryTokens(access: 'token'),
    httpClient: backend.client,
  );
  final forecasting = ForecastingRepository(
    api,
    cache: ForecastCache(store: MemoryForecastCacheStore()),
    evaluationCache: EvaluationCache(store: MemoryForecastCacheStore()),
  );
  final user = AuthUser(
    id: 1,
    email: 'o@voltcast.io',
    fullName: 'Oscar Aranda',
    status: 'active',
    role: role,
  );
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => screen),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(
        path: '/datasets',
        builder: (_, _) => const Text('pantalla de archivos'),
      ),
      GoRoute(
        path: '/limit',
        builder: (_, _) => const Text('pantalla de límite'),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthController>(
          create: (_) => _SignedIn(user, api),
        ),
        Provider<ForecastingRepository>.value(value: forecasting),
        ChangeNotifierProvider(
          create: (_) => InventoryController(
            InventoryRepository(api),
            store: MemoryPendingSwapStore(),
          )..load(),
        ),
      ],
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ),
  );
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('ModelScreen', () {
    ModelController controller(WidgetTester tester) =>
        tester.element(find.byType(Scaffold)).read<ModelController>();

    Map<String, String> lastEvaluationQuery(FakeForecastingBackend b) => b
        .requests
        .lastWhere((r) => r.url.path == '/api/v1/forecasts/evaluation')
        .url
        .queryParameters;

    testWidgets('says in one sentence how far off the forecast is', (
      tester,
    ) async {
      await _pump(tester, FakeForecastingBackend(), const ModelScreen());

      // The model's name and version mean nothing to the user: not shown.
      expect(find.textContaining('BiLSTM'), findsNothing);
      expect(find.textContaining('versión'), findsNothing);
      expect(find.text('Error del pronóstico'), findsOneWidget);
      expect(find.textContaining('0,064'), findsOneWidget);
      expect(find.text('Modelo disponible'), findsOneWidget);
      expect(find.textContaining('En promedio'), findsNothing);
      expect(find.textContaining('Calculado sobre'), findsNothing);
    });

    testWidgets('has no technical detail: only the sentence', (tester) async {
      await _pump(tester, FakeForecastingBackend(), const ModelScreen());

      expect(find.text('Ver detalle técnico'), findsNothing);
      expect(find.text('RMSE'), findsNothing);
    });

    testWidgets(
      'lists the worst cells of the default day, with no order selector',
      (tester) async {
        final backend = FakeForecastingBackend();
        await _pump(tester, backend, const ModelScreen());

        expect(lastEvaluationQuery(backend), {'limit': '10', 'order': 'worst'});
        expect(find.text('Mostrando 4 de 4 celdas'), findsOneWidget);
        expect(find.text('Mayor error'), findsNothing);
        expect(find.text('Menor error'), findsNothing);
        expect(
          find.textContaining('Error promedio de ese día:'),
          findsOneWidget,
        );
        expect(find.text('Pronóstico'), findsNWidgets(4)); // one label per card
        // B12 (id 4) errs the most; its error is shown with a comma.
        expect(find.text('B12'), findsOneWidget);
        expect(find.byIcon(Icons.warning_amber_rounded), findsWidgets);
      },
    );

    testWidgets('a date outside the range is refused in Spanish', (
      tester,
    ) async {
      final backend = FakeForecastingBackend();
      await _pump(tester, backend, const ModelScreen());

      await controller(tester).setDate(DateTime(2027, 1, 1));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('No hay datos de comparación para esa fecha'),
        findsOneWidget,
      );
      expect(find.textContaining('outside the available range'), findsNothing);
      // The table of before stays, and the picker is back inside the range.
      expect(find.text('Mostrando 4 de 4 celdas'), findsOneWidget);
      expect(controller(tester).isSelectable(DateTime(2027, 1, 1)), isFalse);
      expect(controller(tester).date, backend.evalTo);
    });

    testWidgets('the previous table stays dimmed while the next loads', (
      tester,
    ) async {
      final backend = FakeForecastingBackend();
      await _pump(tester, backend, const ModelScreen());

      final c = controller(tester);
      final pending = c.setDate(backend.evalFrom);
      // Asking: the old table is still the one to show, never an empty state.
      expect(c.evaluating, isTrue);
      expect(c.evaluation, isNotNull);
      await pending;
      await tester.pumpAndSettle();
      expect(lastEvaluationQuery(backend)['date'], apiDate(backend.evalFrom));
    });

    testWidgets('without a model there are no numbers, only the empty state', (
      tester,
    ) async {
      await _pump(
        tester,
        FakeForecastingBackend()..noModel = true,
        const ModelScreen(),
      );

      expect(find.text('Aún no hay un modelo entrenado'), findsOneWidget);
      expect(find.text('Error del pronóstico'), findsNothing);
    });

    testWidgets('a model with nothing to compare says so', (tester) async {
      await _pump(
        tester,
        FakeForecastingBackend()..noComparison = true,
        const ModelScreen(),
      );

      expect(
        find.text('No hay datos de comparación para esta fecha'),
        findsOneWidget,
      );
      expect(find.text('Error del pronóstico'), findsOneWidget);
    });

    testWidgets('retraining shows the same banner as the forecasts', (
      tester,
    ) async {
      await _pump(
        tester,
        FakeForecastingBackend()..retraining = true,
        const ModelScreen(),
      );

      expect(
        find.textContaining('Se está reentrenando el modelo'),
        findsOneWidget,
      );
      expect(find.text('Error del pronóstico'), findsOneWidget);
    });

    testWidgets('a server failure offers a retry', (tester) async {
      final backend = FakeForecastingBackend()..failStatus = 500;
      await _pump(tester, backend, const ModelScreen());

      expect(find.text('Reintentar'), findsOneWidget);
      backend.failStatus = null;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.text('Error del pronóstico'), findsOneWidget);
    });

    testWidgets('offline it shows what was saved, and only for saved days', (
      tester,
    ) async {
      final backend = FakeForecastingBackend();
      await _pump(tester, backend, const ModelScreen());
      backend.offline = true;
      await controller(tester).load();
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Sin conexión. Datos guardados el'),
        findsOneWidget,
      );
      expect(find.text('Mostrando 4 de 4 celdas'), findsOneWidget);
      expect(find.text('Error del pronóstico'), findsOneWidget);
      expect(controller(tester).isSelectable(backend.evalTo), isTrue);
      expect(controller(tester).isSelectable(backend.evalFrom), isFalse);
    });

    int seriesCalls(FakeForecastingBackend b) => b.requests
        .where((r) => r.url.path == '/api/v1/forecasts/evaluation/series')
        .length;

    testWidgets('draws the mean error per day, asked once for the screen', (
      tester,
    ) async {
      final backend = FakeForecastingBackend();
      await _pump(tester, backend, const ModelScreen());

      expect(find.byType(ErrorSeriesChart), findsOneWidget);
      expect(find.text('Error medio por día'), findsOneWidget);
      expect(find.textContaining('los últimos 60 días'), findsOneWidget);
      expect(seriesCalls(backend), 1);

      await controller(tester).setDate(backend.evalFrom);
      await tester.pumpAndSettle();
      expect(seriesCalls(backend), 1); // the series does not depend on the day
    });

    testWidgets('touching the chart picks that day, in sync with the table', (
      tester,
    ) async {
      final backend = FakeForecastingBackend();
      await _pump(tester, backend, const ModelScreen());
      expect(controller(tester).date, backend.evalTo);

      final box = tester.getTopLeft(find.byType(ErrorSeriesChart));
      await tester.tapAt(box + const Offset(15, 100)); // the first day
      await tester.pumpAndSettle();

      expect(controller(tester).date, backend.evalFrom);
      expect(lastEvaluationQuery(backend)['date'], apiDate(backend.evalFrom));
      expect(
        find.text('Fecha: ${formatShortDate(backend.evalFrom)}'),
        findsOneWidget,
      );
    });

    testWidgets('offline the chart comes from the saved copy', (tester) async {
      final backend = FakeForecastingBackend();
      await _pump(tester, backend, const ModelScreen());
      backend.offline = true;
      await controller(tester).load();
      await tester.pumpAndSettle();

      expect(find.byType(ErrorSeriesChart), findsOneWidget);
    });

    testWidgets('a failing series says so, with a retry, and the table stays', (
      tester,
    ) async {
      final backend = FakeForecastingBackend()..seriesStatus = 500;
      await _pump(tester, backend, const ModelScreen());

      expect(find.byType(ErrorSeriesChart), findsNothing);
      expect(find.text('Mostrando 4 de 4 celdas'), findsOneWidget);
      backend.seriesStatus = 200;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.byType(ErrorSeriesChart), findsOneWidget);
    });

    testWidgets('an empty series says there is nothing to chart', (
      tester,
    ) async {
      await _pump(
        tester,
        FakeForecastingBackend()..noComparison = true,
        const ModelScreen(),
      );

      expect(find.byType(ErrorSeriesChart), findsNothing);
      expect(find.text('Aún no hay datos para graficar.'), findsOneWidget);
    });

    testWidgets('the cards fit 360 px even with a long cell name', (
      tester,
    ) async {
      final backend = FakeForecastingBackend()
        ..cells['A130-LARGO-123456'] = 9;
      tester.view.physicalSize = const Size(360, 2400);
      await _pump(tester, backend, const ModelScreen());
      // _pump sets 420 px; narrow it before the cards are built again.
      tester.view.physicalSize = const Size(360, 2400);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('A130-LARGO-123456'), findsOneWidget);
    });

    testWidgets('the cards flag only the cells well above the day mean', (
      tester,
    ) async {
      await _pump(tester, FakeForecastingBackend(), const ModelScreen());

      // B12 errs the most: flagged; A1 errs less than the mean: not.
      expect(find.byIcon(Icons.warning_amber_rounded), findsWidgets);
      expect(
        find.byIcon(Icons.warning_amber_rounded).evaluate().length,
        lessThan(4),
      );
    });

    testWidgets('offline with nothing saved says so', (tester) async {
      await _pump(
        tester,
        FakeForecastingBackend()..offline = true,
        const ModelScreen(),
      );

      expect(find.text('No hay datos de precisión guardados'), findsOneWidget);
    });

    testWidgets('the Excel button asks for every cell of the chosen day', (
      tester,
    ) async {
      final backend = FakeForecastingBackend();
      String? name;
      var rows = 0;
      await _pump(
        tester,
        backend,
        ModelScreen(
          export: (fileName, items) async {
            name = fileName;
            rows = items.length;
          },
        ),
      );

      await tester.scrollUntilVisible(
        find.text('Descargar todas las celdas (Excel)'),
        200,
      );
      await tester.tap(find.text('Descargar todas las celdas (Excel)'));
      await tester.pumpAndSettle();

      expect(lastEvaluationQuery(backend), {
        'date': apiDate(backend.evalTo),
        'limit': '300',
        'order': 'worst',
      });
      expect(name, 'comparacion_pronostico_${apiDate(backend.evalTo)}.xlsx');
      expect(rows, 4);
    });

    testWidgets('offline the Excel button needs the 300-row copy of that day', (
      tester,
    ) async {
      final backend = FakeForecastingBackend();
      await _pump(tester, backend, ModelScreen(export: (_, _) async {}));
      backend.offline = true;
      await controller(tester).load();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Descargar todas las celdas (Excel)'),
        200,
      );

      expect(
        tester.widget<SecondaryButton>(find.byType(SecondaryButton)).onPressed,
        isNull,
      );
      expect(
        find.textContaining('guardó completo con conexión'),
        findsOneWidget,
      );
    });

    testWidgets('the Modelo tab no longer lists the files', (tester) async {
      await _pump(tester, FakeForecastingBackend(), const ModelScreen());

      expect(find.text('Archivos históricos'), findsNothing);
      expect(find.text('Límite de voltaje'), findsNothing);
    });
  });

  group('SettingsScreen', () {
    testWidgets('a supervisor sees the three entries', (tester) async {
      await _pump(tester, FakeForecastingBackend(), const SettingsScreen());

      expect(find.text('Centro de control'), findsOneWidget);
      expect(find.text('Oscar Aranda'), findsOneWidget);
      expect(find.text('Archivos históricos'), findsOneWidget);
      expect(find.text('Precisión del modelo'), findsOneWidget);

      await tester.tap(find.text('Límite de voltaje'));
      await tester.pumpAndSettle();
      expect(find.text('pantalla de límite'), findsOneWidget);
    });

    testWidgets('an engineer reaches the files but has no limit entry', (
      tester,
    ) async {
      await _pump(
        tester,
        FakeForecastingBackend(),
        const SettingsScreen(),
        role: 'USER',
      );

      expect(find.text('Límite de voltaje'), findsNothing);
      await tester.tap(find.text('Archivos históricos'));
      await tester.pumpAndSettle();
      expect(find.text('pantalla de archivos'), findsOneWidget);
    });
  });

  group('EvaluationSeries', () {
    test('parses the points and the validation range', () {
      final series = EvaluationSeries.fromJson({
        'model': {'id': 3, 'name': 'x', 'version': 'y'},
        'retraining': false,
        'message': null,
        'available_from': '2026-08-31',
        'available_to': '2026-10-29',
        'items': [
          {'date': '2026-08-31', 'mean_error_pct': 2.14, 'total_cells': 300},
        ],
      });

      expect(series.items.single.meanErrorPct, 2.14);
      expect(series.items.single.totalCells, 300);
      expect(series.days, 60);
      expect(EvaluationSeries.fromJson(series.toJson()).items.length, 1);
    });

    test('without a model it is empty and carries the message', () {
      final series = EvaluationSeries.fromJson({
        'model': null,
        'message': 'Aún no hay un modelo entrenado.',
        'items': [],
      });

      expect(series.model, isNull);
      expect(series.items, isEmpty);
      expect(series.message, 'Aún no hay un modelo entrenado.');
      expect(series.days, isNull);
    });
  });

  group('severityOf', () {
    test('compares the cell with the mean of its day', () {
      expect(severityOf(1.0, 2.0), Severity.normal);
      expect(severityOf(2.0, 2.0), Severity.normal);
      expect(severityOf(3.0, 2.0), Severity.elevated);
      expect(severityOf(4.0, 2.0), Severity.high);
      expect(severityOf(9.0, null), Severity.normal);
    });
  });

  group('evaluationXlsx', () {
    test('writes the header and one numeric row per cell', () {
      final bytes = evaluationXlsx(const [
        EvaluationItem(
          cellId: 1,
          cellName: 'A1',
          real: 3.211,
          predicted: 3.202,
          errorV: 0.009,
          errorPct: 0.28,
        ),
      ]);

      final sheet = Excel.decodeBytes(bytes).tables['Comparación']!;
      expect(sheet.rows.length, 2);
      expect(sheet.rows[0].map((c) => c?.value.toString()), [
        'Celda',
        'V. Real',
        'Pronóstico',
        'Diferencia (V)',
        'Error (%)',
      ]);
      expect(sheet.rows[1][0]!.value.toString(), 'A1');
      expect((sheet.rows[1][1]!.value as DoubleCellValue).value, 3.211);
      expect((sheet.rows[1][4]!.value as DoubleCellValue).value, 0.28);
    });
  });

  group('AlertRulesScreen', () {
    Future<void> enterVoltage(
      WidgetTester tester,
      int field,
      String text,
    ) async {
      await tester.enterText(find.byType(TextField).at(field), text);
    }

    testWidgets('shows the current general limit', (tester) async {
      await _pump(tester, FakeForecastingBackend(), const AlertRulesScreen());

      expect(find.text('4.50 V'), findsOneWidget);
    });

    testWidgets('saves the general limit without a cell', (tester) async {
      final backend = FakeForecastingBackend();
      await _pump(tester, backend, const AlertRulesScreen());

      await enterVoltage(tester, 0, '3,6');
      await tester.tap(find.text('Guardar límite'));
      await tester.pumpAndSettle();

      final post = backend.requests.lastWhere((r) => r.method == 'POST');
      expect(jsonDecode(post.body), {'max_voltage': 3.6});
      expect(find.text('Límite general guardado.'), findsOneWidget);
      expect(find.text('3.60 V'), findsOneWidget);
    });

    testWidgets('a value that is not above zero is refused before sending', (
      tester,
    ) async {
      final backend = FakeForecastingBackend();
      await _pump(tester, backend, const AlertRulesScreen());

      for (final bad in ['', '0']) {
        await enterVoltage(tester, 0, bad);
        await tester.tap(find.text('Guardar límite'));
        await tester.pumpAndSettle();
        expect(find.text('Ingresa un voltaje mayor que cero.'), findsOneWidget);
      }
      expect(backend.requests.where((r) => r.method == 'POST'), isEmpty);
    });

    testWidgets('there is only the general limit, none per cell', (
      tester,
    ) async {
      await _pump(tester, FakeForecastingBackend(), const AlertRulesScreen());

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Límite por celda'), findsNothing);
      expect(find.text('Guardar límite de la celda'), findsNothing);
    });

    testWidgets('a 403 is explained instead of crashing', (tester) async {
      final backend = FakeForecastingBackend()..forbidden = true;
      await _pump(tester, backend, const AlertRulesScreen(), role: 'USER');

      await enterVoltage(tester, 0, '3.5');
      await tester.tap(find.text('Guardar límite'));
      await tester.pumpAndSettle();

      expect(
        find.text('No tienes permisos para realizar esta acción.'),
        findsOneWidget,
      );
    });
  });
}
