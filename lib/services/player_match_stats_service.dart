/// Pure helper to derive per-player match participation (matchesPlayed,
/// goals) from a category's full MatchResult history. No Flutter/web
/// dependency, so this stays unit-testable.
///
/// Manual/No-LUD categories have no league sync to source these numbers
/// from, so — same pattern as attendance — they're recomputed from the real
/// saved history every time a result is logged, edited or deleted, instead
/// of being incremented ad hoc (which would double-count on an edit).
library;

class PlayerMatchStats {
  final int matchesPlayed;
  final int goals;
  const PlayerMatchStats({this.matchesPlayed = 0, this.goals = 0});
}

/// player id -> stats, one entry per id in [playerIds]. A player who never
/// appears in [lineupsById]/[scorersById] gets zeroed stats — not omitted —
/// since a manual player's counts are always known (never "no data yet").
Map<String, PlayerMatchStats> computePlayerMatchStats({
  required List<List<String>> lineups,
  required List<List<String>> scorers,
  required List<String> playerIds,
}) {
  final matches = <String, int>{};
  for (final lineup in lineups) {
    for (final id in lineup) {
      matches[id] = (matches[id] ?? 0) + 1;
    }
  }
  final goals = <String, int>{};
  for (final scorerList in scorers) {
    for (final id in scorerList) {
      goals[id] = (goals[id] ?? 0) + 1;
    }
  }
  return {
    for (final id in playerIds)
      id: PlayerMatchStats(matchesPlayed: matches[id] ?? 0, goals: goals[id] ?? 0),
  };
}

/// Ordered goal count per named scorer, highest first, capped at [limit].
/// [scorers] is one list of player-ids per match; [names] resolves ids the
/// caller wants shown (ids without a name are dropped — never invented).
List<({String name, int goals})> topScorers({
  required List<List<String>> scorers,
  required Map<String, String> names,
  int limit = 3,
}) {
  final counts = <String, int>{};
  for (final list in scorers) {
    for (final id in list) {
      final name = names[id];
      if (name == null || name.trim().isEmpty) continue;
      counts[name] = (counts[name] ?? 0) + 1;
    }
  }
  final ordered = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return [
    for (final e in ordered.take(limit)) (name: e.key, goals: e.value),
  ];
}
