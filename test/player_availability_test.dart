import 'package:flutter_test/flutter_test.dart';

import 'package:cantera_os/data/cantera_data.dart';

Player _player({String status = '', String expectedReturnDate = ''}) {
  return Player(
    id: 'p1',
    categoryId: 'cat-1',
    firstName: 'Juan',
    lastName: 'Pérez',
    age: 20,
    position: 'DEL',
    secondaryPositions: '',
    dominantFoot: '',
    status: status,
    expectedReturnDate: expectedReturnDate,
    attendanceRate: 0,
    trend: '',
    note: '',
  );
}

void main() {
  group('normalizePlayerAvailability', () {
    test('maps the current canonical labels', () {
      expect(normalizePlayerAvailability('Disponible'), PlayerAvailability.disponible);
      expect(normalizePlayerAvailability('Tocado'), PlayerAvailability.tocado);
      expect(normalizePlayerAvailability('Lesionado'), PlayerAvailability.lesionado);
      expect(normalizePlayerAvailability('Sancionado'), PlayerAvailability.sancionado);
      expect(normalizePlayerAvailability('Ausente avisado'), PlayerAvailability.ausente);
    });

    test('maps legacy/free-text values already saved by coaches before this '
        'feature existed', () {
      expect(normalizePlayerAvailability('Activo'), PlayerAvailability.disponible);
      expect(normalizePlayerAvailability('Suspendido'), PlayerAvailability.sancionado);
      expect(normalizePlayerAvailability('Duda'), PlayerAvailability.tocado);
      expect(normalizePlayerAvailability('Viaje'), PlayerAvailability.ausente);
      expect(normalizePlayerAvailability('Examen'), PlayerAvailability.ausente);
    });

    test('is case-insensitive and tolerates extra words', () {
      expect(normalizePlayerAvailability('LESIONADO (rodilla)'), PlayerAvailability.lesionado);
      expect(normalizePlayerAvailability('  sancionado  '), PlayerAvailability.sancionado);
    });

    test('retrocompatibilidad: empty or unrecognized status defaults to '
        'disponible — a player never disappears just for missing data', () {
      expect(normalizePlayerAvailability(''), PlayerAvailability.disponible);
      expect(normalizePlayerAvailability('algo raro'), PlayerAvailability.disponible);
    });
  });

  group('Player.isAvailable / hasAvailabilityWarning', () {
    test('a player with no status set is available (retrocompat)', () {
      final player = _player();
      expect(player.isAvailable, isTrue);
      expect(player.hasAvailabilityWarning, isFalse);
    });

    test('disponible is available, everything else raises a warning', () {
      expect(_player(status: 'Disponible').isAvailable, isTrue);
      expect(_player(status: 'Tocado').hasAvailabilityWarning, isTrue);
      expect(_player(status: 'Lesionado').hasAvailabilityWarning, isTrue);
      expect(_player(status: 'Sancionado').hasAvailabilityWarning, isTrue);
      expect(_player(status: 'Ausente avisado').hasAvailabilityWarning, isTrue);
    });

    test('warning never means unusable — isAvailable/hasAvailabilityWarning '
        'are informational only, nothing here blocks selection', () {
      final injured = _player(status: 'Lesionado');
      expect(injured.availability, PlayerAvailability.lesionado);
      // No separate "canBeSelected" flag exists — the model doesn't gate
      // selection at all, by design.
    });
  });

  group('PlayerAvailability label/color', () {
    test('every state has a distinct, sober label', () {
      final labels = PlayerAvailability.values.map((a) => a.label).toSet();
      expect(labels.length, PlayerAvailability.values.length);
    });
  });
}
