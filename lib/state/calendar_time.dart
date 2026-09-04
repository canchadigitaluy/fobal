/// Pure time helpers for calendar events — no Flutter/web dependency so they
/// stay unit-testable. Times are always stored/displayed as 24h "HH:mm".
library;

/// Formats an hour/minute pair as zero-padded 24h "HH:mm".
String formatHm(int hour, int minute) =>
    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

/// Parses a free-text time value into an (hour, minute) pair.
///
/// Accepts "H:mm", "HH:mm", "H.mm" and "HHmm" with optional surrounding
/// whitespace. Returns null when the value isn't a recognizable time —
/// callers should fall back to no preset rather than guessing.
({int hour, int minute})? parseHm(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  final match = RegExp(r'^(\d{1,2})[:.h]?(\d{2})$').firstMatch(trimmed);
  if (match == null) return null;
  final hour = int.tryParse(match.group(1)!);
  final minute = int.tryParse(match.group(2)!);
  if (hour == null || minute == null) return null;
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
  return (hour: hour, minute: minute);
}
