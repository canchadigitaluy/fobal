// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;

import '../data/cantera_data.dart';
import 'club_backup_codec.dart';

/// Offline safety net for the single-blob club store.
///
/// * Keeps the last [_keepSnapshots] versions of the main blob so an
///   accidental overwrite or a corrupted write can be rolled back.
/// * Exposes a manual JSON export/import the user can trigger by hand.
///
/// The serialization format is [ClubBackupCodec] / [CanteraClub.toJson]; this
/// class only moves those strings in and out of `localStorage` and the browser.
class ClubBackupService {
  const ClubBackupService._();

  static const _mainPrefix = 'cantera_os_club_';
  static const _snapshotPrefix = 'fobal_club_backup_';
  static const _corruptPrefix = 'fobal_club_corrupt_';
  static const _keepSnapshots = 3;

  static String _mainKey(String clubId) => '$_mainPrefix$clubId';
  static String _slotKey(String clubId, int slot) =>
      '$_snapshotPrefix${clubId}_$slot';

  /// Call right before overwriting the main blob for [clubId]. Pushes the value
  /// currently on disk into slot 0 and shifts older snapshots down, keeping the
  /// most recent [_keepSnapshots]. No-op when nothing is stored yet or the
  /// current value already matches the newest snapshot.
  static void rotateSnapshot(String clubId) {
    final current = html.window.localStorage[_mainKey(clubId)];
    if (current == null || current.isEmpty) return;
    if (html.window.localStorage[_slotKey(clubId, 0)] == current) return;
    for (var slot = _keepSnapshots - 1; slot > 0; slot--) {
      final older = html.window.localStorage[_slotKey(clubId, slot - 1)];
      if (older == null || older.isEmpty) {
        html.window.localStorage.remove(_slotKey(clubId, slot));
      } else {
        html.window.localStorage[_slotKey(clubId, slot)] = older;
      }
    }
    if (!_trySet(_slotKey(clubId, 0), current)) {
      // Quota hit: drop the oldest snapshot and try once more.
      html.window.localStorage.remove(_slotKey(clubId, _keepSnapshots - 1));
      _trySet(_slotKey(clubId, 0), current);
    }
  }

  /// Most recent snapshot for [clubId] that still parses into a [CanteraClub],
  /// or null when there is none.
  static CanteraClub? latestValidSnapshot(String clubId) {
    for (var slot = 0; slot < _keepSnapshots; slot++) {
      final club =
          ClubBackupCodec.parseClubJson(html.window.localStorage[_slotKey(clubId, slot)] ?? '');
      if (club != null) return club;
    }
    return null;
  }

  /// The main blob for [clubId] failed to parse. Stash the broken value under a
  /// dedicated key (so a manual recovery stays possible) and return the newest
  /// valid snapshot to fall back to, or null when there is nothing to restore.
  static CanteraClub? recoverCorruptMain(String clubId) {
    final broken = html.window.localStorage[_mainKey(clubId)];
    if (broken != null && broken.isNotEmpty) {
      _trySet('$_corruptPrefix$clubId', broken);
    }
    return latestValidSnapshot(clubId);
  }

  /// Triggers a browser download of [club] as a formatted JSON file.
  static void downloadJson(CanteraClub club) {
    final safeName = club.name.trim().isEmpty
        ? 'club'
        : club.name.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_');
    final stamp = DateTime.now().toIso8601String().split('T').first;
    final blob = html.Blob(
      <Object>[ClubBackupCodec.exportJson(club)],
      'application/json',
    );
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..download = 'fobal_${safeName}_$stamp.json'
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  /// Opens a file picker and returns the parsed club. Throws
  /// [ClubBackupException] with a user-facing message on any failure.
  static Future<CanteraClub> pickAndParse() async {
    final input = html.FileUploadInputElement()
      ..accept = '.json,application/json';
    input.click();
    await input.onChange.first;
    final file = input.files?.isNotEmpty == true ? input.files!.first : null;
    if (file == null) {
      throw const ClubBackupException('No se eligió ningún archivo.');
    }
    final reader = html.FileReader()..readAsText(file);
    await reader.onLoad.first;
    final club = ClubBackupCodec.parseClubJson(reader.result as String? ?? '');
    if (club == null) {
      throw const ClubBackupException(
        'El archivo no tiene un formato válido de fobal.',
      );
    }
    return club;
  }

  static bool _trySet(String key, String value) {
    try {
      html.window.localStorage[key] = value;
      return true;
    } catch (_) {
      return false;
    }
  }
}

class ClubBackupException implements Exception {
  final String message;
  const ClubBackupException(this.message);

  @override
  String toString() => message;
}
