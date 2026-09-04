import 'package:flutter_test/flutter_test.dart';

import 'package:cantera_os/data/cantera_data.dart';
import 'package:cantera_os/services/export_text_service.dart';

void main() {
  group('MatchPreparation serialization', () {
    test('round-trips every field through json', () {
      const prep = MatchPreparation(
        id: 'mp1',
        categoryId: 'cat-1',
        calendarEventId: 'evt-123',
        rival: 'Rampla',
        date: '2026-09-20',
        time: '16:00',
        venue: 'local',
        opponentNotes: 'Presiona alto',
        planIdea: 'Salida corta',
        planObjective: 'Dominar la posesión',
        offensiveKeys: 'Amplitud',
        defensiveKeys: 'Línea alta',
        transitions: 'Recuperar rápido',
        setPiecesFor: 'Córner corto',
        setPiecesAgainst: 'Marca zonal',
        playersToWatch: '9 rival',
        staffNotes: 'Llegar 1h antes',
        linkedSessionId: 'session-1',
        createdAt: '2026-09-01T00:00:00Z',
        updatedAt: '2026-09-02T00:00:00Z',
      );
      final restored = MatchPreparation.fromJson(prep.toJson());
      expect(restored.id, prep.id);
      expect(restored.categoryId, prep.categoryId);
      expect(restored.calendarEventId, prep.calendarEventId);
      expect(restored.rival, prep.rival);
      expect(restored.date, prep.date);
      expect(restored.time, prep.time);
      expect(restored.venue, prep.venue);
      expect(restored.opponentNotes, prep.opponentNotes);
      expect(restored.planIdea, prep.planIdea);
      expect(restored.planObjective, prep.planObjective);
      expect(restored.offensiveKeys, prep.offensiveKeys);
      expect(restored.defensiveKeys, prep.defensiveKeys);
      expect(restored.transitions, prep.transitions);
      expect(restored.setPiecesFor, prep.setPiecesFor);
      expect(restored.setPiecesAgainst, prep.setPiecesAgainst);
      expect(restored.playersToWatch, prep.playersToWatch);
      expect(restored.staffNotes, prep.staffNotes);
      expect(restored.linkedSessionId, prep.linkedSessionId);
      expect(restored.createdAt, prep.createdAt);
      expect(restored.updatedAt, prep.updatedAt);
    });

    test('an empty json still produces a usable record (retrocompat)', () {
      final restored = MatchPreparation.fromJson(const {});
      expect(restored.id, isNotEmpty);
      expect(restored.rival, '');
      expect(restored.calendarEventId, '');
    });

    test('copyWith preserves id/categoryId/calendarEventId/createdAt — the '
        'stable identity fields — while updating editable ones', () {
      const prep = MatchPreparation(
        id: 'mp1',
        categoryId: 'cat-1',
        calendarEventId: 'evt-123',
        rival: 'Rampla',
        createdAt: '2026-09-01T00:00:00Z',
      );
      final updated = prep.copyWith(rival: 'Peñarol', planIdea: 'Nueva idea');
      expect(updated.id, 'mp1');
      expect(updated.categoryId, 'cat-1');
      expect(updated.calendarEventId, 'evt-123');
      expect(updated.createdAt, '2026-09-01T00:00:00Z');
      expect(updated.rival, 'Peñarol');
      expect(updated.planIdea, 'Nueva idea');
    });
  });

  group('asociación estable por calendarEventId', () {
    test('two preparations for the same event share the id — the field the '
        'screen matches on to find an existing plan for a calendar event', () {
      const prepA = MatchPreparation(id: 'mp1', categoryId: 'cat-1', calendarEventId: 'evt-1');
      const prepB = MatchPreparation(id: 'mp2', categoryId: 'cat-1', calendarEventId: 'evt-1');
      expect(prepA.calendarEventId, prepB.calendarEventId);
    });

    test('renaming the rival (a copyWith) never changes calendarEventId — '
        'the link to the calendar event survives an edit', () {
      const original = MatchPreparation(
        id: 'mp1',
        categoryId: 'cat-1',
        calendarEventId: 'evt-1',
        rival: 'Rampla',
      );
      final renamed = original.copyWith(rival: 'Rampla FC');
      expect(renamed.calendarEventId, 'evt-1');
    });
  });

  group('formatMatchPreparationText — exportación de resumen de partido', () {
    test('renders every filled section', () {
      final text = formatMatchPreparationText(
        categoryName: 'Sub 15',
        rival: 'Rampla',
        date: '2026-09-20',
        time: '16:00',
        venue: 'local',
        opponentNotes: 'Presiona alto',
        planObjective: 'Dominar la posesión',
        planIdea: 'Salida corta',
        offensiveKeys: 'Amplitud',
        defensiveKeys: 'Línea alta',
        transitions: 'Recuperar rápido',
        setPiecesFor: 'Córner corto',
        setPiecesAgainst: 'Marca zonal',
        playersToWatch: '9 rival',
        staffNotes: 'Llegar 1h antes',
        linkedSessionTitle: 'Entrenamiento previo al partido',
      );
      expect(text, contains('PARTIDO — Rampla'));
      expect(text, contains('Sub 15'));
      expect(text, contains('Fecha: 2026-09-20'));
      expect(text, contains('Hora: 16:00'));
      expect(text, contains('Condición: Local'));
      expect(text, contains('RIVAL'));
      expect(text, contains('Presiona alto'));
      expect(text, contains('PLAN DE JUEGO'));
      expect(text, contains('Objetivo: Dominar la posesión'));
      expect(text, contains('CLAVES OFENSIVAS'));
      expect(text, contains('CLAVES DEFENSIVAS'));
      expect(text, contains('TRANSICIONES'));
      expect(text, contains('PELOTA QUIETA A FAVOR'));
      expect(text, contains('PELOTA QUIETA EN CONTRA'));
      expect(text, contains('JUGADORES A OBSERVAR'));
      expect(text, contains('ENTRENAMIENTO ASOCIADO'));
      expect(text, contains('Entrenamiento previo al partido'));
      expect(text, contains('NOTAS'));
    });

    test('omits empty sections instead of padding with placeholders', () {
      final text = formatMatchPreparationText(rival: 'Rampla');
      expect(text, isNot(contains('RIVAL')));
      expect(text, isNot(contains('PLAN DE JUEGO')));
      expect(text, isNot(contains('PELOTA QUIETA')));
    });

    test('degrades gracefully with no rival set', () {
      final text = formatMatchPreparationText();
      expect(text, contains('PARTIDO — Rival a definir'));
    });

    test('includes availability alerts with prudent language when there are any', () {
      final text = formatMatchPreparationText(
        rival: 'Rampla',
        availabilityNotes: ['Juan Pérez: lesionado, confirmar antes del partido.'],
      );
      expect(text, contains('A CONFIRMAR ANTES DEL PARTIDO'));
      expect(text, contains('- Juan Pérez: lesionado, confirmar antes del partido.'));
    });
  });
}
