import 'package:flutter_test/flutter_test.dart';

import 'package:cantera_os/data/cantera_data.dart';
import 'package:cantera_os/services/squad_report_service.dart';

CanteraClub _club({List<Player> players = const [], List<MatchResult> matchResults = const []}) {
  return canteraDemoClub.copyWith(players: players, matchResults: matchResults);
}

Player _player({
  String id = 'p1',
  String status = '',
  double attendanceRate = 0,
  int matchesPlayed = 0,
  int goals = 0,
}) {
  return Player(
    id: id,
    categoryId: 'cat-1',
    firstName: 'Juan',
    lastName: 'Pérez',
    age: 20,
    position: 'DEL',
    secondaryPositions: '',
    dominantFoot: '',
    status: status,
    attendanceRate: attendanceRate,
    trend: '',
    matchesPlayed: matchesPlayed,
    goals: goals,
    note: '',
  );
}

void main() {
  group('buildSquadReportContent', () {
    test('composes attendance, warnings and match record for the category', () {
      final players = [
        _player(id: 'p1', attendanceRate: 0.9),
        _player(id: 'p2', status: 'Lesionado', attendanceRate: 0.5),
      ];
      final matchResults = [
        const MatchResult(id: 'r1', categoryId: 'cat-1', date: '2026-09-01', opponent: 'Rampla', goalsFor: 2, goalsAgainst: 1),
      ];
      final content = buildSquadReportContent(
        club: _club(players: players, matchResults: matchResults),
        players: players,
        categoryId: 'cat-1',
        categoryName: 'Sub 15',
      );
      expect(content, contains('Sub 15'));
      expect(content, contains('2 jugadores'));
      expect(content, contains('A CONFIRMAR / SEGUIMIENTO'));
      expect(content, contains('Juan Pérez: Lesionado'));
      expect(content, contains('ASISTENCIA'));
      expect(content, contains('RESULTADOS'));
      expect(content, contains('1 jugados · 1G 0E 0P'));
    });

    test('omits the match record for a LUD category — that record lives in '
        'the league sync, a locally logged result is never authoritative', () {
      final players = [_player(id: 'p1', attendanceRate: 0.9)];
      final matchResults = [
        const MatchResult(id: 'r1', categoryId: 'lud-cat-1-1', date: '2026-09-01', opponent: 'Rampla', goalsFor: 2, goalsAgainst: 1),
      ];
      final content = buildSquadReportContent(
        club: _club(players: players, matchResults: matchResults),
        players: players,
        categoryId: 'lud-cat-1-1',
        categoryName: 'Sub 15',
      );
      expect(content, isNot(contains('RESULTADOS')));
    });

    test('an empty squad produces a report with no optional sections', () {
      final content = buildSquadReportContent(
        club: _club(),
        players: const [],
        categoryId: 'cat-1',
        categoryName: 'Sub 15',
      );
      expect(content, contains('0 jugadores'));
      expect(content, isNot(contains('RESULTADOS')));
      expect(content, isNot(contains('ASISTENCIA')));
    });
  });
}
