/// Builds the "Reporte del plantel" text shared by Mi equipo and
/// Estadísticas — one place composing attendance, goals and match record
/// into the final export text, so both screens produce the exact same
/// report instead of drifting apart. No Flutter/web dependency.
library;

import '../data/cantera_data.dart';
import 'attendance_stats_service.dart';
import 'export_text_service.dart';
import 'player_match_stats_service.dart';
import 'player_profile_service.dart';

String buildSquadReportContent({
  required CanteraClub club,
  required List<Player> players,
  required String categoryId,
  required String categoryName,
}) {
  final warnings = [
    for (final player in players)
      if (player.hasAvailabilityWarning)
        '${player.fullName.trim()}: ${player.availability.label}',
  ];
  final attendanceAverage = summarizeAttendance(
    club.attendanceRecords
        .where((record) => record.categoryId == categoryId)
        .toList(),
  ).average;
  final goals = squadGoalTracker(players);
  final completedGoals = players
      .expand((player) => player.developmentGoals)
      .where((goal) => goal.status == PlayerGoalStatus.logrado)
      .length;
  // For LUD categories the official record lives in the league sync
  // (standings/results shown elsewhere in Estadísticas) — any locally
  // logged results are a personal supplement, never the authoritative
  // record, so the report omits them here rather than risk looking like
  // an official W/D/L next to the real league table.
  final matchStats = isLudCategoryId(categoryId)
      ? null
      : MatchStats.forCategory(club.matchResults, categoryId);
  final scorerLines = matchStats == null
      ? const <String>[]
      : [
          for (final s in topScorers(
            scorers: [
              for (final r in club.matchResults)
                if (r.categoryId == categoryId) r.scorerIds,
            ],
            names: {for (final p in players) p.id: p.fullName.trim()},
          ))
            '${s.name}: ${s.goals}',
        ];
  return formatSquadReportText(
    clubName: club.name,
    categoryName: categoryName,
    totalPlayers: players.length,
    availablePlayers: players.where((p) => p.isAvailable).length,
    availabilityWarnings: warnings,
    attendanceAverage: attendanceAverage,
    activeGoals: goals.length,
    completedGoals: completedGoals,
    topGoalLines: formatPlayerGoalLines(
      goals.take(5).map((entry) => entry.goal).toList(),
    ),
    matchesPlayed: matchStats == null || matchStats.played == 0
        ? null
        : matchStats.played,
    wins: matchStats?.wins ?? 0,
    draws: matchStats?.draws ?? 0,
    losses: matchStats?.losses ?? 0,
    topScorerLines: scorerLines,
  );
}
