import 'dart:convert';
import 'package:blueflora/application/trees_controller.dart';
import 'package:blueflora/data/local_tree_repository.dart';
import 'package:blueflora/domain/tree.dart';
import 'package:blueflora/presentation/design/blueflora_theme.dart';
import 'package:blueflora/presentation/design/flora_components.dart';
import 'package:blueflora/presentation/screens/main_screen.dart';
import 'package:blueflora/presentation/screens/views/home_view.dart';
import 'package:blueflora/presentation/screens/views/tree_detail_view.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:blueflora/presentation/widgets/flora_time_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/test_tree_store.dart';
import 'support/reminder_fakes.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<void> tap(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      final list = find.byType(ListView);
      if (list.evaluate().length == 1) {
        await tester.drag(list, const Offset(0, 8000));
        await tester.pumpAndSettle();
      }
      await tester.scrollUntilVisible(finder, 160);
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<void> tab(WidgetTester tester, IconData icon) => tap(
    tester,
    find.descendant(
      of: find.byType(BottomNavigationBar),
      matching: find.byIcon(icon),
    ),
  );

  for (final dark in [false, true]) {
    testWidgets(
      'Recorrido completo a ${dark ? 320 : 390}px y texto ${dark ? 200 : 100}%',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(dark ? 320 : 390, 760));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final seed = Tree(nombre: 'Pino', frecuenciaRiegoDias: 3);
        final store = TestTreeStore()
          ..treeRecords = [jsonEncode(seed.toJson())];
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? BluefloraTheme.dark : BluefloraTheme.light,
            home: MediaQuery(
              data: MediaQueryData(
                textScaler: TextScaler.linear(dark ? 2 : 1),
                disableAnimations: true,
              ),
              child: MainScreen(
                repository: LocalTreeRepository(store: store),
                notificationGateway: FakeNotificationGateway(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final controller = tester
            .widget<HomeView>(find.byType(HomeView))
            .controller;
        await tap(tester, find.byKey(const ValueKey('home-open-trees')));
        await tap(tester, find.byTooltip('Agregar planta'));
        await tester.enterText(find.byType(TextFormField).at(0), 'Pino');
        await tester.enterText(find.byType(TextFormField).at(3), '4');
        await tap(tester, find.text('Guardar árbol'));
        expect(controller.trees.length, 2);
        expect(controller.trees.map((p) => p.id).toSet().length, 2);
        final id = controller.trees.last.id;
        Finder action(String tooltip) => find.descendant(
          of: find.byKey(ValueKey(id)),
          matching: find.byTooltip(tooltip),
        );
        await tap(tester, action('Editar árbol'));
        await tester.enterText(
          find.byType(TextFormField).at(0),
          'Cambio cancelado',
        );
        await tap(tester, find.text('Cancelar'));
        expect(controller.plantById(id)!.nombre, 'Pino');
        await tap(tester, action('Ver detalle'));
        await tap(tester, find.text('Registrar riego manual'));
        expect(controller.eventsFor(id).length, 1);
        final event = controller.eventsFor(id).single;
        await tap(tester, find.text('Editar planta'));
        await tester.enterText(find.byType(TextFormField).at(0), 'Roble');
        await tap(tester, find.text('Guardar cambios'));
        expect(controller.plantById(id)!.nombre, 'Roble');
        expect(
          controller
              .plantById(id)!
              .ultimoRiego!
              .isAtSameMomentAs(event.occurredAt),
          isTrue,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tab(tester, Icons.home);
        expect(controller.summary.total, 2);
        await tab(tester, Icons.history);
        await tap(tester, find.byKey(ValueKey('event-${event.id}')));
        expect(
          tester.widget<TreeDetailView>(find.byType(TreeDetailView)).plantId,
          id,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tab(tester, Icons.forest);
        await tap(tester, action('Eliminar árbol'));
        await tap(tester, find.text('Eliminar'));
        await tab(tester, Icons.history);
        final tile = tester.widget<ListTile>(
          find.byKey(ValueKey('event-${event.id}')),
        );
        expect(tile.onTap, isNull);
        expect(find.text('Planta eliminada'), findsOneWidget);
        await tab(tester, Icons.account_circle);
        await tap(tester, find.text('Configuraciones'));
        await tester.pageBack();
        await tester.pumpAndSettle();
        final restored = TreesController(
          repository: LocalTreeRepository(store: store),
          autoRefresh: false,
        );
        await restored.load();
        expect(restored.trees.single.id, seed.id);
        expect(restored.eventsFor().single.id, event.id);
        restored.dispose();
      },
    );
  }

  testWidgets(
    'Movimiento reducido no anuncia un porcentaje de progreso inventado',
    (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          home: const MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Scaffold(body: FloraLoading(label: 'Guardando cambios…')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.hourglass_empty), findsOneWidget);
      expect(find.bySemanticsLabel('Guardando cambios…'), findsOneWidget);
      handle.dispose();
    },
  );
  testWidgets('Horario con teclado abierto a 320px y texto al 200%', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: BluefloraTheme.dark,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
            disableAnimations: true,
            viewInsets: const EdgeInsets.only(bottom: 240),
          ),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => showFloraTimePicker(
                context,
                const TimeOfDay(hour: 9, minute: 0),
              ),
              child: const Text('Horario'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Horario'));
    await tester.pumpAndSettle();
    final minute = find.byType(TextFormField).last;
    await tester.ensureVisible(minute);
    await tester.pumpAndSettle();
    await tester.enterText(minute, '25');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
