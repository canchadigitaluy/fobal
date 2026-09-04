/// Pure helpers for the exercise library and the manual session builder:
/// duration parsing, id generation, filtering and duration totals. No
/// Flutter/web dependency, so this stays unit-testable.
library;

import '../data/cantera_data.dart';

/// Extracts minutes from a free-text duration ("15 min", "15'", "15") the
/// AI or a coach may have typed. Returns 0 when nothing numeric is found —
/// callers should treat that as "sin definir", never guess a number.
int parseDurationMinutes(String value) {
  final match = RegExp(r'\d+').firstMatch(value);
  if (match == null) return 0;
  return int.tryParse(match.group(0)!) ?? 0;
}

int _exerciseIdSeq = 0;

/// Fresh id for a new library exercise.
String newExerciseId() {
  _exerciseIdSeq++;
  return 'exercise-${DateTime.now().microsecondsSinceEpoch}-$_exerciseIdSeq';
}

int _blockIdSeq = 0;

/// Fresh id for a block placed in the manual session builder (a builder
/// block may reuse the same library exercise twice in one session, so it
/// needs its own identity separate from the exercise's).
String newBuilderBlockId() {
  _blockIdSeq++;
  return 'block-${DateTime.now().microsecondsSinceEpoch}-$_blockIdSeq';
}

/// Sum of every block/exercise duration, in minutes.
int totalMinutes(Iterable<int> durations) =>
    durations.fold(0, (sum, value) => sum + value);

/// Filters the club's exercise library. Every argument left blank/null is
/// ignored — an empty filter set returns every exercise for the category
/// (plus the club-wide ones, `categoryId == ''`).
List<Exercise> filterExercises(
  List<Exercise> library, {
  String categoryId = '',
  String query = '',
  String space = '',
  String intensity = '',
  int? minPlayers,
  int? maxPlayers,
}) {
  final q = query.trim().toLowerCase();
  final spaceQuery = space.trim().toLowerCase();
  final intensityQuery = intensity.trim().toLowerCase();
  return library.where((exercise) {
    if (categoryId.isNotEmpty &&
        exercise.categoryId.isNotEmpty &&
        exercise.categoryId != categoryId) {
      return false;
    }
    if (q.isNotEmpty) {
      final haystack =
          '${exercise.name} ${exercise.description} ${exercise.objective}'
              .toLowerCase();
      if (!haystack.contains(q)) return false;
    }
    if (spaceQuery.isNotEmpty &&
        !exercise.space.toLowerCase().contains(spaceQuery)) {
      return false;
    }
    if (intensityQuery.isNotEmpty &&
        !exercise.intensity.toLowerCase().contains(intensityQuery)) {
      return false;
    }
    if (minPlayers != null && exercise.players > 0 && exercise.players < minPlayers) {
      return false;
    }
    if (maxPlayers != null && exercise.players > 0 && exercise.players > maxPlayers) {
      return false;
    }
    return true;
  }).toList();
}
