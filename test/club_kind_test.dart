import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cantera_os/data/cantera_data.dart';

CanteraClub _club({
  required String id,
  String dataSource = 'local',
  String league = 'Liga Universitaria',
  List<CategorySquad> categories = const [],
}) {
  return CanteraClub(
    id: id,
    name: 'Club $id',
    league: league,
    sportFocus: 'Futbol',
    dataSource: dataSource,
    primaryColor: const Color(0xFF159463),
    secondaryColor: const Color(0xFF102019),
    methodology: const Methodology(
      playingStyle: '',
      offensivePrinciples: [],
      defensivePrinciples: [],
      ageObjectives: [],
      values: [],
      evaluationCriteria: [],
    ),
    categories: categories,
    players: const [],
    sessions: const [],
    trainingReports: const [],
    alerts: const [],
    aiReports: const [],
    users: const [],
  );
}

CategorySquad _category(String id, {String name = 'Categoría'}) {
  return CategorySquad(
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
}

void main() {
  group('isLudCategoryId', () {
    test('recognizes the lud-cat-<teamId>-<categoryId> shape', () {
      expect(isLudCategoryId('lud-cat-42-7'), isTrue);
    });

    test('rejects a manual category id', () {
      expect(isLudCategoryId('externo-atenas-plantel'), isFalse);
      expect(isLudCategoryId(''), isFalse);
    });
  });

  group('CanteraClubKind', () {
    test('dataSource manual is a manual club', () {
      final club = _club(id: 'c1', dataSource: 'manual', league: 'Liga X');
      expect(club.isManualClub, isTrue);
      expect(club.isLudClub, isFalse);
    });

    test('league Trabajo independiente is a manual club even with another dataSource', () {
      final club = _club(id: 'c2', dataSource: 'local', league: 'Trabajo independiente');
      expect(club.isManualClub, isTrue);
    });

    test('a LUD club (synced league, non-manual dataSource) is not manual', () {
      final club = _club(id: 'c3', dataSource: 'lud', league: 'Liga Universitaria');
      expect(club.isManualClub, isFalse);
      expect(club.isLudClub, isTrue);
    });
  });

  group('clubNeedsManualSwitch — impide que un club manual tome un id LUD', () {
    test('needs a switch when the loaded club is a different id entirely', () {
      final loaded = _club(id: 'lud-jmlm', dataSource: 'lud');
      expect(
        clubNeedsManualSwitch(loadedClub: loaded, requiredManualClubId: 'externo-atenas'),
        isTrue,
      );
    });

    test('needs a switch when the id matches but the club is actually LUD '
        '(belt-and-suspenders)', () {
      final loaded = _club(id: 'externo-atenas', league: 'Liga Universitaria');
      expect(
        clubNeedsManualSwitch(loadedClub: loaded, requiredManualClubId: 'externo-atenas'),
        isTrue,
      );
    });

    test('no switch needed once the correct manual club is already loaded', () {
      final loaded = _club(id: 'externo-atenas', dataSource: 'manual', league: 'Trabajo independiente');
      expect(
        clubNeedsManualSwitch(loadedClub: loaded, requiredManualClubId: 'externo-atenas'),
        isFalse,
      );
    });
  });

  group('resolveStoredCategoryId', () {
    test('rejects a lud-cat-* id for a manual club — never adopted', () {
      final club = _club(
        id: 'externo-atenas',
        dataSource: 'manual',
        league: 'Trabajo independiente',
        // Contrived: even if a lud-cat-* id ended up in this club's own
        // category list somehow, a manual club must still refuse it.
        categories: [_category('lud-cat-42-7')],
      );
      final resolved = resolveStoredCategoryId(
        club: club,
        storedCategoryId: 'lud-cat-42-7',
      );
      expect(resolved, isNull);
    });

    test('preserva la selección LUD correcta cuando corresponde', () {
      final club = _club(
        id: 'lud-jmlm',
        dataSource: 'lud',
        league: 'Liga Universitaria',
        categories: [_category('lud-cat-42-7', name: 'Sub 20')],
      );
      final resolved = resolveStoredCategoryId(
        club: club,
        storedCategoryId: 'lud-cat-42-7',
      );
      expect(resolved, 'lud-cat-42-7');
    });

    test('migración retrocompatible: categoría guardada que ya no existe '
        'en el club cae a null, no rompe', () {
      final club = _club(
        id: 'externo-atenas',
        dataSource: 'manual',
        categories: [_category('externo-atenas-plantel')],
      );
      final resolved = resolveStoredCategoryId(
        club: club,
        storedCategoryId: 'externo-atenas-old-category',
      );
      expect(resolved, isNull);
    });

    test('a manual category belonging to the club is kept', () {
      final club = _club(
        id: 'externo-atenas',
        dataSource: 'manual',
        categories: [_category('externo-atenas-plantel')],
      );
      final resolved = resolveStoredCategoryId(
        club: club,
        storedCategoryId: 'externo-atenas-plantel',
      );
      expect(resolved, 'externo-atenas-plantel');
    });

    test('null when nothing was ever stored', () {
      final club = _club(id: 'c1', categories: [_category('cat-1')]);
      expect(resolveStoredCategoryId(club: club, storedCategoryId: null), isNull);
    });
  });
}
