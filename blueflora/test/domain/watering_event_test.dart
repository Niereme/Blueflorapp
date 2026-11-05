import 'dart:convert';

import 'package:blueflora/domain/plant_snapshot.dart';
import 'package:blueflora/domain/tree.dart';
import 'package:blueflora/domain/watering_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  WateringEvent event() => WateringEvent(
    plantId: 'plant-1',
    plantName: '  Pino  ',
    occurredAt: DateTime.parse('2026-11-04T12:34:56-06:00'),
  );

  test('Evento manual tiene ID propio y conserva la fecha y hora como UTC', () {
    final first = event();
    final second = event();
    expect(first.id, isNot(second.id));
    expect(first.plantId, 'plant-1');
    expect(first.plantName, 'Pino');
    expect(first.type, WateringEventType.manualRegistration);
    expect(first.occurredAt, DateTime.utc(2026, 11, 4, 18, 34, 56));
    expect(first.toJson()['type'], 'manual_registration');
  });

  test(
    'Evento conserva identidad y campos al convertir a texto JSON y volver',
    () {
      final original = event();
      final restored = WateringEvent.fromJson(
        jsonDecode(jsonEncode(original.toJson())),
      );
      expect(restored.toJson(), original.toJson());
    },
  );

  for (final field in ['id', 'plantId', 'plantName', 'occurredAt', 'type']) {
    test('Rechaza evento sin campo obligatorio: $field', () {
      final json = event().toJson()..remove(field);
      expect(
        () => WateringEvent.fromJson(json),
        throwsA(anyOf(isA<TypeError>(), isA<FormatException>())),
      );
    });
  }

  test(
    'No interpreta órdenes de bomba ni tipos desconocidos como registros manuales',
    () {
      for (final type in ['pump_command', 'hardware_confirmed', 'otro', null]) {
        final json = event().toJson()..['type'] = type;
        expect(() => WateringEvent.fromJson(json), throwsFormatException);
      }
    },
  );

  test('Rechaza IDs y nombres vacíos y fecha inválida', () {
    for (final field in ['id', 'plantId', 'plantName']) {
      final json = event().toJson()..[field] = ' ';
      expect(() => WateringEvent.fromJson(json), throwsArgumentError);
    }
    final json = event().toJson()..['occurredAt'] = 'sin fecha';
    expect(() => WateringEvent.fromJson(json), throwsFormatException);
  });

  test('Instantánea conserva plantas y eventos y expone listas inmutables', () {
    final tree = Tree(nombre: 'Pino', frecuenciaRiegoDias: 3);
    final snapshot = PlantSnapshot(trees: [tree], events: [event()]);
    expect(
      PlantSnapshot.fromJson(
        jsonDecode(jsonEncode(snapshot.toJson())),
      ).toJson(),
      snapshot.toJson(),
    );
    expect(() => snapshot.trees.clear(), throwsUnsupportedError);
    expect(() => snapshot.events.clear(), throwsUnsupportedError);
  });

  test('Instantánea rechaza eventos duplicados y versiones desconocidas', () {
    final first = event();
    expect(
      () => PlantSnapshot(trees: [], events: [first, first]),
      throwsFormatException,
    );
    expect(
      () => PlantSnapshot.fromJson({
        'schemaVersion': 2,
        'trees': [],
        'events': [],
      }),
      throwsFormatException,
    );
    expect(
      () => PlantSnapshot.fromJson({'schemaVersion': 1, 'trees': []}),
      throwsFormatException,
    );
  });
  test(
    'El formato de instantánea no asigna IDs nuevos a plantas corruptas',
    () {
      expect(
        () => PlantSnapshot.fromJson({
          'schemaVersion': 1,
          'trees': [
            {'nombre': 'Pino', 'frecuenciaRiegoDias': 3},
          ],
          'events': [],
        }),
        throwsFormatException,
      );
    },
  );
}
