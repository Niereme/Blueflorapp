import 'dart:convert';
import 'settings_repository.dart';

class ReminderRecord {
  const ReminderRecord({required this.id, this.cycle, this.at, this.signature});
  final int id;
  final String? cycle;
  final DateTime? at;
  final String? signature;
  Map<String, dynamic> toJson() => {
    'id': id,
    'cycle': cycle,
    'at': at?.toUtc().toIso8601String(),
    'signature': signature,
  };
  factory ReminderRecord.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! int || id < 1 || id > 2147483647) {
      throw const FormatException('ID de aviso no válido.');
    }
    return ReminderRecord(
      id: id,
      cycle: json['cycle'] as String?,
      at: json['at'] == null ? null : DateTime.parse(json['at'] as String),
      signature: json['signature'] as String?,
    );
  }
}

class ReminderRegistry {
  ReminderRegistry({JsonPreferencesStore? store})
    : _store = store ?? SharedJsonPreferencesStore('blueflora.reminders.v1');
  final JsonPreferencesStore _store;
  Future<Map<String, ReminderRecord>> load() async {
    final raw = await _store.read();
    if (raw == null) return {};
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final result = json.map(
      (key, value) =>
          MapEntry(key, ReminderRecord.fromJson(value as Map<String, dynamic>)),
    );
    if (result.values.map((value) => value.id).toSet().length !=
        result.length) {
      throw const FormatException('IDs de avisos duplicados.');
    }
    return result;
  }

  Future<void> save(Map<String, ReminderRecord> records) async {
    if (!await _store.write(
      jsonEncode(records.map((key, value) => MapEntry(key, value.toJson()))),
    )) {
      throw StateError('No se pudieron guardar los IDs de aviso.');
    }
  }
}
