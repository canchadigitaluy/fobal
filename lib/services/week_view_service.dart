import '../data/cantera_data.dart';

DateTime weekStart(DateTime date) {
  final day = DateTime(date.year, date.month, date.day);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

List<DateTime> daysOfWeek(DateTime date) {
  final start = weekStart(date);
  return List.generate(7, (index) => start.add(Duration(days: index)));
}

bool _inWeek(String raw, DateTime start) {
  final date = DateTime.tryParse(raw);
  if (date == null) return false;
  final normalized = DateTime(date.year, date.month, date.day);
  return !normalized.isBefore(start) &&
      normalized.isBefore(start.add(const Duration(days: 7)));
}

List<AttendanceRecord> attendanceForWeek(
  Iterable<AttendanceRecord> records,
  DateTime date, {
  required String categoryId,
}) {
  final start = weekStart(date);
  return records
      .where((r) => r.categoryId == categoryId && _inWeek(r.date, start))
      .toList()
    ..sort((a, b) => a.date.compareTo(b.date));
}

List<MatchResult> matchesForWeek(
  Iterable<MatchResult> results,
  DateTime date, {
  required String categoryId,
}) {
  final start = weekStart(date);
  return results
      .where((r) => r.categoryId == categoryId && _inWeek(r.date, start))
      .toList()
    ..sort((a, b) => a.date.compareTo(b.date));
}

int? minutesForWeek(Iterable<MatchResult> results) {
  var hasData = false;
  var total = 0;
  for (final result in results) {
    if (result.minutesByPlayer.isEmpty) continue;
    hasData = true;
    total += result.minutesByPlayer.values.fold(0, (sum, value) => sum + value);
  }
  return hasData ? total : null;
}
