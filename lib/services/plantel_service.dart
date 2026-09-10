import '../data/cantera_data.dart';

List<Plantel> plantelesForCategory(CanteraClub club, String categoryId) => club
    .planteles
    .where((plantel) => plantel.categoryId == categoryId)
    .toList();

List<Player> playersForPlantel(Iterable<Player> players, String plantelId) =>
    plantelId.isEmpty
    ? players.toList()
    : players.where((player) => player.plantelId == plantelId).toList();

CanteraClub removePlantel(CanteraClub club, String plantelId) => club.copyWith(
  planteles: club.planteles
      .where((plantel) => plantel.id != plantelId)
      .toList(),
  players: [
    for (final player in club.players)
      if (player.plantelId == plantelId)
        player.copyWith(plantelId: '')
      else
        player,
  ],
);

Set<String> rosterForSelectedPlanteles({
  required Iterable<Player> categoryPlayers,
  required Set<String> selectedPlantelIds,
}) {
  if (selectedPlantelIds.isEmpty) {
    return categoryPlayers.map((player) => player.id).toSet();
  }
  return categoryPlayers
      .where((player) => selectedPlantelIds.contains(player.plantelId))
      .map((player) => player.id)
      .toSet();
}
