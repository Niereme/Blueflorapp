import 'dart:async';
import 'dart:convert';
import 'package:blueflora/application/settings_controller.dart';
import 'package:blueflora/data/settings_repository.dart';
import 'package:blueflora/domain/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../support/reminder_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Por defecto no activa avisos y utiliza 09:00 y tema del sistema',
    () async {
      final value = await SettingsRepository(store: MemoryJsonStore()).load();
      expect(value.remindersEnabled, isFalse);
      expect(value.hour, 9);
      expect(value.minute, 0);
      expect(value.theme, AppTheme.system);
    },
  );
  test(
    'Persiste todas las preferencias al crear un repositorio nuevo sin tocar plantas',
    () async {
      SharedPreferences.setMockInitialValues({
        'trees': ['datos de plantas'],
      });
      final repository = SettingsRepository();
      await repository.save(
        const AppSettings(
          remindersEnabled: true,
          hour: 21,
          minute: 35,
          theme: AppTheme.dark,
        ),
      );
      final restored = await SettingsRepository().load();
      expect(
        restored.toJson(),
        const AppSettings(
          remindersEnabled: true,
          hour: 21,
          minute: 35,
          theme: AppTheme.dark,
        ).toJson(),
      );
      expect((await SharedPreferences.getInstance()).getStringList('trees'), [
        'datos de plantas',
      ]);
    },
  );
  for (final corrupt in [
    '{mal',
    '{"hour":25}',
    jsonEncode({
      'remindersEnabled': true,
      'hour': 9,
      'minute': 0,
      'theme': 'otro',
    }),
  ]) {
    test(
      'Datos inválidos se conservan y bloquean modificaciones: $corrupt',
      () async {
        final store = MemoryJsonStore()..value = corrupt;
        final controller = SettingsController(
          repository: SettingsRepository(store: store),
        );
        addTearDown(controller.dispose);
        expect(await controller.load(), isFalse);
        expect(controller.error, isNotNull);
        expect(
          await controller.save(const AppSettings(theme: AppTheme.dark)),
          isFalse,
        );
        expect(store.value, corrupt);
        expect(store.writes, isEmpty);
      },
    );
  }
  test(
    'Guardado fallido no publica preferencias y permite reintentar',
    () async {
      final store = MemoryJsonStore();
      final controller = SettingsController(
        repository: SettingsRepository(store: store),
      );
      addTearDown(controller.dispose);
      await controller.load();
      store.writeResult = false;
      expect(
        await controller.save(controller.value.copyWith(theme: AppTheme.dark)),
        isFalse,
      );
      expect(controller.value.theme, AppTheme.system);
      expect(controller.error, isNotNull);
      store.writeResult = true;
      expect(
        await controller.save(controller.value.copyWith(theme: AppTheme.dark)),
        isTrue,
      );
      expect(controller.value.theme, AppTheme.dark);
    },
  );
  test(
    'No permite guardar durante la carga ni dos escrituras simultáneas',
    () async {
      final store = MemoryJsonStore()..readGate = Completer<void>();
      final controller = SettingsController(
        repository: SettingsRepository(store: store),
      );
      addTearDown(controller.dispose);
      final load = controller.load();
      expect(
        await controller.save(const AppSettings(theme: AppTheme.dark)),
        isFalse,
      );
      store.readGate!.complete();
      await load;
      store.writeGate = Completer<void>();
      final save = controller.save(const AppSettings(theme: AppTheme.dark));
      expect(
        await controller.save(const AppSettings(theme: AppTheme.light)),
        isFalse,
      );
      expect(controller.value.theme, AppTheme.system);
      store.writeGate!.complete();
      expect(await save, isTrue);
      expect(store.writes, hasLength(1));
    },
  );
  test('Error de lectura se puede reintentar', () async {
    final store = MemoryJsonStore()..readError = StateError('fallo');
    final controller = SettingsController(
      repository: SettingsRepository(store: store),
    );
    addTearDown(controller.dispose);
    expect(await controller.load(), isFalse);
    store.readError = null;
    expect(await controller.load(), isTrue);
    expect(controller.error, isNull);
  });
  test('Destruir durante una carga pendiente no notifica después', () async {
    final store = MemoryJsonStore()..readGate = Completer<void>();
    final controller = SettingsController(
      repository: SettingsRepository(store: store),
    );
    final load = controller.load();
    controller.dispose();
    store.readGate!.complete();
    expect(await load, isFalse);
  });
  test('JSON exige hora y minuto válidos y conserva los tres temas', () {
    for (final theme in AppTheme.values) {
      final original = AppSettings(theme: theme, hour: 23, minute: 59);
      expect(
        AppSettings.fromJson(original.toJson()).toJson(),
        original.toJson(),
      );
    }
    for (final json in [
      {'remindersEnabled': false, 'hour': -1, 'minute': 0, 'theme': 'system'},
      {'remindersEnabled': false, 'hour': 24, 'minute': 0, 'theme': 'system'},
      {'remindersEnabled': false, 'hour': 9, 'minute': 60, 'theme': 'system'},
      {'remindersEnabled': 'sí', 'hour': 9, 'minute': 0, 'theme': 'system'},
    ]) {
      expect(() => AppSettings.fromJson(json), throwsFormatException);
    }
  });
}
