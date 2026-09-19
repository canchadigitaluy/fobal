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

/// Prefijo del id de los eventos que nacen del fixture de la liga. El id
/// derivado del partido es estable, asi que sincronizar dos veces (o desde
/// dos dispositivos) nunca duplica.
const fixtureEventPrefix = 'fixture-';

/// Un partido del fixture ya traducido a lo que necesita la agenda.
class FixtureSlot {
  final String id;
  final String dayKey; // yyyy-MM-dd
  final String time; // HH:mm o '' si la liga no publico hora
  final String opponent;
  final String notes;

  const FixtureSlot({
    required this.id,
    required this.dayKey,
    required this.time,
    required this.opponent,
    this.notes = '',
  });
}

/// Dia y hora del partido en hora de Uruguay (UTC-3, sin horario de verano).
/// La liga publica "2026-09-19T13:30:00" sin zona: ya es hora de pared y se
/// toma tal cual. Si trae zona (Z o +hh:mm) se pasa a UTC-3. Sin hora en el
/// texto (solo fecha) devuelve solo el dia — [fallback] viene con un 12:00
/// de relleno que no debe mostrarse como hora real.
({String dayKey, String time}) parseKickoff(String rawDate, DateTime fallback) {
  final raw = rawDate.trim();
  final wall = RegExp(
    r'(\d{4})-(\d{2})-(\d{2})[T ](\d{1,2}):(\d{2})',
  ).firstMatch(raw);
  if (wall != null) {
    final hasZone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(raw);
    if (hasZone) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) {
        final uy = parsed.toUtc().subtract(const Duration(hours: 3));
        return (
          dayKey: calendarDayKey(uy),
          time:
              '${uy.hour.toString().padLeft(2, '0')}:'
              '${uy.minute.toString().padLeft(2, '0')}',
        );
      }
    }
    return (
      dayKey: '${wall[1]}-${wall[2]}-${wall[3]}',
      time: '${wall[4]!.padLeft(2, '0')}:${wall[5]}',
    );
  }
  return (dayKey: calendarDayKey(fallback.toUtc()), time: '');
}

/// Vuelca el fixture en el calendario de una categoria. [calendar] es el
/// mapa crudo `dayKey -> [evento json]`. Reglas:
///  * un partido ya presente (por id) no se duplica; si la liga lo movio de
///    dia se mueve, y si trae hora distinta se actualiza la hora;
///  * un dia que ya tiene un Partido/Torneo cargado a mano se respeta;
///  * un id en [dismissed] (el DT lo borro) no vuelve a aparecer.
({Map<String, List<Map<String, dynamic>>> calendar, bool changed})
mergeFixtureIntoCalendar(
  Map<String, List<Map<String, dynamic>>> calendar,
  List<FixtureSlot> slots, {
  Set<String> dismissed = const {},
}) {
  final next = {
    for (final entry in calendar.entries)
      entry.key: [for (final item in entry.value) Map<String, dynamic>.of(item)],
  };
  var changed = false;
  for (final slot in slots) {
    if (dismissed.contains(slot.id)) continue;
    String? foundDay;
    var foundIndex = -1;
    for (final entry in next.entries) {
      final index = entry.value.indexWhere((item) => item['id'] == slot.id);
      if (index >= 0) {
        foundDay = entry.key;
        foundIndex = index;
        break;
      }
    }
    if (foundDay != null) {
      final event = next[foundDay]![foundIndex];
      var touched = false;
      if (slot.time.isNotEmpty && event['time'] != slot.time) {
        event['time'] = slot.time;
        touched = true;
      }
      if (foundDay != slot.dayKey) {
        next[foundDay]!.removeAt(foundIndex);
        if (next[foundDay]!.isEmpty) next.remove(foundDay);
        next.putIfAbsent(slot.dayKey, () => []).add(event);
        touched = true;
      }
      changed = changed || touched;
      continue;
    }
    final sameDay = next[slot.dayKey] ?? const <Map<String, dynamic>>[];
    final dayHasMatch = sameDay.any(
      (item) => item['type'] == 'Partido' || item['type'] == 'Torneo',
    );
    if (dayHasMatch) continue;
    next.putIfAbsent(slot.dayKey, () => []).add({
      'id': slot.id,
      'type': 'Partido',
      'title': slot.opponent,
      'time': slot.time,
      'notes': slot.notes,
    });
    changed = true;
  }
  return (calendar: next, changed: changed);
}

int _eventIdSeq = 0;

/// Fresh id for a brand-new event. Not derived from its title, so renaming
/// the event later never breaks its link to a logged result.
String newEventId() {
  _eventIdSeq++;
  return 'evt-${DateTime.now().microsecondsSinceEpoch}-$_eventIdSeq';
}
