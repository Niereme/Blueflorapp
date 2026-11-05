import 'dart:convert';
import 'package:blueflora/application/settings_controller.dart';
import 'package:blueflora/data/settings_repository.dart';
import 'package:blueflora/domain/app_settings.dart';
import 'package:blueflora/main.dart';
import 'package:blueflora/presentation/screens/views/home_view.dart';
import 'package:blueflora/presentation/screens/views/settings_view.dart';
import 'package:blueflora/presentation/squares/tree_square.dart';
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

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      Blueflora(settings: settings, notificationGateway: gateway),
    );
    await tester.pumpAndSettle();
  }

  Future<void> config(WidgetTester tester) async {
    await tapVisible(tester, find.byIcon(Icons.account_circle));
    await tester.pumpAndSettle();
    expect(find.text('Configuraciones'), findsOneWidget);
    await tapVisible(tester, find.text('Configuraciones'));
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String theme) async {
    await tapVisible(tester, find.byKey(const ValueKey('theme-choice')));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text(theme).last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Acceso único desde Perfil, preferencias persistentes y temas funcionales',
    (tester) async {
      await open(tester);
      await config(tester);
      await choose(tester, 'Oscuro');
      expect(settings.value.theme, AppTheme.dark);
      expect(
        Theme.of(tester.element(find.byType(SettingsView))).brightness,
        Brightness.dark,
      );
      expect(
        (await SettingsRepository(store: store).load()).theme,
        AppTheme.dark,
      );
      await choose(tester, 'Claro');
      expect(
        Theme.of(tester.element(find.byType(SettingsView))).brightness,
        Brightness.light,
      );
      await choose(tester, 'Automático (sistema)');
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(SettingsView))).brightness,
        Brightness.dark,
      );
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
    },
  );
  testWidgets(
    'Rechazar permiso conserva interruptor apagado y muestra explicación',
    (tester) async {
      gateway.requestResult = false;
      await open(tester);
      await config(tester);
      await tapVisible(tester, find.byKey(const ValueKey('reminders-toggle')));
      await tester.pumpAndSettle();
      expect(settings.value.remindersEnabled, isFalse);
      expect(find.textContaining('Permiso rechazado'), findsOneWidget);
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const ValueKey('reminders-toggle')),
            )
            .value,
        isFalse,
      );
      expect(gateway.jobs, isEmpty);
    },
  );
  testWidgets('Guardar tema fallido conserva la selección confirmada', (
    tester,
  ) async {
    await open(tester);
    await config(tester);
    store.writeResult = false;
    await choose(tester, 'Oscuro');
    expect(settings.value.theme, AppTheme.system);
    expect(
      tester
          .widget<DropdownButton<AppTheme>>(
            find.byKey(const ValueKey('theme-choice')),
          )
          .value,
      AppTheme.system,
    );
    expect(find.textContaining('No se pudieron guardar'), findsOneWidget);
  });
  testWidgets('Selector de hora guarda un cambio y permite cancelar', (
    tester,
  ) async {
    await open(tester);
    await config(tester);
    await tapVisible(tester, find.text('Hora preferida'));
    await tester.pumpAndSettle();
    // Usar la entrada accesible del selector nativo de Material.
    await tapVisible(tester, find.byIcon(Icons.keyboard_outlined));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '10');
    await tester.enterText(fields.at(1), '25');
    await tapVisible(tester, find.text('OK'));
    await tester.pumpAndSettle();
    expect(settings.value.minute, 25);
    expect(find.textContaining(':25'), findsOneWidget);
    final previous = settings.value.toJson();
    await tapVisible(tester, find.text('Hora preferida'));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(settings.value.toJson(), previous);
  });
  testWidgets(
    'El tema cargado se mantiene al navegar por todas las pantallas',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'trees': [
          jsonEncode({
            'id': 'plant-1',
            'nombre': 'Pino',
            'frecuenciaRiegoDias': 3,
          }),
        ],
      });
      store.value = jsonEncode(
        const AppSettings(theme: AppTheme.dark).toJson(),
      );
      await open(tester);
      expect(
        Theme.of(tester.element(find.byType(HomeView))).brightness,
        Brightness.dark,
      );
      for (final icon in [
        Icons.forest,
        Icons.history,
        Icons.account_circle,
        Icons.home,
      ]) {
        await tapVisible(
          tester,
          find.descendant(
            of: find.byType(BottomNavigationBar),
            matching: find.byIcon(icon),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          Theme.of(tester.element(find.byType(BottomNavigationBar))).brightness,
          Brightness.dark,
        );
      }
      await tapVisible(tester, find.byIcon(Icons.forest));
      await tester.pumpAndSettle();
      final card = tester.widget<Card>(
        find.descendant(
          of: find.byType(TreeSquare),
          matching: find.byType(Card),
        ),
      );
      expect(card.color, isNot(Colors.grey.shade200));
      await tapVisible(tester, find.byTooltip('Ver detalle'));
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.text('Detalle de planta'))).brightness,
        Brightness.dark,
      );
    },
  );
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}
