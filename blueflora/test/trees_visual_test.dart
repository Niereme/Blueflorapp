import 'dart:convert';
import 'package:blueflora/application/trees_controller.dart';
import 'package:blueflora/data/local_tree_repository.dart';
import 'package:blueflora/domain/tree.dart';
import 'package:blueflora/presentation/design/blueflora_theme.dart';
import 'package:blueflora/presentation/screens/views/addtree_view.dart';
import 'package:blueflora/presentation/screens/views/trees_view.dart';
import 'package:blueflora/presentation/squares/tree_square.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/test_tree_store.dart';

void main() {
  final now = DateTime(2026, 11, 5, 12);
  for (final dark in [false, true]) {
    testWidgets('Tarjetas y estados a 320 px/200 %, oscuro=$dark', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final plants = [
        Tree(
          nombre: 'Una planta de nombre bastante largo',
          especie: 'Especie de prueba',
          altura: 1.5,
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
        Tree(nombre: 'Sin fecha', frecuenciaRiegoDias: 3),
      ];
      final expected = [
        'Riego vencido',
        'Pendiente hoy',
        'Programado para mañana',
        'Último riego desconocido',
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? BluefloraTheme.dark : BluefloraTheme.light,
          home: MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: Scaffold(
              body: ListView(
                children: [
                  for (final tree in plants)
                    TreeSquare(
                      tree: tree,
                      now: now,
                      onOpen: () {},
                      onEdit: () {},
                      onWater: () {},
                      onDelete: () {},
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      for (final label in expected) {
        await tester.scrollUntilVisible(find.text(label), 200);
        await tester.pumpAndSettle();
        expect(find.text(label), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.scrollUntilVisible(
        find.text('Registro manual. No activa bombas.').last,
        200,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Formulario a 320 px/200 %, teclado y errores, oscuro=$dark', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? BluefloraTheme.dark : BluefloraTheme.light,
          home: const MediaQuery(
            data: MediaQueryData(
              textScaler: TextScaler.linear(2),
              viewInsets: EdgeInsets.only(bottom: 200),
              disableAnimations: true,
            ),
            child: AddTreeView(),
          ),
        ),
      );
      final save = find.text('Guardar árbol');
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      for (final field in [
        find.byType(TextFormField).at(0),
        find.byType(TextFormField).at(3),
      ]) {
        await tester.ensureVisible(field);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(find.text('Escribe el nombre de tu planta.'), findsOneWidget);
      expect(find.textContaining('Escribe días enteros'), findsOneWidget);
      await tester.ensureVisible(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Vacío invita a agregar; cancelar no escribe datos', (
    tester,
  ) async {
    final store = TestTreeStore()..records = [];
    await tester.pumpWidget(
      MaterialApp(
        theme: BluefloraTheme.light,
        home: TreesView(repository: LocalTreeRepository(store: store)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Aquí empieza tu jardín'), findsOneWidget);
    await tester.tap(find.text('Agregar primera planta'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Cancelar'));
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(store.writes, isEmpty);
    expect(find.text('0 plantas registradas'), findsOneWidget);
  });

  testWidgets(
    'Eliminar explícitamente confirma la identidad entre plantas homónimas',
    (tester) async {
      final first = Tree(nombre: 'Pino', frecuenciaRiegoDias: 3);
      final second = Tree(nombre: 'Pino', frecuenciaRiegoDias: 3);
      final store = TestTreeStore()
        ..treeRecords = [
          jsonEncode(first.toJson()),
          jsonEncode(second.toJson()),
        ];
      final controller = TreesController(
        repository: LocalTreeRepository(store: store),
        autoRefresh: false,
      );
      addTearDown(controller.dispose);
      await controller.load();
      await tester.pumpWidget(
        MaterialApp(
          theme: BluefloraTheme.light,
          home: TreesView(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      final remove = find.descendant(
        of: find.byKey(ValueKey(first.id)),
        matching: find.byTooltip('Eliminar árbol'),
      );
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(controller.trees.length, 2);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar'));
      await tester.pumpAndSettle();
      expect(controller.trees.map((tree) => tree.id), [second.id]);
    },
  );
}
