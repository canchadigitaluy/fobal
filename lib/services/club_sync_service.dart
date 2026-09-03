// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:convert';
import 'dart:html' as html;

import '../data/cantera_data.dart';
import 'club_backup_codec.dart';
import 'supabase_auth_service.dart';

/// Cloud mirror of the full [CanteraClub] blob, one row per (user, club).
///
/// Phase 2a is read-only: [pull] is wired into hydration, [push] exists for
/// Phase 2b and manual use but nothing calls it automatically. No backfill,
/// no debounce, no conflict UI yet.
class ClubSyncService {
  const ClubSyncService._();

  static const _versionKeyPrefix = 'fobal_club_doc_version_';
  static const _dirtyKeyPrefix = 'fobal_club_dirty_';
  static const _deviceKey = 'fobal_device_id';

  /// True when the local blob for [clubId] has unsynced edits. Phase 2a never
  /// sets this (no push path yet), so it is always false today — the guard is
  /// here so the pull path is already correct when Phase 2b starts writing it.
  static bool isDirty(String clubId) =>
      html.window.localStorage['$_dirtyKeyPrefix$clubId'] == '1';

  /// Last cloud [version] this device has already adopted for [clubId] (0 when
  /// never synced).
  static int knownServerVersion(String clubId) =>
      int.tryParse(html.window.localStorage['$_versionKeyPrefix$clubId'] ?? '') ??
      0;

  static void rememberVersion(String clubId, int version) {
    html.window.localStorage['$_versionKeyPrefix$clubId'] = '$version';
  }

  static String deviceId() {
    var id = html.window.localStorage[_deviceKey];
    if (id == null || id.isEmpty) {
      id = 'dev-${DateTime.now().microsecondsSinceEpoch}-'
          '${(html.window.performance.now() * 1000).round()}';
      html.window.localStorage[_deviceKey] = id;
    }
    return id;
  }

  /// Reads the cloud document for [clubId]. Returns null when there is none,
  /// auth is not ready, the network fails, or the row does not parse as a club.
  static Future<ClubDocument?> pull(String clubId) async {
    if (!SupabaseAuthService.isConfigured ||
        SupabaseAuthService.currentSession == null) {
      return null;
    }
    try {
      final rows = await SupabaseAuthService.client
          .from('club_documents')
          .select('data, version')
          .eq('club_id', clubId)
          .limit(1);
      if (rows.isEmpty) return null;
      final row = rows.first;
      final version = (row['version'] as num?)?.toInt() ?? 0;
      final rawData = row['data'];
      if (rawData is! Map) return null;
      final club = ClubBackupCodec.parseClubJson(jsonEncode(rawData));
      if (club == null) return null;
      return ClubDocument(club: club, version: version);
    } catch (_) {
      return null;
    }
  }

  /// Optimistic-concurrency write. NOT called automatically in Phase 2a.
  static Future<ClubPushResult> push(
    String clubId,
    CanteraClub club,
    int baseVersion,
  ) async {
    if (!SupabaseAuthService.isConfigured ||
        SupabaseAuthService.currentSession == null) {
      return const ClubPushResult(ClubPushOutcome.skipped);
    }
    try {
      final res = await SupabaseAuthService.client.rpc(
        'push_club_document',
        params: {
          'p_club_id': clubId,
          'p_data': club.toJson(),
          'p_base_version': baseVersion,
          'p_device_id': deviceId(),
        },
      );
      final map = (res is List ? res.first : res) as Map<String, dynamic>;
      final version = (map['version'] as num?)?.toInt() ?? baseVersion + 1;
      rememberVersion(clubId, version);
      return ClubPushResult(ClubPushOutcome.ok, version: version);
    } catch (error) {
      final text = error.toString();
      if (text.contains('version_conflict')) {
        return const ClubPushResult(ClubPushOutcome.conflict);
      }
      if (text.contains('document_too_large')) {
        return const ClubPushResult(ClubPushOutcome.tooLarge);
      }
      return const ClubPushResult(ClubPushOutcome.error);
    }
  }
}

class ClubDocument {
  final CanteraClub club;
  final int version;

  const ClubDocument({required this.club, required this.version});
}

enum ClubPushOutcome { ok, conflict, tooLarge, error, skipped }

class ClubPushResult {
  final ClubPushOutcome outcome;
  final int? version;

  const ClubPushResult(this.outcome, {this.version});

  bool get ok => outcome == ClubPushOutcome.ok;
}
