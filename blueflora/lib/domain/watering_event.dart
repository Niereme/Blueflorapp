import 'unique_id.dart';

/// Registro declarado por el usuario. No representa una orden ni una
/// confirmación de hardware; esos tipos se incorporarán al integrar dispositivos.
enum WateringEventType { manualRegistration }

class WateringEvent {
  WateringEvent({
    String? id,
    required this.plantId,
    required String plantName,
    required DateTime occurredAt,
    this.type = WateringEventType.manualRegistration,
  }) : id = id ?? createUniqueId(),
       plantName = plantName.trim(),
       occurredAt = occurredAt.toUtc() {
    if (this.id.trim().isEmpty ||
        plantId.trim().isEmpty ||
        this.plantName.isEmpty) {
      throw ArgumentError('El evento requiere identidad de planta y nombre.');
    }
  }

  final String id;
  final String plantId;

  /// Nombre en el momento del registro, conservado incluso tras eliminar planta.
  final String plantName;
  final DateTime occurredAt;
  final WateringEventType type;

  Map<String, dynamic> toJson() => {
    'id': id,
    'plantId': plantId,
    'plantName': plantName,
    'occurredAt': occurredAt.toIso8601String(),
    'type': 'manual_registration',
  };

  factory WateringEvent.fromJson(Map<String, dynamic> json) {
    if (json['type'] != 'manual_registration' || json['id'] is! String) {
      throw const FormatException('Tipo o identificador de evento no válido.');
    }
    return WateringEvent(
      id: json['id'] as String,
      plantId: json['plantId'] as String,
      plantName: json['plantName'] as String,
      occurredAt: DateTime.parse(json['occurredAt'] as String),
    );
  }
}
