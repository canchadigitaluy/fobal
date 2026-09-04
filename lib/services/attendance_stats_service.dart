/// Pure helper to turn saved attendance sessions into a per-player
/// attendance rate. No Flutter/web dependency, so this stays unit-testable.
/// Used only for manual/No-LUD categories — LUD attendance comes from the
/// league sync and must never be overwritten here.
library;

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
