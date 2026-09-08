import 'package:flutter_test/flutter_test.dart';

import 'package:cantera_os/data/cantera_data.dart';
import 'package:cantera_os/services/attendance_stats_service.dart';

void main() {
  group('computeAttendanceRates', () {
    test('no sessions yet -> empty map, never invents a 0%', () {
      final rates = computeAttendanceRates(
        sessions: const [],
        playerIds: ['p1'],
      );
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

  group('averageAttendanceRate', () {
    test('null when there is no data yet — never a fake 0%', () {
      expect(averageAttendanceRate(const []), isNull);
    });

    test('plain mean of the given rates', () {
      expect(averageAttendanceRate([1.0, 0.5, 0.0]), closeTo(0.5, 0.0001));
    });
  });

  group('summarizeAttendance', () {
    test('distinguishes no records from a real zero', () {
      expect(summarizeAttendance(const []).average, isNull);
      final summary = summarizeAttendance(const [
        AttendanceRecord(
          categoryId: 'cat',
          date: '2026-09-08',
          presentIds: [],
          rosterIds: ['a', 'b'],
        ),
      ]);
      expect(summary.average, 0);
      expect(summary.sessions, 1);
    });

    test('uses each saved roster snapshot', () {
      final summary = summarizeAttendance(const [
        AttendanceRecord(
          categoryId: 'cat',
          date: '2026-09-08',
          presentIds: ['a'],
          rosterIds: ['a', 'b'],
        ),
        AttendanceRecord(
          categoryId: 'cat',
          date: '2026-09-01',
          presentIds: ['a', 'b', 'c'],
          rosterIds: ['a', 'b', 'c'],
        ),
      ]);
      expect(summary.average, .75);
    });
  });
}
