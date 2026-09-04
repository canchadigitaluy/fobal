/// Pure text formatters for what a coach shares from fobal — citación,
/// sesión de entrenamiento, asistencia — plus the shared filename builder.
/// No Flutter/web dependency, so this stays unit-testable.
library;

const Map<String, String> _diacritics = {
  'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u',
  'à': 'a', 'è': 'e', 'ì': 'i', 'ò': 'o', 'ù': 'u',
  'ä': 'a', 'ë': 'e', 'ï': 'i', 'ö': 'o', 'ü': 'u',
  'ñ': 'n', 'ç': 'c',
};

/// Lowercase, dash-separated, filesystem-safe fragment. Never empty. Common
/// Spanish accents fold to their plain letter (so "Citación" -> "citacion",
/// not "citaci-n") so filenames stay readable, not fragmented by dashes.
String sanitizeFileNamePart(String value) {
  var folded = value.trim().toLowerCase();
  _diacritics.forEach((accented, plain) {
    folded = folded.replaceAll(accented, plain);
  });
  final cleaned = folded
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return cleaned.isEmpty ? 'fobal' : cleaned;
}

/// "club-categoria-yyyy-MM-dd-tipo.ext" — readable, sortable, safe to share.
/// [category] is omitted when blank (e.g. a club with a single squad).
String buildExportFileName({
  required String club,
  String? category,
  required String type,
  required String extension,
  DateTime? when,
}) {
  final date = when ?? DateTime.now();
  final stamp = '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
  final parts = [
    sanitizeFileNamePart(club),
    if (category != null && category.trim().isNotEmpty)
      sanitizeFileNamePart(category),
    stamp,
    sanitizeFileNamePart(type),
  ];
  return '${parts.join('-')}.$extension';
}

/// WhatsApp-ready citación text. [titulares] and [suplentes] are already
/// display strings (e.g. "POR — Juan Pérez"); this only adds numbering and
/// the surrounding structure so the caller stays free of Player-model
/// coupling.
String formatCitationText({
  required String title,
  String categoryName = '',
  String rival = '',
  String date = '',
  required List<String> titulares,
  required List<String> suplentes,
  String notes = '',
  /// Prudent, non-diagnostic heads-up lines — e.g. "Juan Pérez: tocado,
  /// confirmar antes del partido" — for citados whose availability isn't
  /// plain "disponible". Never a medical claim, just a reminder to check.
  List<String> availabilityNotes = const [],
}) {
  final lines = <String>[
    'CITACIÓN — ${title.trim().isEmpty ? 'Próximo partido' : title.trim()}',
    if (categoryName.trim().isNotEmpty) categoryName.trim(),
    if (rival.trim().isNotEmpty) 'Rival: ${rival.trim()}',
    if (date.trim().isNotEmpty) 'Fecha: ${date.trim()}',
    '',
    'TITULARES',
    if (titulares.isEmpty)
      'Sin definir todavía.'
    else
      for (var i = 0; i < titulares.length; i++) '${i + 1}. ${titulares[i]}',
    '',
    'SUPLENTES',
    if (suplentes.isEmpty)
      'Sin definir todavía.'
    else
      for (var i = 0; i < suplentes.length; i++) '${i + 1}. ${suplentes[i]}',
    if (availabilityNotes.isNotEmpty) ...[
      '',
      'A CONFIRMAR ANTES DEL PARTIDO',
      for (final note in availabilityNotes) '- $note',
    ],
    if (notes.trim().isNotEmpty) ...['', 'NOTAS', notes.trim()],
    '',
    'Quedan citados para el próximo compromiso. Confirmar disponibilidad a '
        'la brevedad.',
  ];
  return lines.join('\n');
}

/// One training block reduced to just what the text summary needs.
typedef SessionBlockText = ({String name, String duration, String description});

/// Professional, scannable text summary of a generated training session.
String formatSessionText({
  required String title,
  String categoryName = '',
  String scheduledDate = '',
  required int duration,
  required int playerCount,
  String space = '',
  required String objective,
  required List<SessionBlockText> blocks,
  List<String> coachCues = const [],
  List<String> successIndicators = const [],
  List<String> limitations = const [],
}) {
  final meta = [
    '$duration min',
    '$playerCount jugadores',
    if (space.trim().isNotEmpty) space.trim(),
  ].join(' · ');

  final lines = <String>[
    'SESIÓN — ${title.trim().isEmpty ? 'Entrenamiento' : title.trim()}',
    if (categoryName.trim().isNotEmpty) categoryName.trim(),
    if (scheduledDate.trim().isNotEmpty) 'Fecha: ${scheduledDate.trim()}',
    meta,
    '',
    'OBJETIVO',
    objective.trim().isEmpty ? 'Sin definir.' : objective.trim(),
    '',
    'BLOQUES',
    if (blocks.isEmpty)
      'Sin bloques cargados.'
    else
      for (var i = 0; i < blocks.length; i++) ...[
        '${i + 1}. ${blocks[i].name} — ${blocks[i].duration}',
        if (blocks[i].description.trim().isNotEmpty)
          '   ${blocks[i].description.trim()}',
      ],
  ];
  if (coachCues.isNotEmpty) {
    lines
      ..addAll(['', 'CONSIGNAS DEL ENTRENADOR'])
      ..addAll(coachCues.map((cue) => '- $cue'));
  }
  if (successIndicators.isNotEmpty) {
    lines
      ..addAll(['', 'INDICADORES DE ÉXITO'])
      ..addAll(successIndicators.map((item) => '- $item'));
  }
  if (limitations.isNotEmpty) {
    lines
      ..addAll(['', 'A TENER EN CUENTA'])
      ..addAll(limitations.map((item) => '- $item'));
  }
  return lines.join('\n');
}

/// Presentes/ausentes summary for a single practice, in plain readable text.
String formatAttendanceText({
  required String categoryName,
  String date = '',
  required List<String> present,
  required List<String> absent,
}) {
  final total = present.length + absent.length;
  final pct = total == 0 ? 0 : (present.length / total * 100).round();
  final lines = <String>[
    'ASISTENCIA — ${categoryName.trim().isEmpty ? 'Categoría' : categoryName.trim()}',
    if (date.trim().isNotEmpty) date.trim(),
    '',
    'Presentes: ${present.length}/$total ($pct%)',
    '',
    'PRESENTES',
    if (present.isEmpty)
      'Nadie marcado presente todavía.'
    else
      for (var i = 0; i < present.length; i++) '${i + 1}. ${present[i]}',
    '',
    'AUSENTES',
    if (absent.isEmpty)
      'Nadie marcado ausente.'
    else
      for (var i = 0; i < absent.length; i++) '${i + 1}. ${absent[i]}',
  ];
  return lines.join('\n');
}

/// Full match-preparation summary: rival context, game plan, set pieces,
/// availability heads-up and the linked training session, if any. Every
/// section is omitted when empty — never pads with placeholder text.
String formatMatchPreparationText({
  String categoryName = '',
  String rival = '',
  String date = '',
  String time = '',
  String venue = '', // 'local' | 'visitante' | 'neutral' | ''
  String opponentNotes = '',
  String planIdea = '',
  String planObjective = '',
  String offensiveKeys = '',
  String defensiveKeys = '',
  String transitions = '',
  String setPiecesFor = '',
  String setPiecesAgainst = '',
  String playersToWatch = '',
  String staffNotes = '',
  List<String> availabilityNotes = const [],
  String linkedSessionTitle = '',
}) {
  final venueLabel = switch (venue) {
    'local' => 'Local',
    'visitante' => 'Visitante',
    'neutral' => 'Cancha neutral',
    _ => '',
  };
  final lines = <String>[
    'PARTIDO — ${rival.trim().isEmpty ? 'Rival a definir' : rival.trim()}',
    if (categoryName.trim().isNotEmpty) categoryName.trim(),
    if (date.trim().isNotEmpty) 'Fecha: ${date.trim()}',
    if (time.trim().isNotEmpty) 'Hora: ${time.trim()}',
    if (venueLabel.isNotEmpty) 'Condición: $venueLabel',
    if (opponentNotes.trim().isNotEmpty) ...[
      '',
      'RIVAL',
      opponentNotes.trim(),
    ],
    if (planObjective.trim().isNotEmpty || planIdea.trim().isNotEmpty) ...[
      '',
      'PLAN DE JUEGO',
      if (planObjective.trim().isNotEmpty) 'Objetivo: ${planObjective.trim()}',
      if (planIdea.trim().isNotEmpty) planIdea.trim(),
    ],
    if (offensiveKeys.trim().isNotEmpty) ...[
      '',
      'CLAVES OFENSIVAS',
      offensiveKeys.trim(),
    ],
    if (defensiveKeys.trim().isNotEmpty) ...[
      '',
      'CLAVES DEFENSIVAS',
      defensiveKeys.trim(),
    ],
    if (transitions.trim().isNotEmpty) ...[
      '',
      'TRANSICIONES',
      transitions.trim(),
    ],
    if (setPiecesFor.trim().isNotEmpty) ...[
      '',
      'PELOTA QUIETA A FAVOR',
      setPiecesFor.trim(),
    ],
    if (setPiecesAgainst.trim().isNotEmpty) ...[
      '',
      'PELOTA QUIETA EN CONTRA',
      setPiecesAgainst.trim(),
    ],
    if (playersToWatch.trim().isNotEmpty) ...[
      '',
      'JUGADORES A OBSERVAR',
      playersToWatch.trim(),
    ],
    if (availabilityNotes.isNotEmpty) ...[
      '',
      'A CONFIRMAR ANTES DEL PARTIDO',
      for (final note in availabilityNotes) '- $note',
    ],
    if (linkedSessionTitle.trim().isNotEmpty) ...[
      '',
      'ENTRENAMIENTO ASOCIADO',
      linkedSessionTitle.trim(),
    ],
    if (staffNotes.trim().isNotEmpty) ...['', 'NOTAS', staffNotes.trim()],
  ];
  return lines.join('\n');
}

/// Player profile summary — identity, availability, league performance
/// (only when [hasLeagueStats] is true, never fabricated), attendance and
/// individual goals. [goalLines] and stat fields are pre-formatted by the
/// caller so this stays free of Player-model coupling.
String formatPlayerProfileText({
  required String fullName,
  String categoryName = '',
  String position = '',
  List<String> secondaryPositions = const [],
  String dominantFoot = '',
  required String availabilityLabel,
  String availabilityNote = '',
  String expectedReturnDate = '',
  bool hasLeagueStats = false,
  int matchesPlayed = 0,
  int minutesPlayed = 0,
  int goalsScored = 0,
  int assists = 0,
  int yellowCards = 0,
  int redCards = 0,
  double attendanceRate = 0,
  List<String> goalLines = const [],
  String staffNote = '',
}) {
  final positionLine = [
    if (position.trim().isNotEmpty) position.trim(),
    if (secondaryPositions.isNotEmpty) '(tb. ${secondaryPositions.join(', ')})',
  ].join(' ');
  final lines = <String>[
    'PERFIL — ${fullName.trim().isEmpty ? 'Jugador' : fullName.trim()}',
    if (categoryName.trim().isNotEmpty) categoryName.trim(),
    if (positionLine.trim().isNotEmpty) 'Posición: $positionLine',
    if (dominantFoot.trim().isNotEmpty) 'Pie hábil: ${dominantFoot.trim()}',
    '',
    'DISPONIBILIDAD',
    availabilityLabel,
    if (availabilityNote.trim().isNotEmpty) availabilityNote.trim(),
    if (expectedReturnDate.trim().isNotEmpty)
      'Regreso estimado: ${expectedReturnDate.trim()}',
    if (hasLeagueStats) ...[
      '',
      'RENDIMIENTO EN LIGA',
      '$matchesPlayed PJ · $minutesPlayed min · $goalsScored goles · '
          '$assists asistencias',
      if (yellowCards > 0 || redCards > 0)
        '$yellowCards amarillas · $redCards rojas',
    ],
    if (attendanceRate > 0) ...[
      '',
      'ASISTENCIA',
      '${(attendanceRate * 100).round()}% promedio',
    ],
    if (goalLines.isNotEmpty) ...[
      '',
      'OBJETIVOS INDIVIDUALES',
      for (final line in goalLines) '- $line',
    ],
    if (staffNote.trim().isNotEmpty) ...[
      '',
      'NOTAS DEL CUERPO TÉCNICO',
      staffNote.trim(),
    ],
  ];
  return lines.join('\n');
}
