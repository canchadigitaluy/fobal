import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cantera_os/data/cantera_data.dart';
import 'package:cantera_os/state/calendar_events.dart';

TrainingSession _session({
  String id = 's1',
  String scheduledDate = '',
  String status = 'planned',
}) {
  return TrainingSession(
    id: id,
    categoryId: 'cat-1',
    title: 'Sesión',
    objective: '',
    duration: 60,
    space: '',
    playerCount: 18,
    generatedByAi: false,
    status: status,
    scheduledDate: scheduledDate,
    blocks: const [],
    coachCues: const [],
    successIndicators: const [],
  );
}

void main() {
  group('calendarDayKey', () {
    test('zero-pads month and day', () {
      expect(calendarDayKey(DateTime(2026, 3, 5)), '2026-03-05');
      expect(calendarDayKey(DateTime(2026, 12, 31)), '2026-12-31');
    });
  });

  group('legacyEventId', () {
    test('joins day key and normalized title', () {
      expect(
        legacyEventId('2026-03-05', '  Vs Rampla  '),
        '2026-03-05|vs rampla',
      );
    });

    test('is stable regardless of title casing/whitespace', () {
      final a = legacyEventId('2026-03-05', 'Vs Rampla');
      final b = legacyEventId('2026-03-05', '  VS RAMPLA ');
      expect(a, b);
    });
  });

  group('normalizeEventJson', () {
    test('keeps an existing id untouched', () {
      final json = {'id': 'evt-1', 'title': 'Vs Rampla', 'type': 'Partido'};
      final result = normalizeEventJson(json, '2026-03-05');
      expect(result['id'], 'evt-1');
    });

    test('derives a legacy id from day key + title when id is missing', () {
      final json = {'title': 'Vs Rampla', 'type': 'Partido'};
      final result = normalizeEventJson(json, '2026-03-05');
      expect(result['id'], '2026-03-05|vs rampla');
      // Every other field survives untouched.
      expect(result['title'], 'Vs Rampla');
      expect(result['type'], 'Partido');
    });

    test('derives a legacy id when id is an empty string', () {
      final json = {'id': '', 'title': 'Vs Rampla'};
      final result = normalizeEventJson(json, '2026-03-05');
      expect(result['id'], '2026-03-05|vs rampla');
    });

    test(
      'the migrated id matches the pre-migration MatchResult.calendarKey '
      'formula, so an already-logged result keeps its link',
      () {
        // The old scheme wrote calendarKey as '<dayKey>|<title lowercased>'.
        // A legacy event without an id must migrate to that same string.
        const preExistingCalendarKey = '2026-03-05|vs rampla';
        final migrated =
            normalizeEventJson({'title': 'Vs Rampla'}, '2026-03-05');
        expect(migrated['id'], preExistingCalendarKey);
      },
    );
  });

  group('sessionsOnDay', () {
    test('matches by calendar day key, ignoring any time-of-day suffix', () {
      final target = DateTime(2026, 3, 5);
      final sessions = [
        _session(id: 'a', scheduledDate: '2026-03-05'),
        _session(id: 'b', scheduledDate: '2026-03-05T18:00:00'),
        _session(id: 'c', scheduledDate: '2026-03-06'),
      ];
      final result = sessionsOnDay(sessions, target);
      expect(result.map((s) => s.id).toSet(), {'a', 'b'});
    });

    test('a session with no date matches nothing — never guessed', () {
      final result = sessionsOnDay(
        [_session(id: 'a', scheduledDate: '')],
        DateTime(2026, 3, 5),
      );
      expect(result, isEmpty);
    });

    test('an unparseable date matches nothing', () {
      final result = sessionsOnDay(
        [_session(id: 'a', scheduledDate: 'not-a-date')],
        DateTime(2026, 3, 5),
      );
      expect(result, isEmpty);
    });
  });

  group('pendingMatchResults', () {
    final now = DateTime(2026, 9, 10);
    String cal(Map<String, List<Map<String, dynamic>>> m) => jsonEncode(m);

    test('flags a past match event with no matching result', () {
      final json = cal({
        '2026-09-05': [
          {'id': 'evt-1', 'title': 'vs Rampla', 'type': 'Partido'},
        ],
      });
      final pending = pendingMatchResults(json, const [], now: now);
      expect(pending.length, 1);
      expect(pending.first.title, 'vs Rampla');
    });

    test('a match with a result logged (calendarKey == event id) is not flagged', () {
      final json = cal({
        '2026-09-05': [
          {'id': 'evt-1', 'title': 'vs Rampla', 'type': 'Partido'},
        ],
      });
      const result = MatchResult(
        id: 'r1', categoryId: 'c', date: '2026-09-05',
        opponent: 'Rampla', calendarKey: 'evt-1',
      );
      expect(pendingMatchResults(json, [result], now: now), isEmpty);
    });

    test('future matches and non-match event types are ignored', () {
      final json = cal({
        '2026-09-20': [
          {'id': 'evt-2', 'title': 'vs Peñarol', 'type': 'Partido'},
        ],
        '2026-09-05': [
          {'id': 'evt-3', 'title': 'Entrenamiento', 'type': 'Entrenamiento'},
        ],
      });
      expect(pendingMatchResults(json, const [], now: now), isEmpty);
    });

    test('empty or malformed json -> empty, never throws', () {
      expect(pendingMatchResults('', const [], now: now), isEmpty);
      expect(pendingMatchResults('not json', const [], now: now), isEmpty);
    });
  });

  group('newEventId', () {
    test('produces non-empty, distinct ids on consecutive calls', () {
      final a = newEventId();
      final b = newEventId();
      expect(a, isNotEmpty);
      expect(b, isNotEmpty);
      expect(a, isNot(b));
    });
  });
}
