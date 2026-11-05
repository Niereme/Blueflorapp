import 'package:blueflora/domain/tree.dart';
import 'package:blueflora/presentation/screens/views/addtree_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Tree? result;

  Future<void> open(WidgetTester tester, {Tree? tree}) async {
    result = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                result = await Navigator.push<Tree>(
                  context,
                  MaterialPageRoute(builder: (_) => AddTreeView(tree: tree)),
                );
              },
              child: const Text('Abrir formulario'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir formulario'));
    await tester.pumpAndSettle();
  }

  Future<void> fill(
    WidgetTester tester, {
    String nombre = 'Pino',
    String altura = '',
    String frecuencia = '3',
  }) async {
    await tester.enterText(find.byType(TextFormField).at(0), nombre);
    await tester.enterText(find.byType(TextFormField).at(2), altura);
    await tester.enterText(find.byType(TextFormField).at(3), frecuencia);
  }

  Future<void> submit(WidgetTester tester, {bool editing = false}) async {
    final button = find.text(editing ? 'Guardar cambios' : 'Guardar árbol');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('Registra nombre y especie normalizados y altura con coma', (
    tester,
  ) async {
    await open(tester);
    await fill(tester, nombre: '  Roble  ', altura: ' 1,5 ', frecuencia: ' 7 ');
    await tester.enterText(find.byType(TextFormField).at(1), '  Quercus  ');
    await submit(tester);
    expect(result!.nombre, 'Roble');
    expect(result!.especie, 'Quercus');
    expect(result!.altura, 1.5);
    expect(result!.frecuenciaRiegoDias, 7);
    expect(result!.id, isNotEmpty);
    expect(result!.ultimoRiego, isNotNull);
  });

  testWidgets('Permite omitir especie y altura', (tester) async {
    await open(tester);
    await fill(tester);
    await submit(tester);
    expect(result!.especie, isNull);
    expect(result!.altura, isNull);
  });

  testWidgets('Nombre compuesto solo por espacios muestra error', (
    tester,
  ) async {
    await open(tester);
    await fill(tester, nombre: '   ');
    await submit(tester);
    expect(find.text('Escribe el nombre de tu planta.'), findsOneWidget);
    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });

  for (final height in ['abc', '0', '-1', 'NaN', 'Infinity', '1.2.3']) {
    testWidgets('Altura inválida no provoca excepciones: $height', (
      tester,
    ) async {
      await open(tester);
      await fill(tester, altura: height);
      await submit(tester);
      expect(
        find.text('Escribe una altura positiva, por ejemplo 1,5.'),
        findsOneWidget,
      );
      expect(result, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  for (final frequency in [
    '',
    '0',
    '-2',
    '1 semana',
    '2.5 días',
    '2.5',
    '2,5',
    '1e2',
    '36501',
    '99999999999999999999999',
  ]) {
    testWidgets('Frecuencia inválida muestra mensaje: $frequency', (
      tester,
    ) async {
      await open(tester);
      await fill(tester, frecuencia: frequency);
      await submit(tester);
      expect(
        find.text('Escribe días enteros entre 1 y ${Tree.maxFrecuenciaDias}.'),
        findsOneWidget,
      );
      expect(result, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Editar precarga los datos y conserva ID y último riego', (
    tester,
  ) async {
    final original = Tree(
      nombre: 'Pino',
      especie: 'Pinus',
      altura: 2,
      frecuenciaRiegoDias: 3,
      ultimoRiego: DateTime.utc(2026, 11, 3),
    );
    await open(tester, tree: original);
    final fields = tester
        .widgetList<TextFormField>(find.byType(TextFormField))
        .toList();
    expect(fields[0].controller!.text, 'Pino');
    expect(fields[1].controller!.text, 'Pinus');
    expect(fields[2].controller!.text, '2.0');
    expect(fields[3].controller!.text, '3');
    await fill(tester, nombre: 'Roble', altura: '4.5', frecuencia: '7');
    await tester.enterText(find.byType(TextFormField).at(1), 'Quercus');
    await submit(tester, editing: true);
    expect(result!.nombre, 'Roble');
    expect(result!.especie, 'Quercus');
    expect(result!.altura, 4.5);
    expect(result!.frecuenciaRiegoDias, 7);
    expect(result!.id, original.id);
    expect(result!.ultimoRiego, original.ultimoRiego);
    expect(original.nombre, 'Pino');
  });

  testWidgets('Editar permite vaciar opcionales sin alterar la fecha nula', (
    tester,
  ) async {
    final original = Tree(
      nombre: 'Pino',
      especie: 'Pinus',
      altura: 2,
      frecuenciaRiegoDias: 3,
    );
    await open(tester, tree: original);
    await fill(tester);
    await tester.enterText(find.byType(TextFormField).at(1), '   ');
    await submit(tester, editing: true);
    expect(result!.especie, isNull);
    expect(result!.altura, isNull);
    expect(result!.ultimoRiego, isNull);
    expect(result!.id, original.id);
  });

  testWidgets('Cancelar una edición no devuelve cambios', (tester) async {
    final original = Tree(nombre: 'Pino', frecuenciaRiegoDias: 3);
    await open(tester, tree: original);
    await fill(tester, nombre: 'Cambio sin guardar');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(original.nombre, 'Pino');
  });
}
