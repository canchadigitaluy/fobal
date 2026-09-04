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
