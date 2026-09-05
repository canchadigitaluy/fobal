import 'package:flutter_test/flutter_test.dart';

import 'package:cantera_os/data/cantera_data.dart';
import 'package:cantera_os/screens/add_player_dialog.dart';

Player _p(String first, String last) => Player(
      id: '$first-$last',
      categoryId: 'c',
      firstName: first,
      lastName: last,
      age: 0,
      position: '',
      secondaryPositions: '',
      dominantFoot: '',
      status: '',
      attendanceRate: 0,
      trend: '',
      note: '',
    );

void main() {
  group('normalizedPlayerNames', () {
    test('lowercases and trims "nombre apellido"', () {
      final names = normalizedPlayerNames([_p('  Juan ', 'Pérez')]);
      expect(names, contains('juan pérez'));
    });

    test('a typed "JUAN PEREZ" would match the stored normalized key', () {
      final names = normalizedPlayerNames([_p('Juan', 'Perez')]);
      final typedKey = '${'JUAN'.trim().toLowerCase()} ${'PEREZ'.trim().toLowerCase()}'.trim();
      expect(names.contains(typedKey), isTrue);
    });
  });
}
