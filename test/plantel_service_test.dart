import 'package:flutter_test/flutter_test.dart';

import 'package:cantera_os/data/cantera_data.dart';
import 'package:cantera_os/services/plantel_service.dart';

Player player(String id, String plantelId) => Player(
  id: id,
  categoryId: 'cat-1',
  plantelId: plantelId,
  firstName: id,
  lastName: '',
  age: 0,
  position: '',
  secondaryPositions: '',
  dominantFoot: '',
  status: 'Disponible',
  attendanceRate: 0,
  trend: '',
  note: '',
);

void main() {
  test('plantel filter is ephemeral and empty means every player', () {
    final players = [player('a', 'p1'), player('b', 'p2'), player('c', '')];
    expect(playersForPlantel(players, ''), hasLength(3));
    expect(playersForPlantel(players, 'p1').map((p) => p.id), ['a']);
  });

  test('mixed practice roster is the union of selected planteles', () {
    final players = [player('a', 'p1'), player('b', 'p2'), player('c', 'p3')];
    expect(
      rosterForSelectedPlanteles(
        categoryPlayers: players,
        selectedPlantelIds: {'p1', 'p3'},
      ),
      {'a', 'c'},
    );
  });

  test('deleting a plantel leaves its players unassigned', () {
    final club = canteraDemoClub.copyWith(
      planteles: const [Plantel(id: 'p1', categoryId: 'cat-1', name: 'A')],
      players: [player('a', 'p1')],
    );
    final next = removePlantel(club, 'p1');
    expect(next.planteles, isEmpty);
    expect(next.players.single.plantelId, isEmpty);
  });
}
