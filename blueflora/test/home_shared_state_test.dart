import 'dart:async';
import 'dart:convert';

import 'package:blueflora/data/local_tree_repository.dart';
import 'package:blueflora/domain/tree.dart';
import 'package:blueflora/presentation/screens/main_screen.dart';
import 'package:blueflora/presentation/screens/views/home_view.dart';
import 'package:blueflora/presentation/screens/views/trees_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_tree_store.dart';

void main() {
  late TestTreeStore store;
  setUp(() => store = TestTreeStore()..records = []);

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MainScreen(repository: LocalTreeRepository(store: store)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tab(WidgetTester tester, IconData icon) async {
    await tapVisible(tester, find.byIcon(icon));
    await tester.pumpAndSettle();
  }

  Future<void> metric(WidgetTester tester, String name, int expected) async {
    // Inicio tiene desplazamiento; regresar arriba antes de buscar cada tarjeta.
    await tester.drag(find.byType(ListView), const Offset(0, 2000));
    await tester.pumpAndSettle();
    final finder = find.byKey(ValueKey('summary-$name'));
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        finder,
        160,
        scrollable: find.byType(Scrollable),
      );
      await tester.pumpAndSettle();
    }
    expect(tester.widget<Text>(finder).data, '$expected');
  }

  testWidgets(
    'Inicio y Mis árboles comparten controlador y sincronizan todas las operaciones',
    (tester) async {
      final now = DateTime.now();
      final overdue = Tree(
        nombre: 'Pino',
        frecuenciaRiegoDias: 1,
        ultimoRiego: now.subtract(const Duration(days: 2)),
      );
      final undated = Tree(nombre: 'Roble', frecuenciaRiegoDias: 3);
      store.treeRecords = [
        jsonEncode(overdue.toJson()),
        jsonEncode(undated.toJson()),
      ];
      await open(tester);
      final controller = tester
          .widget<HomeView>(find.byType(HomeView))
          .controller;
      expect(
        tester
            .widget<TreesView>(find.byType(TreesView, skipOffstage: false))
            .controller,
        same(controller),
      );
      await metric(tester, 'total', 2);
      await metric(tester, 'pending', 2);

      await tab(tester, Icons.forest);
      await tapVisible(tester, find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'Helecho');
      await tester.enterText(find.byType(TextFormField).at(3), '3');
      await tapVisible(tester, find.text('Guardar árbol'));
      await tester.pumpAndSettle();
      await tab(tester, Icons.home);
      await metric(tester, 'total', 3);
      await metric(tester, 'pending', 2);

      await tab(tester, Icons.forest);
      await tapVisible(
        tester,
        find.descendant(
          of: find.byKey(ValueKey(overdue.id)),
          matching: find.byIcon(Icons.edit),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(3), '3');
      await tester.ensureVisible(find.text('Guardar cambios'));
      await tapVisible(tester, find.text('Guardar cambios'));
      await tester.pumpAndSettle();
      await tab(tester, Icons.home);
      await metric(tester, 'pending', 1);
      await metric(tester, 'overdue', 0);
      await metric(tester, 'tomorrow', 1);

      await tab(tester, Icons.forest);
      final water = find.descendant(
        of: find.byKey(ValueKey(undated.id)),
        matching: find.text('Registrar riego'),
      );
      await tester.ensureVisible(water);
      await tapVisible(tester, water);
      await tester.pumpAndSettle();
      await tab(tester, Icons.home);
      await metric(tester, 'pending', 0);
      await metric(tester, 'undated', 0);

      await tab(tester, Icons.forest);
      await tester.drag(find.byType(ListView), const Offset(0, 1000));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(ValueKey(overdue.id)),
        const Offset(-700, 0),
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Eliminar'));
      await tester.pumpAndSettle();
      await tab(tester, Icons.home);
      await metric(tester, 'total', 2);
      expect(controller.trees.map((tree) => tree.nombre), ['Roble', 'Helecho']);
      expect(store.reads, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Lista vacía muestra invitación y todos los indicadores en cero',
    (tester) async {
      await open(tester);
      expect(find.text('Tu jardín empieza aquí'), findsOneWidget);
      await metric(tester, 'total', 0);
      await metric(tester, 'pending', 0);
      await metric(tester, 'overdue', 0);
      await metric(tester, 'today', 0);
      await metric(tester, 'tomorrow', 0);
      await metric(tester, 'undated', 0);
    },
  );

  testWidgets(
    'Carga fallida se comparte entre pantallas y un reintento recupera ambas',
    (tester) async {
      store.readError = StateError('sin acceso');
      await open(tester);
      expect(find.textContaining('No se pudieron cargar'), findsOneWidget);
      await tab(tester, Icons.forest);
      expect(find.textContaining('No se pudieron cargar'), findsOneWidget);
      expect(
        tester
            .widget<FloatingActionButton>(find.byType(FloatingActionButton))
            .onPressed,
        isNull,
      );
      store.readError = null;
      await tapVisible(tester, find.text('Reintentar'));
      await tester.pumpAndSettle();
      await tab(tester, Icons.home);
      await metric(tester, 'total', 0);
      expect(store.reads, 2);
      expect(store.writes, isEmpty);
    },
  );

  testWidgets(
    'Un guardado fallido no publica datos en Inicio y se reintenta desde allí',
    (tester) async {
      store.treeRecords = [
        jsonEncode(Tree(nombre: 'Pino', frecuenciaRiegoDias: 3).toJson()),
      ];
      await open(tester);
      await tab(tester, Icons.forest);
      store.writeResult = false;
      await tapVisible(tester, find.text('Registrar riego'));
      await tester.pumpAndSettle();
      await tab(tester, Icons.home);
      expect(find.textContaining('No se pudieron guardar'), findsOneWidget);
      await metric(tester, 'pending', 1);
      store.writeResult = true;
      await tester.drag(find.byType(ListView), const Offset(0, 2000));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Reintentar guardado'));
      await tester.pumpAndSettle();
      await metric(tester, 'pending', 0);
      await tab(tester, Icons.forest);
      expect(find.text('Último riego desconocido'), findsNothing);
      expect(find.textContaining('No se pudieron guardar'), findsNothing);
    },
  );

  testWidgets(
    'Navegar durante un guardado mantiene los indicadores confirmados',
    (tester) async {
      store.treeRecords = [
        jsonEncode(Tree(nombre: 'Pino', frecuenciaRiegoDias: 3).toJson()),
      ];
      await open(tester);
      await tab(tester, Icons.forest);
      store.writeGate = Completer<void>();
      await tapVisible(tester, find.text('Registrar riego'));
      await tester.pump();
      // No pumpAndSettle mientras el indicador de progreso está activo.
      await tapVisible(tester, find.byIcon(Icons.home));
      await tester.pump();
      final controller = tester
          .widget<HomeView>(find.byType(HomeView))
          .controller;
      expect(controller.saving, isTrue);
      expect(controller.summary.pending, 1);
      expect(find.text('Guardando cambios…'), findsOneWidget);
      store.writeGate!.complete();
      await tester.pumpAndSettle();
      await metric(tester, 'pending', 0);
      expect(controller.saving, isFalse);
    },
  );
}

// Las tarjetas y el formulario son desplazables, también con texto grande.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}
