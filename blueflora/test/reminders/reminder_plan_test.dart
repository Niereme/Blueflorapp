import 'package:blueflora/domain/app_settings.dart';
import 'package:blueflora/domain/tree.dart';
import 'package:blueflora/domain/reminder_plan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(tzdata.initializeTimeZones);
  const settings = AppSettings(remindersEnabled: true, hour: 9, minute: 30);
  final now = DateTime.utc(2026, 11, 4, 8);
  Tree due(DateTime date) => Tree(
    nombre: 'Pino',
    frecuenciaRiegoDias: 3,
    ultimoRiego: date.subtract(const Duration(days: 3)),
  );

  test('No planifica si está desactivado o no existe último riego', () {
    expect(planReminder(due(now), const AppSettings(), now, tz.UTC), isNull);
    expect(
      planReminder(
        Tree(nombre: 'Pino', frecuenciaRiegoDias: 3),
        settings,
        now,
        tz.UTC,
      ),
      isNull,
    );
  });
  test('Vencimiento anterior a la hora elegida permite aviso el mismo día', () {
    expect(
      planReminder(
        due(DateTime.utc(2026, 11, 5, 7)),
        settings,
        now,
        tz.UTC,
      )!.at,
      tz.TZDateTime(tz.UTC, 2026, 11, 5, 9, 30),
    );
  });
  test('Vencimiento posterior a la hora elegida pasa al día siguiente', () {
    expect(
      planReminder(
        due(DateTime.utc(2026, 11, 5, 17)),
        settings,
        now,
        tz.UTC,
      )!.at,
      tz.TZDateTime(tz.UTC, 2026, 11, 6, 9, 30),
    );
  });
  test('Coincidir con el vencimiento es válido si todavía es futuro', () {
    expect(
      planReminder(
        due(DateTime.utc(2026, 11, 5, 9, 30)),
        settings,
        now,
        tz.UTC,
      )!.at.hour,
      9,
    );
    expect(
      planReminder(
        due(DateTime.utc(2026, 11, 5, 9, 30)),
        settings,
        now,
        tz.UTC,
      )!.at.day,
      5,
    );
  });
  test('Un vencido usa un único horario futuro, sin días antiguos', () {
    final tree = due(DateTime.utc(2020));
    final first = planReminder(tree, settings, now, tz.UTC)!;
    expect(first.at, tz.TZDateTime(tz.UTC, 2026, 11, 4, 9, 30));
    final later = planReminder(
      tree,
      settings,
      DateTime.utc(2026, 11, 4, 10),
      tz.UTC,
    )!;
    expect(later.at, tz.TZDateTime(tz.UTC, 2026, 11, 5, 9, 30));
    expect(first.cycle, later.cycle);
  });
  test('Nunca programa ahora ni una hora pasada', () {
    final current = DateTime.utc(2026, 11, 4, 9, 30);
    expect(planReminder(due(current), settings, current, tz.UTC)!.at.day, 5);
  });
  test('Respeta la hora de México y los periodos de 24 horas', () {
    final zone = tz.getLocation('America/Mexico_City');
    final current = tz.TZDateTime(zone, 2026, 11, 4, 8);
    final tree = due(tz.TZDateTime(zone, 2026, 11, 5, 7));
    final plan = planReminder(tree, settings, current, zone)!;
    expect(plan.at.hour, 9);
    expect(plan.at.minute, 30);
    expect(plan.at.timeZoneOffset, const Duration(hours: -6));
    expect(
      plan.at.isBefore(tree.ultimoRiego!.add(const Duration(days: 3))),
      isFalse,
    );
  });
  test('Cambio de año se calcula por calendario local', () {
    final current = DateTime.utc(2026, 12, 31, 23);
    expect(
      planReminder(due(current), settings, current, tz.UTC)!.at,
      tz.TZDateTime(tz.UTC, 2027, 1, 1, 9, 30),
    );
  });
  test('Saltos de horario no programan antes del vencimiento', () {
    final zone = tz.getLocation('America/New_York');
    final current = tz.TZDateTime(zone, 2026, 3, 7, 23);
    final deadline = tz.TZDateTime(zone, 2026, 3, 8, 3);
    final plan = planReminder(
      due(deadline),
      settings.copyWith(hour: 2, minute: 30),
      current,
      zone,
    )!;
    expect(plan.at.isAfter(current), isTrue);
    expect(plan.at.isBefore(deadline), isFalse);
  });
  test('Regar cambia el ciclo; cambiar hora o nombre cambia la firma', () {
    final tree = due(now);
    final plan = planReminder(tree, settings, now, tz.UTC)!;
    expect(
      planReminder(
        tree.copyWith(ultimoRiego: now),
        settings,
        now,
        tz.UTC,
      )!.cycle,
      isNot(plan.cycle),
    );
    expect(
      planReminder(tree, settings.copyWith(hour: 10), now, tz.UTC)!.signature,
      isNot(plan.signature),
    );
    expect(
      planReminder(
        tree.copyWith(nombre: 'Roble'),
        settings,
        now,
        tz.UTC,
      )!.signature,
      isNot(plan.signature),
    );
  });
}
