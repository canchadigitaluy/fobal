import 'package:flutter_test/flutter_test.dart';

import 'package:cantera_os/data/cantera_data.dart';

void main() {
  group('MatchResult.lineupIds / scorerIds', () {
    test('round-trip through json', () {
      const result = MatchResult(
        id: 'r1',
        categoryId: 'cat-1',
        date: '2026-09-01',
        opponent: 'Rampla',
        lineupIds: ['p1', 'p2'],
        scorerIds: ['p1', 'p1'],
      );
      final restored = MatchResult.fromJson(result.toJson());
      expect(restored.lineupIds, ['p1', 'p2']);
      expect(restored.scorerIds, ['p1', 'p1']);
    });

    test('a pre-existing result with no lineup/scorer keys loads as empty (retrocompat)', () {
      final restored = MatchResult.fromJson({
        'id': 'r1',
        'categoryId': 'cat-1',
        'date': '2026-09-01',
        'opponent': 'Rampla',
      });
      expect(restored.lineupIds, isEmpty);
      expect(restored.scorerIds, isEmpty);
    });

    test('copyWith preserves lineup/scorers when not overridden', () {
      const result = MatchResult(
        id: 'r1',
        categoryId: 'cat-1',
        date: '2026-09-01',
        opponent: 'Rampla',
        lineupIds: ['p1'],
        scorerIds: ['p1'],
      );
      final updated = result.copyWith(goalsFor: 2);
      expect(updated.lineupIds, ['p1']);
      expect(updated.scorerIds, ['p1']);
    });
  });
}
