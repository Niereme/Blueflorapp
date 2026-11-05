import 'package:blueflora/domain/tree.dart';
import 'package:blueflora/domain/watering_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 4, 12);
  Tree dueAt(DateTime due) => Tree(
    nombre: 'Pino',
    frecuenciaRiegoDias: 3,
    ultimoRiego: due.subtract(const Duration(days: 3)),
  );

  test('Clasifica cada planta una sola vez y separa pendientes y futuras', () {
    final plants = [
      dueAt(now.subtract(const Duration(minutes: 1))),
      dueAt(now.subtract(const Duration(days: 5))),
      dueAt(now.add(const Duration(hours: 1))),
      dueAt(DateTime(2026, 11, 5, 8)),
      dueAt(DateTime(2026, 11, 7, 8)),
      Tree(nombre: 'Sin fecha', frecuenciaRiegoDias: 3),
    ];
    final summary = WateringSummary(plants, now);
    expect(summary.total, 6);
    expect(summary.overdue, 2);
    expect(summary.today, 1);
    expect(summary.tomorrow, 1);
    expect(summary.later, 1);
    expect(summary.undated, 1);
    expect(summary.pending, 4);
    expect(
      summary.overdue +
          summary.today +
          summary.tomorrow +
          summary.later +
          summary.undated,
      summary.total,
    );
  });

  test(
    'Un vencimiento de hace treinta minutos es vencido aunque diasRestantes sea cero',
    () {
      final tree = dueAt(now.subtract(const Duration(minutes: 30)));
      expect(tree.diasRestantes(ahora: now), 0);
      expect(WateringSummary.statusOf(tree, now), WateringStatus.overdue);
    },
  );

  test(
    'Vencimiento exacto sigue en hoy y un microsegundo después es vencido',
    () {
      final tree = dueAt(now);
      expect(WateringSummary.statusOf(tree, now), WateringStatus.today);
      expect(
        WateringSummary.statusOf(
          tree,
          now.add(const Duration(microseconds: 1)),
        ),
        WateringStatus.overdue,
      );
    },
  );

  test('Hoy y mañana son fechas locales, no ventanas móviles de 24 horas', () {
    final late = DateTime(2026, 11, 4, 23, 45);
    final tomorrow = dueAt(DateTime(2026, 11, 5, 0, 15));
    expect(tomorrow.diasRestantes(ahora: late), 1);
    expect(WateringSummary.statusOf(tomorrow, late), WateringStatus.tomorrow);
    expect(
      WateringSummary.statusOf(dueAt(DateTime(2026, 11, 5, 23, 45)), now),
      WateringStatus.tomorrow,
    );
  });

  test(
    'Medianoche cambia mañana a hoy sin alterar la fecha de vencimiento',
    () {
      final tree = dueAt(DateTime(2027, 1, 1, 8));
      expect(
        WateringSummary.statusOf(tree, DateTime(2026, 12, 31, 23, 59)),
        WateringStatus.tomorrow,
      );
      expect(
        WateringSummary.statusOf(tree, DateTime(2027, 1, 1)),
        WateringStatus.today,
      );
    },
  );

  test('Fechas UTC se clasifican por su equivalente local', () {
    final due = DateTime(2026, 11, 5, 0, 15).toUtc();
    expect(
      WateringSummary.statusOf(dueAt(due), now.toUtc()),
      WateringStatus.tomorrow,
    );
  });

  test('Deduplica por ID, nunca por nombre', () {
    final first = dueAt(now);
    final second = dueAt(now);
    final summary = WateringSummary([first, first, second], now);
    expect(summary.total, 2);
    expect(summary.today, 2);
    expect(summary.pending, 2);
  });

  test('Lista vacía tiene todos los indicadores en cero', () {
    final summary = WateringSummary([], now);
    expect(summary.total, 0);
    expect(summary.pending, 0);
    expect(
      summary.today +
          summary.overdue +
          summary.tomorrow +
          summary.undated +
          summary.later,
      0,
    );
  });
}
