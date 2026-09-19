import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/cantera_data.dart';
import 'supabase_auth_service.dart';

class ClubAccessService {
  static SupabaseClient get _client => SupabaseAuthService.client;
  static String? _selectedClubId;
  static ClubMembership? _previewMembership;
  static ClubMembership? _activeMembershipCache;

  static void selectActiveClub(String clubId) {
    _selectedClubId = clubId;
  }

  static void selectActiveMembership(ClubMembership membership) {
    _previewMembership = null;
    _activeMembershipCache = membership;
    _selectedClubId = membership.clubId;
  }

  static void selectPreviewMembership(ClubMembership membership) {
    _activeMembershipCache = null;
    _previewMembership = membership;
    _selectedClubId = membership.clubId;
  }

  static void clearPreviewMembership() {
    _previewMembership = null;
  }

  static List<CategorySquad> accessibleCategories(
    List<CategorySquad> categories,
  ) {
    final membership = _previewMembership ?? _activeMembershipCache;
    if (membership == null) return categories;
    return membership.accessibleCategories(categories);
  }

  static Future<List<ClubMembership>> activeMemberships() async {
    if (!SupabaseAuthService.isConfigured) return [];
    final userId = SupabaseAuthService.currentUserId;
    if (userId == null) return [];

    final rows = await _client
        .from('club_memberships')
        .select(
          'club_id, role, status, category_ids, cantera_clubs(display_name, lud_team_id)',
        )
        .eq('user_id', userId)
        .eq('status', 'active');
    return rows.map(ClubMembership.fromJson).toList()
      ..sort((a, b) => a.clubName.compareTo(b.clubName));
  }

  static Future<ClubMembership?> activeMembership() async {
    if (_previewMembership != null) {
      return _previewMembership;
    }
    final memberships = await activeMemberships();
    if (memberships.isEmpty) return null;
    if (_selectedClubId == null && memberships.length == 1) {
      _selectedClubId = memberships.first.clubId;
    }
    final membership = memberships.cast<ClubMembership?>().firstWhere(
      (membership) => membership?.clubId == _selectedClubId,
      orElse: () => null,
    );
    if (membership != null) _activeMembershipCache = membership;
    return membership;
  }

  static Future<ClubMembership?> pendingMembership() async {
    if (!SupabaseAuthService.isConfigured) return null;
    final userId = SupabaseAuthService.currentUserId;
    if (userId == null) return null;

    final rows = await _client
        .from('club_memberships')
        .select(
          'club_id, role, status, cantera_clubs(display_name, lud_team_id)',
        )
        .eq('user_id', userId)
        .eq('status', 'pending')
        .limit(1);

    if (rows.isEmpty) return null;
    return ClubMembership.fromJson(rows.first);
  }

  /// Quien dirige un club, visto por quien intenta entrar: 'mine' (ya sos
  /// miembro), 'pending' (tu solicitud espera), 'claimed' (otro lo dirige) o
  /// 'free' (nadie). Si la consulta falla devuelve 'mine': el bloqueo real de
  /// datos lo hace RLS, esto solo evita dejar afuera a alguien por un corte.
  static Future<String> clubClaimStatus(String clubId) async {
    if (!SupabaseAuthService.isConfigured) return 'mine';
    try {
      final status = await _client.rpc(
        'club_claim_status',
        params: {'target_club_id': clubId},
      );
      return status as String? ?? 'mine';
    } catch (_) {
      return 'mine';
    }
  }

  static Future<List<CanteraAccessClub>> listClubs() async {
    if (!SupabaseAuthService.isConfigured) return [];
    dynamic rows;
    try {
      rows = await _client
          .from('cantera_clubs')
          .select('id, display_name, lud_team_id, logo_url')
          .eq('status', 'active')
          .order('display_name')
          .timeout(const Duration(seconds: 6), onTimeout: () => []);
    } catch (_) {
      rows = await _client
          .from('cantera_clubs')
          .select('id, display_name, lud_team_id')
          .eq('status', 'active')
          .order('display_name')
          .timeout(const Duration(seconds: 6), onTimeout: () => []);
    }

    return (rows as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map(CanteraAccessClub.fromJson)
        .toList();
  }

  static Future<List<CanteraAccessClub>> listLigaClubs() async {
    try {
      final response = await http
          .get(
            Uri.base.resolve('/api/lud-teams?v=4'),
            headers: const {'cache-control': 'no-cache'},
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return [];

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return (json['clubs'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(CanteraAccessClub.fromJson)
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
    } catch (_) {
      return [];
    }
  }

  static Future<String> requestAccess({
    required String clubId,
    required String role,
    required String inviteCode,
  }) async {
    final status = await _client.rpc(
      'request_club_access',
      params: {
        'target_club_id': clubId,
        'desired_role': role,
        'invite_code': inviteCode.trim().isEmpty ? null : inviteCode.trim(),
      },
    );
    return status as String? ?? 'pending';
  }

  static Future<CanteraClubContext?> loadClubContext(
    ClubMembership membership,
  ) async {
    // Club-level endpoint: the team comes straight from the membership.
    final teamId = membership.ludTeamId?.trim() ?? '';
    if (teamId.isEmpty) return null;

    final response = await http
        .get(Uri.base.resolve('/api/lud-team-context?teamId=$teamId'))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw ClubContextLoadException(response.statusCode);
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final responseTeamId = int.tryParse(
      (json['team'] as Map<String, dynamic>?)?['id']?.toString() ?? '',
    );
    if (responseTeamId != null && responseTeamId.toString() != teamId) {
      throw const ClubContextLoadException(409);
    }
    return CanteraClubContext.fromJson(json);
  }

  static Future<List<LudFixtureMatch>> loadFixture({
    required ClubMembership membership,
    required CategorySquad category,
    bool forceRefresh = false,
  }) async {
    final target = _ludTarget(membership, category);
    if (target == null) return const [];

    final uri = Uri.base
        .resolve('/api/lud-team-fixture')
        .replace(
          queryParameters: {
            'teamId': '${target.teamId}',
            'clubName': membership.clubName,
            if (target.categoryId != null) 'categoryId': '${target.categoryId}',
            'categoryName': target.categoryName,
            'horizonDays': '120',
            if (forceRefresh)
              '_ts': '${DateTime.now().millisecondsSinceEpoch}',
          },
        );
    final response = await http
        .get(uri, headers: _leagueHeaders(forceRefresh))
        .timeout(const Duration(seconds: 18));
    if (response.statusCode != 200) {
      throw ClubContextLoadException(response.statusCode);
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final diagnostics =
        json['fixtureDiagnostics'] as Map<String, dynamic>? ?? const {};
    final source = json['source']?.toString() ?? '';
    final categoryVerified = diagnostics['categoryVerified'] as bool? ?? true;
    final rawRows = diagnostics['rawRows'] as int? ?? 0;
    final categoryRows = diagnostics['categoryRows'] as int? ?? 0;
    final invalidDateRows = diagnostics['invalidDateRows'] as int? ?? 0;
    final checkedAttempts = diagnostics['checkedAttempts'] as int? ?? 1;
    return (json['matches'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(
          (match) => LudFixtureMatch.fromJson(
            match,
            fixtureSource: source,
            categoryVerified: categoryVerified,
            rawRows: rawRows,
            categoryRows: categoryRows,
            invalidDateRows: invalidDateRows,
            checkedAttempts: checkedAttempts,
          ),
        )
        .where(
          (match) => match.hasValidDate && match.opponentName.trim().isNotEmpty,
        )
        .toList();
  }

  static Future<List<LudFixtureMatch>> loadResults({
    required ClubMembership membership,
    required CategorySquad category,
    bool forceRefresh = false,
  }) async {
    final target = _ludTarget(membership, category);
    if (target == null) return const [];

    final uri = Uri.base.resolve('/api/lud-team-fixture').replace(
      queryParameters: {
        'teamId': '${target.teamId}',
        'clubName': membership.clubName,
        if (target.categoryId != null) 'categoryId': '${target.categoryId}',
        'categoryName': target.categoryName,
        'history': '1',
        // 5 alcanzaba para "ultimos resultados" pero Estadisticas necesita
        // comparar los ultimos 5 contra los 5 anteriores (10 minimo).
        'limit': '10',
        if (forceRefresh) '_ts': '${DateTime.now().millisecondsSinceEpoch}',
      },
    );
    final response = await http
        .get(uri, headers: _leagueHeaders(forceRefresh))
        .timeout(const Duration(seconds: 18));
    if (response.statusCode != 200) {
      throw ClubContextLoadException(response.statusCode);
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final diagnostics =
        json['fixtureDiagnostics'] as Map<String, dynamic>? ?? const {};
    final source = json['source']?.toString() ?? '';
    final categoryVerified = diagnostics['categoryVerified'] as bool? ?? true;
    final played = (json['matches'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(
          (match) => LudFixtureMatch.fromJson(
            match,
            fixtureSource: source,
            categoryVerified: categoryVerified,
          ),
        )
        .where(
          (match) =>
              match.hasValidDate &&
              match.categoryVerified &&
              match.opponentName.trim().isNotEmpty &&
              match.isPlayedResult,
        )
        .toList();
    // Real results only, newest first. No 0-0 padding for rounds that were
    // never played (isPlayedResult already excludes them). 10 so screens
    // that compare "ultimos 5 vs 5 anteriores" have enough to work with.
    played.sort((a, b) => b.date.compareTo(a.date));
    return played.take(10).toList();
  }

  static Future<LudStandingsTable?> loadStandings({
    required ClubMembership membership,
    required CategorySquad category,
    bool forceRefresh = false,
  }) async {
    final target = _ludTarget(membership, category);
    if (target == null) return null;

    final uri = Uri.base.resolve('/api/lud-team-standings').replace(
      queryParameters: {
        'teamId': '${target.teamId}',
        'clubName': membership.clubName,
        if (target.categoryId != null) 'categoryId': '${target.categoryId}',
        'categoryName': target.categoryName,
        if (forceRefresh) '_ts': '${DateTime.now().millisecondsSinceEpoch}',
      },
    );
    final response = await http
        .get(uri, headers: _leagueHeaders(forceRefresh))
        .timeout(const Duration(seconds: 18));
    if (response.statusCode != 200) {
      throw ClubContextLoadException(response.statusCode);
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return LudStandingsTable.fromJson(json);
  }

  static Future<OpponentAnalysis?> loadOpponentAnalysis({
    required LudFixtureMatch match,
    required CategorySquad category,
    bool forceRefresh = false,
  }) async {
    if (match.opponentTeamId == null) return null;
    final uri = Uri.base.resolve('/api/lud-opponent-analysis').replace(
      queryParameters: {
        'opponentTeamId': '${match.opponentTeamId}',
        if (match.phaseId != null) 'phaseId': '${match.phaseId}',
        'categoryName': category.name.trim(),
        if (forceRefresh) '_ts': '${DateTime.now().millisecondsSinceEpoch}',
      },
    );
    final response = await http
        .get(uri, headers: _leagueHeaders(forceRefresh))
        .timeout(const Duration(seconds: 18));
    if (response.statusCode != 200) {
      throw ClubContextLoadException(response.statusCode);
    }
    return OpponentAnalysis.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  static Future<void> prewarmPrimaryLeagueData({
    required ClubMembership membership,
    required List<CategorySquad> categories,
  }) async {
    final category = _preferredCategory(categories);
    if (category == null) return;
    await _prewarmCategory(membership: membership, category: category);
  }

  static Future<void> prewarmAllLeagueData({
    required ClubMembership membership,
    required List<CategorySquad> categories,
  }) async {
    final ordered = [
      if (_preferredCategory(categories) != null) _preferredCategory(categories)!,
      ...categories.where((category) => category.id != _preferredCategory(categories)?.id),
    ];
    await Future.wait(
      ordered.take(8).map(
            (category) => _prewarmCategory(
              membership: membership,
              category: category,
            ),
          ),
      eagerError: false,
    );
  }

  static Future<void> _prewarmCategory({
    required ClubMembership membership,
    required CategorySquad category,
  }) async {
    await Future.wait<void>(
      [
        _ignoreLeagueError(loadStandings(membership: membership, category: category)),
        _ignoreLeagueError(loadFixture(membership: membership, category: category)),
      ],
      eagerError: false,
    );
  }

  static Future<void> _ignoreLeagueError(Future<dynamic> request) async {
    try {
      await request;
    } catch (_) {}
  }

  static CategorySquad? _preferredCategory(List<CategorySquad> categories) {
    if (categories.isEmpty) return null;
    for (final category in categories) {
      final name = category.name.toLowerCase().replaceAll(' ', '');
      if (name.contains('sub18') || name.contains('u18')) return category;
    }
    return categories.first;
  }

  static Future<bool> saveTacticalData({
    required String type,
    required String title,
    required Map<String, dynamic> content,
    int? relatedLudTeamId,
    List<int> relatedLudPlayerIds = const [],
    String? categoryId,
  }) async {
    if (!SupabaseAuthService.isConfigured) return false;
    final userId = SupabaseAuthService.currentUserId;
    if (userId == null) return false;

    final membership = await activeMembership();
    if (membership == null) return false;
    const writableRoles = {
      'platform_admin',
      'club_admin',
      'coach',
      'assistant',
      'physical_trainer',
    };
    if (!writableRoles.contains(membership.role)) return false;

    await _client.from('club_tactical_data').insert({
      'club_id': membership.clubId,
      'created_by': userId,
      'type': type,
      'title': title,
      'content': content,
      'related_lud_team_id': relatedLudTeamId,
      'related_lud_player_ids': relatedLudPlayerIds,
      if (categoryId != null && categoryId.isNotEmpty)
        'category_id': categoryId,
    });
    return true;
  }

  static Future<List<ClubTacticalRecord>> loadTacticalData({
    int limit = 12,
    // When the caller only cares about one record type (calendario,
    // asistencia, etc), pass it so the row limit applies WITHIN that type
    // instead of across every type sharing this table — otherwise enough
    // records of other types can push older rows of the type you want past
    // the limit before you ever get to filter by type client-side.
    String? type,
  }) async {
    if (!SupabaseAuthService.isConfigured ||
        SupabaseAuthService.currentUserId == null) {
      return [];
    }

    final membership = await activeMembership();
    if (membership == null) return [];

    var query = _client
        .from('club_tactical_data')
        .select('id, type, title, content, created_at, created_by, category_id')
        .eq('club_id', membership.clubId);
    if (type != null) query = query.eq('type', type);
    if (!membership.isClubAdmin && membership.categoryIds.isNotEmpty) {
      query = query.inFilter('category_id', membership.categoryIds);
    }
    final rows = await query.order('created_at', ascending: false).limit(limit);
    return rows.map(ClubTacticalRecord.fromJson).toList();
  }

  static Future<List<ClubMemberAccess>> loadClubMembers() async {
    if (!SupabaseAuthService.isConfigured ||
        SupabaseAuthService.currentUserId == null) {
      return [];
    }
    final membership = await activeMembership();
    if (membership == null) return [];

    List<Map<String, dynamic>> rows;
    try {
      rows = await _client
          .from('club_memberships')
          .select('user_id, role, status, category_ids, created_at')
          .eq('club_id', membership.clubId)
          .order('status')
          .order('created_at');
    } catch (_) {
      rows = await _client
          .from('club_memberships')
          .select('user_id, role, status, created_at')
          .eq('club_id', membership.clubId)
          .order('status')
          .order('created_at');
    }
    return rows.map(ClubMemberAccess.fromJson).toList();
  }

  static Future<void> reviewMembership({
    required String userId,
    required bool approve,
    List<String> categoryIds = const [],
  }) async {
    final membership = await activeMembership();
    final token = SupabaseAuthService.currentSession?.accessToken;
    if (membership == null || token == null) {
      throw const ClubAccessException('Tu sesion no esta disponible.');
    }
    final response = await http
        .post(
          Uri.base.resolve('/api/review-club-membership'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'clubId': membership.clubId,
            'userId': userId,
          'action': approve ? 'approve' : 'reject',
          'categoryIds': categoryIds,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      try {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        throw ClubAccessException(
          data['message'] as String? ?? 'No se pudo revisar el acceso.',
        );
      } on ClubAccessException {
        rethrow;
      } catch (_) {
        throw const ClubAccessException('No se pudo revisar el acceso.');
      }
    }
  }

  static Future<void> updateMembershipCategories({
    required String userId,
    required List<String> categoryIds,
  }) async {
    final membership = await activeMembership();
    final token = SupabaseAuthService.currentSession?.accessToken;
    if (membership == null || token == null) {
      throw const ClubAccessException('Tu sesion no esta disponible.');
    }
    final response = await http
        .post(
          Uri.base.resolve('/api/review-club-membership'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'clubId': membership.clubId,
            'userId': userId,
            'action': 'update',
            'categoryIds': categoryIds,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      try {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        throw ClubAccessException(
          data['message'] as String? ?? 'No se pudo actualizar el acceso.',
        );
      } on ClubAccessException {
        rethrow;
      } catch (_) {
        throw const ClubAccessException('No se pudo actualizar el acceso.');
      }
    }
  }

  static Future<void> claimInitialCategory({
    required ClubMembership membership,
    required String categoryId,
  }) async {
    if (membership.isClubAdmin || membership.categoryIds.contains(categoryId)) {
      return;
    }
    final token = SupabaseAuthService.currentSession?.accessToken;
    if (token == null) return;
    final response = await http
        .post(
          Uri.base.resolve('/api/claim-category-access'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'clubId': membership.clubId,
            'categoryId': categoryId,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      try {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        throw ClubAccessException(
          data['message'] as String? ?? 'No se pudo asignar la categoria.',
        );
      } on ClubAccessException {
        rethrow;
      } catch (_) {
        throw const ClubAccessException(
          'No se pudo confirmar la categoria asignada.',
        );
      }
    }
  }

  static Future<bool> updateSession(TrainingSession session) async {
    if (!SupabaseAuthService.isConfigured ||
        SupabaseAuthService.currentUserId == null) {
      return false;
    }
    final membership = await activeMembership();
    if (membership == null) return false;
    const writableRoles = {
      'platform_admin',
      'club_admin',
      'coach',
      'assistant',
      'physical_trainer',
    };
    if (!writableRoles.contains(membership.role)) return false;

    final rows = await _client
        .from('club_tactical_data')
        .update({
          'content': session.toJson(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('club_id', membership.clubId)
        .eq('type', 'session')
        .contains('content', {'id': session.id})
        .select('id');
    if (rows.isNotEmpty) return true;

    await _client.from('club_tactical_data').insert({
      'club_id': membership.clubId,
      'created_by': SupabaseAuthService.currentUserId,
      'type': 'session',
      'title': session.title,
      'content': session.toJson(),
      'related_lud_team_id': int.tryParse(membership.ludTeamId ?? ''),
      'category_id': session.categoryId,
    });
    return true;
  }

  /// Resolves which Liga Universitaria team + category to query for this
  /// [membership] / [category] pair, or null when there is not enough
  /// trustworthy data. The category id (`lud-cat-<teamId>-<categoryId>`) is
  /// the authority; if the membership also names a team and the two disagree
  /// this returns null instead of mixing one club's team with another club's
  /// category.
  static _LudTarget? _ludTarget(
    ClubMembership membership,
    CategorySquad category,
  ) {
    final ref = LudCategoryRef.tryParse(category);
    final membershipTeam = int.tryParse(membership.ludTeamId?.trim() ?? '');
    if (ref != null) {
      if (membershipTeam != null && membershipTeam != ref.teamId) return null;
      return _LudTarget(ref.teamId, ref.categoryId, ref.categoryName);
    }
    if (membershipTeam == null) return null;
    return _LudTarget(membershipTeam, null, category.name.trim());
  }

  static Map<String, String> _leagueHeaders(bool forceRefresh) =>
      forceRefresh ? const {'cache-control': 'no-cache'} : const {};
}

class _LudTarget {
  final int teamId;
  final int? categoryId;
  final String categoryName;
  const _LudTarget(this.teamId, this.categoryId, this.categoryName);
}

class ClubMemberAccess {
  final String userId;
  final String role;
  final String status;
  final DateTime? createdAt;
  final bool isCurrentUser;
  final List<String> categoryIds;

  const ClubMemberAccess({
    required this.userId,
    required this.role,
    required this.status,
    required this.createdAt,
    required this.isCurrentUser,
    this.categoryIds = const [],
  });

  factory ClubMemberAccess.fromJson(Map<String, dynamic> json) {
    final userId = json['user_id'] as String? ?? '';
    return ClubMemberAccess(
      userId: userId,
      role: json['role'] as String? ?? 'viewer',
      status: json['status'] as String? ?? 'pending',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      isCurrentUser: userId == SupabaseAuthService.currentUserId,
      categoryIds: (json['category_ids'] as List<dynamic>? ?? const [])
          .map((value) => value.toString())
          .where((value) => value.isNotEmpty)
          .toList(),
    );
  }
}

class ClubContextLoadException implements Exception {
  final int statusCode;
  const ClubContextLoadException(this.statusCode);
}

class ClubAccessException implements Exception {
  final String message;
  const ClubAccessException(this.message);
}

class ClubTacticalRecord {
  final String id;
  final String type;
  final String title;
  final Map<String, dynamic> content;
  final DateTime? createdAt;
  final bool createdByCurrentUser;

  const ClubTacticalRecord({
    required this.id,
    required this.type,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.createdByCurrentUser,
  });

  factory ClubTacticalRecord.fromJson(Map<String, dynamic> json) {
    return ClubTacticalRecord(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? '',
      title: json['title'] as String? ?? 'Registro sin titulo',
      content: Map<String, dynamic>.from(
        json['content'] as Map<dynamic, dynamic>? ?? const {},
      ),
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      createdByCurrentUser:
          json['created_by'] == SupabaseAuthService.currentUserId,
    );
  }
}

class OpponentAnalysis {
  final String tableContext;
  final String styleSummary;
  final String dangerPlayers;
  final String memorySummary;
  final String squadSummary;
  final List<String> recentMatches;
  final OpponentHomeAwaySplit homeAwaySplit;
  final double avgGoalsFor;
  final double avgGoalsAgainst;
  final String? biggestWinScore;
  final String? biggestWinOpponent;
  final String? biggestLossScore;
  final String? biggestLossOpponent;
  final String? streakType;
  final int streakCount;
  final int cleanSheets;
  final List<OpponentGoalBucket> goalMinuteBuckets;
  final int goalMinuteSampleSize;

  const OpponentAnalysis({
    required this.tableContext,
    required this.styleSummary,
    required this.dangerPlayers,
    required this.memorySummary,
    required this.squadSummary,
    this.recentMatches = const [],
    this.homeAwaySplit = OpponentHomeAwaySplit.empty,
    this.avgGoalsFor = 0,
    this.avgGoalsAgainst = 0,
    this.biggestWinScore,
    this.biggestWinOpponent,
    this.biggestLossScore,
    this.biggestLossOpponent,
    this.streakType,
    this.streakCount = 0,
    this.cleanSheets = 0,
    this.goalMinuteBuckets = const [],
    this.goalMinuteSampleSize = 0,
  });

  Map<String, dynamic> toJson() => {
    'tableContext': tableContext,
    'styleSummary': styleSummary,
    'dangerPlayers': dangerPlayers,
    'memorySummary': memorySummary,
    'squadSummary': squadSummary,
    'recentMatches': recentMatches,
    'homeAwaySplit': homeAwaySplit.toJson(),
    'avgGoalsPerMatch': {
      'for': avgGoalsFor,
      'against': avgGoalsAgainst,
    },
    'biggestWin': {
      if (biggestWinScore != null) 'score': biggestWinScore,
      if (biggestWinOpponent != null) 'opponent': biggestWinOpponent,
    },
    'biggestLoss': {
      if (biggestLossScore != null) 'score': biggestLossScore,
      if (biggestLossOpponent != null) 'opponent': biggestLossOpponent,
    },
    'currentStreak': {
      if (streakType != null) 'type': streakType,
      'count': streakCount,
    },
    'cleanSheets': cleanSheets,
    'goalMinuteBuckets': goalMinuteBuckets
        .map((bucket) => bucket.toJson())
        .toList(),
    'goalMinuteSampleSize': goalMinuteSampleSize,
  };

  factory OpponentAnalysis.fromJson(Map<String, dynamic> json) {
    final avg = _mapOf(json['avgGoalsPerMatch']);
    final biggestWin = _mapOf(json['biggestWin']);
    final biggestLoss = _mapOf(json['biggestLoss']);
    final streak = _mapOf(json['currentStreak']);
    final streakType = streak['type']?.toString();
    return OpponentAnalysis(
      tableContext: json['tableContext']?.toString() ?? '',
      styleSummary: json['styleSummary']?.toString() ?? '',
      dangerPlayers: json['dangerPlayers']?.toString() ?? '',
      memorySummary: json['memorySummary']?.toString() ?? '',
      squadSummary: json['squadSummary']?.toString() ?? '',
      recentMatches: (json['recentMatches'] as List<dynamic>? ?? const [])
          .map((value) => value.toString())
          .where((value) => value.trim().isNotEmpty)
          .toList(),
      homeAwaySplit: OpponentHomeAwaySplit.fromJson(
        _mapOf(json['homeAwaySplit']),
      ),
      avgGoalsFor: _doubleOf(avg['for']),
      avgGoalsAgainst: _doubleOf(avg['against']),
      biggestWinScore: _stringOrNull(biggestWin['score']),
      biggestWinOpponent: _stringOrNull(biggestWin['opponent']),
      biggestLossScore: _stringOrNull(biggestLoss['score']),
      biggestLossOpponent: _stringOrNull(biggestLoss['opponent']),
      streakType: streakType == 'W' || streakType == 'D' || streakType == 'L'
          ? streakType
          : null,
      streakCount: _intOf(streak['count']),
      cleanSheets: _intOf(json['cleanSheets']),
      goalMinuteBuckets:
          (json['goalMinuteBuckets'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(OpponentGoalBucket.fromJson)
              .toList(),
      goalMinuteSampleSize: _intOf(json['goalMinuteSampleSize']),
    );
  }

  static Map<String, dynamic> _mapOf(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const {};
  }

  static int _intOf(Object? value) =>
      value is num ? value.toInt() : int.tryParse('${value ?? ''}') ?? 0;

  static double _doubleOf(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse('${value ?? ''}') ?? 0;

  static String? _stringOrNull(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}

class OpponentHomeAwaySplit {
  final OpponentSplitSide home;
  final OpponentSplitSide away;

  static const empty = OpponentHomeAwaySplit(
    home: OpponentSplitSide.empty,
    away: OpponentSplitSide.empty,
  );

  const OpponentHomeAwaySplit({required this.home, required this.away});

  Map<String, dynamic> toJson() => {
    'home': home.toJson(),
    'away': away.toJson(),
  };

  factory OpponentHomeAwaySplit.fromJson(Map<String, dynamic> json) {
    return OpponentHomeAwaySplit(
      home: OpponentSplitSide.fromJson(OpponentAnalysis._mapOf(json['home'])),
      away: OpponentSplitSide.fromJson(OpponentAnalysis._mapOf(json['away'])),
    );
  }
}

class OpponentSplitSide {
  final int played;
  final int won;
  final int drawn;
  final int lost;
  final int gf;
  final int ga;

  static const empty = OpponentSplitSide(
    played: 0,
    won: 0,
    drawn: 0,
    lost: 0,
    gf: 0,
    ga: 0,
  );

  const OpponentSplitSide({
    required this.played,
    required this.won,
    required this.drawn,
    required this.lost,
    required this.gf,
    required this.ga,
  });

  Map<String, dynamic> toJson() => {
    'played': played,
    'won': won,
    'drawn': drawn,
    'lost': lost,
    'gf': gf,
    'ga': ga,
  };

  factory OpponentSplitSide.fromJson(Map<String, dynamic> json) {
    return OpponentSplitSide(
      played: OpponentAnalysis._intOf(json['played']),
      won: OpponentAnalysis._intOf(json['won']),
      drawn: OpponentAnalysis._intOf(json['drawn']),
      lost: OpponentAnalysis._intOf(json['lost']),
      gf: OpponentAnalysis._intOf(json['gf']),
      ga: OpponentAnalysis._intOf(json['ga']),
    );
  }
}

class OpponentGoalBucket {
  final String range;
  final int goalsFor;
  final int goalsAgainst;

  const OpponentGoalBucket({
    required this.range,
    required this.goalsFor,
    required this.goalsAgainst,
  });

  Map<String, dynamic> toJson() => {
    'range': range,
    'goalsFor': goalsFor,
    'goalsAgainst': goalsAgainst,
  };

  factory OpponentGoalBucket.fromJson(Map<String, dynamic> json) {
    return OpponentGoalBucket(
      range: json['range']?.toString() ?? '',
      goalsFor: OpponentAnalysis._intOf(json['goalsFor']),
      goalsAgainst: OpponentAnalysis._intOf(json['goalsAgainst']),
    );
  }
}

class LudFixtureMatch {
  final String id;
  final DateTime date;
  final String opponentName;
  final String homeTeamName;
  final String awayTeamName;
  final String categoryName;
  final String competition;
  final String venue;
  final String round;
  final String status;
  final int? opponentTeamId;
  final int? phaseId;
  final int? homeScore;
  final int? awayScore;
  final String fixtureSource;
  final bool categoryVerified;
  final int rawRows;
  final int categoryRows;
  final int invalidDateRows;
  final int checkedAttempts;

  /// Fecha tal cual la publica la liga (con la hora de pared si la trae);
  /// [date] es un instante normalizado y pierde la hora real.
  final String rawDate;

  const LudFixtureMatch({
    required this.id,
    required this.date,
    this.rawDate = '',
    required this.opponentName,
    required this.homeTeamName,
    required this.awayTeamName,
    required this.categoryName,
    required this.competition,
    required this.venue,
    required this.round,
    required this.status,
    this.opponentTeamId,
    this.phaseId,
    this.homeScore,
    this.awayScore,
    this.fixtureSource = '',
    this.categoryVerified = true,
    this.rawRows = 0,
    this.categoryRows = 0,
    this.invalidDateRows = 0,
    this.checkedAttempts = 1,
  });

  factory LudFixtureMatch.fromJson(
    Map<String, dynamic> json, {
    String fixtureSource = '',
    bool categoryVerified = true,
    int rawRows = 0,
    int categoryRows = 0,
    int invalidDateRows = 0,
    int checkedAttempts = 1,
  }) {
    final parsedDate = DateTime.tryParse(json['date']?.toString() ?? '');
    return LudFixtureMatch(
      id: json['id']?.toString() ?? '',
      date: parsedDate ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      rawDate: json['rawDate']?.toString() ?? '',
      opponentName: json['opponentName']?.toString() ?? '',
      homeTeamName: json['homeTeamName']?.toString() ?? '',
      awayTeamName: json['awayTeamName']?.toString() ?? '',
      categoryName: json['categoryName']?.toString() ?? '',
      competition: json['competition']?.toString() ?? '',
      venue: json['venue']?.toString() ?? '',
      round: json['round']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      opponentTeamId: int.tryParse(json['opponentTeamId']?.toString() ?? ''),
      phaseId: int.tryParse(json['phaseId']?.toString() ?? ''),
      homeScore: int.tryParse(json['homeScore']?.toString() ?? ''),
      awayScore: int.tryParse(json['awayScore']?.toString() ?? ''),
      fixtureSource: fixtureSource,
      categoryVerified: categoryVerified,
      rawRows: rawRows,
      categoryRows: categoryRows,
      invalidDateRows: invalidDateRows,
      checkedAttempts: checkedAttempts,
    );
  }

  bool get hasValidDate => date.millisecondsSinceEpoch > 0;

  bool get isUpcoming {
    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    return !date.toLocal().isBefore(startOfToday);
  }

  bool get isPlayedResult {
    if (homeScore == null || awayScore == null || !hasValidDate) return false;
    final normalizedStatus = status
        .toLowerCase()
        .replaceAll(RegExp(r'[áàä]'), 'a')
        .replaceAll(RegExp(r'[éèë]'), 'e')
        .replaceAll(RegExp(r'[íìï]'), 'i')
        .replaceAll(RegExp(r'[óòö]'), 'o')
        .replaceAll(RegExp(r'[úùü]'), 'u');
    if (normalizedStatus.contains('programad') ||
        normalizedStatus.contains('proximo') ||
        normalizedStatus.contains('pendiente') ||
        normalizedStatus.contains('fixture')) {
      return false;
    }
    if (normalizedStatus.contains('jugado') ||
        normalizedStatus.contains('final') ||
        normalizedStatus.contains('finish') ||
        normalizedStatus.contains('terminad') ||
        normalizedStatus.contains('played') ||
        normalizedStatus.contains('complet')) {
      return true;
    }
    // A 0-0 with no explicit "played" status is almost always a fixture row
    // that was never played; never let it pad "recent form".
    if (homeScore == 0 && awayScore == 0) return false;
    return date.toLocal().isBefore(DateTime.now());
  }

  String get dateLabel {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year}';
  }

  String get tacticalContext {
    final parts = [
      'Fixture de la liga: $homeTeamName vs $awayTeamName',
      if (competition.trim().isNotEmpty) competition.trim(),
      if (round.trim().isNotEmpty) round.trim(),
      if (venue.trim().isNotEmpty) 'Cancha: ${venue.trim()}',
      if (categoryName.trim().isNotEmpty) 'Categoria: ${categoryName.trim()}',
    ];
    return parts.where((item) => item.trim().isNotEmpty).join(' / ');
  }

  String get fixtureDetail {
    final parts = [
      if (categoryName.trim().isNotEmpty) categoryName.trim(),
      if (competition.trim().isNotEmpty) competition.trim(),
      if (round.trim().isNotEmpty) round.trim(),
      if (venue.trim().isNotEmpty) venue.trim(),
    ];
    return parts.where((item) => item.trim().isNotEmpty).join(' / ');
  }

  String get fixtureTrustLabel {
    if (!categoryVerified) return 'Categoria no verificada';
    if (fixtureSource == 'lud_cache') return 'Datos guardados';
    if (invalidDateRows > 0) return 'Fixture depurado';
    if (fixtureSource == 'lud_live') return 'Liga verificada';
    if (fixtureSource == 'ludfan_public_fallback') {
      return 'Respaldo publico verificado';
    }
    return 'Fixture conectado';
  }

  /// True when this data came from the offline cache, not a live league fetch.
  /// UI must not present it as "updated now".
  bool get isFromCache => fixtureSource == 'lud_cache';

  String get fixtureTrustDetail {
    if (fixtureSource == 'ludfan_public_fallback') {
      final parts = [
        if (categoryRows > 0) '$categoryRows partidos publicados del club',
        if (rawRows > 0) '$rawRows filas revisadas',
        'La liga no respondio; se uso fixture publico por categoria',
      ];
      return parts.join(' / ');
    }
    final parts = [
      if (categoryRows > 0) '$categoryRows partidos de la categoria',
      if (rawRows > 0) '$rawRows filas revisadas',
      if (invalidDateRows > 0) '$invalidDateRows fechas descartadas',
      if (checkedAttempts > 1) '$checkedAttempts consultas a la liga',
    ];
    if (parts.isEmpty) {
      return categoryVerified
          ? 'Partidos filtrados por equipo, categoria y fecha valida.'
          : 'La liga no confirmo la categoria; revisar antes de usar rival.';
    }
    return parts.join(' / ');
  }
}

class LudStandingsTable {
  final String categoryName;
  final String seasonYear;
  final String phaseName;
  final String teamName;
  final List<LudStandingRow> rows;

  const LudStandingsTable({
    required this.categoryName,
    required this.seasonYear,
    required this.phaseName,
    required this.teamName,
    required this.rows,
  });

  factory LudStandingsTable.fromJson(Map<String, dynamic> json) {
    return LudStandingsTable(
      categoryName: json['categoryName']?.toString() ?? '',
      seasonYear: json['seasonYear']?.toString() ?? '',
      phaseName: json['phaseName']?.toString() ?? '',
      teamName: json['teamName']?.toString() ?? '',
      rows: (json['rows'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(LudStandingRow.fromJson)
          .toList(),
    );
  }

  LudStandingRow? get ownRow {
    for (final row in rows) {
      if (row.isOwnTeam) return row;
    }
    return null;
  }
}

class LudStandingRow {
  final int rank;
  final String teamName;
  final int played;
  final int won;
  final int drawn;
  final int lost;
  final int goalsFor;
  final int goalsAgainst;
  final int goalDifference;
  final int points;
  final bool isOwnTeam;

  const LudStandingRow({
    required this.rank,
    required this.teamName,
    required this.played,
    required this.won,
    required this.drawn,
    required this.lost,
    required this.goalsFor,
    required this.goalsAgainst,
    required this.goalDifference,
    required this.points,
    required this.isOwnTeam,
  });

  factory LudStandingRow.fromJson(Map<String, dynamic> json) {
    int number(String key) => int.tryParse(json[key]?.toString() ?? '') ?? 0;
    return LudStandingRow(
      rank: number('rank'),
      teamName: json['teamName']?.toString() ?? '',
      played: number('played'),
      won: number('won'),
      drawn: number('drawn'),
      lost: number('lost'),
      goalsFor: number('goalsFor'),
      goalsAgainst: number('goalsAgainst'),
      goalDifference: number('goalDifference'),
      points: number('points'),
      isOwnTeam: json['isOwnTeam'] == true,
    );
  }
}

/// Single source of truth for turning a picked [CategorySquad] into the Liga
/// Universitaria team + category it points at. LUD category ids follow
/// `lud-cat-<teamId>-<categoryId>` where both parts are integers. Every screen
/// and service that queries LUD data must go through this instead of writing
/// its own regex, so a club never ends up paired with another club's team or
/// category.
class LudCategoryRef {
  final int teamId;
  // Null when the category has no real numeric LUD category id (the backend
  // falls back to a slugified category name — e.g. "lud-cat-1-sub-20" — when
  // /teams/{id}/categories/ doesn't expose one). teamId + categoryName still
  // identify the category; callers must not assume this is always set.
  final int? categoryId;
  final String categoryName;

  const LudCategoryRef({
    required this.teamId,
    required this.categoryId,
    required this.categoryName,
  });

  // Suffix after the team id can be a real LUD category id (digits) or a
  // normalized category name (letters/digits/hyphens) — see normalize() in
  // api/lud-team-context.js. Only the team id needs to be numeric.
  static final RegExp _pattern = RegExp(r'^lud-cat-(\d+)-(.+)$');

  /// Null when [category] is not a Liga Universitaria category. Callers must
  /// treat null as "no LUD data for this selection" and must not substitute
  /// another team or category.
  static LudCategoryRef? tryParse(CategorySquad category) {
    final match = _pattern.firstMatch(category.id.trim());
    if (match == null) return null;
    final teamId = int.tryParse(match.group(1)!);
    if (teamId == null) return null;
    return LudCategoryRef(
      teamId: teamId,
      categoryId: int.tryParse(match.group(2)!),
      categoryName: category.name.trim(),
    );
  }

  /// Like [tryParse] but also rejects the category when its embedded team does
  /// not match [expectedTeamId] (a club's own LUD team id). Use this at call
  /// sites that already know which club they are in.
  static LudCategoryRef? forTeam(
    CategorySquad category,
    String? expectedTeamId,
  ) {
    final ref = tryParse(category);
    if (ref == null) return null;
    final expected = int.tryParse(expectedTeamId?.trim() ?? '');
    if (expected != null && expected != ref.teamId) return null;
    return ref;
  }

  /// The team id behind a raw category id, for call sites that only need that.
  static int? teamIdOf(String categoryId) {
    final match = _pattern.firstMatch(categoryId.trim());
    return match == null ? null : int.tryParse(match.group(1)!);
  }
}

class CanteraAccessClub {
  final String id;
  final String name;
  final String? ludTeamId;
  final String logoUrl;

  const CanteraAccessClub({
    required this.id,
    required this.name,
    required this.ludTeamId,
    this.logoUrl = '',
  });

  factory CanteraAccessClub.fromJson(Map<String, dynamic> json) {
    return CanteraAccessClub(
      id: json['id'] as String,
      name: json['display_name'] as String? ?? '',
      ludTeamId: json['lud_team_id']?.toString(),
      logoUrl: json['logo_url'] as String? ?? '',
    );
  }
}

class ClubMembership {
  final String clubId;
  final String clubName;
  final String? ludTeamId;
  final String role;
  final String status;
  final List<String> categoryIds;

  const ClubMembership({
    required this.clubId,
    required this.clubName,
    required this.ludTeamId,
    required this.role,
    required this.status,
    this.categoryIds = const [],
  });

  factory ClubMembership.fromJson(Map<String, dynamic> json) {
    final club = json['cantera_clubs'] as Map<String, dynamic>? ?? {};
    return ClubMembership(
      clubId: json['club_id'] as String? ?? '',
      clubName: club['display_name'] as String? ?? 'Club',
      ludTeamId: club['lud_team_id']?.toString(),
      role: json['role'] as String? ?? 'coach',
      status: json['status'] as String? ?? 'pending',
      categoryIds: (json['category_ids'] as List<dynamic>? ?? const [])
          .map((value) => value.toString())
          .where((value) => value.isNotEmpty)
          .toList(),
    );
  }

  bool get isClubAdmin =>
      role == 'club_admin' || role == 'platform_admin';

  List<CategorySquad> accessibleCategories(List<CategorySquad> categories) {
    if (isClubAdmin || categoryIds.isEmpty) return categories;
    final allowed = categoryIds.toSet();
    return categories.where((category) => allowed.contains(category.id)).toList();
  }
}

class CanteraClubContext {
  final String teamName;
  final String logoUrl;
  final String? seasonYear;
  final String source;
  final DateTime? syncedAt;
  final List<CategorySquad> categories;
  final List<Player> players;

  const CanteraClubContext({
    required this.teamName,
    required this.logoUrl,
    required this.seasonYear,
    required this.source,
    required this.syncedAt,
    required this.categories,
    required this.players,
  });

  factory CanteraClubContext.fromJson(Map<String, dynamic> json) {
    final team = json['team'] as Map<String, dynamic>? ?? {};
    final categories = (json['categories'] as List<dynamic>? ?? [])
        .map((item) => item as Map<String, dynamic>)
        .map(
          (item) => CategorySquad(
            id: item['id'] as String? ?? '',
            name: item['name'] as String? ?? '',
            sport: 'Futbol',
            ageGroup: item['ageGroup'] as String? ?? '',
            coachName: item['coachName'] as String? ?? '',
            playerCount: item['playerCount'] as int? ?? 0,
            attendanceRate: 0,
            objectives: const [],
            currentFocus: item['currentFocus'] as String? ?? '',
            lastRegistered: '',
            practiceSchedule: item['practiceSchedule'] as String? ?? '',
          ),
        )
        .where((category) => category.id.isNotEmpty && category.name.isNotEmpty)
        .toList();

    final validCategoryIds = categories.map((c) => c.id).toSet();
    final players = (json['players'] as List<dynamic>? ?? [])
        .map((item) => item as Map<String, dynamic>)
        .map((item) {
          final names = (item['fullName'] as String? ?? '').trim().split(' ');
          final firstName = names.isEmpty ? '' : names.first;
          final lastName = names.length <= 1 ? '' : names.skip(1).join(' ');
          final categoryId = item['categoryId'] as String? ?? '';
          return Player(
            id: item['id'] as String? ?? '',
            categoryId: validCategoryIds.contains(categoryId) ? categoryId : '',
            firstName: firstName,
            lastName: lastName,
            age: 0,
            position: item['position'] as String? ?? '',
            secondaryPositions: '',
            dominantFoot: '',
            status: 'Activo',
            attendanceRate: 0,
            trend: _playerTrend(item),
            matchesPlayed: _intOf(item['matches']),
            minutesPlayed: _intOf(item['minutes']),
            goals: _intOf(item['goals']),
            assists: _intOf(item['assists']),
            yellowCards: _intOf(item['yellowCards']),
            redCards: _intOf(item['redCards']),
            note: _playerNote(item),
          );
        })
        .where((player) => player.id.isNotEmpty && player.firstName.isNotEmpty)
        .toList();

    return CanteraClubContext(
      teamName: team['name'] as String? ?? '',
      logoUrl: team['logoUrl'] as String? ?? '',
      seasonYear: json['seasonYear']?.toString(),
      source: json['source'] as String? ?? 'lud_live',
      syncedAt: DateTime.tryParse(json['syncedAt'] as String? ?? ''),
      categories: categories,
      players: players,
    );
  }

  static int _intOf(Object? value) =>
      value is num ? value.toInt() : int.tryParse('${value ?? ''}') ?? 0;

  static String _playerTrend(Map<String, dynamic> item) {
    final matches = item['matches'] ?? 0;
    final minutes = item['minutes'] ?? 0;
    final goals = item['goals'] ?? 0;
    final assists = item['assists'] ?? 0;
    final yellowCards = item['yellowCards'] ?? 0;
    final redCards = item['redCards'] ?? 0;
    return [
      '$matches PJ',
      '$minutes min',
      '$goals goles',
      if (assists != 0) '$assists asistencias',
      if (yellowCards != 0) '$yellowCards amarillas',
      if (redCards != 0) '$redCards rojas',
    ].join(' - ');
  }

  // Nota manual del DT, no un texto generado — un placeholder identico para
  // los 26 jugadores del plantel no aporta nada al contexto del plantel.
  static String _playerNote(Map<String, dynamic> item) => '';
}

List<Player> preservePlayerProfiles({
  required List<Player> incoming,
  required List<Player> existing,
}) {
  final existingById = {for (final player in existing) player.id: player};
  return incoming.map((player) {
    final current = existingById[player.id];
    if (current == null) return player;
    return player.copyWith(
      position: current.position.trim().isNotEmpty
          ? current.position
          : player.position,
      secondaryPositions: current.secondaryPositions.trim().isNotEmpty
          ? current.secondaryPositions
          : player.secondaryPositions,
      dominantFoot: current.dominantFoot.trim().isNotEmpty
          ? current.dominantFoot
          : player.dominantFoot,
      status: current.status.trim().isNotEmpty ? current.status : player.status,
      attendanceRate: current.attendanceRate > 0
          ? current.attendanceRate
          : player.attendanceRate,
      note: _mergePlayerNote(player.note, current.note),
    );
  }).toList();
}

List<Player> applyRemotePlayerProfiles({
  required List<Player> players,
  required List<ClubTacticalRecord> records,
}) {
  final updates = <String, Player>{};
  for (final record in records) {
    if (record.type != 'staff_note') continue;
    if (record.content['kind'] != 'player_profile_update') continue;
    final rawPlayer = record.content['player'];
    if (rawPlayer is! Map) continue;
    final player = Player.fromJson(Map<String, dynamic>.from(rawPlayer));
    if (player.id.isNotEmpty) updates[player.id] = player;
  }
  if (updates.isEmpty) return players;
  return players.map((player) {
    final update = updates[player.id];
    if (update == null) return player;
    return player.copyWith(
      categoryId: update.categoryId.isNotEmpty
          ? update.categoryId
          : player.categoryId,
      plantelId: update.plantelId,
      position: update.position,
      secondaryPositions: update.secondaryPositions,
      dominantFoot: update.dominantFoot,
      status: update.status,
      statusDetail: update.statusDetail,
      suspensionDates: update.suspensionDates,
      expectedReturnDate: update.expectedReturnDate,
      attendanceRate: update.attendanceRate,
      note: _mergePlayerNote(player.note, update.note),
      developmentGoals: update.developmentGoals,
    );
  }).toList();
}

// Placeholder que una version anterior de _playerNote() escribia para TODOS
// los jugadores LUD por igual (ver historial). Quedo guardado como si fuera
// una nota real del DT; hay que tratarlo como vacio para que se autolimpie
// en cualquier club, sin necesitar una migracion aparte.
const _staleLudPlaceholderNote = 'Importado desde la liga';

String _stripStalePlaceholder(String note) =>
    note.trim() == _staleLudPlaceholderNote ? '' : note.trim();

String _mergePlayerNote(String ludNote, String currentNote) {
  final cleanLud = _stripStalePlaceholder(ludNote);
  final cleanCurrent = _stripStalePlaceholder(currentNote);
  if (cleanCurrent.isEmpty) return cleanLud;
  if (cleanLud.isEmpty || cleanCurrent.contains(cleanLud)) return cleanCurrent;
  if (cleanLud.contains(cleanCurrent)) return cleanLud;
  return '$cleanLud | Perfil tecnico: $cleanCurrent';
}
