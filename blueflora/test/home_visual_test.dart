import 'dart:async';
import 'dart:convert';
import 'package:blueflora/application/trees_controller.dart';
import 'package:blueflora/data/local_tree_repository.dart';
import 'package:blueflora/domain/tree.dart';
import 'package:blueflora/presentation/design/blueflora_theme.dart';
import 'package:blueflora/presentation/design/flora_components.dart';
import 'package:blueflora/presentation/screens/main_screen.dart';
import 'package:blueflora/presentation/screens/views/home_view.dart';
import 'package:blueflora/presentation/screens/views/trees_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/test_tree_store.dart';

void main() {
  final now = DateTime(2026, 11, 5, 12);
  late TestTreeStore store;
  late TreesController controller;
  setUp(() {
    store = TestTreeStore()..records = [];
    controller = TreesController(
      repository: LocalTreeRepository(store: store),
      clock: () => now,
      autoRefresh: false,
    );
  });
  tearDown(() => controller.dispose());

  Future<void> open(WidgetTester tester, {bool dark = false}) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? BluefloraTheme.dark : BluefloraTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(
            textScaler: TextScaler.linear(2),
            disableAnimations: true,
            viewInsets: EdgeInsets.only(bottom: 160),
          ),
          child: HomeView(controller: controller, onOpenTrees: () {}),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> metric(WidgetTester tester, String name, int value) async {
    await tester.drag(find.byType(ListView), const Offset(0, 3000));
    await tester.pumpAndSettle();
    final finder = find.byKey(ValueKey('summary-$name'));
    await tester.scrollUntilVisible(finder, 140);
    expect(tester.widget<Text>(finder).data, '$value');
    expect(tester.takeException(), isNull);
  }

  for (final dark in [false, true]) {
    testWidgets('Inicio vacío a 320px/200% con teclado y tema oscuro=$dark', (
      tester,
    ) async {
      await tester.runAsync(controller.load);
      await open(tester, dark: dark);
      await tester.scrollUntilVisible(find.text('Tu jardín empieza aquí'), 140);
      expect(find.text('Tu jardín empieza aquí'), findsOneWidget);
      for (final name in [
        'total',
        'overdue',
        'today',
        'tomorrow',
        'undated',
        'pending',
      ]) {
        await metric(tester, name, 0);
      }
      await tester.scrollUntilVisible(find.text('Un consejo para cuidar'), 140);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Calendario mixto a 320px/200% con tema oscuro=$dark', (
      tester,
    ) async {
      store.treeRecords = [
        Tree(
          nombre: 'Vencida',
          frecuenciaRiegoDias: 1,
          ultimoRiego: now.subtract(const Duration(days: 2)),
        ),
        Tree(
          nombre: 'Hoy',
          frecuenciaRiegoDias: 1,
          ultimoRiego: now.subtract(const Duration(hours: 20)),
        ),
        Tree(
          nombre: 'Mañana',
          frecuenciaRiegoDias: 2,
          ultimoRiego: now.subtract(const Duration(days: 1)),
        ),
        Tree(nombre: 'Después', frecuenciaRiegoDias: 5, ultimoRiego: now),
        Tree(nombre: 'Desconocida', frecuenciaRiegoDias: 3),
      ].map((tree) => jsonEncode(tree.toJson())).toList();
      await tester.runAsync(controller.load);
      await open(tester, dark: dark);
      for (final entry in {
        'total': 5,
        'overdue': 1,
        'today': 1,
        'tomorrow': 1,
        'undated': 1,
        'pending': 3,
      }.entries) {
        await metric(tester, entry.key, entry.value);
      }
      expect(
        find.text('Información desconocida; no indica falta de agua.'),
        findsOneWidget,
      );
      // Los estados no dependen únicamente del color.
      expect(find.text('Por revisar'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Un consejo para cuidar'), 140);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Un riego actualiza la presentación y no afirma salud desconocida',
    (tester) async {
      final plant = Tree(nombre: 'Pino', frecuenciaRiegoDias: 2);
      store.treeRecords = [jsonEncode(plant.toJson())];
      await tester.runAsync(controller.load);
      await tester.pumpWidget(
        MaterialApp(
          theme: BluefloraTheme.light,
          home: HomeView(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Completa las fechas'), findsOneWidget);
      await tester.runAsync(() => controller.water(plant.id));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('¡Tu calendario está al día!'),
        findsOneWidget,
      );
      await metric(tester, 'undated', 0);
      await metric(tester, 'pending', 0);
      await metric(tester, 'total', 1);
    },
  );

  testWidgets(
    'Carga y error caben con texto ampliado; reintento conserva datos',
    (tester) async {
      store.readGate = Completer<void>();
      late Future<bool> loading;
      await tester.runAsync(() async {
        loading = controller.load();
      });
      await open(tester);
      await tester.scrollUntilVisible(find.byType(FloraLoading), 140);
      expect(find.byType(FloraLoading), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.hourglass_empty), findsOneWidget);
      store.readError = StateError('sin acceso');
      store.readGate!.complete();
      await tester.runAsync(() => loading);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Reintentar'), 140);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No se pudieron cargar'), findsOneWidget);
      expect(tester.takeException(), isNull);
      store.readError = null;
      store.readGate = null;
      await tester.tap(find.text('Reintentar'));
      await tester.runAsync(() async {});
      await tester.pumpAndSettle();
      expect(controller.loadError, isNull);
      expect(controller.loading, isFalse);
      await metric(tester, 'total', 0);
      expect(store.writes, isEmpty);
    },
  );

  testWidgets('Acceso desde Inicio abre Mis árboles con el mismo controlador', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BluefloraTheme.light,
        home: MainScreen(repository: LocalTreeRepository(store: store)),
      ),
    );
    await tester.pumpAndSettle();
    final shared = tester.widget<HomeView>(find.byType(HomeView)).controller;
    final button = find.byKey(const ValueKey('home-open-trees'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TreesView>(find.byType(TreesView)).controller,
      same(shared),
    );
    expect(
      tester
          .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
          .currentIndex,
      1,
    );
  });
}
