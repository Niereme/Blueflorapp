import 'dart:convert';

import '../../domain/plant_snapshot.dart';
import '../../domain/tree.dart';
import '../../domain/unique_id.dart';

/// Interpretación conservadora del origen. El envelope íntegro se conserva aparte.
class MigrationSource {
  MigrationSource(this.records);
  final List<String>? records;
  final List<String> diagnostics = [];

  String get envelope => jsonEncode({
    'version': 1,
    'keyPresent': records != null,
    'records': records,
  });

  static bool hasZone(String text) =>
      RegExp(r'(Z|[+-]\d{2}:?\d{2})$', caseSensitive: false).hasMatch(text);

  // DateTime.parse acepta desbordamientos (p.ej. 31 de febrero). No permitirlos.
  static void validateDate(String text, {required bool requireZone}) {
    final parts = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,6})?(?:Z|[+-]\d{2}:?\d{2})?$',
    ).firstMatch(text);
    if (parts == null || (requireZone && !hasZone(text))) {
      throw const FormatException(
        'Fecha incompatible o evento sin zona horaria.',
      );
    }
    final year = int.parse(parts[1]!);
    final month = int.parse(parts[2]!);
    final day = int.parse(parts[3]!);
    final calendar = DateTime.utc(year, month, day);
    if (calendar.year != year ||
        calendar.month != month ||
        calendar.day != day ||
        int.parse(parts[4]!) > 23 ||
        int.parse(parts[5]!) > 59 ||
        int.parse(parts[6]!) > 59) {
      throw const FormatException('Fecha fuera del calendario.');
    }
    DateTime.parse(text);
    if (!hasZone(text)) {
      final parsed = DateTime.parse(text);
      if (parsed.year != year ||
          parsed.month != month ||
          parsed.day != day ||
          parsed.hour != int.parse(parts[4]!) ||
          parsed.minute != int.parse(parts[5]!)) {
        throw const FormatException('Hora local inexistente en esta zona.');
      }
    }
  }

  /// IDs faltantes se asignan en un mapa persistido ANTES de poblar tablas.
  PlantSnapshot? decode(Map<String, String> assignedIds) {
    if (records == null) return null;
    final decoded = records!.map(jsonDecode).toList();
    final modern =
        decoded.length == 1 &&
        decoded.single is Map &&
        (decoded.single as Map).containsKey('schemaVersion');
    final root = modern
        ? Map<String, dynamic>.from(decoded.single as Map)
        : null;
    if (root != null) {
      _keys(root, {'schemaVersion', 'trees', 'events'});
      if (root['schemaVersion'] != 1 ||
          root['trees'] is! List ||
          root['events'] is! List) {
        throw const FormatException('Versión o listas incompatibles.');
      }
    }
    final plants = modern ? root!['trees'] as List : decoded;
    final events = modern ? root!['events'] as List : const [];
    final treeJson = <Map<String, dynamic>>[];
    for (var i = 0; i < plants.length; i++) {
      final tree = Map<String, dynamic>.from(plants[i] as Map);
      _keys(tree, {
        'id',
        'nombre',
        'especie',
        'altura',
        'frecuenciaRiegoDias',
        'frecuenciaRiego',
        'ultimoRiego',
      });
      if (!tree.containsKey('id')) {
        if (modern) {
          throw const FormatException('Falta identidad en la instantánea.');
        }
        tree['id'] = assignedIds.putIfAbsent('$i', createUniqueId);
      }
      _identity(tree['id']);
      _text(tree['nombre'], optional: false);
      _text(tree['especie'], optional: true);
      if (tree['ultimoRiego'] != null) {
        final text = tree['ultimoRiego'] as String;
        validateDate(text, requireZone: false);
        if (!hasZone(text)) {
          diagnostics.add(
            'Fecha local sin zona conservada: planta ${tree['id']}.',
          );
        }
      }
      final parsed = Tree.fromJson(tree);
      treeJson.add(parsed.toJson());
    }
    final eventJson = <Map<String, dynamic>>[];
    for (final raw in events) {
      final event = Map<String, dynamic>.from(raw as Map);
      _keys(event, {'id', 'plantId', 'plantName', 'occurredAt', 'type'});
      _identity(event['id']);
      _identity(event['plantId']);
      _text(event['plantName'], optional: false);
      validateDate(event['occurredAt'] as String, requireZone: true);
      eventJson.add(event);
    }
    return PlantSnapshot.fromJson({
      'schemaVersion': 1,
      'trees': treeJson,
      'events': eventJson,
    });
  }

  void _identity(dynamic value) {
    if (value is! String || value.trim().isEmpty) {
      throw const FormatException('Identificador incompatible.');
    }
    // El modelo anterior admite IDs no UUID: conservarlos sin renombrarlos.
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(value)) {
      diagnostics.add('ID legado conservado sin transformar: $value.');
    }
  }

  static void _text(dynamic value, {required bool optional}) {
    if (value == null && optional) return;
    if (value is! String || value.isEmpty || value != value.trim()) {
      throw const FormatException(
        'Texto incompatible; requiere revisión sin recortarlo.',
      );
    }
  }

  static void _keys(Map<String, dynamic> value, Set<String> allowed) {
    if (value.keys.any((key) => !allowed.contains(key))) {
      throw const FormatException(
        'Campos desconocidos; se conserva el original para revisión.',
      );
    }
  }
}
