import 'dart:convert';
import 'package:blueflora/application/trees_controller.dart';
import 'package:blueflora/data/local_tree_repository.dart';
import 'package:blueflora/domain/plant_snapshot.dart';
import 'package:blueflora/domain/tree.dart';
import 'package:blueflora/domain/watering_event.dart';
import 'package:blueflora/presentation/design/blueflora_theme.dart';
import 'package:blueflora/presentation/design/flora_components.dart';
import 'package:blueflora/presentation/screens/views/history_view.dart';
import 'package:blueflora/presentation/screens/views/tree_detail_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/test_tree_store.dart';

void main() {
  Future<void> open(
    WidgetTester tester,
    TreesController controller,
    bool dark,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? BluefloraTheme.dark : BluefloraTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(
            textScaler: TextScaler.linear(2),
            disableAnimations: true,
          ),
          child: HistoryView(controller: controller),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> see(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) await tester.scrollUntilVisible(finder, 180);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  for (final dark in [false, true]) {
    testWidgets('Historial vacío a 320px/200%, oscuro=$dark', (tester) async {
      final store = TestTreeStore()..records = [];
      final controller = TreesController(
        repository: LocalTreeRepository(store: store),
        autoRefresh: false,
      );
      addTearDown(controller.dispose);
      await controller.load();
      await open(tester, controller, dark);
      await see(tester, find.text('Aún no hay riegos registrados'));
      await see(
        tester,
        find.text('Tu historial empieza con el próximo riego que registres.'),
      );
      expect(store.writes, isEmpty);
    });
    testWidgets(
      'Eventos renombrados, eliminados y homónimos a 320px/200%, oscuro=$dark',
      (tester) async {
        final first = Tree(
          nombre: 'Nombre actual bastante largo',
          frecuenciaRiegoDias: 3,
        );
        final twin = Tree(nombre: first.nombre, frecuenciaRiegoDias: 4);
        final events = [
          WateringEvent(
            plantId: first.id,
            plantName: 'Nombre anterior',
            occurredAt: DateTime.utc(2026, 11, 5, 13),
          ),
          WateringEvent(
            plantId: twin.id,
            plantName: twin.nombre,
            occurredAt: DateTime.utc(2026, 11, 5, 12),
          ),
          WateringEvent(
            plantId: 'deleted',
            plantName: 'Planta anterior',
            occurredAt: DateTime.utc(2026, 11, 4, 8),
          ),
        ];
        final store = TestTreeStore()
          ..records = [
            jsonEncode(
              PlantSnapshot(
                trees: [first, twin],
                events: events.reversed.toList(),
              ).toJson(),
            ),
          ];
        final controller = TreesController(
          repository: LocalTreeRepository(store: store),
          autoRefresh: false,
        );
        addTearDown(controller.dispose);
        await controller.load();
        await open(tester, controller, dark);
        for (final event in events) {
          await see(tester, find.byKey(ValueKey('event-${event.id}')));
          final tile = tester.widget<ListTile>(
            find.byKey(ValueKey('event-${event.id}')),
          );
          expect(
            (tile.title! as Text).data,
            event.plantId == 'deleted' ? event.plantName : first.nombre,
          );
          expect(tile.onTap == null, event.plantId == 'deleted');
        }
        expect(find.text('Planta eliminada'), findsOneWidget);
        // Abrir la segunda planta homónima usa su ID, no su nombre.
        await tester.drag(find.byType(ListView), const Offset(0, 4000));
        await tester.pumpAndSettle();
        final secondEvent = find.byKey(ValueKey('event-${events[1].id}'));
        await see(tester, secondEvent);
        await tester.tap(secondEvent);
        await tester.pumpAndSettle();
        expect(
          tester.widget<TreeDetailView>(find.byType(TreeDetailView)).plantId,
          twin.id,
        );
        expect(
          controller.eventsFor().map((event) => event.id),
          events.map((event) => event.id),
        );
        expect(store.writes, isEmpty);
      },
    );
  }

  testWidgets('Carga, error y reintento en Historial con movimiento reducido', (
    tester,
  ) async {
    final store = TestTreeStore()..records = [];
    final controller = TreesController(
      repository: LocalTreeRepository(store: store),
      autoRefresh: false,
    );
    addTearDown(controller.dispose);
    // Sin carga inicial confirmada, el controlador presenta el estado de carga.
    await open(tester, controller, false);
    await see(tester, find.byType(FloraLoading));
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.hourglass_empty), findsOneWidget);
    store.readError = StateError('lectura fallida');
    await controller.load();
    await tester.pumpAndSettle();
    await see(tester, find.text('Reintentar'));
    store.readError = null;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    await see(tester, find.text('Aún no hay riegos registrados'));
    expect(store.writes, isEmpty);
  });
}
