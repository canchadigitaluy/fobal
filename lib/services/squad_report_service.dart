/// Builds the "Reporte del plantel" text shared by Mi equipo and
/// Estadísticas — one place composing attendance, goals and match record
/// into the final export text, so both screens produce the exact same
/// report instead of drifting apart. No Flutter/web dependency.
library;

import '../data/cantera_data.dart';
import 'attendance_stats_service.dart';
import 'export_text_service.dart';
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
  final attendanceAverage = averageAttendanceRate(
    players.map((p) => p.attendanceRate).toList(),
  );
  final goals = squadGoalTracker(players);
  final completedGoals = players
      .expand((player) => player.developmentGoals)
      .where((goal) => goal.status == PlayerGoalStatus.logrado)
      .length;
  final matchStats = MatchStats.forCategory(club.matchResults, categoryId);
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
    matchesPlayed: matchStats.played == 0 ? null : matchStats.played,
    wins: matchStats.wins,
    draws: matchStats.draws,
    losses: matchStats.losses,
  );
}
