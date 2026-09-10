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

  group('AttendanceStatus semantics', () {
    test('tarde counts as attended and as expected', () {
      expect(AttendanceStatus.tarde.attended, isTrue);
      expect(AttendanceStatus.tarde.expected, isTrue);
    });

    test('lesionado and permiso are neither attended nor expected', () {
      for (final s in [AttendanceStatus.lesionado, AttendanceStatus.permiso]) {
        expect(s.attended, isFalse);
        expect(s.expected, isFalse);
      }
    });

    test('absent-with-notice still counts in the denominator', () {
      expect(AttendanceStatus.ausenteAvisado.attended, isFalse);
      expect(AttendanceStatus.ausenteAvisado.expected, isTrue);
    });

    test('attendanceStatusFromName falls back to absent-no-notice', () {
      expect(attendanceStatusFromName('tarde'), AttendanceStatus.tarde);
      expect(
        attendanceStatusFromName('garbage'),
        AttendanceStatus.ausenteSinAviso,
      );
    });
  });

  group('attendanceRecordRate (status-aware)', () {
    test('late counts as present; injury drops out of the denominator', () {
      final record = AttendanceRecord(
        categoryId: 'cat',
        date: '2026-09-08',
        presentIds: const [],
        rosterIds: const ['a', 'b', 'c'],
        statusByPlayer: const {
          'a': AttendanceStatus.presente,
          'b': AttendanceStatus.tarde,
          'c': AttendanceStatus.lesionado,
        },
      );
      // attended 2 (a,b), expected 2 (a,b) -> 1.0
      expect(attendanceRecordRate(record), 1.0);
    });

    test('granted leave never penalises the rate', () {
      final record = AttendanceRecord(
        categoryId: 'cat',
        date: '2026-09-08',
        presentIds: const [],
        rosterIds: const ['a', 'b'],
        statusByPlayer: const {
          'a': AttendanceStatus.presente,
          'b': AttendanceStatus.permiso,
        },
      );
      expect(attendanceRecordRate(record), 1.0);
    });

    test('a real absence lowers the rate', () {
      final record = AttendanceRecord(
        categoryId: 'cat',
        date: '2026-09-08',
        presentIds: const [],
        rosterIds: const ['a', 'b'],
        statusByPlayer: const {
          'a': AttendanceStatus.presente,
          'b': AttendanceStatus.ausenteSinAviso,
        },
      );
      expect(attendanceRecordRate(record), 0.5);
    });

    test('legacy record with only presentIds keeps its old rate', () {
      const record = AttendanceRecord(
        categoryId: 'cat',
        date: '2026-09-08',
        presentIds: ['a'],
        rosterIds: ['a', 'b'],
      );
      expect(attendanceRecordRate(record), 0.5);
    });

    test('everyone injured or on leave -> null, not a fake 0%', () {
      final record = AttendanceRecord(
        categoryId: 'cat',
        date: '2026-09-08',
        presentIds: const [],
        rosterIds: const ['a', 'b'],
        statusByPlayer: const {
          'a': AttendanceStatus.lesionado,
          'b': AttendanceStatus.permiso,
        },
      );
      expect(attendanceRecordRate(record), isNull);
    });
  });

  group('computeAttendanceRatesFromRecords', () {
    test('no records -> empty map', () {
      expect(
        computeAttendanceRatesFromRecords(records: const [], playerIds: ['a']),
        isEmpty,
      );
    });

    test('per-player attended / expected across sessions', () {
      final records = [
        AttendanceRecord(
          categoryId: 'cat',
          date: '2026-09-08',
          presentIds: const [],
          rosterIds: const ['a', 'b'],
          statusByPlayer: const {
            'a': AttendanceStatus.presente,
            'b': AttendanceStatus.lesionado,
          },
        ),
        AttendanceRecord(
          categoryId: 'cat',
          date: '2026-09-01',
          presentIds: const [],
          rosterIds: const ['a', 'b'],
          statusByPlayer: const {
            'a': AttendanceStatus.ausenteSinAviso,
            'b': AttendanceStatus.presente,
          },
        ),
      ];
      final rates = computeAttendanceRatesFromRecords(
        records: records,
        playerIds: ['a', 'b'],
      );
      expect(rates['a'], 0.5); // present once of two expected
      expect(rates['b'], 1.0); // one injury (ignored) + one present
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
