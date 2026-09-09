// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import '../data/cantera_data.dart';
import 'club_backup_codec.dart';
import 'supabase_auth_service.dart';
import 'sync_conflict_service.dart';

/// Cloud mirror of the full [CanteraClub] blob, one row per (user, club).
///
/// Phase 2a wired [pull] into hydration (read-only). Phase 2b adds automatic
/// push: the local blob stays the working copy, and edits are mirrored to
/// `club_documents` when there is a session and connectivity. Still no
/// backfill and no full conflict UI — a conflict stashes the local copy,
/// adopts the server version, and shows a simple message.
class ClubSyncService {
  const ClubSyncService._();

  static const _mainBlobPrefix = 'cantera_os_club_';
  static const _versionKeyPrefix = 'fobal_club_doc_version_';
  static const _dirtyKeyPrefix = 'fobal_club_dirty_';
  static const _pushedAtKeyPrefix = 'fobal_club_pushed_at_';
  static const _pushedHashKeyPrefix = 'fobal_club_pushed_hash_';
  static const _conflictKeyPrefix = 'fobal_club_conflicts_';
  static const _syncErrorKeyPrefix = 'fobal_club_sync_error_';
  static const _deviceKey = 'fobal_device_id';

  static final _events = StreamController<ClubSyncEvent>.broadcast();

  /// Emits when a push succeeds ([ClubSyncEventType.synced]) or a conflict was
  /// resolved by adopting the server version ([ClubSyncEventType.conflict]).
  static Stream<ClubSyncEvent> get events => _events.stream;

  static bool get _canSync =>
      SupabaseAuthService.isConfigured &&
      SupabaseAuthService.currentSession != null;

  // --- dirty / version bookkeeping ----------------------------------------

  /// True when the local blob for [clubId] has edits not yet mirrored.
  static bool isDirty(String clubId) =>
      html.window.localStorage['$_dirtyKeyPrefix$clubId'] == '1';

  static void markDirty(String clubId) {
    html.window.localStorage['$_dirtyKeyPrefix$clubId'] = '1';
  }

  static void clearDirty(String clubId) {
    html.window.localStorage.remove('$_dirtyKeyPrefix$clubId');
  }

  /// Last cloud [version] this device has already adopted for [clubId].
  static int knownServerVersion(String clubId) =>
      int.tryParse(
        html.window.localStorage['$_versionKeyPrefix$clubId'] ?? '',
      ) ??
      0;

  static void rememberVersion(String clubId, int version) {
    html.window.localStorage['$_versionKeyPrefix$clubId'] = '$version';
  }

  static DateTime? lastPushedAt(String clubId) {
    final raw = html.window.localStorage['$_pushedAtKeyPrefix$clubId'];
    return raw == null ? null : DateTime.tryParse(raw)?.toLocal();
  }

  static void _rememberPushed(String clubId, String rawBlob) {
    html.window.localStorage['$_pushedAtKeyPrefix$clubId'] = DateTime.now()
        .toUtc()
        .toIso8601String();
    html.window.localStorage['$_pushedHashKeyPrefix$clubId'] =
        '${rawBlob.hashCode}';
  }

  /// Change-detection so an unchanged blob is not re-pushed (which would only
  /// inflate the version). Cheap hash; a hash miss just costs one extra push,
  /// never data.
  static bool _unchangedSinceLastPush(String clubId, String rawBlob) =>
      html.window.localStorage['$_pushedHashKeyPrefix$clubId'] ==
      '${rawBlob.hashCode}';

  static List<SyncConflictSnapshot> conflicts(String clubId) {
    try {
      final raw = html.window.localStorage['$_conflictKeyPrefix$clubId'];
      if (raw == null) return [];
      return (jsonDecode(raw) as List<dynamic>)
          .whereType<Map>()
          .map(
            (item) =>
                SyncConflictSnapshot.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((item) => item.id.isNotEmpty && item.rawClub.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static void stashConflict(String clubId, String rawBlob) {
    try {
      final snapshot = SyncConflictSnapshot(
        id: 'conflict-${DateTime.now().microsecondsSinceEpoch}',
        clubId: clubId,
        baseVersion: knownServerVersion(clubId),
        createdAt: DateTime.now().toUtc().toIso8601String(),
        rawClub: rawBlob,
        bytes: utf8.encode(rawBlob).length,
      );
      final next = retainConflictSnapshots(conflicts(clubId), snapshot);
      html.window.localStorage['$_conflictKeyPrefix$clubId'] = jsonEncode(
        next.map((item) => item.toJson()).toList(),
      );
    } catch (_) {}
  }

  static void discardConflict(String clubId, String snapshotId) {
    final next = conflicts(
      clubId,
    ).where((item) => item.id != snapshotId).toList();
    if (next.isEmpty) {
      html.window.localStorage.remove('$_conflictKeyPrefix$clubId');
    } else {
      html.window.localStorage['$_conflictKeyPrefix$clubId'] = jsonEncode(
        next.map((item) => item.toJson()).toList(),
      );
    }
    _events.add(ClubSyncEvent(ClubSyncEventType.statusChanged, clubId));
  }

  static String? syncError(String clubId) =>
      html.window.localStorage['$_syncErrorKeyPrefix$clubId'];

  static void _setSyncError(String clubId, String message) {
    html.window.localStorage['$_syncErrorKeyPrefix$clubId'] = message;
  }

  static void _clearSyncError(String clubId) {
    html.window.localStorage.remove('$_syncErrorKeyPrefix$clubId');
  }

  static String deviceId() {
    var id = html.window.localStorage[_deviceKey];
    if (id == null || id.isEmpty) {
      id =
          'dev-${DateTime.now().microsecondsSinceEpoch}-'
          '${(html.window.performance.now() * 1000).round()}';
      html.window.localStorage[_deviceKey] = id;
    }
    return id;
  }

  // --- read -------------------------------------------------------------------

  /// Reads the cloud document for [clubId]. Returns null when there is none,
  /// auth is not ready, the network fails, or the row does not parse as a club.
  static Future<ClubDocument?> pull(String clubId) async {
    if (!_canSync) return null;
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

  /// Finds the newest manual workspace visible to the authenticated user.
  /// RLS on `club_documents` limits the result set to `auth.uid()`, so this is
  /// safe to use when a browser has no user-scoped local pointer yet.
  static Future<ClubDocument?> pullLatestOwnedManualClub() async {
    if (!_canSync) return null;
    try {
      final rows = await SupabaseAuthService.client
          .from('club_documents')
          .select('data, version, updated_at')
          .order('updated_at', ascending: false)
          .limit(50);
      for (final row in rows) {
        final rawData = row['data'];
        if (rawData is! Map) continue;
        final club = ClubBackupCodec.parseClubJson(jsonEncode(rawData));
        if (club == null || !club.isManualClub) continue;
        return ClubDocument(
          club: club,
          version: (row['version'] as num?)?.toInt() ?? 0,
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // --- write ---------------------------------------------------------------

  /// Pushes the CURRENT local blob for [clubId] (read fresh from storage, never
  /// a stale copy). Called from the offline mutation queue, so it is only
  /// reached when there is a session and connectivity.
  ///
  /// On success: remembers the new version + timestamp, clears dirty, emits
  /// [ClubSyncEventType.synced].
  /// On conflict: stashes the local blob, adopts the server version into the
  /// blob, clears dirty, emits [ClubSyncEventType.conflict]. Returns true so
  /// the queue drops the mutation instead of looping.
  static Future<ClubQueueOutcome> pushCurrentLocal(String clubId) async {
    if (!_canSync) return ClubQueueOutcome.keep;

    final raw = html.window.localStorage['$_mainBlobPrefix$clubId'];
    final club = raw == null ? null : ClubBackupCodec.parseClubJson(raw);
    if (raw == null || club == null) return ClubQueueOutcome.drop;

    if (_unchangedSinceLastPush(clubId, raw)) {
      clearDirty(clubId);
      return ClubQueueOutcome.drop;
    }

    final result = await push(clubId, club, knownServerVersion(clubId));
    switch (result.outcome) {
      case ClubPushOutcome.ok:
        _clearSyncError(clubId);
        _rememberPushed(clubId, raw);
        clearDirty(clubId);
        _events.add(ClubSyncEvent(ClubSyncEventType.synced, clubId));
        return ClubQueueOutcome.drop;
      case ClubPushOutcome.conflict:
        stashConflict(clubId, raw);
        final doc = await pull(clubId);
        if (doc != null && doc.club.id == clubId) {
          html.window.localStorage['$_mainBlobPrefix$clubId'] = jsonEncode(
            doc.club.toJson(),
          );
          rememberVersion(clubId, doc.version);
          _rememberPushed(clubId, jsonEncode(doc.club.toJson()));
        }
        clearDirty(clubId);
        _events.add(ClubSyncEvent(ClubSyncEventType.conflict, clubId));
        return ClubQueueOutcome.drop;
      case ClubPushOutcome.tooLarge:
        _setSyncError(
          clubId,
          'El club superó el límite sincronizable. La copia local sigue guardada.',
        );
        _events.add(ClubSyncEvent(ClubSyncEventType.tooLarge, clubId));
        return ClubQueueOutcome.drop;
      case ClubPushOutcome.skipped:
        return ClubQueueOutcome.keep;
      case ClubPushOutcome.error:
        return ClubQueueOutcome.keep;
    }
  }

  /// Low-level optimistic-concurrency write. Prefer [pushCurrentLocal].
  static Future<ClubPushResult> push(
    String clubId,
    CanteraClub club,
    int baseVersion,
  ) async {
    if (!_canSync) return const ClubPushResult(ClubPushOutcome.skipped);
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

  static Future<bool> restoreConflict(SyncConflictSnapshot snapshot) async {
    final localClub = snapshot.parseClub();
    if (localClub == null || localClub.id != snapshot.clubId) return false;
    final current = await pull(snapshot.clubId);
    if (current == null) return false;
    final result = await push(snapshot.clubId, localClub, current.version);
    if (!result.ok) {
      if (result.outcome == ClubPushOutcome.conflict) {
        stashConflict(snapshot.clubId, snapshot.rawClub);
      }
      return false;
    }
    html.window.localStorage['$_mainBlobPrefix${snapshot.clubId}'] =
        snapshot.rawClub;
    _rememberPushed(snapshot.clubId, snapshot.rawClub);
    clearDirty(snapshot.clubId);
    discardConflict(snapshot.clubId, snapshot.id);
    _events.add(ClubSyncEvent(ClubSyncEventType.restored, snapshot.clubId));
    return true;
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

/// What the offline queue should do with a `club_document.push` mutation after
/// an attempt.
enum ClubQueueOutcome { drop, keep }

enum ClubSyncEventType { synced, conflict, restored, tooLarge, statusChanged }

class ClubSyncEvent {
  final ClubSyncEventType type;
  final String clubId;

  const ClubSyncEvent(this.type, this.clubId);
}
