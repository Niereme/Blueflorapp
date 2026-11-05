import 'package:blueflora/data/settings_repository.dart';
import 'package:blueflora/domain/app_settings.dart';
import 'package:flutter/foundation.dart';

class SettingsController extends ChangeNotifier {
  SettingsController({SettingsRepository? repository})
    : _repository = repository ?? SettingsRepository();
  final SettingsRepository _repository;
  AppSettings _value = const AppSettings();
  AppSettings get value => _value;
  bool ready = false;
  bool _loading = false;
  bool saving = false;
  String? error;
  bool _disposed = false;
  bool get loading => _loading || !ready && error == null;
  bool get canModify => ready && !_loading && !saving && !_disposed;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<bool> load() async {
    if (_loading || saving || _disposed) return false;
    _loading = true;
    error = null;
    _emit();
    try {
      final value = await _repository.load();
      if (_disposed) return false;
      _value = value;
      ready = true;
      return true;
    } catch (_) {
      if (!_disposed) {
        error = 'No se pudieron cargar las preferencias. No se han borrado.';
      }
      return false;
    } finally {
      _loading = false;
      _emit();
    }
  }

  Future<bool> save(AppSettings next) async {
    if (!canModify) return false;
    saving = true;
    error = null;
    _emit();
    try {
      await _repository.save(next);
      if (_disposed) return false;
      _value = next;
      return true;
    } catch (_) {
      if (!_disposed) {
        error = 'No se pudieron guardar las preferencias. Inténtalo de nuevo.';
      }
      return false;
    } finally {
      saving = false;
      _emit();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
