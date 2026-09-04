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

String _normalizeForDedup(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Result of checking a would-be library capture against what's already
/// saved, so the caller can decide how to react.
enum ExerciseDedupResult {
  /// Same name, duration and description (normalized) — already saved,
  /// nothing new to add.
  exactMatch,

  /// Same name but something else differs — likely the same exercise
  /// tweaked, or a coincidence. Worth a confirmation, not a hard block.
  nameMatch,

  /// No obvious match — safe to save.
  none,
}

/// Checks a candidate exercise (about to be captured from an AI block, or
/// entered by hand) against the existing library. There's no stable
/// "origin id" on a generated block, so this compares normalized
/// name/duration/description instead.
ExerciseDedupResult findExerciseDuplicate({
  required List<Exercise> library,
  required String name,
  required int duration,
  required String description,
}) {
  final normalizedName = _normalizeForDedup(name);
  if (normalizedName.isEmpty) return ExerciseDedupResult.none;
  final normalizedDescription = _normalizeForDedup(description);
  for (final existing in library) {
    if (_normalizeForDedup(existing.name) != normalizedName) continue;
    final sameDuration = existing.duration == duration;
    final sameDescription =
        _normalizeForDedup(existing.description) == normalizedDescription;
    if (sameDuration && sameDescription) return ExerciseDedupResult.exactMatch;
    return ExerciseDedupResult.nameMatch;
  }
  return ExerciseDedupResult.none;
}

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
