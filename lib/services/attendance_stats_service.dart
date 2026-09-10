import '../data/cantera_data.dart';

// Pure attendance helpers. This file has no Flutter/web dependency so the
// distinction between missing data and a real zero remains unit-testable.

/// One saved attendance session: just who was marked present.
class AttendanceSession {
  final Set<String> presentIds;
  const AttendanceSession({required this.presentIds});
}

/// player id -> rate (0..1), one entry per id in [playerIds]. Returns an
/// empty map when there are no saved sessions yet — never invents a 0%
/// before the first practice was taken.
Map<String, double> computeAttendanceRates({
  required List<AttendanceSession> sessions,
  required List<String> playerIds,
}) {
  if (sessions.isEmpty) return {};
  final total = sessions.length;
  return {
    for (final id in playerIds)
      id: sessions.where((s) => s.presentIds.contains(id)).length / total,
  };
}

/// Plain mean of a squad's attendance rates, for the "Asistencia" stat
/// tile. Null when there's no data yet — never shows a fake 0%.
double? averageAttendanceRate(List<double> rates) =>
    rates.isEmpty ? null : rates.reduce((a, b) => a + b) / rates.length;

DateTime attendanceRecordDate(String value) =>
    DateTime.tryParse(value)?.toLocal() ??
    DateTime.fromMillisecondsSinceEpoch(0);

/// Attendance rate for one session: (present + late) / (players expected).
/// Injured players and granted leave drop out of the denominator, so they
/// never drag a rate down. Null when nobody was expected or there is no
/// roster snapshot.
double? attendanceRecordRate(AttendanceRecord record) {
  if (record.rosterIds.isEmpty) return null;
  var attended = 0;
  var expected = 0;
  for (final id in record.rosterIds) {
    final status = record.effectiveStatus(id);
    if (status.expected) expected++;
    if (status.attended) attended++;
  }
  if (expected == 0) return null;
  return attended / expected;
}

/// Count of each [AttendanceStatus] across the roster snapshot of [record].
Map<AttendanceStatus, int> attendanceStatusBreakdown(AttendanceRecord record) {
  final counts = <AttendanceStatus, int>{};
  for (final id in record.rosterIds) {
    final status = record.effectiveStatus(id);
    counts[status] = (counts[status] ?? 0) + 1;
  }
  return counts;
}

/// player id -> rate (0..1) across [records], status-aware. Empty map when
/// there are no records — never invents a 0%.
Map<String, double> computeAttendanceRatesFromRecords({
  required List<AttendanceRecord> records,
  required List<String> playerIds,
}) {
  if (records.isEmpty) return {};
  final result = <String, double>{};
  for (final id in playerIds) {
    var attended = 0;
    var expected = 0;
    for (final record in records) {
      if (!record.rosterIds.contains(id)) continue;
      final status = record.effectiveStatus(id);
      if (status.expected) expected++;
      if (status.attended) attended++;
    }
    result[id] = expected == 0 ? 0 : attended / expected;
  }
  return result;
}

class AttendanceSummary {
  final int sessions;
  final double? average;
  final double? recentAverage;
  final double? previousAverage;

  const AttendanceSummary({
    required this.sessions,
    required this.average,
    required this.recentAverage,
    required this.previousAverage,
  });

  double? get trend {
    if (recentAverage == null || previousAverage == null) return null;
    return recentAverage! - previousAverage!;
  }
}

AttendanceSummary summarizeAttendance(List<AttendanceRecord> records) {
  final usable = records.where((record) => record.rosterIds.isNotEmpty).toList()
    ..sort(
      (a, b) =>
          attendanceRecordDate(b.date).compareTo(attendanceRecordDate(a.date)),
    );
  if (usable.isEmpty) {
    return const AttendanceSummary(
      sessions: 0,
      average: null,
      recentAverage: null,
      previousAverage: null,
    );
  }
  double rate(AttendanceRecord record) => attendanceRecordRate(record)!;
  double mean(List<AttendanceRecord> values) =>
      values.map(rate).reduce((a, b) => a + b) / values.length;
  final split = usable.length.clamp(1, 3);
  final recent = usable.take(split).toList();
  final previous = usable.skip(split).take(split).toList();
  return AttendanceSummary(
    sessions: usable.length,
    average: mean(usable),
    recentAverage: mean(recent),
    previousAverage: previous.isEmpty ? null : mean(previous),
  );
}
