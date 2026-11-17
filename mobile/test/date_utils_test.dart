import 'package:flutter_test/flutter_test.dart';
import 'package:familia_prado/core/api.dart';

void main() {
  test('lunes de una semana que termina en domingo', () {
    expect(isoDate(firstMonday(DateTime(2026, 11, 22))), '2026-11-16');
  });
  test('una cita se almacena en UTC desde la hora peruana', () {
    expect(peruToUtcIso(DateTime(2026, 11, 20), 9, 30), '2026-11-20T14:30:00.000Z');
  });
  test('el horario peruano no cambia por zona del dispositivo', () {
    final clock = peruClock('2026-11-20T14:30:00Z');
    expect(clock.hour, 9);
    expect(clock.minute, 30);
  });
}
