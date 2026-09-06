/// Offline heuristic parser that turns a coach's free-text / dictated
/// post-training note into a structured [TrainingReport]. No AI, no network,
/// no Flutter/web dependency — pure regex extraction, so it stays
/// unit-testable and works with the tab in airplane mode.
library;

import '../data/cantera_data.dart';

/// Comparable key for a [TrainingReport.date] — which this parser writes as
/// "DD/MM/YYYY" (not sortable as a plain string). Also tolerates a plain
/// ISO "yyyy-MM-dd". Unparseable dates sort oldest.
DateTime trainingReportDate(String date) {
  final d = date.trim();
  final dmy = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(d);
  if (dmy != null) {
    return DateTime(
      int.parse(dmy.group(3)!),
      int.parse(dmy.group(2)!),
      int.parse(dmy.group(1)!),
    );
  }
  return DateTime.tryParse(d) ?? DateTime.fromMillisecondsSinceEpoch(0);
}

class ParsedTrainingNote {
  final String attendance;
  final String objective;
  final String positive;
  final String toImprove;
  final String highlighted;
  final String injuries;
  final String nextFocus;

  const ParsedTrainingNote({
    required this.attendance,
    required this.objective,
    required this.positive,
    required this.toImprove,
    required this.highlighted,
    required this.injuries,
    required this.nextFocus,
  });

  bool get isEmpty =>
      attendance.isEmpty &&
      objective.isEmpty &&
      positive.isEmpty &&
      toImprove.isEmpty &&
      highlighted.isEmpty &&
      injuries.isEmpty &&
      nextFocus.isEmpty;

  bool get canSave => attendance.isNotEmpty || objective.isNotEmpty;

  TrainingReport toReport({
    required String categoryId,
    required int totalPlayers,
  }) {
    final attendanceCount = _firstNumber(attendance);
    return TrainingReport(
      categoryId: categoryId,
      date: _todayLabel(),
      attendanceCount: attendanceCount,
      totalPlayers: totalPlayers > 0 ? totalPlayers : attendanceCount,
      objectiveWorked: objective,
      whatWentWell: positive,
      whatWentWrong: toImprove,
      highlightedPlayers: _splitNames(highlighted),
      injuries: _splitNames(injuries),
      nextRecommendation: nextFocus,
    );
  }

  static int _firstNumber(String value) {
    final match = RegExp(r'\d+').firstMatch(value);
    return int.tryParse(match?.group(0) ?? '') ?? 0;
  }

  static List<String> _splitNames(String value) {
    return value
        .split(RegExp(r',| y '))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  static String _todayLabel() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(now.day)}/${two(now.month)}/${now.year}';
  }

  factory ParsedTrainingNote.fromText(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return const ParsedTrainingNote(
        attendance: '',
        objective: '',
        positive: '',
        toImprove: '',
        highlighted: '',
        injuries: '',
        nextFocus: '',
      );
    }

    String find(List<RegExp> patterns) {
      for (final pattern in patterns) {
        final match = pattern.firstMatch(text);
        if (match != null) {
          return (match.group(1) ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
        }
      }
      return '';
    }

    final attendance = find([
      RegExp(
        r'(?:asistieron|asistencia|presentes?)\s*:?\s*([^.;\n]+)',
        caseSensitive: false,
      ),
      RegExp(
        r'(\d+\s*(?:de|/)\s*\d+)\s*(?:presentes|asistieron|jugadores)?',
        caseSensitive: false,
      ),
    ]);

    return ParsedTrainingNote(
      attendance: attendance,
      objective: find([
        RegExp(
          r'(?:objetivo|trabajamos|se trabajo)\s*:?\s*([^.;\n]+)',
          caseSensitive: false,
        ),
      ]),
      positive: find([
        RegExp(
          r'(?:positivo|bien|fortaleza)\s*:?\s*([^.;\n]+)',
          caseSensitive: false,
        ),
      ]),
      toImprove: find([
        RegExp(
          r'(?:a mejorar|mejorar|debilidad|problema)\s*:?\s*([^.;\n]+)',
          caseSensitive: false,
        ),
      ]),
      highlighted: find([
        RegExp(
          r'(?:destacados?|destaco|destacaron)\s*:?\s*([^.;\n]+)',
          caseSensitive: false,
        ),
      ]),
      injuries: find([
        RegExp(
          r'(?:lesion|lesionado|molestia)\s*:?\s*([^.;\n]+)',
          caseSensitive: false,
        ),
      ]),
      nextFocus: find([
        RegExp(
          r'(?:proximo foco|siguiente foco|proxima sesion)\s*:?\s*([^.;\n]+)',
          caseSensitive: false,
        ),
      ]),
    );
  }
}
