/// Pure helpers for calendar event identity and its link to a logged match
/// result. No Flutter/web dependency, so this stays unit-testable.
library;

import 'dart:convert';

import '../data/cantera_data.dart';

/// "yyyy-MM-dd" day key — matches the calendar screen's storage map key.
String calendarDayKey(DateTime day) =>
    '${day.year}-${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// Legacy event identity: day key + normalized title. Every event saved
/// before per-event ids existed can be re-derived to this exact string —
/// and it is also what `MatchResult.calendarKey` already holds for any
/// result logged from Calendario before this change, so migrating an old
/// event never breaks an existing result link.
String legacyEventId(String dayKey, String title) =>
    '$dayKey|${title.trim().toLowerCase()}';

/// Normalizes one decoded event map so it always carries a non-empty,
/// stable `id`: keeps an existing one as-is, or derives the pre-migration
/// id from [dayKey] + its title.
Map<String, dynamic> normalizeEventJson(
  Map<String, dynamic> json,
  String dayKey,
) {
  final existing = (json['id'] as String? ?? '').trim();
  if (existing.isNotEmpty) return json;
  final title = json['title'] as String? ?? '';
  return {...json, 'id': legacyEventId(dayKey, title)};
}

/// Sessions from Planificar/Constructor scheduled on [day] — matched by
/// calendar day key so a session's plain "yyyy-MM-dd" scheduledDate always
/// lines up with the calendar's own day keys. A session with no date, or an
/// unparseable one, matches nothing (never guessed). This lets Calendario
/// show a planned session without it having to also exist as a separate
/// hand-created event — one date entered once, not twice.
List<TrainingSession> sessionsOnDay(List<TrainingSession> sessions, DateTime day) {
  final key = calendarDayKey(day);
  return sessions.where((session) {
    final date = DateTime.tryParse(session.scheduledDate);
    return date != null && calendarDayKey(date) == key;
  }).toList();
}

/// Past match events (type Partido/Torneo) that still have no logged
/// result. [calendarJson] is the raw localStorage value for a category's
/// calendar — a `dayKey -> [eventJson]` map. Matched to results by the
/// event's stable id == [MatchResult.calendarKey]. Never throws on bad
/// data; future days are skipped.
List<({String title, String dayKey})> pendingMatchResults(
  String calendarJson,
  List<MatchResult> results, {
  DateTime? now,
}) {
  if (calendarJson.trim().isEmpty) return const [];
  final logged = {
    for (final r in results)
      if (r.calendarKey.isNotEmpty) r.calendarKey,
  };
  final today = calendarDayKey(now ?? DateTime.now());
  final out = <({String title, String dayKey})>[];
  try {
    final data = jsonDecode(calendarJson) as Map<String, dynamic>;
    for (final entry in data.entries) {
      if (entry.key.compareTo(today) > 0) continue;
      for (final raw in (entry.value as List<dynamic>? ?? const [])) {
        final map = normalizeEventJson(raw as Map<String, dynamic>, entry.key);
        final type = map['type'] as String? ?? '';
        if (type != 'Partido' && type != 'Torneo') continue;
        final id = (map['id'] as String? ?? '').trim();
        if (id.isEmpty || logged.contains(id)) continue;
        out.add((
          title: (map['title'] as String? ?? 'Partido').trim(),
          dayKey: entry.key,
        ));
      }
    }
  } catch (_) {
    return const [];
  }
  out.sort((a, b) => b.dayKey.compareTo(a.dayKey));
  return out;
}

int _eventIdSeq = 0;

/// Fresh id for a brand-new event. Not derived from its title, so renaming
/// the event later never breaks its link to a logged result.
String newEventId() {
  _eventIdSeq++;
  return 'evt-${DateTime.now().microsecondsSinceEpoch}-$_eventIdSeq';
}
