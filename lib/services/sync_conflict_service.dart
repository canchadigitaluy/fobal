import 'dart:convert';

import '../data/cantera_data.dart';

class SyncConflictSnapshot {
  final String id;
  final String clubId;
  final int baseVersion;
  final String createdAt;
  final String rawClub;
  final int bytes;

  const SyncConflictSnapshot({
    required this.id,
    required this.clubId,
    required this.baseVersion,
    required this.createdAt,
    required this.rawClub,
    required this.bytes,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'clubId': clubId,
    'baseVersion': baseVersion,
    'createdAt': createdAt,
    'rawClub': rawClub,
    'bytes': bytes,
  };

  factory SyncConflictSnapshot.fromJson(Map<String, dynamic> json) =>
      SyncConflictSnapshot(
        id: json['id'] as String? ?? '',
        clubId: json['clubId'] as String? ?? '',
        baseVersion: (json['baseVersion'] as num?)?.toInt() ?? 0,
        createdAt: json['createdAt'] as String? ?? '',
        rawClub: json['rawClub'] as String? ?? '',
        bytes: (json['bytes'] as num?)?.toInt() ?? 0,
      );

  CanteraClub? parseClub() {
    try {
      return CanteraClub.fromJson(
        Map<String, dynamic>.from(jsonDecode(rawClub) as Map),
      );
    } catch (_) {
      return null;
    }
  }
}

List<SyncConflictSnapshot> retainConflictSnapshots(
  List<SyncConflictSnapshot> current,
  SyncConflictSnapshot incoming,
) {
  final unique = [incoming, ...current.where((item) => item.id != incoming.id)];
  // Conflict copies are unresolved by definition. Never evict one silently.
  // The UI encourages reviewing the newest three first, but older unresolved
  // copies remain recoverable.
  return unique;
}

class ClubDifferenceSummary {
  final int players;
  final int sessions;
  final int results;
  final int attendanceRecords;

  const ClubDifferenceSummary({
    required this.players,
    required this.sessions,
    required this.results,
    required this.attendanceRecords,
  });
}

ClubDifferenceSummary summarizeClubDifferences(
  CanteraClub local,
  CanteraClub current,
) {
  int changedById<T>(
    List<T> a,
    List<T> b,
    String Function(T) id,
    Map<String, dynamic> Function(T) json,
  ) {
    final left = {for (final item in a) id(item): json(item)};
    final right = {for (final item in b) id(item): json(item)};
    final ids = {...left.keys, ...right.keys};
    return ids
        .where((key) => jsonEncode(left[key]) != jsonEncode(right[key]))
        .length;
  }

  return ClubDifferenceSummary(
    players: changedById(
      local.players,
      current.players,
      (p) => p.id,
      (p) => p.toJson(),
    ),
    sessions: changedById(
      local.sessions,
      current.sessions,
      (s) => s.id,
      (s) => s.toJson(),
    ),
    results: changedById(
      local.matchResults,
      current.matchResults,
      (r) => r.id,
      (r) => r.toJson(),
    ),
    attendanceRecords: changedById(
      local.attendanceRecords,
      current.attendanceRecords,
      (r) => '${r.categoryId}|${r.date}',
      (r) => r.toJson(),
    ),
  );
}
