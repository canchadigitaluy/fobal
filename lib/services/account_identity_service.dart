// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;

import 'account_identity.dart';
import 'supabase_auth_service.dart';

/// Owns every browser pointer that selects a user's working space.
///
/// Club data is never selected through the old global keys: two authenticated
/// users sharing a browser must always resolve independent workspaces.
class AccountIdentityService {
  const AccountIdentityService._();

  static const legacyLocalClubKey = 'fobal_local_profile_club_id';
  static const legacyActiveClubKey = 'fobal_active_club_id';

  static String localClubKeyFor(String userId) => localClubKeyForUser(userId);

  static String activeClubKeyFor(String userId) => activeClubKeyForUser(userId);

  static String manualClubIdFor(String userId, String clubSlug) =>
      manualClubIdForUser(userId, clubSlug);

  static String? get currentUserId {
    final value = SupabaseAuthService.currentUserId?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static String? readLocalClubId() => _readForCurrentUser(localClubKeyFor);

  static String? readActiveClubId() => _readForCurrentUser(activeClubKeyFor);

  static void writeLocalClubId(String clubId) =>
      _writeForCurrentUser(localClubKeyFor, clubId);

  static void writeActiveClubId(String clubId) =>
      _writeForCurrentUser(activeClubKeyFor, clubId);

  static String? _readForCurrentUser(String Function(String) keyFor) {
    final userId = currentUserId;
    if (userId == null) return null;
    final value = html.window.localStorage[keyFor(userId)]?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static void _writeForCurrentUser(
    String Function(String) keyFor,
    String value,
  ) {
    final userId = currentUserId;
    if (userId == null || value.trim().isEmpty) return;
    html.window.localStorage[keyFor(userId)] = value.trim();
  }
}
