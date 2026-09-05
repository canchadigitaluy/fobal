import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cantera_os/services/alignment_history_service.dart';

void main() {
  group('findLineupForRival', () {
    final history = jsonEncode([
      {
        'rival': 'Rampla FC',
        'xi': ['p1', 'p2', null],
        'subs': ['p3'],
      },
      {
        'rival': 'Peñarol',
        'xi': ['p4'],
        'subs': [],
      },
    ]);

    test('matches case-insensitively and by substring either direction', () {
      expect(
        findLineupForRival(historyJson: history, rivalName: 'rampla'),
        ['p1', 'p2', 'p3'],
      );
    });

    test('no match returns null, never a wrong guess', () {
      expect(
        findLineupForRival(historyJson: history, rivalName: 'Nacional'),
        isNull,
      );
    });

    test('empty rival or empty history returns null', () {
      expect(findLineupForRival(historyJson: history, rivalName: ''), isNull);
      expect(findLineupForRival(historyJson: '', rivalName: 'Rampla'), isNull);
    });

    test('malformed json never throws — returns null', () {
      expect(
        findLineupForRival(historyJson: 'not json', rivalName: 'Rampla'),
        isNull,
      );
    });
  });
}
