import 'package:flutter_test/flutter_test.dart';

import 'package:cantera_os/services/attendance_stats_service.dart';

void main() {
  group('computeAttendanceRates', () {
    test('no sessions yet -> empty map, never invents a 0%', () {
      final rates = computeAttendanceRates(sessions: const [], playerIds: ['p1']);
      expect(rates, isEmpty);
    });

    test('rate is present-sessions / total-sessions per player', () {
      final sessions = [
        const AttendanceSession(presentIds: {'p1', 'p2'}),
        const AttendanceSession(presentIds: {'p1'}),
      ];
      final rates = computeAttendanceRates(
        sessions: sessions,
        playerIds: ['p1', 'p2', 'p3'],
      );
      expect(rates['p1'], 1.0);
      expect(rates['p2'], 0.5);
      expect(rates['p3'], 0.0);
    });
  });
}
