import 'dart:async';
import 'dart:convert';

import 'package:blueflora/application/trees_controller.dart';
import 'package:blueflora/data/local_tree_repository.dart';
import 'package:blueflora/domain/plant_snapshot.dart';
import 'package:blueflora/domain/tree.dart';
import 'package:blueflora/domain/watering_event.dart';
import 'package:blueflora/presentation/screens/main_screen.dart';
import 'package:blueflora/presentation/screens/views/home_view.dart';
import 'package:blueflora/presentation/screens/views/tree_detail_view.dart';
import 'package:blueflora/presentation/widgets/watering_event_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_tree_store.dart';

void main() {
  late TestTreeStore store;
  late Tree first;
  late Tree second;
  setUp(() {
    first = Tree(
      nombre: 'Pino',
      especie: 'Pinus',
      altura: 2,
      frecuenciaRiegoDias: 3,
    );
    second = Tree(
      nombre: 'Pino',
      especie: 'Otro ejemplar',
      frecuenciaRiegoDias: 5,
    );
    store = TestTreeStore()
      ..records = [jsonEncode(first.toJson()), jsonEncode(second.toJson())];
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MainScreen(repository: LocalTreeRepository(store: store)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tab(WidgetTester tester, IconData icon) async {
    await tester.tap(
      find.descendant(
        of: find.byType(BottomNavigationBar),
        matching: find.byIcon(icon),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> detail(WidgetTester tester, Tree plant) async {
    await tab(tester, Icons.forest);
    final button = find.descendant(
      of: find.byKey(ValueKey(plant.id)),
      matching: find.byTooltip('Ver detalle'),
    );
    if (button.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        button,
        150,
        scrollable: find.byType(Scrollable),
      );
    } else {
      await Scrollable.ensureVisible(tester.element(button), alignment: 0.5);
    }
    await Scrollable.ensureVisible(tester.element(button), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Future<void> visible(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        finder,
        160,
        scrollable: find.byType(Scrollable),
      );
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  TreesController shared(WidgetTester tester) => tester
      .widget<HomeView>(find.byType(HomeView, skipOffstage: false))
      .controller;

  testWidgets(
    'Abre el detalle por ID y muestra datos, fechas desconocidas y estado vacío',
    (tester) async {
      await open(tester);
      await detail(tester, first);
      expect(find.text('Detalle de planta'), findsOneWidget);
      expect(find.text('Especie: Pinus'), findsOneWidget);
      expect(find.text('Altura: 2.0 m'), findsOneWidget);
      expect(find.text('Frecuencia: cada 3 días'), findsOneWidget);
      expect(find.text('Último riego: desconocido'), findsOneWidget);
      expect(
        find.text('Próximo riego: no se puede calcular sin una fecha previa.'),
        findsOneWidget,
      );
      expect(
        find.text('Calendario desconocido: falta la fecha del último riego.'),
        findsOneWidget,
      );
      expect(find.textContaining('necesita agua'), findsNothing);
      await visible(
        tester,
        find.text('Aún no hay riegos registrados para esta planta.'),
      );
      expect(find.byType(WateringEventTile), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await detail(tester, second);
      expect(find.text('Especie: Otro ejemplar'), findsOneWidget);
      expect(find.textContaining('Altura:'), findsNothing);
      expect(
        tester.widget<TreeDetailView>(find.byType(TreeDetailView)).controller,
        same(shared(tester)),
      );
      expect(store.reads, 1);
    },
  );

  testWidgets(
    'Editar desde el detalle actualiza datos y conserva identidad y último riego',
    (tester) async {
      final original = first.copyWith(ultimoRiego: DateTime.utc(2026, 11, 3));
      store.records = [jsonEncode(original.toJson())];
      await open(tester);
      await detail(tester, original);
      await visible(tester, find.text('Editar planta'));
      await tester.tap(find.text('Editar planta'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'Roble editado');
      await tester.enterText(find.byType(TextFormField).at(1), 'Quercus');
      await tester.enterText(find.byType(TextFormField).at(2), '4,5');
      await tester.enterText(find.byType(TextFormField).at(3), '7');
      await visible(tester, find.text('Guardar cambios'));
      await tester.tap(find.text('Guardar cambios'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, 1000));
      await tester.pumpAndSettle();
      expect(find.text('Roble editado'), findsOneWidget);
      expect(find.text('Especie: Quercus'), findsOneWidget);
      expect(find.text('Altura: 4.5 m'), findsOneWidget);
      expect(find.text('Frecuencia: cada 7 días'), findsOneWidget);
      expect(
        find.textContaining(
          'Próximo riego: ${formatLocalDateTime(original.ultimoRiego!.add(const Duration(days: 7)))}',
        ),
        findsOneWidget,
      );
      expect(
        shared(tester).plantById(first.id)!.ultimoRiego,
        original.ultimoRiego,
      );
      expect(shared(tester).eventsFor(), isEmpty);
    },
  );

  testWidgets(
    'Registrar desde detalle crea un evento que aparece en historial y persiste',
    (tester) async {
      store.records = [jsonEncode(first.toJson())];
      await open(tester);
      await detail(tester, first);
      await visible(tester, find.text('Registrar riego manual'));
      await tester.tap(find.text('Registrar riego manual'));
      await tester.pumpAndSettle();
      final controller = shared(tester);
      final event = controller.eventsFor(first.id).single;
      expect(
        controller
            .plantById(first.id)!
            .ultimoRiego!
            .isAtSameMomentAs(event.occurredAt),
        isTrue,
      );
      await visible(tester, find.byKey(ValueKey('event-${event.id}')));
      expect(find.textContaining('Registro manual'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tab(tester, Icons.history);
      expect(find.byKey(ValueKey('event-${event.id}')), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('event-${event.id}')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TreeDetailView>(find.byType(TreeDetailView)).plantId,
        first.id,
      );
      expect(
        tester.widget<TreeDetailView>(find.byType(TreeDetailView)).controller,
        same(controller),
      );
      await tester.pumpWidget(const SizedBox());
      await open(tester);
      await tab(tester, Icons.history);
      expect(find.byKey(ValueKey('event-${event.id}')), findsOneWidget);
      expect(shared(tester).eventsFor(), hasLength(1));
      expect(shared(tester).plantById(first.id)!.ultimoRiego, isNotNull);
    },
  );

  testWidgets('Detalle de plantas homónimas filtra eventos por ID', (
    tester,
  ) async {
    final event = WateringEvent(
      plantId: first.id,
      plantName: first.nombre,
      occurredAt: DateTime.utc(2026, 11, 4),
    );
    store.records = [
      jsonEncode(
        PlantSnapshot(
          trees: [
            first.copyWith(ultimoRiego: event.occurredAt),
            second,
          ],
          events: [event],
        ).toJson(),
      ),
    ];
    await open(tester);
    await detail(tester, second);
    await visible(
      tester,
      find.text('Aún no hay riegos registrados para esta planta.'),
    );
    expect(find.byType(WateringEventTile), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await detail(tester, first);
    await visible(tester, find.byKey(ValueKey('event-${event.id}')));
    expect(find.byType(WateringEventTile), findsOneWidget);
  });

  testWidgets(
    'Historial ordena eventos descendentes y muestra nombre actual y planta eliminada',
    (tester) async {
      final oldest = WateringEvent(
        plantId: first.id,
        plantName: 'Nombre original',
        occurredAt: DateTime.utc(2026, 1, 1),
      );
      final middle = WateringEvent(
        plantId: second.id,
        plantName: 'Planta borrada',
        occurredAt: DateTime.utc(2026, 6, 1),
      );
      final newest = WateringEvent(
        plantId: first.id,
        plantName: first.nombre,
        occurredAt: DateTime.utc(2026, 11, 4),
      );
      store.records = [
        jsonEncode(
          PlantSnapshot(
            trees: [first],
            events: [oldest, newest, middle],
          ).toJson(),
        ),
      ];
      await open(tester);
      await tab(tester, Icons.history);
      final tiles = tester
          .widgetList<WateringEventTile>(find.byType(WateringEventTile))
          .toList();
      expect(tiles.map((tile) => tile.event.id), [
        newest.id,
        middle.id,
        oldest.id,
      ]);
      expect(find.textContaining('Planta eliminada'), findsOneWidget);
      expect(
        find.textContaining('Nombre al registrar: Nombre original'),
        findsOneWidget,
      );
      final deleted = tester.widget<ListTile>(
        find.byKey(ValueKey('event-${middle.id}')),
      );
      expect(deleted.onTap, isNull);
      expect(deleted.title, isA<Text>());
    },
  );

  testWidgets(
    'Un fallo de riego no publica evento y su reintento genera solo uno',
    (tester) async {
      store.records = [jsonEncode(first.toJson())];
      await open(tester);
      await detail(tester, first);
      store.writeResult = false;
      await visible(tester, find.text('Registrar riego manual'));
      await tester.tap(find.text('Registrar riego manual'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No se pudieron guardar'), findsOneWidget);
      expect(shared(tester).eventsFor(), isEmpty);
      expect(shared(tester).plantById(first.id)!.ultimoRiego, isNull);
      final failed = jsonDecode(store.writes.single.single)['events'][0];
      store.writeResult = true;
      await visible(tester, find.text('Reintentar guardado'));
      await tester.tap(find.text('Reintentar guardado'));
      await tester.pumpAndSettle();
      expect(shared(tester).eventsFor().single.toJson(), failed);
      expect(find.textContaining('No se pudieron guardar'), findsNothing);
    },
  );

  testWidgets(
    'Durante el guardado del detalle se bloquea un segundo registro',
    (tester) async {
      store.records = [jsonEncode(first.toJson())];
      await open(tester);
      await detail(tester, first);
      await visible(tester, find.text('Registrar riego manual'));
      store.writeGate = Completer<void>();
      await tester.tap(find.text('Registrar riego manual'));
      await tester.pump();
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Registrar riego manual'),
            )
            .onPressed,
        isNull,
      );
      expect(shared(tester).eventsFor(), isEmpty);
      store.writeGate!.complete();
      await tester.pumpAndSettle();
      expect(shared(tester).eventsFor(), hasLength(1));
      expect(store.writes, hasLength(1));
    },
  );

  testWidgets(
    'Eliminar una planta abierta muestra ausencia y conserva su historial',
    (tester) async {
      store.records = [jsonEncode(first.toJson())];
      await open(tester);
      final controller = shared(tester);
      await controller.water(first.id);
      await tester.pumpAndSettle();
      await detail(tester, first);
      await controller.delete(first.id);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Esta planta ya no está registrada. Su historial se conserva.',
        ),
        findsOneWidget,
      );
      expect(controller.eventsFor(), hasLength(1));
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tab(tester, Icons.history);
      expect(find.textContaining('Planta eliminada'), findsOneWidget);
    },
  );

  testWidgets('Historial vacío informa que no se inventan eventos anteriores', (
    tester,
  ) async {
    store.records = [
      jsonEncode(first.copyWith(ultimoRiego: DateTime.utc(2020)).toJson()),
    ];
    await open(tester);
    await tab(tester, Icons.history);
    expect(
      find.text('Tu historial empieza con el próximo riego que registres.'),
      findsOneWidget,
    );
    expect(find.byType(WateringEventTile), findsNothing);
    expect(store.writes, isEmpty);
  });
}
