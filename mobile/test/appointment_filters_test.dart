import 'package:flutter_test/flutter_test.dart';
import 'package:familia_prado/core/appointment_filters.dart';

void main() {
  test('history builds all filters without truncating the requested window', () {
    final uri = Uri.parse(appointmentSearchPath(bucket: 'HISTORY',
      limit: 20, offset: 40, from: '2026-01-01', to: '2026-11-18',
      responsibleMemberId: 'abc-123', status: 'COMPLETED'));
    expect(uri.path, '/api/appointments/search');
    expect(uri.queryParameters['bucket'], 'HISTORY');
    expect(uri.queryParameters['offset'], '40');
    expect(uri.queryParameters['from'], '2026-01-01');
    expect(uri.queryParameters['to'], '2026-11-18');
    expect(uri.queryParameters['responsibleMemberId'], 'abc-123');
    expect(uri.queryParameters['status'], 'COMPLETED');
  });
  test('upcoming ignores a historical status filter', () {
    final uri = Uri.parse(appointmentSearchPath(bucket: 'UPCOMING',
      limit: 20, offset: 0, status: 'COMPLETED'));
    expect(uri.queryParameters['status'], isNull);
  });
  test('cancelled retains an optional date range', () {
    final uri = Uri.parse(appointmentSearchPath(bucket: 'CANCELLED',
      limit: 20, offset: 0, from: '2026-11-01', to: '2026-11-30'));
    expect(uri.queryParameters['from'], '2026-11-01');
    expect(uri.queryParameters['to'], '2026-11-30');
  });
}
