import 'package:flutter_test/flutter_test.dart';
import 'package:familia_prado/core/month_calendar.dart';

void main() {
  test('Noviembre de 2026 incluye 6 semanas y cruce octubre/diciembre', () {
    final mondays = weeksInMonth(2026, 11);
    expect(mondays.length, 6);
    expect(mondays.first, DateTime(2026, 10, 26));
    expect(mondays.last, DateTime(2026, 11, 30));
  });

  test('Todas las semanas son lunes y cubren todos los días del mes', () {
    for (var year = 2024; year <= 2034; year++) {
      for (var month = 1; month <= 12; month++) {
        final weeks = weeksInMonth(year, month);
        expect(weeks.length, inInclusiveRange(4, 6));
        expect(weeks.every((w) => w.weekday == DateTime.monday), true);
        final end = DateTime(year, month + 1, 0).day;
        for (var day = 1; day <= end; day++) {
          final current = DateTime(year, month, day);
          expect(weeks.any((mon) =>
            !current.isBefore(mon) && current.isBefore(mon.add(const Duration(days: 7)))),
            true);
        }
      }
    }
  });

  test('Semanas de borde se reconocen en ambos meses', () {
    expect(weekIntersectsMonth(DateTime(2026, 10, 26), 2026, 11), true);
    expect(weekIntersectsMonth(DateTime(2026, 11, 30), 2026, 12), true);
    expect(weekIntersectsMonth(DateTime(2026, 10, 19), 2026, 11), false);
  });
}
