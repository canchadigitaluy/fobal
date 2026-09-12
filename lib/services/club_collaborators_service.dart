// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'supabase_auth_service.dart';

class ClubCollaboratorsException implements Exception {
  final String message;
  final String? code;
  const ClubCollaboratorsException(this.message, {this.code});
  @override
  String toString() => message;
}

class ClubCollaborator {
  final String userId;
  final String role;
  final String email;
  final String fullName;
  const ClubCollaborator({
    required this.userId,
    required this.role,
    required this.email,
    required this.fullName,
  });

  factory ClubCollaborator.fromJson(Map<String, dynamic> json) =>
      ClubCollaborator(
        userId: json['userId'] as String? ?? '',
        role: json['role'] as String? ?? 'coach',
        email: json['email'] as String? ?? '',
        fullName: json['fullName'] as String? ?? '',
      );
}

/// A manual club another owner invited the current user into.
class ClubCollaboration {
  final String clubId;
  final String role;
  final String clubName;
  const ClubCollaboration({
    required this.clubId,
    required this.role,
    required this.clubName,
  });

  factory ClubCollaboration.fromJson(Map<String, dynamic> json) =>
      ClubCollaboration(
        clubId: json['clubId'] as String? ?? '',
        role: json['role'] as String? ?? 'coach',
        clubName: json['clubName'] as String? ?? 'Club',
      );
}

/// Roles a club owner can grant a collaborator. Same vocabulary as the LUD
/// membership roles (`club_memberships.role`) so the two systems read the
/// same way in the UI, even though they're backed by separate tables.
const clubCollaboratorRoles = [
  'coach',
  'assistant',
  'physical_trainer',
  'viewer',
];

/// Invite/manage collaborators on a manual (No-LUD) club. Shares
/// /api/review-club-membership with the LUD membership review flow and the
/// platform-admin panel (distinguished by the `action` field) to stay under
/// Vercel's Hobby-plan serverless function cap.
class ClubCollaboratorsService {
  const ClubCollaboratorsService._();

  static const _endpoint = '/api/review-club-membership';

  static String? get _token => SupabaseAuthService.currentSession?.accessToken;

  static Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    final token = _token;
    if (token == null) {
      throw const ClubCollaboratorsException('Tu sesion no esta disponible.');
    }
    final response = await http
        .post(
          Uri.base.resolve(_endpoint),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $token',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    Map<String, dynamic> data = const {};
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {}
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ClubCollaboratorsException(
        data['message'] as String? ?? 'No se pudo completar la accion.',
        code: data['error'] as String?,
      );
    }
    return data;
  }

  static Future<List<ClubCollaborator>> list(String clubId) async {
    final data = await _post({
      'action': 'list_collaborators',
      'clubId': clubId,
    });
    return (data['collaborators'] as List<dynamic>? ?? [])
        .map((e) => ClubCollaborator.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> invite({
    required String clubId,
    required String email,
    required String role,
  }) => _post({
    'action': 'invite_collaborator',
    'clubId': clubId,
    'email': email,
    'role': role,
  });

  static Future<void> revoke({
    required String clubId,
    required String userId,
  }) => _post({
    'action': 'revoke_collaborator',
    'clubId': clubId,
    'userId': userId,
  });

  /// Clubs someone else invited the current user into.
  static Future<List<ClubCollaboration>> myCollaborations() async {
    final data = await _post({'action': 'list_my_collaborations'});
    return (data['collaborations'] as List<dynamic>? ?? [])
        .map((e) => ClubCollaboration.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
