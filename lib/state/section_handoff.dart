// Payloads carried between shell sections when a read turns into an action.
// Pure value objects — no Flutter — so the derivation logic below is
// unit-tested.

/// Seeds the training planner: what to work on and why.
class SessionFocusHandoff {
  final String objective;
  final String problem;
  final String context; // one short line: form + origin
  final String origin; // 'Lectura de la semana' | 'Estadísticas'

  const SessionFocusHandoff({
    required this.objective,
    this.problem = '',
    this.context = '',
    this.origin = '',
  });
}

/// Seeds the match-preparation form. Only factual context (form, table); never
/// an invented tactical system.
class MatchPrepHandoff {
  final String rivalName;
  final String rivalContext;
  final String note;
  final String origin;
  // Stable id of the calendar event this prep came from, if any — lets the
  // planner link the session it generates back to that match's prep, the
  // same stable-id pattern MatchPreparation itself uses.
  final String calendarEventId;

  const MatchPrepHandoff({
    this.rivalName = '',
    this.rivalContext = '',
    this.note = '',
    this.origin = '',
    this.calendarEventId = '',
  });
}

/// A non-binding nudge for the lineup / call-up screen. Highlights players,
/// never builds an XI. May also carry the match's rival/date/time so the
/// lineup form prefills them instead of the DT retyping what the match prep
/// already has.
class LineupHint {
  final String reason;
  final List<String> players;
  final String rival;
  final String date;
  final String time;

  const LineupHint({
    this.reason = '',
    this.players = const [],
    this.rival = '',
    this.date = '',
    this.time = '',
  });
}

/// Plain shortcuts the dashboard can jump to. The shell resolves each to the
/// right section for the current layout (LUD vs No-LUD), so no screen hardcodes
/// a navigation index.
enum ShellSection { myTeam, planner, calendar, attendance, stats, week, lineup }

/// Turns a performance read into one concrete training focus. Deterministic;
/// never invents numbers. Returns null when nothing is clearly off — in that
/// case the reading shows no "prepare training" action rather than a vague one.
SessionFocusHandoff? deriveSessionFocus({
  required double scoring, // goals for per game
  required double conceding, // goals against per game
  double? leagueScoring,
  double? leagueConceding,
  required int played,
  String formSummary = '',
  String origin = 'Lectura de la semana',
}) {
  if (played < 2) return null;

  final offenseGap = (leagueScoring ?? 1.4) - scoring; // >0 => under-producing
  final defenseGap = conceding - (leagueConceding ?? 1.3); // >0 => leaking

  final worthOffense = offenseGap > 0.15 || scoring < 1.1;
  final worthDefense = defenseGap > 0.15 || conceding > 1.5;

  String objective;
  String problem;
  if (worthDefense && (!worthOffense || defenseGap >= offenseGap)) {
    objective = 'Reforzar la solidez defensiva y la cobertura tras pérdida';
    problem =
        'El equipo recibe ${conceding.toStringAsFixed(1)} goles por partido'
        '${leagueConceding != null ? ' (media de la categoría ${leagueConceding.toStringAsFixed(1)})' : ''}.';
  } else if (worthOffense) {
    objective = 'Mejorar la finalización y el volumen ofensivo';
    problem =
        'El equipo genera poco: ${scoring.toStringAsFixed(1)} goles por partido'
        '${leagueScoring != null ? ' (media de la categoría ${leagueScoring.toStringAsFixed(1)})' : ''}.';
  } else {
    return null;
  }

  final context = [
    if (formSummary.trim().isNotEmpty) formSummary.trim(),
    'Origen: $origin',
  ].join(' · ');

  return SessionFocusHandoff(
    objective: objective,
    problem: problem,
    context: context,
    origin: origin,
  );
}
