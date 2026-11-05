import 'dart:convert';

import 'package:blueflora/domain/tree.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Tree JSON', () {
    test('Serializa todos los campos y la fecha ISO 8601', () {
      final fecha = DateTime.utc(2026, 11, 3, 10, 30);
      final tree = Tree(
        nombre: 'Álamo',
        especie: 'Populus alba',
        altura: 2.5,
        frecuenciaRiegoDias: 3,
        ultimoRiego: fecha,
      );

      expect(tree.toJson(), {
        'id': tree.id,
        'nombre': 'Álamo',
        'especie': 'Populus alba',
        'altura': 2.5,
        'frecuenciaRiegoDias': 3,
        'ultimoRiego': '2026-11-03T10:30:00.000Z',
      });
    });

    test('Deserializa altura entera y fecha UTC', () {
      final tree = Tree.fromJson({
        'nombre': 'Pino',
        'especie': 'Pinus pinea',
        'altura': 4,
        'frecuenciaRiego': '5 días',
        'ultimoRiego': '2026-11-03T10:30:00.000Z',
      });

      expect(tree.nombre, 'Pino');
      expect(tree.especie, 'Pinus pinea');
      expect(tree.altura, 4.0);
      expect(tree.altura, isA<double>());
      expect(tree.frecuenciaRiegoDias, 5);
      expect(tree.ultimoRiego, DateTime.utc(2026, 11, 3, 10, 30));
    });

    test('Conserva los datos en una ida y vuelta por texto JSON', () {
      final original = Tree(
        nombre: 'Árbol del jardín',
        especie: 'Quercus robur',
        altura: 1.75,
        frecuenciaRiegoDias: 7,
        ultimoRiego: DateTime.utc(2026, 1, 31, 18),
      );
      final restored = Tree.fromJson(jsonDecode(jsonEncode(original.toJson())));

      expect(restored.toJson(), original.toJson());
    });

    test('Serializa y recupera campos opcionales nulos', () {
      final original = Tree(nombre: 'Suculenta', frecuenciaRiegoDias: 7);
      final json = original.toJson();
      final restored = Tree.fromJson(jsonDecode(jsonEncode(json)));

      expect(json['especie'], isNull);
      expect(json['altura'], isNull);
      expect(json['ultimoRiego'], isNull);
      expect(restored.nombre, 'Suculenta');
      expect(restored.frecuenciaRiegoDias, 7);
      expect(restored.especie, isNull);
      expect(restored.altura, isNull);
      expect(restored.ultimoRiego, isNull);
    });

    test('Acepta registros sin campos opcionales', () {
      final tree = Tree.fromJson({
        'nombre': 'Helecho',
        'frecuenciaRiego': '2 días',
      });

      expect(tree.especie, isNull);
      expect(tree.altura, isNull);
      expect(tree.ultimoRiego, isNull);
    });
  });

  group('Identidad, edición y validación del modelo', () {
    test('Genera IDs UUID v4 distintos para plantas con el mismo nombre', () {
      final first = Tree(nombre: 'Pino', frecuenciaRiegoDias: 3);
      final second = Tree(nombre: 'Pino', frecuenciaRiegoDias: 3);
      expect(
        first.id,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      expect(second.id, isNot(first.id));
      expect(Tree.fromJson(first.toJson()).id, first.id);
    });

    test('copyWith conserva identidad y último riego al editar', () {
      final original = Tree(
        nombre: 'Pino',
        especie: 'Pinus',
        altura: 2,
        frecuenciaRiegoDias: 3,
        ultimoRiego: DateTime.utc(2026, 11, 3),
      );
      final edited = original.copyWith(
        nombre: 'Roble',
        especie: 'Quercus',
        altura: 4.5,
        frecuenciaRiegoDias: 7,
      );
      expect(edited.id, original.id);
      expect(edited.ultimoRiego, original.ultimoRiego);
      expect(edited.nombre, 'Roble');
      expect(edited.especie, 'Quercus');
      expect(edited.altura, 4.5);
      expect(edited.frecuenciaRiegoDias, 7);
      expect(original.nombre, 'Pino');
      expect(original.frecuenciaRiegoDias, 3);
    });

    test('copyWith distingue entre omitir y limpiar campos opcionales', () {
      final original = Tree(
        nombre: 'Pino',
        especie: 'Pinus',
        altura: 2,
        frecuenciaRiegoDias: 3,
        ultimoRiego: DateTime.utc(2026),
      );
      expect(original.copyWith().toJson(), original.toJson());
      final cleared = original.copyWith(
        especie: null,
        altura: null,
        ultimoRiego: null,
      );
      expect(cleared.id, original.id);
      expect(cleared.especie, isNull);
      expect(cleared.altura, isNull);
      expect(cleared.ultimoRiego, isNull);
    });

    test('Normaliza espacios de nombre y especie', () {
      final tree = Tree(
        nombre: '  Pino  ',
        especie: '   ',
        frecuenciaRiegoDias: 3,
      );
      expect(tree.nombre, 'Pino');
      expect(tree.especie, isNull);
    });

    for (final height in [0.0, -1.0, double.nan, double.infinity]) {
      test('Rechaza altura inválida: $height', () {
        expect(
          () => Tree(nombre: 'Pino', altura: height, frecuenciaRiegoDias: 3),
          throwsArgumentError,
        );
      });
    }

    test('Rechaza nombre e identificador vacíos', () {
      expect(
        () => Tree(nombre: '   ', frecuenciaRiegoDias: 3),
        throwsArgumentError,
      );
      expect(
        () => Tree(id: ' ', nombre: 'Pino', frecuenciaRiegoDias: 3),
        throwsArgumentError,
      );
    });

    for (final days in [0, -1, Tree.maxFrecuenciaDias + 1]) {
      test('Rechaza frecuencia fuera de rango: $days', () {
        expect(
          () => Tree(nombre: 'Pino', frecuenciaRiegoDias: days),
          throwsArgumentError,
        );
      });
    }

    for (final text in ['1 semana', '2.5 días', '2,5', '-3', '0', '', '1e2']) {
      test('No interpreta texto ambiguo como días: $text', () {
        expect(Tree.parseFrecuenciaDias(text), isNull);
        expect(
          () => Tree.fromJson({'nombre': 'Pino', 'frecuenciaRiego': text}),
          throwsFormatException,
        );
      });
    }

    test(
      'El formato nuevo exige frecuencia JSON entera y no acepta ID nulo',
      () {
        for (final value in ['3', 2.5, null]) {
          expect(
            () =>
                Tree.fromJson({'nombre': 'Pino', 'frecuenciaRiegoDias': value}),
            throwsFormatException,
          );
        }
        expect(
          () => Tree.fromJson({
            'id': null,
            'nombre': 'Pino',
            'frecuenciaRiegoDias': 3,
          }),
          throwsFormatException,
        );
      },
    );

    test('Acepta días enteros con espacios y el límite superior', () {
      expect(Tree.parseFrecuenciaDias(' 7 '), 7);
      expect(
        Tree.parseFrecuenciaDias('${Tree.maxFrecuenciaDias}'),
        Tree.maxFrecuenciaDias,
      );
    });
  });

  group('Tree días restantes', () {
    test('Sin último riego devuelve cero', () {
      expect(Tree(nombre: 'Pino', frecuenciaRiegoDias: 3).diasRestantes(), 0);
    });

    final ahora = DateTime.utc(2026, 11, 4, 12);

    Tree conProximoRiegoEn(Duration intervalo) => Tree(
      nombre: 'Pino',
      frecuenciaRiegoDias: 3,
      ultimoRiego: ahora.add(intervalo).subtract(const Duration(days: 3)),
    );

    final casos = <String, (Duration, int)>{
      'dos días y medio pendientes': (const Duration(hours: 60), 3),
      'doce horas pendientes': (const Duration(hours: 12), 1),
      'treinta minutos pendientes': (const Duration(minutes: 30), 1),
      'un segundo pendiente': (const Duration(seconds: 1), 1),
      'un microsegundo pendiente': (const Duration(microseconds: 1), 1),
      'vence exactamente ahora': (Duration.zero, 0),
      'venció hace un microsegundo': (const Duration(microseconds: -1), 0),
      'venció hace treinta minutos': (const Duration(minutes: -30), 0),
      'venció hace doce horas': (const Duration(hours: -12), 0),
      'faltan exactamente veinticuatro horas': (const Duration(days: 1), 1),
      'faltan veinticuatro horas menos un microsegundo': (
        const Duration(days: 1) - const Duration(microseconds: 1),
        1,
      ),
      'faltan veinticuatro horas más un microsegundo': (
        const Duration(days: 1, microseconds: 1),
        2,
      ),
      'venció hace veinticuatro horas menos un microsegundo': (
        const Duration(days: -1, microseconds: 1),
        0,
      ),
      'venció hace exactamente veinticuatro horas': (
        const Duration(days: -1),
        -1,
      ),
      'venció hace veinticuatro horas más un microsegundo': (
        const Duration(days: -1, microseconds: -1),
        -1,
      ),
      'venció hace dos días y medio': (const Duration(hours: -60), -2),
    };

    for (final caso in casos.entries) {
      test(caso.key, () {
        final (intervalo, esperado) = caso.value;
        expect(
          conProximoRiegoEn(intervalo).diasRestantes(ahora: ahora),
          esperado,
        );
      });
    }

    test('Interpreta una frecuencia numérica en días', () {
      final tree = Tree(
        nombre: 'Pino',
        frecuenciaRiegoDias: 5,
        ultimoRiego: ahora.subtract(const Duration(hours: 12)),
      );
      expect(tree.diasRestantes(ahora: ahora), 5);
    });

    test('Cruzar medianoche no añade un día al intervalo pendiente', () {
      final tree = Tree(
        nombre: 'Pino',
        frecuenciaRiegoDias: 1,
        ultimoRiego: DateTime.utc(2026, 11, 3, 0, 15),
      );
      expect(tree.diasRestantes(ahora: DateTime.utc(2026, 11, 3, 23, 45)), 1);
      expect(tree.diasRestantes(ahora: DateTime.utc(2026, 11, 4, 0, 15)), 0);
    });

    test('Calcula el vencimiento al cambiar de año y en un año bisiesto', () {
      for (final fechas in [
        (DateTime.utc(2026, 12, 31, 23, 30), DateTime.utc(2027, 1, 1, 23, 30)),
        (DateTime.utc(2024, 2, 28, 12), DateTime.utc(2024, 2, 29, 12)),
      ]) {
        final tree = Tree(
          nombre: 'Pino',
          frecuenciaRiegoDias: 1,
          ultimoRiego: fechas.$1,
        );
        expect(tree.diasRestantes(ahora: fechas.$2), 0);
      }
    });

    test('El mismo instante con distinto offset da el mismo resultado', () {
      final tree = Tree(
        nombre: 'Pino',
        frecuenciaRiegoDias: 1,
        ultimoRiego: DateTime.parse('2026-11-03T12:00:00-06:00'),
      );
      expect(
        tree.diasRestantes(ahora: DateTime.parse('2026-11-04T11:30:00-06:00')),
        1,
      );
      expect(tree.diasRestantes(ahora: DateTime.utc(2026, 11, 4, 17, 30)), 1);
    });

    test(
      'Conserva intervalos de 24 horas ante un cambio de offset horario',
      () {
        final tree = Tree(
          nombre: 'Pino',
          frecuenciaRiegoDias: 1,
          ultimoRiego: DateTime.parse('2026-03-07T12:00:00-05:00'),
        );
        expect(
          tree.diasRestantes(
            ahora: DateTime.parse('2026-03-08T12:00:00-04:00'),
          ),
          1,
        );
        expect(
          tree.diasRestantes(
            ahora: DateTime.parse('2026-03-08T13:00:00-04:00'),
          ),
          0,
        );
      },
    );
  });
}
