import 'tree.dart';
import 'watering_event.dart';

/// Unidad de persistencia: plantas y eventos siempre se guardan juntos.
class PlantSnapshot {
  PlantSnapshot({
    required Iterable<Tree> trees,
    Iterable<WateringEvent> events = const [],
  }) : trees = List.unmodifiable(trees),
       events = List.unmodifiable(events) {
    if (this.trees.map((tree) => tree.id).toSet().length != this.trees.length ||
        this.events.map((event) => event.id).toSet().length !=
            this.events.length) {
      throw const FormatException(
        'Hay identificadores duplicados en los datos.',
      );
    }
  }

  final List<Tree> trees;
  final List<WateringEvent> events;

  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'trees': trees.map((tree) => tree.toJson()).toList(),
    'events': events.map((event) => event.toJson()).toList(),
  };

  factory PlantSnapshot.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != 1 ||
        json['trees'] is! List ||
        json['events'] is! List) {
      throw const FormatException(
        'La instantánea local no es válida o no es compatible.',
      );
    }
    return PlantSnapshot(
      trees: (json['trees'] as List).map((tree) {
        if (tree is! Map<String, dynamic> ||
            !tree.containsKey('id') ||
            !tree.containsKey('frecuenciaRiegoDias')) {
          throw const FormatException(
            'La instantánea requiere IDs y frecuencias estables.',
          );
        }
        return Tree.fromJson(tree);
      }),
      events: (json['events'] as List).map(
        (event) => WateringEvent.fromJson(event as Map<String, dynamic>),
      ),
    );
  }
}
