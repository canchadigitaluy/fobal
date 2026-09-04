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

  test('a player without league stats reads zero and hasLeagueStats is false', () {
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
  });
}
