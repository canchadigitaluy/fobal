/// Pure helpers for calendar event identity and its link to a logged match
/// result. No Flutter/web dependency, so this stays unit-testable.
library;

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

int _eventIdSeq = 0;

/// Fresh id for a brand-new event. Not derived from its title, so renaming
/// the event later never breaks its link to a logged result.
String newEventId() {
  _eventIdSeq++;
  return 'evt-${DateTime.now().microsecondsSinceEpoch}-$_eventIdSeq';
}
