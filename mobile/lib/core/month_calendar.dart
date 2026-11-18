/// Reglas puras: semanas de lunes a domingo que intersectan un mes.
DateTime mondayOf(DateTime day) =>
    DateTime(day.year, day.month, day.day - day.weekday + DateTime.monday);

List<DateTime> weeksInMonth(int year, int month) {
  final start = DateTime(year, month, 1);
  final next = DateTime(year, month + 1, 1);
  final mondays = <DateTime>[];
  for (var week = mondayOf(start); week.isBefore(next);
      week = week.add(const Duration(days: 7))) {
    mondays.add(week);
  }
  return mondays;
}

bool weekIntersectsMonth(DateTime monday, int year, int month) {
  final start = DateTime(year, month, 1);
  final next = DateTime(year, month + 1, 1);
  return monday.isBefore(next) &&
      !monday.add(const Duration(days: 6)).isBefore(start);
}
