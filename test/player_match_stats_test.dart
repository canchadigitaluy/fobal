import 'package:flutter_test/flutter_test.dart';

import 'package:cantera_os/services/player_match_stats_service.dart';

void main() {
  group('computePlayerMatchStats', () {
    test('counts one match per lineup appearance and one goal per scorer entry', () {
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
    });

    test('a player with no appearances gets zeroed stats, not omitted', () {
      final stats = computePlayerMatchStats(
        lineups: const [],
        scorers: const [],
        playerIds: ['p1'],
      );
      expect(stats['p1']!.matchesPlayed, 0);
      expect(stats['p1']!.goals, 0);
    });

    test('recomputing from scratch never double-counts an edited match', () {
      // Simulates: match originally had p1 scoring twice, then edited down
      // to once. The caller always passes the FULL current history, so an
      // edit's old entry is simply gone — never incremented on top of.
      final before = computePlayerMatchStats(
        lineups: [['p1']],
        scorers: [['p1', 'p1']],
        playerIds: ['p1'],
      );
      expect(before['p1']!.goals, 2);
      final after = computePlayerMatchStats(
        lineups: [['p1']],
        scorers: [['p1']],
        playerIds: ['p1'],
      );
      expect(after['p1']!.goals, 1);
    });
  });
}
