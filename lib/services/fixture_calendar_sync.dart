// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:convert';
import 'dart:html' as html;

import '../state/calendar_events.dart';
import 'club_access_service.dart';

/// Pasa el fixture de la liga a la agenda de la categoria. La logica de
/// fusion vive en `mergeFixtureIntoCalendar` (pura); aca solo el pegamento
/// con localStorage, que es donde Calendario guarda sus eventos.
class FixtureCalendarSync {
  const FixtureCalendarSync._();

  /// Misma clave que usa CalendarioScreen.
  static String storageKey(String clubId, String categoryId) =>
      'cantera_calendar_${clubId}_$categoryId';

  static String _dismissedKey(String calendarKey) =>
      '${calendarKey}_fixture_dismissed';

  static List<FixtureSlot> slots(List<LudFixtureMatch> matches) {
    return [
      for (final match in matches)
        if (match.hasValidDate && match.opponentName.trim().isNotEmpty)
          _slot(match),
    ];
  }

  static FixtureSlot _slot(LudFixtureMatch match) {
    final kickoff = parseKickoff(match.rawDate, match.date);
    final opponent = match.opponentName.trim();
    final side = match.awayTeamName.trim() == opponent
        ? 'Local'
        : match.homeTeamName.trim() == opponent
        ? 'Visitante'
        : '';
    return FixtureSlot(
      id: '$fixtureEventPrefix${match.id}',
      dayKey: kickoff.dayKey,
      time: kickoff.time,
      opponent: opponent,
      notes: [
        match.round.trim(),
        side,
        match.venue.trim(),
      ].where((part) => part.isNotEmpty).join(' · '),
    );
  }

  /// Ids de partidos del fixture que el DT borro a mano: no se re-agregan.
  static Set<String> dismissed(String calendarKey) {
    try {
      final raw = html.window.localStorage[_dismissedKey(calendarKey)];
      if (raw == null || raw.isEmpty) return {};
      return (jsonDecode(raw) as List<dynamic>).whereType<String>().toSet();
    } catch (_) {
      return {};
    }
  }

  static void dismiss(String calendarKey, String eventId) {
    final next = dismissed(calendarKey)..add(eventId);
    html.window.localStorage[_dismissedKey(calendarKey)] = jsonEncode(
      next.toList(),
    );
  }

  /// Aplica el fixture directo sobre localStorage (para pantallas que no son
  /// Calendario, ej. Inicio). No sube nada al servidor: cada dispositivo
  /// deriva los mismos ids, y Calendario empuja el snapshot completo cuando
  /// el DT edita. Devuelve true si cambio algo.
  static bool applyToStorage(String calendarKey, List<LudFixtureMatch> matches) {
    try {
      final raw = html.window.localStorage[calendarKey];
      final current = <String, List<Map<String, dynamic>>>{};
      if (raw != null && raw.isNotEmpty) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        for (final entry in data.entries) {
          current[entry.key] = [
            for (final item in (entry.value as List<dynamic>))
              if (item is Map) Map<String, dynamic>.from(item),
          ];
        }
      }
      final result = mergeFixtureIntoCalendar(
        current,
        slots(matches),
        dismissed: dismissed(calendarKey),
      );
      if (!result.changed) return false;
      html.window.localStorage[calendarKey] = jsonEncode(result.calendar);
      return true;
    } catch (_) {
      return false;
    }
  }
}
