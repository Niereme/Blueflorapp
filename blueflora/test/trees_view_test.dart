import 'dart:async';
import 'dart:convert';

import 'package:blueflora/data/local_tree_repository.dart';
import 'package:blueflora/domain/tree.dart';
import 'package:blueflora/presentation/screens/views/trees_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_tree_store.dart';

void main() {
  late TestTreeStore store;

  setUp(() {
    store = TestTreeStore();
    store.treeRecords = [
      jsonEncode(Tree(nombre: 'Pino', frecuenciaRiegoDias: 3).toJson()),
    ];
  });

  Future<void> open(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: TreesView(repository: LocalTreeRepository(store: store)),
    ),
  );

  testWidgets('Bloquea acciones hasta terminar la carga inicial', (
    tester,
  ) async {
    store.readGate = Completer<void>();
    await open(tester);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester
          .widget<FloatingActionButton>(find.byType(FloatingActionButton))
          .onPressed,
      isNull,
    );
    expect(find.text('Pino'), findsNothing);
    expect(store.writes, isEmpty);
    store.readGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Pino'), findsOneWidget);
    expect(
      tester
          .widget<FloatingActionButton>(find.byType(FloatingActionButton))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('Muestra fallo de carga y permite reintentar sin sobrescribir', (
    tester,
  ) async {
    store.readError = StateError('lectura fallida');
    await open(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('No se pudieron cargar'), findsOneWidget);
    expect(
      tester
          .widget<FloatingActionButton>(find.byType(FloatingActionButton))
          .onPressed,
      isNull,
    );
    expect(store.writes, isEmpty);
    store.readError = null;
    await tapVisible(tester, find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('Pino'), findsOneWidget);
  });

  testWidgets('Agregar, regar y eliminar persiste los cambios', (tester) async {
    await open(tester);
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Roble');
    await tester.enterText(find.byType(TextField).at(3), '3');
    await tapVisible(tester, find.text('Guardar árbol'));
    await tester.pumpAndSettle();
    expect(find.text('Roble'), findsOneWidget);
    expect(store.treeRecords, hasLength(2));

    await tapVisible(tester, find.text('Registrar riego').first);
    await tester.pumpAndSettle();
    final watered = Tree.fromJson(jsonDecode(store.treeRecords!.first));
    expect(watered.ultimoRiego, isNotNull);
    expect(find.text('Último riego desconocido'), findsNothing);

    await dragCard(
      tester,
      find.byType(Dismissible).first,
      const Offset(-700, 0),
    );
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Eliminar'));
    await tester.pumpAndSettle();
    expect(find.text('Pino'), findsNothing);
    expect(find.text('Roble'), findsOneWidget);
    expect(store.treeRecords, hasLength(1));
    expect(jsonDecode(store.treeRecords!.single)['nombre'], 'Roble');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Bloquea acciones durante guardado y evita riegos duplicados', (
    tester,
  ) async {
    await open(tester);
    await tester.pumpAndSettle();
    final initialWater = tester
        .widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Registrar riego'),
        )
        .onPressed!;
    store.writeGate = Completer<void>();
    await tapVisible(tester, find.text('Registrar riego'));
    await tester.pump();
    expect(find.text('Guardando cambios…'), findsOneWidget);
    expect(
      tester
          .widget<FloatingActionButton>(find.byType(FloatingActionButton))
          .onPressed,
      isNull,
    );
    // Incluso una segunda llamada al callback queda protegida por el estado.
    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Registrar riego'),
    );
    expect(button.onPressed, isNull);
    initialWater();
    await tester.pump();
    expect(store.writes, hasLength(1));
    expect(find.text('Último riego desconocido'), findsOneWidget);
    store.writeGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Guardando cambios…'), findsNothing);
    expect(find.text('Último riego desconocido'), findsNothing);
  });

  testWidgets('Un riego fallido conserva el estado y puede reintentarse', (
    tester,
  ) async {
    await open(tester);
    await tester.pumpAndSettle();
    store.writeResult = false;
    await tapVisible(tester, find.text('Registrar riego'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No se pudieron guardar'), findsOneWidget);
    expect(find.text('Último riego desconocido'), findsOneWidget);
    expect(jsonDecode(store.treeRecords!.single)['ultimoRiego'], isNull);
    store.writeResult = true;
    await tapVisible(tester, find.text('Registrar riego'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No se pudieron guardar'), findsNothing);
    expect(jsonDecode(store.treeRecords!.single)['ultimoRiego'], isNotNull);
  });

  testWidgets('Eliminar con fallo de guardado conserva la planta', (
    tester,
  ) async {
    await open(tester);
    await tester.pumpAndSettle();
    store.writeError = StateError('sin espacio');
    await dragCard(tester, find.byType(Dismissible), const Offset(-700, 0));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Eliminar'));
    await tester.pumpAndSettle();
    expect(find.text('Pino'), findsOneWidget);
    expect(store.treeRecords, hasLength(1));
    expect(find.textContaining('No se pudieron guardar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Conserva el alta fallida para reintentar sin repetir el formulario',
    (tester) async {
      await open(tester);
      await tester.pumpAndSettle();
      store.writeResult = false;
      await tapVisible(tester, find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'Roble');
      await tester.enterText(find.byType(TextField).at(3), '3');
      await tapVisible(tester, find.text('Guardar árbol'));
      await tester.pumpAndSettle();
      expect(find.text('Roble'), findsNothing);
      expect(store.treeRecords, hasLength(1));
      expect(find.text('Reintentar guardado'), findsOneWidget);
      store.writeResult = true;
      await tapVisible(tester, find.text('Reintentar guardado'));
      await tester.pumpAndSettle();
      expect(find.text('Roble'), findsOneWidget);
      expect(store.treeRecords, hasLength(2));
      expect(find.text('Reintentar guardado'), findsNothing);
    },
  );

  testWidgets('Eliminar la última planta conserva una lista vacía al reabrir', (
    tester,
  ) async {
    await open(tester);
    await tester.pumpAndSettle();
    await dragCard(tester, find.byType(Dismissible), const Offset(-700, 0));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Eliminar'));
    await tester.pumpAndSettle();
    expect(store.treeRecords, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await open(tester);
    await tester.pumpAndSettle();
    expect(find.byType(Dismissible), findsNothing);
    expect(find.text('Árbol de prueba'), findsNothing);
  });

  testWidgets('Terminar la carga tras desmontar no provoca setState', (
    tester,
  ) async {
    store.readGate = Completer<void>();
    await open(tester);
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    store.readGate!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Edita y recarga plantas homónimas, riega y elimina por identidad',
    (tester) async {
      final first = Tree(
        nombre: 'Pino',
        especie: 'Primero',
        altura: 2,
        frecuenciaRiegoDias: 3,
        ultimoRiego: DateTime.utc(2026, 11, 3),
      );
      final second = Tree(
        nombre: 'Pino',
        especie: 'Segundo',
        frecuenciaRiegoDias: 5,
      );
      store.treeRecords = [
        jsonEncode(first.toJson()),
        jsonEncode(second.toJson()),
      ];
      await open(tester);
      await tester.pumpAndSettle();
      final firstCard = find.byKey(ValueKey(first.id));
      await tapVisible(
        tester,
        find.descendant(of: firstCard, matching: find.byIcon(Icons.edit)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'Pino editado');
      await tester.enterText(find.byType(TextFormField).at(1), '');
      await tester.enterText(find.byType(TextFormField).at(2), '');
      await tester.enterText(find.byType(TextFormField).at(3), '7');
      await tester.ensureVisible(find.text('Guardar cambios'));
      await tapVisible(tester, find.text('Guardar cambios'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await open(tester);
      await tester.pumpAndSettle();
      final saved = Tree.fromJson(jsonDecode(store.treeRecords!.first));
      expect(saved.id, first.id);
      expect(saved.nombre, 'Pino editado');
      expect(saved.especie, isNull);
      expect(saved.altura, isNull);
      expect(saved.frecuenciaRiegoDias, 7);
      expect(saved.ultimoRiego, first.ultimoRiego);
      expect(
        Tree.fromJson(jsonDecode(store.treeRecords![1])).toJson(),
        second.toJson(),
      );
      expect(find.text('Pino editado'), findsOneWidget);

      await tapVisible(
        tester,
        find.descendant(
          of: find.byKey(ValueKey(first.id)),
          matching: find.text('Registrar riego'),
        ),
      );
      await tester.pumpAndSettle();
      expect(Tree.fromJson(jsonDecode(store.treeRecords!.first)).id, first.id);
      expect(
        Tree.fromJson(jsonDecode(store.treeRecords!.first)).ultimoRiego,
        isNot(first.ultimoRiego),
      );
      expect(
        Tree.fromJson(jsonDecode(store.treeRecords![1])).toJson(),
        second.toJson(),
      );

      await dragCard(
        tester,
        find.byKey(ValueKey(first.id)),
        const Offset(-700, 0),
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Eliminar'));
      await tester.pumpAndSettle();
      expect(store.treeRecords, hasLength(1));
      expect(
        Tree.fromJson(jsonDecode(store.treeRecords!.single)).toJson(),
        second.toJson(),
      );
    },
  );

  testWidgets(
    'Editar una planta sin renombrar no modifica otra con el mismo nombre',
    (tester) async {
      final first = Tree(nombre: 'Pino', frecuenciaRiegoDias: 3);
      final second = Tree(nombre: 'Pino', frecuenciaRiegoDias: 5);
      store.treeRecords = [
        jsonEncode(first.toJson()),
        jsonEncode(second.toJson()),
      ];
      await open(tester);
      await tester.pumpAndSettle();
      await tapVisible(
        tester,
        find.descendant(
          of: find.byKey(ValueKey(first.id)),
          matching: find.byIcon(Icons.edit),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(3), '7');
      await tester.ensureVisible(find.text('Guardar cambios'));
      await tapVisible(tester, find.text('Guardar cambios'));
      await tester.pumpAndSettle();
      expect(
        Tree.fromJson(jsonDecode(store.treeRecords!.first)).frecuenciaRiegoDias,
        7,
      );
      expect(
        Tree.fromJson(jsonDecode(store.treeRecords![1])).toJson(),
        second.toJson(),
      );
      await tapVisible(
        tester,
        find.descendant(
          of: find.byKey(ValueKey(first.id)),
          matching: find.text('Registrar riego'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        Tree.fromJson(jsonDecode(store.treeRecords![1])).ultimoRiego,
        isNull,
      );
      await dragCard(
        tester,
        find.byKey(ValueKey(first.id)),
        const Offset(-700, 0),
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Eliminar'));
      await tester.pumpAndSettle();
      expect(
        Tree.fromJson(jsonDecode(store.treeRecords!.single)).id,
        second.id,
      );
    },
  );

  testWidgets('Un fallo de edición conserva los datos y permite reintentar', (
    tester,
  ) async {
    final original = List<String>.of(store.treeRecords!);
    await open(tester);
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byIcon(Icons.edit));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Editado');
    store.writeResult = false;
    await tester.ensureVisible(find.text('Guardar cambios'));
    await tapVisible(tester, find.text('Guardar cambios'));
    await tester.pumpAndSettle();
    expect(store.treeRecords, original);
    expect(find.text('Pino'), findsOneWidget);
    expect(find.text('Editado'), findsNothing);
    store.writeResult = true;
    await tapVisible(tester, find.text('Reintentar guardado'));
    await tester.pumpAndSettle();
    expect(find.text('Editado'), findsOneWidget);
    expect(
      jsonDecode(store.treeRecords!.single)['id'],
      jsonDecode(original.single)['id'],
    );
  });

  testWidgets('La planta inicial también conserva su ID al reabrir', (
    tester,
  ) async {
    store.treeRecords = null;
    await open(tester);
    await tester.pumpAndSettle();
    final id = jsonDecode(store.treeRecords!.single)['id'] as String;
    await tester.pumpWidget(const SizedBox());
    await open(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey(id)), findsOneWidget);
    expect(jsonDecode(store.treeRecords!.single)['id'], id);
  });
}

// Las tarjetas y el formulario son desplazables, también con texto grande.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}

Future<void> dragCard(WidgetTester tester, Finder finder, Offset offset) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.1);
  await tester.pumpAndSettle();
  await tester.drag(finder, offset);
}
