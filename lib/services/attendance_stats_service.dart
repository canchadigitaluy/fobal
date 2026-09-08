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

double? attendanceRecordRate(AttendanceRecord record) {
  if (record.rosterIds.isEmpty) return null;
  return record.presentIds.where(record.rosterIds.contains).length /
      record.rosterIds.length;
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
