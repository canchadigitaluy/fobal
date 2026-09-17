// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'supabase_auth_service.dart';

class AdminAccountsException implements Exception {
  final String message;
  const AdminAccountsException(this.message);
  @override
  String toString() => message;
}

class AdminManualClub {
  final String clubId;
  final String name;
  final String updatedAt;
  final List<String> categories;
  const AdminManualClub({
    required this.clubId,
    required this.name,
    required this.updatedAt,
    this.categories = const [],
  });

  factory AdminManualClub.fromJson(Map<String, dynamic> json) =>
      AdminManualClub(
        clubId: json['clubId'] as String? ?? '',
        name: json['name'] as String? ?? '',
        updatedAt: json['updatedAt'] as String? ?? '',
        categories: (json['categories'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      );
}

class AdminLudMembership {
  final String name;
  final String role;
  final String status;
  const AdminLudMembership({
    required this.name,
    required this.role,
    required this.status,
  });

  factory AdminLudMembership.fromJson(Map<String, dynamic> json) =>
      AdminLudMembership(
        name: json['name'] as String? ?? '',
        role: json['role'] as String? ?? '',
        status: json['status'] as String? ?? '',
      );
}

/// One registered fobal account, as seen from the platform-admin panel —
/// combines auth.users (via /api/admin-accounts) with both club worlds a
/// person can belong to: a self-made manual club, and/or LUD memberships.
class AdminAccount {
  final String userId;
  final String email;
  final String fullName;
  final String createdAt;
  final bool banned;
  final List<AdminManualClub> manualClubs;
  final List<AdminLudMembership> ludMemberships;

  const AdminAccount({
    required this.userId,
    required this.email,
    required this.fullName,
    required this.createdAt,
    required this.banned,
    required this.manualClubs,
    required this.ludMemberships,
  });

  factory AdminAccount.fromJson(Map<String, dynamic> json) => AdminAccount(
    userId: json['userId'] as String? ?? '',
    email: json['email'] as String? ?? '',
    fullName: json['fullName'] as String? ?? '',
    createdAt: json['createdAt'] as String? ?? '',
    banned: json['banned'] as bool? ?? false,
    manualClubs: (json['manualClubs'] as List<dynamic>? ?? [])
        .map((e) => AdminManualClub.fromJson(e as Map<String, dynamic>))
        .toList(),
    ludMemberships: (json['ludMemberships'] as List<dynamic>? ?? [])
        .map((e) => AdminLudMembership.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class PlatformMetrics {
  final int activeUsers;
  final int manualClubs;
  final int activeLudClubs;
  final int activeCollaborators;
  final int recentUsers;
  final int recentManualClubs;
  final int recentLudMemberships;
  final String recentSince;

  const PlatformMetrics({
    required this.activeUsers,
    required this.manualClubs,
    required this.activeLudClubs,
    required this.activeCollaborators,
    required this.recentUsers,
    required this.recentManualClubs,
    required this.recentLudMemberships,
    required this.recentSince,
  });

  int get recentTotal =>
      recentUsers + recentManualClubs + recentLudMemberships;

  factory PlatformMetrics.fromJson(Map<String, dynamic> json) =>
      PlatformMetrics(
        activeUsers: json['activeUsers'] as int? ?? 0,
        manualClubs: json['manualClubs'] as int? ?? 0,
        activeLudClubs: json['activeLudClubs'] as int? ?? 0,
        activeCollaborators: json['activeCollaborators'] as int? ?? 0,
        recentUsers: json['recentUsers'] as int? ?? 0,
        recentManualClubs: json['recentManualClubs'] as int? ?? 0,
        recentLudMemberships: json['recentLudMemberships'] as int? ?? 0,
        recentSince: json['recentSince'] as String? ?? '',
      );
}

class AdminAccountsService {
  const AdminAccountsService._();

  static String? get _token => SupabaseAuthService.currentSession?.accessToken;

  // Shares /api/review-club-membership with the per-club membership review
  // flow (distinguished by the "action" field) to stay under Vercel's
  // Hobby-plan serverless function cap instead of shipping a new endpoint.
  static const _endpoint = '/api/review-club-membership';

  static Future<List<AdminAccount>> listAccounts() async {
    final token = _token;
    if (token == null) {
      throw const AdminAccountsException('Tu sesion no esta disponible.');
    }
    final response = await http
        .post(
          Uri.base.resolve(_endpoint),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $token',
          },
          body: jsonEncode({'action': 'list_accounts'}),
        )
        .timeout(const Duration(seconds: 15));
    final data = _decode(response);
    return (data['accounts'] as List<dynamic>? ?? [])
        .map((e) => AdminAccount.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<PlatformMetrics> platformMetrics() async {
    final token = _token;
    if (token == null) {
      throw const AdminAccountsException('Tu sesion no esta disponible.');
    }
    final response = await http
        .post(
          Uri.base.resolve(_endpoint),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $token',
          },
          body: jsonEncode({'action': 'platform_metrics'}),
        )
        .timeout(const Duration(seconds: 15));
    final data = _decode(response);
    return PlatformMetrics.fromJson(
      data['metrics'] as Map<String, dynamic>? ?? const {},
    );
  }

  static Future<void> setBanned(String userId, bool banned) async {
    final token = _token;
    if (token == null) {
      throw const AdminAccountsException('Tu sesion no esta disponible.');
    }
    final response = await http
        .post(
          Uri.base.resolve(_endpoint),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'userId': userId,
            'action': banned ? 'ban' : 'unban',
          }),
        )
        .timeout(const Duration(seconds: 15));
    _decode(response);
  }

  static Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> data = const {};
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      // fall through to status-based message below
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AdminAccountsException(
        data['message'] as String? ?? 'No se pudo completar la accion.',
      );
    }
    return data;
  }
}
