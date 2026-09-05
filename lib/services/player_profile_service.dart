/// Pure helpers for the player 360° profile: safe LUD/manual data relation,
/// and small derived-text builders shared by the screen and the exporter.
/// No Flutter/web dependency, so this stays unit-testable.
library;

import '../data/cantera_data.dart';

/// True only when this player's numbers can be trusted as real league
/// stats: the category itself has to be a LUD one (passed in by the
/// caller, which already knows how to tell — `LudCategoryRef`) AND the
/// player has to actually carry league numbers. Never inferred by matching
/// names/ids across sources — too unsafe, and unnecessary: a LUD player's
/// stats already arrive attached to the same [Player] record via the
/// existing membership hydration.
bool hasReliableLeagueStats({
  required bool categoryIsLud,
  required Player player,
}) => categoryIsLud && player.hasLeagueStats;

/// True for a No-LUD player who has real matches/goals from the DT's own
/// "Cargar resultado" entries (see player_match_stats_service). Never true
/// for LUD — that data comes from the league sync via
/// [hasReliableLeagueStats] instead, never from this manual path.
bool hasManualMatchStats({
  required bool categoryIsLud,
  required Player player,
}) => !categoryIsLud && (player.matchesPlayed > 0 || player.goals > 0);

/// One line per goal, ready to drop into a list or the exporter:
/// "Título (Área) — Estado".
String formatPlayerGoalLine(PlayerGoal goal) =>
    '${goal.title} (${goal.area.label}) — ${goal.status.label}';

List<String> formatPlayerGoalLines(List<PlayerGoal> goals) =>
    goals.map(formatPlayerGoalLine).toList();

/// Goals still open (not logrado/pausado) — what the DT should look at
/// first when opening a player's plan.
List<PlayerGoal> activePlayerGoals(List<PlayerGoal> goals) => goals
    .where(
      (goal) =>
          goal.status == PlayerGoalStatus.pendiente ||
          goal.status == PlayerGoalStatus.enProgreso,
    )
    .toList();

/// Fresh id for a new development goal.
String newPlayerGoalId() =>
    'goal-${DateTime.now().microsecondsSinceEpoch}-${(1000 + DateTime.now().microsecond) % 1000}';

enum GoalReviewStatus { none, upcoming, overdue }

/// Where a goal's review date sits relative to today. Only an ISO
/// `yyyy-MM-dd` (what the date picker now writes) is understood — a legacy
/// free-text value like "30/09" or "en un mes" simply yields [none], never a
/// wrong guess. [overdue] = date already past; [upcoming] = within 7 days.
GoalReviewStatus goalReviewStatus(String reviewDate, {DateTime? now}) {
  final parsed = DateTime.tryParse(reviewDate.trim());
  if (parsed == null) return GoalReviewStatus.none;
  final today = now ?? DateTime.now();
  final day = DateTime(parsed.year, parsed.month, parsed.day);
  final ref = DateTime(today.year, today.month, today.day);
  final diff = day.difference(ref).inDays;
  if (diff < 0) return GoalReviewStatus.overdue;
  if (diff <= 7) return GoalReviewStatus.upcoming;
  return GoalReviewStatus.none;
}

/// One active goal, paired with the player it belongs to — the unit the
/// squad-wide tracker below hands back so the UI can show "who" next to
/// "what" without re-joining the two lists itself.
typedef PlayerGoalEntry = ({Player player, PlayerGoal goal});

/// Every player's open goals, flattened into one list. Goals with a review
/// date that's overdue or due within a week bubble to the top (that's the
/// DT's actual next action); the rest fall back to priority order (alta
/// first). A legacy free-text `reviewDate` that doesn't parse just doesn't
/// get the bump — never a guessed date.
List<PlayerGoalEntry> squadGoalTracker(List<Player> players, {DateTime? now}) {
  final entries = <PlayerGoalEntry>[
    for (final player in players)
      for (final goal in activePlayerGoals(player.developmentGoals))
        (player: player, goal: goal),
  ];
  int reviewRank(PlayerGoal goal) => switch (goalReviewStatus(goal.reviewDate, now: now)) {
    GoalReviewStatus.overdue => 0,
    GoalReviewStatus.upcoming => 1,
    GoalReviewStatus.none => 2,
  };
  int priorityRank(PlayerGoalPriority priority) => switch (priority) {
    PlayerGoalPriority.alta => 0,
    PlayerGoalPriority.media => 1,
    PlayerGoalPriority.baja => 2,
  };
  entries.sort((a, b) {
    final byReview = reviewRank(a.goal).compareTo(reviewRank(b.goal));
    if (byReview != 0) return byReview;
    return priorityRank(a.goal.priority).compareTo(priorityRank(b.goal.priority));
  });
  return entries;
}
