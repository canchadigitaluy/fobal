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
