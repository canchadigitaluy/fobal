import 'package:cantera_os/data/cantera_data.dart';
import 'package:cantera_os/services/sync_conflict_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SyncConflictSnapshot snapshot(String id) => SyncConflictSnapshot(
    id: id,
    clubId: 'club',
    baseVersion: 1,
    createdAt: '2026-09-08T12:00:00Z',
    rawClub: '{}',
    bytes: 2,
  );

  test('unreviewed conflict copies are never silently evicted', () {
    var values = <SyncConflictSnapshot>[];
    for (var i = 0; i < 5; i++) {
      values = retainConflictSnapshots(values, snapshot('$i'));
    }
    expect(values.map((item) => item.id), ['4', '3', '2', '1', '0']);
  });

  test('same snapshot id is deduplicated', () {
    final values = retainConflictSnapshots([snapshot('a')], snapshot('a'));
    expect(values, hasLength(1));
  });

  test('difference summary counts changed domain records', () {
    final current = canteraDemoClub.copyWith(
      id: 'club',
      attendanceRecords: const [],
    );
    final local = current.copyWith(
      attendanceRecords: const [
        AttendanceRecord(
          categoryId: 'cat',
          date: '2026-09-08',
          presentIds: ['p1'],
          rosterIds: ['p1'],
        ),
      ],
    );
    expect(summarizeClubDifferences(local, current).attendanceRecords, 1);
  });
}
