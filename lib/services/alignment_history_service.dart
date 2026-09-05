/// Pure helper to suggest a match's lineup from Alineación's saved history,
/// so logging a result doesn't mean re-checking every name from scratch.
/// No Flutter/web dependency (only dart:convert), so this stays
/// unit-testable — reading the actual localStorage entry is the caller's job.
library;

import 'dart:convert';

/// Player ids (XI + subs, in that order) from the most recent saved
/// alignment whose rival matches [rivalName] (case-insensitive, either name
/// containing the other so "Rampla" matches "Rampla FC"). A best-effort
/// suggestion only — never authoritative, and null when nothing matches or
/// the history is empty/unreadable (never throws on bad data).
List<String>? findLineupForRival({
  required String historyJson,
  required String rivalName,
}) {
  final rival = rivalName.trim().toLowerCase();
  if (rival.isEmpty || historyJson.trim().isEmpty) return null;
  try {
    final list = jsonDecode(historyJson) as List<dynamic>;
    for (final item in list) {
      final map = item as Map<String, dynamic>;
      final itemRival = (map['rival'] as String? ?? '').trim().toLowerCase();
      if (itemRival.isEmpty) continue;
      if (!itemRival.contains(rival) && !rival.contains(itemRival)) continue;
      final xi = List<dynamic>.from(map['xi'] as List<dynamic>? ?? const []);
      final subs = List<dynamic>.from(map['subs'] as List<dynamic>? ?? const []);
      final ids = [...xi, ...subs].whereType<String>().toList();
      if (ids.isNotEmpty) return ids;
    }
  } catch (_) {
    // Malformed/legacy history entry — never a reason to crash the flow.
  }
  return null;
}
