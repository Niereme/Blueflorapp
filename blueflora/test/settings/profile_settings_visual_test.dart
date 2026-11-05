import 'dart:async';
import 'dart:convert';
import 'package:blueflora/application/settings_controller.dart';
import 'package:blueflora/data/settings_repository.dart';
import 'package:blueflora/domain/app_settings.dart';
import 'package:blueflora/main.dart';
import 'package:blueflora/presentation/screens/views/profile_view.dart';
import 'package:blueflora/presentation/screens/views/settings_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../support/reminder_fakes.dart';

void main() {
  late MemoryJsonStore store;
  late SettingsController settings;
  late FakeNotificationGateway gateway;
  setUp(() {
    SharedPreferences.setMockInitialValues({'trees': <String>[]});
    store = MemoryJsonStore();
    settings = SettingsController(repository: SettingsRepository(store: store));
    gateway = FakeNotificationGateway();
  });
  tearDown(() => settings.dispose());

  Future<void> see(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) await tester.scrollUntilVisible(finder, 160);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          textScaler: TextScaler.linear(2),
          disableAnimations: true,
        ),
        child: Blueflora(settings: settings, notificationGateway: gateway),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.account_circle));
    await tester.pumpAndSettle();
    await see(tester, find.text('Configuraciones'));
    await tester.tap(find.text('Configuraciones'));
    await tester.pumpAndSettle();
    expect(
      MediaQuery.textScalerOf(
        tester.element(find.byType(SettingsView)),
      ).scale(16),
      32,
    );
    expect(gateway.requests, 0);
  }

  for (final dark in [false, true]) {
    testWidgets(
      'Perfil y Configuraciones a 320px/200%, oscuro=$dark, sin permisos automáticos',
      (tester) async {
        store.value = jsonEncode(
          AppSettings(theme: dark ? AppTheme.dark : AppTheme.light).toJson(),
        );
        await open(tester);
        expect(
          Theme.of(tester.element(find.byType(SettingsView))).brightness,
          dark ? Brightness.dark : Brightness.light,
        );
        await see(tester, find.byKey(const ValueKey('theme-choice')));
        await tester.tap(find.byKey(const ValueKey('theme-choice')));
        await tester.pumpAndSettle();
        await see(tester, find.text('Automático (sistema)').last);
        await tester.tap(find.text('Automático (sistema)').last);
        await tester.pumpAndSettle();
        expect(settings.value.theme, AppTheme.system);
        await see(tester, find.text('Hora preferida'));
        await tester.tap(find.text('Hora preferida'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        await see(tester, find.text('Información y ayuda'));
        expect(gateway.requests, 0);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(ProfileView), findsOneWidget);
        expect(store.writes.length, 1);
      },
    );
  }

  testWidgets(
    'Permiso rechazado y reintento explícito; desactivar conserva la política',
    (tester) async {
      gateway.requestResult = false;
      await open(tester);
      final toggle = find.byKey(const ValueKey('reminders-toggle'));
      await see(tester, toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(settings.value.remindersEnabled, isFalse);
      expect(gateway.requests, 1);
      await see(tester, find.textContaining('Permiso rechazado'));
      expect(find.textContaining('concedido'), findsNothing);
      gateway.requestResult = true;
      await see(tester, find.text('Solicitar permiso'));
      await tester.tap(find.text('Solicitar permiso'));
      await tester.pumpAndSettle();
      expect(settings.value.remindersEnabled, isTrue);
      expect(gateway.requests, 2);
      await see(tester, toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(settings.value.remindersEnabled, isFalse);
      expect(gateway.requests, 2);
      expect(gateway.jobs, isEmpty);
      expect(
        (await SettingsRepository(store: store).load()).remindersEnabled,
        isFalse,
      );
    },
  );

  testWidgets(
    'No se muestra el tema como guardado mientras la escritura está pendiente',
    (tester) async {
      await open(tester);
      final choice = find.byKey(const ValueKey('theme-choice'));
      await see(tester, choice);
      await tester.tap(choice);
      await tester.pumpAndSettle();
      store.writeGate = Completer<void>();
      await tester.tap(find.text('Oscuro').last);
      await tester.pump(const Duration(milliseconds: 300));
      expect(settings.saving, isTrue);
      expect(settings.value.theme, AppTheme.system);
      expect(
        tester.widget<DropdownButton<AppTheme>>(choice).value,
        AppTheme.system,
      );
      expect(tester.widget<DropdownButton<AppTheme>>(choice).onChanged, isNull);
      store.writeGate!.complete();
      await tester.pumpAndSettle();
      expect(settings.value.theme, AppTheme.dark);
      expect(
        (await SettingsRepository(store: store).load()).theme,
        AppTheme.dark,
      );
    },
  );

  testWidgets('Error de lectura permite reintentar sin borrar preferencias', (
    tester,
  ) async {
    store.readError = StateError('sin acceso');
    await open(tester);
    await see(tester, find.text('Reintentar preferencias'));
    expect(
      tester
          .widget<DropdownButton<AppTheme>>(
            find.byKey(const ValueKey('theme-choice')),
          )
          .onChanged,
      isNull,
    );
    expect(store.writes, isEmpty);
    store.readError = null;
    await tester.tap(find.text('Reintentar preferencias'));
    await tester.pumpAndSettle();
    expect(settings.ready, isTrue);
    expect(settings.error, isNull);
    expect(store.writes, isEmpty);
    expect(gateway.requests, 0);
  });
  testWidgets(
    'Horario accesible valida minutos y conserva el cambio confirmado',
    (tester) async {
      await open(tester);
      await see(tester, find.text('Hora preferida'));
      await tester.tap(find.text('Hora preferida'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), '23');
      await tester.enterText(fields.at(1), '60');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(
        find.text('Escribe un número entero entre 0 y 59.'),
        findsOneWidget,
      );
      expect(store.writes, isEmpty);
      await tester.enterText(fields.at(1), '25');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(settings.value.hour, 23);
      expect(settings.value.minute, 25);
      final restored = await SettingsRepository(store: store).load();
      expect(restored.hour, 23);
      expect(restored.minute, 25);
      expect(gateway.requests, 0);
      expect(store.writes.length, 1);
    },
  );
}
