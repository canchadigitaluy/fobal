import 'package:flutter_test/flutter_test.dart';

import 'package:cantera_os/services/training_note_parser.dart';

void main() {
  group('ParsedTrainingNote.fromText', () {
    test('empty text -> empty note, not saveable', () {
      final n = ParsedTrainingNote.fromText('   ');
      expect(n.isEmpty, isTrue);
      expect(n.canSave, isFalse);
    });

    test('extracts attendance from "asistieron 16 de 20"', () {
      final n = ParsedTrainingNote.fromText('Asistieron 16 de 20. Trabajamos salida.');
      expect(n.attendance, contains('16 de 20'));
      expect(n.objective, contains('salida'));
      expect(n.canSave, isTrue);
    });

    test('extracts positivo / a mejorar / destacados / lesion', () {
      final n = ParsedTrainingNote.fromText(
        'positivo: intensidad alta. a mejorar: los pases largos. '
        'destacaron Juan, Pedro y Ariel. lesion: Tomás',
      );
      expect(n.positive, contains('intensidad'));
      expect(n.toImprove, contains('pases largos'));
      expect(n.highlighted, contains('Juan'));
      expect(n.injuries, contains('Tomás'));
    });

    test('toReport splits names on comma and " y ", counts attendance', () {
      final n = ParsedTrainingNote.fromText(
        'presentes: 14. destacados: Ana, Bea y Cata',
      );
      final report = n.toReport(categoryId: 'cat-1', totalPlayers: 20);
      expect(report.attendanceCount, 14);
      expect(report.totalPlayers, 20);
      expect(report.highlightedPlayers, ['Ana', 'Bea', 'Cata']);
    });

    test('totalPlayers falls back to attendance count when unknown', () {
      final n = ParsedTrainingNote.fromText('asistencia: 12');
      final report = n.toReport(categoryId: 'c', totalPlayers: 0);
      expect(report.totalPlayers, 12);
    });
  });

  group('trainingReportDate', () {
    test('parses DD/MM/YYYY so 05/09 sorts after 28/08 (chronological)', () {
      final a = trainingReportDate('28/08/2026');
      final b = trainingReportDate('05/09/2026');
      expect(b.isAfter(a), isTrue);
    });

    test('also accepts ISO yyyy-MM-dd', () {
      expect(trainingReportDate('2026-09-05'), DateTime(2026, 9, 5));
    });

    test('unparseable -> epoch, sorts oldest', () {
      expect(trainingReportDate('en un rato'),
          DateTime.fromMillisecondsSinceEpoch(0));
    });
  });
}
