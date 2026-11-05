import 'dart:convert';
import 'package:blueflora/domain/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class JsonPreferencesStore {
  Future<String?> read();
  Future<bool> write(String value);
}

class SharedJsonPreferencesStore implements JsonPreferencesStore {
  SharedJsonPreferencesStore(this.key);
  final String key;
  @override
  Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs.getString(key);
  }

  @override
  Future<bool> write(String value) async =>
      (await SharedPreferences.getInstance()).setString(key, value);
}

class SettingsRepository {
  SettingsRepository({JsonPreferencesStore? store})
    : _store = store ?? SharedJsonPreferencesStore('blueflora.settings.v1');
  final JsonPreferencesStore _store;
  Future<AppSettings> load() async {
    final value = await _store.read();
    return value == null
        ? const AppSettings()
        : AppSettings.fromJson(jsonDecode(value) as Map<String, dynamic>);
  }

  Future<void> save(AppSettings settings) async {
    // Validación también en release, antes de escribir.
    AppSettings.fromJson(settings.toJson());
    if (!await _store.write(jsonEncode(settings.toJson()))) {
      throw StateError('Preferencias no guardadas.');
    }
  }
}
