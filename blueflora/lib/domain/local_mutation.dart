import 'dart:convert';

import 'plant_snapshot.dart';
import 'tree.dart';
import 'unique_id.dart';
import 'watering_event.dart';

/// Intención local; su formato no es un DTO HTTP ni un envelope sync.
class LocalMutation {
  LocalMutation({
    String? operationId,
    required this.spaceId,
    required this.action,
    required this.entityId,
    required this.expectedRevision,
    required this.expectedVersion,
    required Map<String, Object?> payload,
  }) : operationId = operationId ?? createUniqueId(),
       payloadJson = canonicalLocalJson(payload) {
    if (!RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(this.operationId) ||
        spaceId.isEmpty ||
        entityId.isEmpty ||
        expectedRevision < 0 ||
        expectedVersion < 0) {
      throw ArgumentError('Identidad o revisión local inválida.');
    }
  }

  final String operationId;
  final String spaceId;
  final String action;
  final String entityId;
  final int expectedRevision;
  final int expectedVersion;
  final String payloadJson;
  Map<String, dynamic> get payload =>
      jsonDecode(payloadJson) as Map<String, dynamic>;
  String get identityJson => canonicalLocalJson({
    'format': 1,
    'space': spaceId,
    'action': action,
    'entity': entityId,
    'revision': expectedRevision,
    'version': expectedVersion,
    'payload': payload,
  });
}

String canonicalLocalJson(Object? value) {
  Object? sorted(Object? item) {
    if (item is Map) {
      final keys = item.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: sorted(item[key])};
    }
    if (item is List) return item.map(sorted).toList();
    return item;
  }

  return jsonEncode(sorted(value));
}

/// Aplica solo la semántica de compatibilidad SharedPreferences, sin outbox.
PlantSnapshot applyLegacyMutation(
  PlantSnapshot source,
  LocalMutation mutation,
) {
  final trees = source.trees.toList();
  final events = source.events.toList();
  final index = trees.indexWhere((tree) => tree.id == mutation.entityId);
  switch (mutation.action) {
    case 'plant.create':
      if (index != -1) throw StateError('La planta ya existe.');
      trees.add(Tree.fromJson(mutation.payload));
    case 'plant.update':
      if (index == -1) throw StateError('La planta no existe.');
      trees[index] = Tree.fromJson({
        ...trees[index].toJson(),
        ...mutation.payload,
      });
    case 'plant.delete':
      if (index == -1) throw StateError('La planta no existe.');
      trees.removeAt(index);
    case 'watering_event.append':
      if (index == -1) throw StateError('La planta no existe.');
      final event = WateringEvent.fromJson(mutation.payload);
      if (events.any((old) => old.id == event.id)) {
        throw StateError('Evento duplicado.');
      }
      events.add(event);
      // Preservar E.2 en destinos SharedPreferences, incluso reloj atrasado.
      trees[index] = trees[index].copyWith(
        ultimoRiego: mutation.payload['declarationText'] == null
            ? event.occurredAt
            : DateTime.parse(mutation.payload['declarationText'] as String),
      );
    default:
      throw StateError('Intención desconocida.');
  }
  return PlantSnapshot(trees: trees, events: events);
}
