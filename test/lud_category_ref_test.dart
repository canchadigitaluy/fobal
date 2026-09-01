import 'package:flutter_test/flutter_test.dart';

import 'package:cantera_os/data/cantera_data.dart';
import 'package:cantera_os/services/club_access_service.dart';

CategorySquad _cat(String id, [String name = 'Categoria']) => CategorySquad(
      id: id,
      name: name,
      sport: 'Futbol',
      ageGroup: '',
      coachName: '',
      playerCount: 0,
      attendanceRate: 0,
      objectives: const [],
      currentFocus: '',
      lastRegistered: '',
    );

void main() {
  group('LudCategoryRef.tryParse', () {
    test('extracts team, category and trims name', () {
      final ref = LudCategoryRef.tryParse(_cat('lud-cat-1-6', '  Sub 18 '));
      expect(ref, isNotNull);
      expect(ref!.teamId, 1);
      expect(ref.categoryId, 6);
      expect(ref.categoryName, 'Sub 18');
    });

    test('rejects non-LUD and malformed ids', () {
      for (final id in [
        'externo-mi-club-plantel',
        'lud-cat-1',
        'lud-cat-1-6-extra',
        'lud-cat-a-b',
        'cat-1699999999999',
        '',
      ]) {
        expect(LudCategoryRef.tryParse(_cat(id)), isNull, reason: id);
      }
    });
  });

  group('LudCategoryRef.forTeam', () {
    test('passes when the embedded team matches the club team', () {
      final ref = LudCategoryRef.forTeam(_cat('lud-cat-2-7', 'Sub 16'), '2');
      expect(ref, isNotNull);
      expect(ref!.teamId, 2);
      expect(ref.categoryId, 7);
    });

    test('refuses when a club team is paired with another team\'s category', () {
      // Club A is LUD team 1, but the picked category id belongs to team 2.
      expect(LudCategoryRef.forTeam(_cat('lud-cat-2-7'), '1'), isNull);
    });

    test('still parses when the club has no team id to cross-check', () {
      final ref = LudCategoryRef.forTeam(_cat('lud-cat-3-1'), null);
      expect(ref?.teamId, 3);
    });
  });

  test('teamIdOf mirrors tryParse', () {
    expect(LudCategoryRef.teamIdOf('lud-cat-9-4'), 9);
    expect(LudCategoryRef.teamIdOf('not-a-lud-id'), isNull);
  });
}
