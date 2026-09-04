/// Pure helpers for calendar event identity and its link to a logged match
/// result. No Flutter/web dependency, so this stays unit-testable.
library;

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

int _eventIdSeq = 0;

/// Fresh id for a brand-new event. Not derived from its title, so renaming
/// the event later never breaks its link to a logged result.
String newEventId() {
  _eventIdSeq++;
  return 'evt-${DateTime.now().microsecondsSinceEpoch}-$_eventIdSeq';
}
