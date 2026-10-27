import 'package:actualvoltcast/core/network/api_client.dart';
import 'package:actualvoltcast/core/theme/app_theme.dart';
import 'package:actualvoltcast/features/cells/data/inventory_repository.dart';
import 'package:actualvoltcast/features/cells/data/pending_swap.dart';
import 'package:actualvoltcast/features/cells/presentation/cell_sounds.dart';
import 'package:actualvoltcast/features/cells/presentation/inventory_controller.dart';
import 'package:actualvoltcast/features/cells/presentation/swap_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../helpers/fake_inventory_backend.dart';
import '../helpers/memory_tokens.dart';

/// Opens the swap screen over a stand-in for the screen it came from, with A1 preselected.
Future<FakeInventoryBackend> _pump(WidgetTester tester, {FakeInventoryBackend? backend}) async {
  CellSounds.enabled = false;
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  backend ??= FakeInventoryBackend();
  final repository = InventoryRepository(
    ApiClient(
      tokenStorage: MemoryTokens(access: 'token'),
      httpClient: backend.client,
    ),
  );
  final router = GoRouter(
    initialLocation: '/from',
    routes: [
      ShellRoute(
        builder: (context, state, child) => ChangeNotifierProvider(
          create: (_) =>
              InventoryController(repository, store: MemoryPendingSwapStore(), retryEvery: const Duration(hours: 1))
                ..load(),
          child: child,
        ),
        routes: [
          GoRoute(
            path: '/from',
            builder: (_, _) => const Scaffold(body: Text('previous screen')),
          ),
          GoRoute(
            path: '/swap',
            builder: (_, state) => SwapScreen(initialCellId: int.tryParse(state.uri.queryParameters['cell'] ?? '')),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(theme: AppTheme.light(), routerConfig: router));
  await tester.pumpAndSettle();
  router.push('/swap?cell=1');
  await tester.pumpAndSettle();
  return backend;
}

Future<void> _pickRight(WidgetTester tester, int cellId) async {
  await tester.tap(find.byKey(const ValueKey('swap-pick-1')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('pick-$cellId')));
  await tester.pumpAndSettle();
}

/// Picks [type] in the toggle and presses "Intercambiar ánodos" / "Intercambiar cátodos".
Future<void> _stage(WidgetTester tester, String type) async {
  await tester.tap(find.byKey(ValueKey('swap-type-$type')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('swap-stage')));
  await tester.pumpAndSettle();
}

final _save = find.widgetWithText(FilledButton, 'Guardar cambios');

/// "Guardar cambios" is always there; it only turns on once a swap is staged.
bool _canSave(WidgetTester tester) => tester.widget<FilledButton>(_save).onPressed != null;

Future<void> _back(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Volver'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens on the cell it came from and lists the others to pick', (tester) async {
    await _pump(tester);

    expect(find.text('Celda A1'), findsOneWidget);
    expect(find.text('Elegir celda'), findsOneWidget); // the right one
    await tester.tap(find.byKey(const ValueKey('swap-pick-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pick-1')), findsNothing); // already on the left
    expect(find.byKey(const ValueKey('pick-150')), findsNothing);

    await tester.enterText(find.byType(TextField), 'cat-014'); // A2's cathode
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pick-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('pick-3')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('pick-2')));
    await tester.pumpAndSettle();
    expect(find.text('Celda A2'), findsOneWidget);
  });

  testWidgets('"Intercambiar" only stages the swap; "Guardar cambios" sends it', (tester) async {
    final backend = await _pump(tester);
    await _pickRight(tester, 2);
    expect(_canSave(tester), isFalse); // nothing to save yet

    await _stage(tester, 'cathode');
    expect(_canSave(tester), isTrue);
    expect(backend.swapRequests, 0); // not sent until saved
    // The cells already show the exchange.
    expect(
      find.descendant(of: find.byKey(const ValueKey('swap-cathode-1')), matching: find.text('CAT-001')),
      findsOneWidget,
    );

    await tester.ensureVisible(_save);
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(backend.swapRequests, 1);
    expect(backend.component(1)['cell_id'], 2);
    expect(backend.component(3)['cell_id'], 1);
    expect(find.text('Cambios guardados.'), findsOneWidget);
    expect(_canSave(tester), isFalse);
  });

  testWidgets('both pairs can be swapped and saved together', (tester) async {
    final backend = await _pump(tester);
    await _pickRight(tester, 2);

    await _stage(tester, 'cathode');
    await _stage(tester, 'anode');
    await tester.ensureVisible(_save);
    await tester.tap(_save);
    await tester.pumpAndSettle();

    expect(backend.swapRequests, 2);
    expect([backend.component(1)['cell_id'], backend.component(2)['cell_id']], [2, 2]);
    expect([backend.component(3)['cell_id'], backend.component(4)['cell_id']], [1, 1]);
  });

  testWidgets('the type toggle picks what "Intercambiar" swaps; undo clears it', (tester) async {
    final backend = await _pump(tester);
    await _pickRight(tester, 2);
    expect(find.text('Sin cambios pendientes'), findsOneWidget);
    expect(find.text('Intercambiar ánodos'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('swap-type-cathode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Intercambiar cátodos'));
    await tester.pumpAndSettle();
    expect(find.text('1 intercambio pendiente'), findsOneWidget);
    expect(_canSave(tester), isTrue);
    expect(
      find.descendant(of: find.byKey(const ValueKey('swap-cathode-1')), matching: find.text('CAT-001')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('swap-undo')));
    await tester.pumpAndSettle();
    expect(find.text('Sin cambios pendientes'), findsOneWidget);
    expect(_canSave(tester), isFalse);
    expect(backend.swapRequests, 0);
  });

  testWidgets('pressing "Intercambiar" again undoes the staged swap', (tester) async {
    await _pump(tester);
    await _pickRight(tester, 2);

    await _stage(tester, 'cathode');
    await _stage(tester, 'cathode');
    expect(_canSave(tester), isFalse);
  });

  testWidgets('nothing can be dragged: swaps only go through "Intercambiar"', (tester) async {
    await _pump(tester);
    await _pickRight(tester, 2);

    expect(find.byWidgetPredicate((w) => w is Draggable), findsNothing);
  });

  testWidgets('a cell without that component cannot take part', (tester) async {
    await _pump(tester);
    await _pickRight(tester, 3); // B3 has neither

    await _stage(tester, 'cathode');
    expect(find.text('El intercambio no se puede realizar porque no hay un componente disponible.'), findsOneWidget);
    expect(_canSave(tester), isFalse);
  });

  testWidgets('going back without changes leaves at once', (tester) async {
    await _pump(tester);
    await _back(tester);
    expect(find.text('previous screen'), findsOneWidget);

    // Not awaited: push completes only once the screen is popped.
    GoRouter.of(tester.element(find.text('previous screen'))).push('/swap?cell=1');
    await tester.pumpAndSettle();
    await _pickRight(tester, 2); // a cell picked but nothing staged
    await _back(tester);
    expect(find.text('previous screen'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('going back with changes asks; "Descartar" leaves without saving', (tester) async {
    final backend = await _pump(tester);
    await _pickRight(tester, 2);
    await _stage(tester, 'cathode');

    await _back(tester);
    expect(find.text('Tienes cambios sin guardar'), findsOneWidget);
    await tester.tap(find.text('Descartar'));
    await tester.pumpAndSettle();

    expect(find.text('previous screen'), findsOneWidget);
    expect(backend.swapRequests, 0);
    expect(backend.component(1)['cell_id'], 1);
  });

  testWidgets('going back with changes and choosing "Guardar" saves, then leaves', (tester) async {
    final backend = await _pump(tester);
    await _pickRight(tester, 2);
    await _stage(tester, 'cathode');

    await tester.binding.handlePopRoute(); // the system back asks too
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('previous screen'), findsOneWidget);
    expect(backend.component(1)['cell_id'], 2);
  });

  testWidgets('offline the saved swap is applied on the device and queued', (tester) async {
    final backend = await _pump(tester);
    await _pickRight(tester, 2);
    await _stage(tester, 'cathode');

    backend.offline = true;
    await tester.ensureVisible(_save);
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(find.textContaining('Sin conexión'), findsOneWidget);
    expect(backend.component(1)['cell_id'], 1); // the server was not reached
    expect(_canSave(tester), isFalse);
  });
}
