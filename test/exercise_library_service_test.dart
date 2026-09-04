import 'package:flutter_test/flutter_test.dart';

import 'package:cantera_os/data/cantera_data.dart';
import 'package:cantera_os/services/exercise_library_service.dart';

Exercise _ex({
  required String id,
  String name = 'Ejercicio',
  String description = '',
  String objective = '',
  String space = '',
  int players = 0,
  int duration = 10,
  String intensity = '',
  String categoryId = '',
}) {
  return Exercise(
    id: id,
    name: name,
    description: description,
    objective: objective,
    space: space,
    players: players,
    duration: duration,
    intensity: intensity,
    categoryId: categoryId,
  );
}

void main() {
  group('parseDurationMinutes', () {
    test('extracts the leading number from free text', () {
      expect(parseDurationMinutes('15 min'), 15);
      expect(parseDurationMinutes("20'"), 20);
      expect(parseDurationMinutes('7'), 7);
    });

    test('returns 0 for text with no number, never guesses', () {
      expect(parseDurationMinutes('sin definir'), 0);
      expect(parseDurationMinutes(''), 0);
    });
  });

  group('newExerciseId / newBuilderBlockId', () {
    test('produce non-empty, distinct ids on consecutive calls', () {
      final a = newExerciseId();
      final b = newExerciseId();
      expect(a, isNotEmpty);
      expect(a, isNot(b));

      final c = newBuilderBlockId();
      final d = newBuilderBlockId();
      expect(c, isNotEmpty);
      expect(c, isNot(d));
    });
  });

  group('totalMinutes', () {
    test('sums a list of durations', () {
      expect(totalMinutes([15, 20, 10]), 45);
    });

    test('is 0 for an empty list', () {
      expect(totalMinutes(const []), 0);
    });
  });

  group('filterExercises', () {
    final library = [
      _ex(id: '1', name: 'Rondo 4v2', objective: 'Posesión', space: 'Reducido', intensity: 'Alta', players: 6, categoryId: ''),
      _ex(id: '2', name: 'Finalización', objective: 'Definición', space: 'Área', intensity: 'Media', players: 10, categoryId: 'cat-sub15'),
      _ex(id: '3', name: 'Salida en corto', objective: 'Posesión', space: 'Media cancha', intensity: 'Baja', players: 12, categoryId: 'cat-sub17'),
    ];

    test('no filters returns everything', () {
      expect(filterExercises(library).length, 3);
    });

    test('categoryId keeps the shared ones plus that category\'s own', () {
      final result = filterExercises(library, categoryId: 'cat-sub15');
      expect(result.map((e) => e.id), containsAll(['1', '2']));
      expect(result.map((e) => e.id), isNot(contains('3')));
    });

    test('text query matches name/description/objective, case-insensitive', () {
      final result = filterExercises(library, query: 'posesión');
      expect(result.map((e) => e.id).toSet(), {'1', '3'});
    });

    test('space filter is a case-insensitive substring match', () {
      final result = filterExercises(library, space: 'área');
      expect(result.map((e) => e.id), ['2']);
    });

    test('intensity filter matches exactly what it says', () {
      final result = filterExercises(library, intensity: 'alta');
      expect(result.map((e) => e.id), ['1']);
    });

    test('player range filters out exercises outside it, ignoring unset (0) players', () {
      final result = filterExercises(library, minPlayers: 8, maxPlayers: 12);
      expect(result.map((e) => e.id).toSet(), {'2', '3'});
    });

    test('combines filters with AND semantics', () {
      final result = filterExercises(
        library,
        query: 'posesión',
        intensity: 'baja',
      );
      expect(result.map((e) => e.id), ['3']);
    });
  });

  group('Exercise <-> TrainingBlock <-> json', () {
    test('toBlock carries duration, cues and constraints', () {
      final exercise = _ex(
        id: 'e1',
        name: 'Rondo 4v2',
        description: 'Espacio reducido',
        duration: 15,
        intensity: 'Alta',
      ).copyWith(
        coachingPoints: ['Presionar rápido'],
        constraints: ['Dos toques'],
        successMetric: '5 pases seguidos',
      );
      final block = exercise.toBlock();
      expect(block.name, 'Rondo 4v2');
      expect(block.duration, '15 min');
      expect(block.description, 'Espacio reducido');
      expect(block.coachingPoints, ['Presionar rápido']);
      expect(block.constraints, ['Dos toques']);
      expect(block.successMetric, '5 pases seguidos');
    });

    test('fromBlock captures a generated block into the library shape', () {
      final block = TrainingBlock(
        'Juego 8v8',
        '30 min',
        'Fase de posesión',
        intensity: 'Media',
        coachingPoints: ['Amplitud'],
      );
      final exercise = Exercise.fromBlock(
        block,
        id: 'e2',
        minutes: parseDurationMinutes(block.duration),
        objective: 'Posesión',
        players: 16,
        space: 'Cancha completa',
        categoryId: 'cat-sub15',
        source: 'ai',
      );
      expect(exercise.name, 'Juego 8v8');
      expect(exercise.duration, 30);
      expect(exercise.objective, 'Posesión');
      expect(exercise.source, 'ai');
      expect(exercise.categoryId, 'cat-sub15');
      expect(exercise.coachingPoints, ['Amplitud']);
    });

    test('round-trips through json without losing fields', () {
      final original = _ex(
        id: 'e3',
        name: 'Salida en corto',
        description: 'Desde el arquero',
        objective: 'Posesión',
        space: 'Media cancha',
        players: 12,
        duration: 20,
        intensity: 'Baja',
        categoryId: 'cat-sub17',
      );
      final restored = Exercise.fromJson(original.toJson());
      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.description, original.description);
      expect(restored.objective, original.objective);
      expect(restored.space, original.space);
      expect(restored.players, original.players);
      expect(restored.duration, original.duration);
      expect(restored.intensity, original.intensity);
      expect(restored.categoryId, original.categoryId);
    });
  });

  group('findExerciseDuplicate — deduplicación al guardar desde IA', () {
    final library = [
      _ex(id: 'e1', name: 'Rondo 4v2', duration: 15, description: 'Espacio reducido, 2 toques'),
    ];

    test('exact match (name + duration + description, normalized) — no duplica', () {
      final result = findExerciseDuplicate(
        library: library,
        name: '  Rondo 4v2  ',
        duration: 15,
        description: 'espacio reducido, 2 toques',
      );
      expect(result, ExerciseDedupResult.exactMatch);
    });

    test('same name but different duration/description — pide confirmación', () {
      final result = findExerciseDuplicate(
        library: library,
        name: 'Rondo 4v2',
        duration: 20,
        description: 'Otra consigna',
      );
      expect(result, ExerciseDedupResult.nameMatch);
    });

    test('no relation to anything saved — se puede guardar sin avisar', () {
      final result = findExerciseDuplicate(
        library: library,
        name: 'Finalización desde el segundo palo',
        duration: 12,
        description: 'Centro y definición',
      );
      expect(result, ExerciseDedupResult.none);
    });

    test('empty library — nunca hay duplicado', () {
      final result = findExerciseDuplicate(
        library: const [],
        name: 'Rondo 4v2',
        duration: 15,
        description: 'Espacio reducido',
      );
      expect(result, ExerciseDedupResult.none);
    });
  });

  group('Exercise.fromBlock preserves as much as the block carries', () {
    test('constraints, coachingPoints, successMetric and animationScene all '
        'survive the capture', () {
      final scene = AnimationScene.fromBlockText(
        text: 'Rondo con presión',
        space: 'Reducido',
        playerCount: 8,
        cues: const ['Presionar rápido'],
      );
      final block = TrainingBlock(
        'Rondo 4v2',
        '15 min',
        'Espacio reducido',
        intensity: 'Alta',
        constraints: const ['Dos toques'],
        coachingPoints: const ['Presionar rápido'],
        successMetric: '5 pases seguidos',
        animationScene: scene,
      );
      final exercise = Exercise.fromBlock(
        block,
        id: 'e9',
        minutes: 15,
        objective: 'Posesión',
        players: 8,
        space: 'Reducido',
        categoryId: 'cat-1',
        source: 'ai',
      );
      expect(exercise.constraints, ['Dos toques']);
      expect(exercise.coachingPoints, ['Presionar rápido']);
      expect(exercise.successMetric, '5 pases seguidos');
      expect(exercise.animationScene, isNotNull);
      expect(exercise.animationScene!.hasContent, isTrue);
    });
  });
}
