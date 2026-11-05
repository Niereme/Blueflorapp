import 'package:timezone/timezone.dart' as tz;
import 'app_settings.dart';
import 'tree.dart';

/// Una notificación por ciclo (último riego + frecuencia). Nunca antes del
/// vencimiento: primera hora preferida futura a partir de ese instante.
/// Sin fecha no se planifica. Un vencido se traslada al siguiente horario,
/// sin reconstruir días pasados ni repetirlo diariamente.
class ReminderPlan {
  ReminderPlan({
    required this.plant,
    required this.at,
    required this.cycle,
    required this.signature,
  });
  final Tree plant;
  final tz.TZDateTime at;
  final String cycle;
  final String signature;
}

ReminderPlan? planReminder(
  Tree plant,
  AppSettings settings,
  DateTime now,
  tz.Location zone,
) {
  if (!settings.remindersEnabled || plant.ultimoRiego == null) return null;
  final due = plant.ultimoRiego!.add(Duration(days: plant.frecuenciaRiegoDias));
  final floor = due.isAfter(now) ? due : now;
  final local = tz.TZDateTime.from(floor, zone);
  var target = tz.TZDateTime(
    zone,
    local.year,
    local.month,
    local.day,
    settings.hour,
    settings.minute,
  );
  if (target.isBefore(due) || !target.isAfter(now)) {
    target = tz.TZDateTime(
      zone,
      local.year,
      local.month,
      local.day + 1,
      settings.hour,
      settings.minute,
    );
  }
  // En un salto horario, el constructor de timezone normaliza la hora inexistente.
  final cycle =
      '${plant.ultimoRiego!.toUtc().toIso8601String()}|${plant.frecuenciaRiegoDias}';
  final signature =
      '${plant.id}|${plant.nombre}|$cycle|${settings.hour}:${settings.minute}|${zone.name}';
  return ReminderPlan(
    plant: plant,
    at: target,
    cycle: cycle,
    signature: signature,
  );
}
