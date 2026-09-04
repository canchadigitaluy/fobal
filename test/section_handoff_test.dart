import 'package:flutter_test/flutter_test.dart';

import 'package:cantera_os/state/section_handoff.dart';

void main() {
  test('low scoring vs league -> offensive focus', () {
    final f = deriveSessionFocus(
      scoring: 0.8,
      conceding: 1.0,
      leagueScoring: 1.3,
      leagueConceding: 1.3,
      played: 12,
    );
    expect(f, isNotNull);
    expect(f!.objective, contains('finalización'));
    expect(f.problem, contains('0.8 goles por partido'));
    expect(f.problem, contains('media de la categoría 1.3'));
    expect(f.origin, 'Lectura de la semana');
  });

  test('high conceding vs league -> defensive focus', () {
    final f = deriveSessionFocus(
      scoring: 1.4,
      conceding: 1.9,
      leagueScoring: 1.4,
      leagueConceding: 1.3,
      played: 10,
    );
    expect(f, isNotNull);
    expect(f!.objective, contains('defensiva'));
    expect(f.problem, contains('1.9 goles por partido'));
  });

  test('both sides off -> the bigger gap wins', () {
    final f = deriveSessionFocus(
      scoring: 0.9, // 0.5 under a 1.4 league
      conceding: 1.8, // 0.6 over a 1.2 league
      leagueScoring: 1.4,
      leagueConceding: 1.2,
      played: 8,
    );
    expect(f!.objective, contains('defensiva')); // defense gap 0.6 > offense 0.5
  });

  test('balanced team -> no forced action', () {
    final f = deriveSessionFocus(
      scoring: 1.5,
      conceding: 1.1,
      leagueScoring: 1.4,
      leagueConceding: 1.3,
      played: 12,
    );
    expect(f, isNull);
  });

  test('too few matches -> no action', () {
    final f = deriveSessionFocus(scoring: 0.2, conceding: 3.0, played: 1);
    expect(f, isNull);
  });

  test('no league averages still derives from absolute thresholds', () {
    final f = deriveSessionFocus(
      scoring: 0.7,
      conceding: 1.0,
      played: 5,
      formSummary: '9° · últimos 5: 1G 1E 3P',
    );
    expect(f, isNotNull);
    expect(f!.objective, contains('finalización'));
    expect(f.problem, isNot(contains('media de la categoría')));
    expect(f.context, contains('9°'));
    expect(f.context, contains('Origen: Lectura de la semana'));
  });
}
