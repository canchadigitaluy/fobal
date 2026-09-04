import 'package:flutter_test/flutter_test.dart';

import 'package:cantera_os/state/calendar_events.dart';

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
