import 'dart:convert';

import '../data/cantera_data.dart';

/// Pure (no `dart:html`) serialization for the single-blob club store, shared by
/// [ClubBackupService] and reusable from VM tests. The on-disk format is exactly
/// [CanteraClub.toJson] — this codec never changes the shape, it only adds a
/// sanity gate so a random JSON file is not mistaken for a club.
class ClubBackupCodec {
  const ClubBackupCodec._();

  /// Human-readable JSON for a manual export.
  static String exportJson(CanteraClub club) =>
      const JsonEncoder.withIndent('  ').convert(club.toJson());

  /// Parses [raw] into a [CanteraClub], or returns null when it is not valid
  /// JSON, not an object, or does not look like a club export.
  ///
  /// The shape check matters because [CanteraClub.fromJson] is lenient: given
  /// `{"foo": 1}` it would happily return a demo club with default fields
  /// instead of failing, which would silently wipe real data on import.
  static CanteraClub? parseClubJson(String raw) {
    if (raw.trim().isEmpty) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    if (decoded['id'] is! String || (decoded['id'] as String).isEmpty) {
      return null;
    }
    final looksLikeClub = decoded.containsKey('name') ||
        decoded.containsKey('categories') ||
        decoded.containsKey('players') ||
        decoded.containsKey('methodology');
    if (!looksLikeClub) return null;
    try {
      return CanteraClub.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }
}
