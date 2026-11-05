import 'tree.dart';

/// Categorías excluyentes. El vencimiento usa periodos de 24 horas; hoy y
/// mañana usan fechas locales. Un vencimiento anterior al instante actual es
/// vencido incluso si cayó hoy. Sin último riego no se inventa una fecha.
enum WateringStatus { overdue, today, tomorrow, later, undated }

class WateringSummary {
  WateringSummary(Iterable<Tree> trees, DateTime now) {
    final seen = <String>{};
    for (final tree in trees) {
      if (!seen.add(tree.id)) continue;
      _total++;
      switch (statusOf(tree, now)) {
        case WateringStatus.overdue:
          _overdue++;
        case WateringStatus.today:
          _today++;
        case WateringStatus.tomorrow:
          _tomorrow++;
        case WateringStatus.later:
          _later++;
        case WateringStatus.undated:
          _undated++;
      }
    }
  }

  int _total = 0;
  int get total => _total;
  int _overdue = 0;
  int get overdue => _overdue;
  int _today = 0;
  int get today => _today;
  int _tomorrow = 0;
  int get tomorrow => _tomorrow;
  int _later = 0;
  int get later => _later;
  int _undated = 0;
  int get undated => _undated;
  int get pending => overdue + today + undated;

  static WateringStatus statusOf(Tree tree, DateTime now) {
    if (tree.ultimoRiego == null) return WateringStatus.undated;
    final due = tree.ultimoRiego!.add(Duration(days: tree.frecuenciaRiegoDias));
    if (due.isBefore(now)) return WateringStatus.overdue;
    final localNow = now.toLocal();
    final localDue = due.toLocal();
    final tomorrow = DateTime(localNow.year, localNow.month, localNow.day + 1);
    bool sameDate(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;
    if (sameDate(localDue, localNow)) return WateringStatus.today;
    if (sameDate(localDue, tomorrow)) return WateringStatus.tomorrow;
    return WateringStatus.later;
  }
}
