import 'package:flutter_test/flutter_test.dart';
import 'package:cantera_os/data/cantera_data.dart';
import 'package:cantera_os/services/week_view_service.dart';

void main() {
  test('week runs Monday through Sunday across month boundaries', () {
    final days = daysOfWeek(DateTime(2026, 9, 3));
    expect(days.first, DateTime(2026, 8, 31));
    expect(days.last, DateTime(2026, 9, 6));
  });

  test('filters records by category and week', () {
    const records = [
      AttendanceRecord(
        categoryId: 'a',
        date: '2026-09-01',
        presentIds: [],
        rosterIds: [],
      ),
      AttendanceRecord(
        categoryId: 'b',
        date: '2026-09-02',
        presentIds: [],
        rosterIds: [],
      ),
      AttendanceRecord(
        categoryId: 'a',
        date: '2026-09-08',
        presentIds: [],
        rosterIds: [],
      ),
    ];
    expect(
      attendanceForWeek(records, DateTime(2026, 9, 3), categoryId: 'a'),
      hasLength(1),
    );
  });

  test('minutes are unknown until at least one match has minute data', () {
    const empty = MatchResult(
      id: '1',
      categoryId: 'a',
      date: '2026-09-01',
      opponent: 'X',
    );
    const loaded = MatchResult(
      id: '2',
      categoryId: 'a',
      date: '2026-09-02',
      opponent: 'Y',
      minutesByPlayer: {'p1': 90, 'p2': 30},
    );
    expect(minutesForWeek([empty]), isNull);
    expect(minutesForWeek([empty, loaded]), 120);
  });
}
