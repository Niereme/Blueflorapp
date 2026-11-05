import 'dart:convert';
import 'package:blueflora/application/trees_controller.dart';
import 'package:blueflora/data/local_tree_repository.dart';
import 'package:blueflora/domain/plant_snapshot.dart';
import 'package:blueflora/domain/tree.dart';
import 'package:blueflora/domain/watering_event.dart';
import 'package:blueflora/presentation/design/blueflora_theme.dart';
import 'package:blueflora/presentation/screens/views/tree_detail_view.dart';
import 'package:blueflora/presentation/widgets/watering_event_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/test_tree_store.dart';

void main() {
  final now = DateTime(2026, 11, 5, 12);
  Future<TreesController> open(
    WidgetTester tester,
    Tree tree, {
    bool dark = false,
    List<WateringEvent> events = const [],
  }) async {
    final store = TestTreeStore()
      ..records = [
        jsonEncode(PlantSnapshot(trees: [tree], events: events).toJson()),
      ];
    final controller = TreesController(
      repository: LocalTreeRepository(store: store),
      clock: () => now,
      autoRefresh: false,
    );
    addTearDown(controller.dispose);
    await controller.load();
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? BluefloraTheme.dark : BluefloraTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(
            textScaler: TextScaler.linear(2),
            disableAnimations: true,
          ),
          child: TreeDetailView(controller: controller, plantId: tree.id),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  Future<void> see(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) await tester.scrollUntilVisible(finder, 180);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  for (final dark in [false, true]) {
    testWidgets('Ficha a 320px/200%, todos los estados, oscuro=$dark', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final dates = <DateTime?>[
        null,
        now.subtract(const Duration(days: 3)),
        now.subtract(const Duration(hours: 20)),
        now,
        now.add(const Duration(days: 1)),
      ];
      final labels = [
        'Calendario desconocido: falta la fecha del último riego.',
        'Riego vencido según el calendario.',
        'Riego programado para hoy.',
        'Riego programado para mañana.',
        'Riego programado para más adelante.',
      ];
      for (var i = 0; i < dates.length; i++) {
        final tree = Tree(
          nombre: 'Una planta con un nombre largo',
          especie: i.isEven ? 'Especie registrada' : null,
          altura: i.isEven ? 1.5 : null,
          frecuenciaRiegoDias: 1,
          ultimoRiego: dates[i],
        );
        await open(tester, tree, dark: dark);
        await see(tester, find.text(labels[i]));
        if (dates[i] == null) {
          expect(find.byKey(const ValueKey('detail-remaining')), findsNothing);
        }
        await see(tester, find.text('Registrar riego manual'));
        await see(
          tester,
          find.text('Aún no hay riegos registrados para esta planta.'),
        );
        final containers = tester.widgetList<AnimatedContainer>(
          find.byType(AnimatedContainer),
        );
        for (final container in containers) {
          expect(container.duration, Duration.zero);
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    });
  }

  testWidgets(
    'Historial individual conserva orden real y nombre al registrar',
    (tester) async {
      final tree = Tree(
        nombre: 'Nombre nuevo',
        frecuenciaRiegoDias: 2,
        ultimoRiego: now,
      );
      final old = WateringEvent(
        plantId: tree.id,
        plantName: 'Nombre anterior',
        occurredAt: now.subtract(const Duration(days: 3)),
      );
      final recent = WateringEvent(
        plantId: tree.id,
        plantName: tree.nombre,
        occurredAt: now,
      );
      await open(tester, tree, events: [old, recent]);
      await see(tester, find.byKey(ValueKey('event-${old.id}')));
      final tiles = tester.widgetList<WateringEventTile>(
        find.byType(WateringEventTile),
      );
      expect(tiles.map((tile) => tile.event.id), [recent.id, old.id]);
      expect(find.text('Nombre al registrar: Nombre anterior'), findsOneWidget);
      expect(find.text('Registro manual'), findsNWidgets(2));
    },
  );

  testWidgets(
    'Un vencido de minutos muestra menos de 24h sin alterar el modelo',
    (tester) async {
      final tree = Tree(
        nombre: 'Pino',
        frecuenciaRiegoDias: 1,
        ultimoRiego: now.subtract(const Duration(days: 1, minutes: 5)),
      );
      await open(tester, tree);
      await see(tester, find.byKey(const ValueKey('detail-remaining')));
      expect(find.text('Vencido hace menos de 24 horas.'), findsOneWidget);
      expect(tree.diasRestantes(ahora: now), 0);
    },
  );
}
