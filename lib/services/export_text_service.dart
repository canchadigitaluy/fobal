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
