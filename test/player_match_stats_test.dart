import 'package:flutter_test/flutter_test.dart';

import 'package:cantera_os/services/player_match_stats_service.dart';

void main() {
  group('computePlayerMatchStats', () {
    test(
      'counts one match per lineup appearance and one goal per scorer entry',
      () {
        final stats = computePlayerMatchStats(
          lineups: [
            ['p1', 'p2'],
            ['p1'],
          ],
          scorers: [
            ['p1', 'p1'],
            [],
          ],
          playerIds: ['p1', 'p2', 'p3'],
        );
        expect(stats['p1']!.matchesPlayed, 2);
        expect(stats['p1']!.goals, 2);
        expect(stats['p2']!.matchesPlayed, 1);
        expect(stats['p2']!.goals, 0);
      },
    );

    test('a player with no appearances gets zeroed stats, not omitted', () {
      final stats = computePlayerMatchStats(
        lineups: const [],
        scorers: const [],
        playerIds: ['p1'],
      );
      expect(stats['p1']!.matchesPlayed, 0);
      expect(stats['p1']!.goals, 0);
      expect(stats['p1']!.minutesPlayed, 0);
    });

    test('sums minutes from every saved match without inventing values', () {
      final stats = computePlayerMatchStats(
        lineups: const [
          ['p1', 'p2'],
          ['p1'],
        ],
        scorers: const [[], []],
        minutesByMatch: const [
          {'p1': 90, 'p2': 35},
          {'p1': 62},
        ],
        playerIds: const ['p1', 'p2', 'p3'],
      );
      expect(stats['p1']!.minutesPlayed, 152);
      expect(stats['p2']!.minutesPlayed, 35);
      expect(stats['p3']!.minutesPlayed, 0);
    });

    test('topScorers ranks by goal count, drops ids without a name', () {
      final ranked = topScorers(
        scorers: [
          ['p1', 'p1', 'p2'],
          ['p1', 'p3-unknown'],
        ],
        names: {'p1': 'Juan', 'p2': 'Pedro'},
      );
      expect(ranked.map((e) => e.name).toList(), ['Juan', 'Pedro']);
      expect(ranked.first.goals, 3);
    });

    test('recomputing from scratch never double-counts an edited match', () {
      // Simulates: match originally had p1 scoring twice, then edited down
      // to once. The caller always passes the FULL current history, so an
      // edit's old entry is simply gone — never incremented on top of.
      final before = computePlayerMatchStats(
        lineups: [
          ['p1'],
        ],
        scorers: [
          ['p1', 'p1'],
        ],
        playerIds: ['p1'],
      );
      expect(before['p1']!.goals, 2);
      final after = computePlayerMatchStats(
        lineups: [
          ['p1'],
        ],
        scorers: [
          ['p1'],
        ],
        playerIds: ['p1'],
      );
      expect(after['p1']!.goals, 1);
    });
  });
}
