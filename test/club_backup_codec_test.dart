import 'package:flutter_test/flutter_test.dart';

import 'package:cantera_os/data/cantera_data.dart';
import 'package:cantera_os/services/club_backup_codec.dart';

void main() {
  const category = CategorySquad(
    id: 'cat-1',
    name: 'Sub 15',
    sport: 'Futbol',
    ageGroup: 'Sub 15',
    coachName: 'Ana',
    playerCount: 1,
    attendanceRate: 0.8,
    objectives: ['Presion tras perdida'],
    currentFocus: 'Salida limpia',
    lastRegistered: '2026-09-01',
  );

  final club = canteraDemoClub.copyWith(
    id: 'club-x',
    name: 'Atlético Test',
    league: 'Liga X',
    seasonYear: '2026',
    dataSource: 'manual',
    categories: [category],
  );

  test('exportJson round-trips through parseClubJson', () {
    final restored = ClubBackupCodec.parseClubJson(
      ClubBackupCodec.exportJson(club),
    );
    expect(restored, isNotNull);
    expect(restored!.id, 'club-x');
    expect(restored.name, 'Atlético Test');
    expect(restored.league, 'Liga X');
    expect(restored.seasonYear, '2026');
    expect(restored.categories, hasLength(1));
    expect(restored.categories.first.name, 'Sub 15');
    expect(restored.categories.first.currentFocus, 'Salida limpia');
  });

  test('parseClubJson rejects input that is not a club export', () {
    expect(ClubBackupCodec.parseClubJson(''), isNull);
    expect(ClubBackupCodec.parseClubJson('   '), isNull);
    expect(ClubBackupCodec.parseClubJson('not json'), isNull);
    expect(ClubBackupCodec.parseClubJson('[]'), isNull);
    expect(ClubBackupCodec.parseClubJson('{"foo":1}'), isNull);
    expect(ClubBackupCodec.parseClubJson('{"id":""}'), isNull);
    // Valid JSON object with an id but no club-shaped keys.
    expect(ClubBackupCodec.parseClubJson('{"id":"z","other":true}'), isNull);
  });

  test('parseClubJson accepts a minimal club shape', () {
    final restored = ClubBackupCodec.parseClubJson(
      '{"id":"z","name":"Z","categories":[],"players":[]}',
    );
    expect(restored, isNotNull);
    expect(restored!.name, 'Z');
    expect(restored.categories, isEmpty);
  });

  test('typed league stats survive the club round-trip', () {
    const player = Player(
      id: 'lud-player-9-mayores',
      categoryId: 'cat-1',
      firstName: 'Juan',
      lastName: 'Pérez',
      age: 0,
      position: 'Delantero',
      secondaryPositions: '',
      dominantFoot: '',
      status: 'Activo',
      attendanceRate: 0,
      trend: '12 PJ - 890 min - 7 goles',
      matchesPlayed: 12,
      minutesPlayed: 890,
      goals: 7,
      assists: 3,
      yellowCards: 4,
      redCards: 1,
      note: '',
    );
    final withPlayer = club.copyWith(players: [player]);
    final restored = ClubBackupCodec.parseClubJson(
      ClubBackupCodec.exportJson(withPlayer),
    );
    expect(restored, isNotNull);
    final back = restored!.players.single;
    expect(back.matchesPlayed, 12);
    expect(back.minutesPlayed, 890);
    expect(back.goals, 7);
    expect(back.assists, 3);
    expect(back.yellowCards, 4);
    expect(back.redCards, 1);
    expect(back.goals + back.assists, 10);
  });

  MatchResult res(
    String date,
    String opp,
    int gf,
    int ga, {
    String kind = 'oficial',
    String venue = 'home',
  }) => MatchResult(
    id: 'r-$date-$opp',
    categoryId: 'cat-1',
    date: date,
    opponent: opp,
    goalsFor: gf,
    goalsAgainst: ga,
    kind: kind,
    venue: venue,
  );

  test('MatchResult round-trips through the club blob', () {
    final withResults = club.copyWith(
      matchResults: [
        res('2026-08-30', 'Rival A', 2, 1, venue: 'away'),
        res('2026-08-23', 'Rival B', 0, 0, kind: 'amistoso'),
      ],
    );
    final restored = ClubBackupCodec.parseClubJson(
      ClubBackupCodec.exportJson(withResults),
    );
    expect(restored, isNotNull);
    expect(restored!.matchResults, hasLength(2));
    final a = restored.matchResults.first;
    expect(a.opponent, 'Rival A');
    expect(a.goalsFor, 2);
    expect(a.venue, 'away');
    expect(a.outcome, 'G');
    expect(a.points, 3);
    expect(a.isCompetitive, isTrue);
    expect(restored.matchResults[1].isCompetitive, isFalse); // amistoso
  });

  test('MatchResult keeps player minutes and old records default to empty', () {
    final result = res(
      '2026-09-01',
      'Rival',
      1,
      0,
    ).copyWith(lineupIds: const ['p1'], minutesByPlayer: const {'p1': 73});
    final restored = MatchResult.fromJson(result.toJson());
    expect(restored.minutesByPlayer, {'p1': 73});
    expect(MatchResult.fromJson(const {'id': 'old'}).minutesByPlayer, isEmpty);
  });

  test('AttendanceRecord round-trips through the club blob', () {
    final club = canteraDemoClub.copyWith(
      attendanceRecords: const [
        AttendanceRecord(
          categoryId: 'cat-1',
          date: '2026-09-08',
          presentIds: ['p1'],
          rosterIds: ['p1', 'p2'],
          note: 'Lluvia',
        ),
      ],
    );
    final restored = ClubBackupCodec.parseClubJson(
      ClubBackupCodec.exportJson(club),
    );
    expect(restored!.attendanceRecords, hasLength(1));
    expect(restored.attendanceRecords.single.rosterIds, ['p1', 'p2']);
    expect(restored.attendanceRecords.single.note, 'Lluvia');
  });

  test('planteles and their roster scope survive the club round-trip', () {
    final scoped = club.copyWith(
      planteles: const [
        Plantel(id: 'pl-1', categoryId: 'cat-1', name: 'Competencia'),
      ],
      players: const [
        Player(
          id: 'p1',
          categoryId: 'cat-1',
          plantelId: 'pl-1',
          firstName: 'Ana',
          lastName: 'Pérez',
          age: 15,
          position: 'Volante',
          secondaryPositions: '',
          dominantFoot: 'Derecho',
          status: 'Activo',
          attendanceRate: 1,
          trend: '',
          note: '',
        ),
      ],
      attendanceRecords: const [
        AttendanceRecord(
          categoryId: 'cat-1',
          date: '2026-09-09',
          plantelIds: ['pl-1'],
          presentIds: ['p1'],
          rosterIds: ['p1'],
        ),
      ],
    );

    final restored = ClubBackupCodec.parseClubJson(
      ClubBackupCodec.exportJson(scoped),
    )!;
    expect(restored.planteles.single.name, 'Competencia');
    expect(restored.players.single.plantelId, 'pl-1');
    expect(restored.attendanceRecords.single.plantelIds, ['pl-1']);
  });

  test('MatchStats computes standings-style numbers from manual results', () {
    final results = [
      res('2026-08-30', 'A', 3, 1), // G
      res('2026-08-23', 'B', 1, 1), // E
      res('2026-08-16', 'C', 0, 2), // P
      res('2026-08-09', 'D', 2, 0), // G
      res('2026-08-02', 'E', 0, 0), // E
      res('2026-07-26', 'F', 1, 0, kind: 'amistoso'), // excluded from points
    ];
    // A result from another category must be ignored entirely.
    final other = res('2026-07-19', 'X', 9, 0).copyWith(categoryId: 'other');

    final s = MatchStats.forCategory([...results, other], 'cat-1');
    expect(
      s.played,
      5,
    ); // 6 logged, 1 friendly excluded, other-category ignored
    expect(s.wins, 2);
    expect(s.draws, 2);
    expect(s.losses, 1);
    expect(s.points, 8); // 2*3 + 2
    expect(s.goalsFor, 6); // 3+1+0+2+0
    expect(s.goalsAgainst, 4); // 1+1+2+0+0
    expect(s.goalDiff, 2);
    expect((s.pointsRate * 100).round(), 53); // 8 / 15
    expect(s.scoring, closeTo(1.2, 0.001));
    expect(s.conceding, closeTo(0.8, 0.001));
    expect(s.friendlies, 1);
    expect(s.last5, ['G', 'E', 'P', 'G', 'E']);
  });

  test(
    'MatchStats streak reads the leading run, grouping draws with losses',
    () {
      final losing = MatchStats.forCategory([
        res('2026-08-30', 'A', 0, 1), // P (newest)
        res('2026-08-23', 'B', 1, 1), // E
        res('2026-08-16', 'C', 0, 3), // P
        res('2026-08-09', 'D', 2, 0), // G  -> run stops here
      ], 'cat-1');
      expect(losing.streak.count, 3);
      expect(losing.streak.label, 'sin ganar');

      final winning = MatchStats.forCategory([
        res('2026-08-30', 'A', 2, 0),
        res('2026-08-23', 'B', 1, 0),
        res('2026-08-16', 'C', 0, 1),
      ], 'cat-1');
      expect(winning.streak.count, 2);
      expect(winning.streak.label, 'ganando');
    },
  );

  test(
    'MatchStats with no competitive matches is an empty, honest summary',
    () {
      final s = MatchStats.forCategory([
        res('2026-08-30', 'A', 3, 0, kind: 'amistoso'),
        res('2026-08-23', 'B', 1, 1, kind: 'practica'),
      ], 'cat-1');
      expect(s.played, 0);
      expect(s.points, 0);
      expect(s.pointsRate, 0);
      expect(s.friendlies, 2);
      expect(s.streak.count, 0);
    },
  );

  test(
    'a player without league stats reads zero and hasLeagueStats is false',
    () {
      const player = Player(
        id: 'manual-1',
        categoryId: 'cat-1',
        firstName: 'Ana',
        lastName: 'Gómez',
        age: 0,
        position: '',
        secondaryPositions: '',
        dominantFoot: '',
        status: 'Activo',
        attendanceRate: 0,
        trend: '',
        note: '',
      );
      expect(player.hasLeagueStats, isFalse);
      final restored = ClubBackupCodec.parseClubJson(
        ClubBackupCodec.exportJson(club.copyWith(players: [player])),
      );
      expect(restored!.players.single.goals, 0);
      expect(restored.players.single.hasLeagueStats, isFalse);
    },
  );
}
