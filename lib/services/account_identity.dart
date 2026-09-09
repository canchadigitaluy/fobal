String localClubKeyForUser(String userId) =>
    'fobal_local_profile_club_id_${safeAccountUserId(userId)}';

String activeClubKeyForUser(String userId) =>
    'fobal_active_club_id_${safeAccountUserId(userId)}';

String manualClubIdForUser(String userId, String clubSlug) {
  final owner = safeAccountUserId(userId).replaceAll('-', '');
  final shortOwner = owner.length <= 16 ? owner : owner.substring(0, 16);
  final safeSlug = clubSlug.isEmpty ? 'equipo' : clubSlug;
  return 'externo-$shortOwner-$safeSlug';
}

String safeAccountUserId(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9-]'), '_');
