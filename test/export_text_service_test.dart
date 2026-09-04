import 'package:flutter_test/flutter_test.dart';

import 'package:cantera_os/services/export_text_service.dart';

void main() {
  group('sanitizeFileNamePart', () {
    test('lowercases and dashes non-alphanumeric runs', () {
      expect(sanitizeFileNamePart('Atenas F.C.'), 'atenas-f-c');
      expect(sanitizeFileNamePart('  Sub 15  '), 'sub-15');
    });

    test('trims leading/trailing dashes and never returns empty', () {
      expect(sanitizeFileNamePart('***'), 'fobal');
      expect(sanitizeFileNamePart(''), 'fobal');
    });

    test('folds common Spanish accents instead of dashing them out', () {
      expect(sanitizeFileNamePart('Citación'), 'citacion');
      expect(sanitizeFileNamePart('Peñarol Niños'), 'penarol-ninos');
    });
  });

  group('buildExportFileName', () {
    test('builds club-categoria-fecha-tipo.ext', () {
      final name = buildExportFileName(
        club: 'Atenas',
        category: 'Sub 15',
        type: 'Citación',
        extension: 'txt',
        when: DateTime(2026, 3, 5),
      );
      expect(name, 'atenas-sub-15-2026-03-05-citacion.txt');
    });

    test('omits the category segment when blank', () {
      final name = buildExportFileName(
        club: 'Atenas',
        category: '',
        type: 'backup',
        extension: 'json',
        when: DateTime(2026, 3, 5),
      );
      expect(name, 'atenas-2026-03-05-backup.json');
    });
  });

  group('formatCitationText', () {
    test('renders a complete citación with all sections', () {
      final text = formatCitationText(
        title: 'Vs Rampla',
        categoryName: 'Sub 15',
        rival: 'Rampla',
        date: 'Sábado 14, 16:00',
        titulares: ['POR — Juan Pérez', 'LI — Ana Gómez'],
        suplentes: ['Marcos Díaz'],
        notes: 'Traer petos.',
      );
      expect(text, contains('CITACIÓN — Vs Rampla'));
      expect(text, contains('Sub 15'));
      expect(text, contains('Rival: Rampla'));
      expect(text, contains('Fecha: Sábado 14, 16:00'));
      expect(text, contains('1. POR — Juan Pérez'));
      expect(text, contains('2. LI — Ana Gómez'));
      expect(text, contains('1. Marcos Díaz'));
      expect(text, contains('NOTAS'));
      expect(text, contains('Traer petos.'));
    });

    test('degrades gracefully with incomplete data', () {
      final text = formatCitationText(
        title: '',
        titulares: const [],
        suplentes: const [],
      );
      expect(text, contains('CITACIÓN — Próximo partido'));
      expect(text, contains('Sin definir todavía.'));
      expect(text, isNot(contains('Rival:')));
      expect(text, isNot(contains('NOTAS')));
    });

    test('includes a prudent availability warning section when there is one', () {
      final text = formatCitationText(
        title: 'Vs Rampla',
        titulares: ['POR — Juan Pérez'],
        suplentes: const [],
        availabilityNotes: [
          'Juan Pérez: tocado, confirmar antes del partido.',
        ],
      );
      expect(text, contains('A CONFIRMAR ANTES DEL PARTIDO'));
      expect(text, contains('- Juan Pérez: tocado, confirmar antes del partido.'));
    });

    test('omits the warning section when nobody has one', () {
      final text = formatCitationText(
        title: 'Vs Rampla',
        titulares: const [],
        suplentes: const [],
      );
      expect(text, isNot(contains('A CONFIRMAR ANTES DEL PARTIDO')));
    });
  });

  group('formatSessionText', () {
    test('lists blocks, cues and indicators', () {
      final text = formatSessionText(
        title: 'Presión alta',
        categoryName: 'Sub 17',
        scheduledDate: '2026-03-05',
        duration: 75,
        playerCount: 18,
        space: 'Media cancha',
        objective: 'Mejorar la salida corta',
        blocks: const [
          (name: 'Rondo 4v2', duration: '15 min', description: 'Espacio reducido'),
          (name: 'Juego 8v8', duration: '30 min', description: ''),
        ],
        coachCues: const ['Presionar al primer pase'],
        successIndicators: const ['Recuperar en 5 segundos'],
        limitations: const ['Sin datos de rival'],
      );
      expect(text, contains('SESIÓN — Presión alta'));
      expect(text, contains('75 min · 18 jugadores · Media cancha'));
      expect(text, contains('1. Rondo 4v2 — 15 min'));
      expect(text, contains('   Espacio reducido'));
      expect(text, contains('2. Juego 8v8 — 30 min'));
      expect(text, contains('CONSIGNAS DEL ENTRENADOR'));
      expect(text, contains('- Presionar al primer pase'));
      expect(text, contains('INDICADORES DE ÉXITO'));
      expect(text, contains('A TENER EN CUENTA'));
    });

    test('handles a session with no blocks or extras', () {
      final text = formatSessionText(
        title: '',
        duration: 60,
        playerCount: 16,
        objective: '',
        blocks: const [],
      );
      expect(text, contains('SESIÓN — Entrenamiento'));
      expect(text, contains('Sin definir.'));
      expect(text, contains('Sin bloques cargados.'));
      expect(text, isNot(contains('CONSIGNAS')));
    });
  });

  group('formatAttendanceText', () {
    test('computes the percentage and lists both groups', () {
      final text = formatAttendanceText(
        categoryName: 'Sub 15',
        date: '2026-03-05',
        present: ['Ana', 'Beto', 'Caro'],
        absent: ['Dani'],
      );
      expect(text, contains('ASISTENCIA — Sub 15'));
      expect(text, contains('Presentes: 3/4 (75%)'));
      expect(text, contains('1. Ana'));
      expect(text, contains('1. Dani'));
    });

    test('handles nobody marked yet without dividing by zero', () {
      final text = formatAttendanceText(
        categoryName: 'Sub 15',
        present: const [],
        absent: const [],
      );
      expect(text, contains('Presentes: 0/0 (0%)'));
      expect(text, contains('Nadie marcado presente todavía.'));
      expect(text, contains('Nadie marcado ausente.'));
    });
  });

  group('formatSquadReportText — reporte consolidado del plantel', () {
    test('renders every filled section', () {
      final generatedAt = DateTime(2026, 9, 4);
      final text = formatSquadReportText(
        clubName: 'Atenas',
        categoryName: 'Sub 15',
        generatedAt: generatedAt,
        totalPlayers: 20,
        availablePlayers: 18,
        availabilityWarnings: ['Juan Pérez: Lesionado'],
        attendanceAverage: 0.82,
        activeGoals: 4,
        completedGoals: 2,
        topGoalLines: ['Mejorar el remate (Técnica) — En progreso'],
        matchesPlayed: 10,
        wins: 6,
        draws: 2,
        losses: 2,
      );
      expect(text, contains('REPORTE DEL PLANTEL — Atenas'));
      expect(text, contains('Sub 15'));
      expect(text, contains('04/09/2026'));
      expect(text, contains('20 jugadores · 18 disponibles'));
      expect(text, contains('A CONFIRMAR / SEGUIMIENTO'));
      expect(text, contains('- Juan Pérez: Lesionado'));
      expect(text, contains('82% promedio del plantel'));
      expect(text, contains('4 en curso · 2 logrados'));
      expect(text, contains('- Mejorar el remate (Técnica) — En progreso'));
      expect(text, contains('10 jugados · 6G 2E 2P'));
    });

    test('omits every optional section when there is no data', () {
      final text = formatSquadReportText(
        clubName: 'Atenas',
        totalPlayers: 5,
        availablePlayers: 5,
      );
      expect(text, isNot(contains('A CONFIRMAR / SEGUIMIENTO')));
      expect(text, isNot(contains('ASISTENCIA')));
      expect(text, isNot(contains('OBJETIVOS INDIVIDUALES')));
      expect(text, isNot(contains('RESULTADOS')));
    });

    test('never divides by a null matchesPlayed / shows record only when real', () {
      final text = formatSquadReportText(
        clubName: 'Atenas',
        totalPlayers: 5,
        availablePlayers: 5,
        matchesPlayed: 0,
      );
      expect(text, isNot(contains('RESULTADOS')));
    });
  });
}
