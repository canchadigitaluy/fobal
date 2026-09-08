import 'package:flutter/material.dart';

enum UserRole { coordinator, coach, viewer }

String cleanVisiblePlayerNote(String value) {
  return value
      .replaceAll(
        RegExp(r'Importado desde LUD Stats', caseSensitive: false),
        'Importado desde la liga',
      )
      .replaceAll(
        RegExp(r'LUD\s*player_id\s*:?\s*\d+', caseSensitive: false),
        '',
      )
      .replaceAll(RegExp(r'player_id\s*:?\s*\d+', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

// ---------------------------------------------------------------------------
// LUD vs manual (No-LUD) identity guards.
//
// A club/category pair belongs to exactly one world — LUD (synced from the
// university league) or manual (a coach's own independent club). These
// helpers are the single source of truth for telling them apart, so every
// screen and every hydration path checks the same thing instead of
// reimplementing (and possibly drifting on) the same OR-expression.
// ---------------------------------------------------------------------------

/// A LUD category id always looks like `lud-cat-<teamId>-<categoryId>` (see
/// `LudCategoryRef` in club_access_service.dart). Cheap, no-parse check for
/// call sites that just need to know "is this id from the league".
bool isLudCategoryId(String id) => id.startsWith('lud-cat-');

extension CanteraClubKind on CanteraClub {
  /// True for a coach's own independent club (No-LUD): created locally, not
  /// synced from the university league.
  bool get isManualClub =>
      dataSource == 'manual' || league == 'Trabajo independiente';

  /// True for a club synced from the university league (LUD).
  bool get isLudClub => !isManualClub;
}

/// True when [loadedClub] must NOT be trusted as the active club for the
/// manual/No-LUD flow that needs [requiredManualClubId] — either it's a
/// different club outright, or (belt-and-suspenders) it's a LUD club even
/// though the id happened to match. Guards against a stale
/// `fobal_active_club_id` — left over from a LUD session on the same
/// browser — leaking LUD data into the No-LUD shell.
bool clubNeedsManualSwitch({
  required CanteraClub loadedClub,
  required String requiredManualClubId,
}) {
  if (loadedClub.id != requiredManualClubId) return true;
  return loadedClub.isLudClub;
}

/// Resolves the category id a club should use, given what was last stored
/// for it. Rejects a category that isn't in [club.categories] (stale,
/// deleted, or from a different club entirely), and — for a manual club —
/// also rejects a `lud-cat-*` id even if it somehow ended up stored there.
/// Returns null when nothing stored is valid; the caller decides the
/// fallback (typically `club.categories.first.id`).
String? resolveStoredCategoryId({
  required CanteraClub club,
  required String? storedCategoryId,
}) {
  if (storedCategoryId == null) return null;
  final belongsToClub = club.categories.any(
    (item) => item.id == storedCategoryId,
  );
  if (!belongsToClub) return null;
  if (club.isManualClub && isLudCategoryId(storedCategoryId)) return null;
  return storedCategoryId;
}

class CanteraClub {
  final String id;
  final String name;
  final String league;
  final String sportFocus;
  final String dataSource;
  final String seasonYear;
  final String syncedAt;
  final String logoUrl;
  final String headCoachName;
  final String assistantCoachName;
  final Color primaryColor;
  final Color secondaryColor;
  final Methodology methodology;
  final List<CategorySquad> categories;
  final List<Player> players;
  final List<TrainingSession> sessions;
  final List<TrainingReport> trainingReports;
  final List<AttendanceRecord> attendanceRecords;

  /// Match results a coach logs by hand (No-LUD). LUD clubs get their results
  /// from the league and normally leave this empty; a friendly the league does
  /// not track can still be added here.
  final List<MatchResult> matchResults;

  /// Club-wide reusable exercise library — not filtered by category (an
  /// exercise with an empty `categoryId` applies to every squad).
  final List<Exercise> savedExercises;
  final List<MatchPreparation> matchPreparations;
  final List<IntelligentAlert> alerts;
  final List<AiReport> aiReports;
  final List<ClubUserAccess> users;

  const CanteraClub({
    required this.id,
    required this.name,
    required this.league,
    required this.sportFocus,
    this.dataSource = 'local',
    this.seasonYear = '',
    this.syncedAt = '',
    this.logoUrl = '',
    this.headCoachName = '',
    this.assistantCoachName = '',
    required this.primaryColor,
    required this.secondaryColor,
    required this.methodology,
    required this.categories,
    required this.players,
    required this.sessions,
    required this.trainingReports,
    this.attendanceRecords = const [],
    this.matchResults = const [],
    this.savedExercises = const [],
    this.matchPreparations = const [],
    required this.alerts,
    required this.aiReports,
    required this.users,
  });

  CanteraClub copyWith({
    String? id,
    String? name,
    String? league,
    String? sportFocus,
    String? dataSource,
    String? seasonYear,
    String? syncedAt,
    String? logoUrl,
    String? headCoachName,
    String? assistantCoachName,
    Color? primaryColor,
    Color? secondaryColor,
    Methodology? methodology,
    List<CategorySquad>? categories,
    List<Player>? players,
    List<TrainingSession>? sessions,
    List<TrainingReport>? trainingReports,
    List<AttendanceRecord>? attendanceRecords,
    List<MatchResult>? matchResults,
    List<Exercise>? savedExercises,
    List<MatchPreparation>? matchPreparations,
    List<IntelligentAlert>? alerts,
    List<AiReport>? aiReports,
    List<ClubUserAccess>? users,
  }) {
    return CanteraClub(
      id: id ?? this.id,
      name: name ?? this.name,
      league: league ?? this.league,
      sportFocus: sportFocus ?? this.sportFocus,
      dataSource: dataSource ?? this.dataSource,
      seasonYear: seasonYear ?? this.seasonYear,
      syncedAt: syncedAt ?? this.syncedAt,
      logoUrl: logoUrl ?? this.logoUrl,
      headCoachName: headCoachName ?? this.headCoachName,
      assistantCoachName: assistantCoachName ?? this.assistantCoachName,
      primaryColor: primaryColor ?? this.primaryColor,
      secondaryColor: secondaryColor ?? this.secondaryColor,
      methodology: methodology ?? this.methodology,
      categories: categories ?? this.categories,
      players: players ?? this.players,
      sessions: sessions ?? this.sessions,
      trainingReports: trainingReports ?? this.trainingReports,
      attendanceRecords: attendanceRecords ?? this.attendanceRecords,
      matchResults: matchResults ?? this.matchResults,
      savedExercises: savedExercises ?? this.savedExercises,
      matchPreparations: matchPreparations ?? this.matchPreparations,
      alerts: alerts ?? this.alerts,
      aiReports: aiReports ?? this.aiReports,
      users: users ?? this.users,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'league': league,
      'sportFocus': sportFocus,
      'dataSource': dataSource,
      'seasonYear': seasonYear,
      'syncedAt': syncedAt,
      'logoUrl': logoUrl,
      'headCoachName': headCoachName,
      'assistantCoachName': assistantCoachName,
      'primaryColor': primaryColor.toARGB32(),
      'secondaryColor': secondaryColor.toARGB32(),
      'methodology': methodology.toJson(),
      'categories': categories.map((c) => c.toJson()).toList(),
      'players': players.map((p) => p.toJson()).toList(),
      'sessions': sessions.map((s) => s.toJson()).toList(),
      'trainingReports': trainingReports.map((r) => r.toJson()).toList(),
      'attendanceRecords': attendanceRecords.map((r) => r.toJson()).toList(),
      'matchResults': matchResults.map((r) => r.toJson()).toList(),
      'savedExercises': savedExercises.map((e) => e.toJson()).toList(),
      'matchPreparations': matchPreparations.map((m) => m.toJson()).toList(),
      'users': users.map((u) => u.toJson()).toList(),
    };
  }

  factory CanteraClub.fromJson(Map<String, dynamic> json) {
    return canteraDemoClub.copyWith(
      id: json['id'] as String? ?? canteraDemoClub.id,
      name: json['name'] as String? ?? canteraDemoClub.name,
      league: json['league'] as String? ?? json['city'] as String? ?? '',
      sportFocus: json['sportFocus'] as String? ?? '',
      dataSource: json['dataSource'] as String? ?? 'local',
      seasonYear: json['seasonYear'] as String? ?? '',
      syncedAt: json['syncedAt'] as String? ?? '',
      logoUrl: json['logoUrl'] as String? ?? '',
      headCoachName: json['headCoachName'] as String? ?? '',
      assistantCoachName: json['assistantCoachName'] as String? ?? '',
      primaryColor: Color(json['primaryColor'] as int? ?? 0xFF6EE7B7),
      secondaryColor: Color(json['secondaryColor'] as int? ?? 0xFF10231D),
      methodology: Methodology.fromJson(
        json['methodology'] as Map<String, dynamic>? ?? {},
      ),
      categories: (json['categories'] as List<dynamic>? ?? [])
          .map((item) => CategorySquad.fromJson(item as Map<String, dynamic>))
          .toList(),
      players: (json['players'] as List<dynamic>? ?? [])
          .map((item) => Player.fromJson(item as Map<String, dynamic>))
          .toList(),
      sessions: (json['sessions'] as List<dynamic>? ?? [])
          .map((item) => TrainingSession.fromJson(item as Map<String, dynamic>))
          .toList(),
      trainingReports: (json['trainingReports'] as List<dynamic>? ?? [])
          .map((item) => TrainingReport.fromJson(item as Map<String, dynamic>))
          .toList(),
      attendanceRecords: (json['attendanceRecords'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map(
            (item) =>
                AttendanceRecord.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
      matchResults: (json['matchResults'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(MatchResult.fromJson)
          .toList(),
      savedExercises: (json['savedExercises'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(Exercise.fromJson)
          .toList(),
      matchPreparations: (json['matchPreparations'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(MatchPreparation.fromJson)
          .toList(),
      users: (json['users'] as List<dynamic>? ?? [])
          .map((item) => ClubUserAccess.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class CategorySquad {
  final String id;
  final String name;
  final String sport;
  final String ageGroup;
  final String coachName;
  final int playerCount;
  final double attendanceRate;
  final List<String> objectives;
  final String currentFocus;
  final String lastRegistered;
  final String practiceSchedule;

  const CategorySquad({
    required this.id,
    required this.name,
    required this.sport,
    required this.ageGroup,
    required this.coachName,
    required this.playerCount,
    required this.attendanceRate,
    required this.objectives,
    required this.currentFocus,
    required this.lastRegistered,
    this.practiceSchedule = '',
  });

  CategorySquad copyWith({
    String? name,
    String? sport,
    String? ageGroup,
    String? coachName,
    int? playerCount,
    double? attendanceRate,
    List<String>? objectives,
    String? currentFocus,
    String? lastRegistered,
    String? practiceSchedule,
  }) {
    return CategorySquad(
      id: id,
      name: name ?? this.name,
      sport: sport ?? this.sport,
      ageGroup: ageGroup ?? this.ageGroup,
      coachName: coachName ?? this.coachName,
      playerCount: playerCount ?? this.playerCount,
      attendanceRate: attendanceRate ?? this.attendanceRate,
      objectives: objectives ?? this.objectives,
      currentFocus: currentFocus ?? this.currentFocus,
      lastRegistered: lastRegistered ?? this.lastRegistered,
      practiceSchedule: practiceSchedule ?? this.practiceSchedule,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'sport': sport,
      'ageGroup': ageGroup,
      'coachName': coachName,
      'playerCount': playerCount,
      'attendanceRate': attendanceRate,
      'objectives': objectives,
      'currentFocus': currentFocus,
      'lastRegistered': lastRegistered,
      'practiceSchedule': practiceSchedule,
    };
  }

  factory CategorySquad.fromJson(Map<String, dynamic> json) {
    return CategorySquad(
      id:
          json['id'] as String? ??
          'cat-${DateTime.now().millisecondsSinceEpoch}',
      name: json['name'] as String? ?? '',
      sport: json['sport'] as String? ?? '',
      ageGroup: json['ageGroup'] as String? ?? '',
      coachName: json['coachName'] as String? ?? '',
      playerCount: json['playerCount'] as int? ?? 0,
      attendanceRate: (json['attendanceRate'] as num?)?.toDouble() ?? 0,
      objectives: List<String>.from(json['objectives'] as List<dynamic>? ?? []),
      currentFocus: json['currentFocus'] as String? ?? '',
      lastRegistered: json['lastRegistered'] as String? ?? '',
      practiceSchedule: json['practiceSchedule'] as String? ?? '',
    );
  }
}

class Player {
  final String id;
  final String categoryId;
  final String firstName;
  final String lastName;
  final int age;
  final String position;
  final String secondaryPositions;
  final String dominantFoot;
  final String status;
  final String statusDetail;
  final int suspensionDates;

  /// Optional, free-text ("15/09" or "en 2 semanas") — only meaningful for
  /// lesionado/tocado. Never parsed/compared, just shown as a courtesy.
  final String expectedReturnDate;
  final double attendanceRate;

  /// Human-readable season line ("12 PJ - 890 min - 4 goles"). Kept for the
  /// screens and the AI payload that still consume it as text; the typed fields
  /// below are the source of truth for anything that does maths.
  final String trend;

  /// Season stats from the league. 0 for players without league data
  /// (No-LUD, or a LUD player with no minutes yet).
  final int matchesPlayed;
  final int minutesPlayed;
  final int goals;
  final int assists;
  final int yellowCards;
  final int redCards;
  final String note;

  /// Individual development plan — objectives the DT sets and tracks for
  /// this player. Named apart from [goals] (season goals scored) on purpose.
  final List<PlayerGoal> developmentGoals;

  const Player({
    required this.id,
    required this.categoryId,
    required this.firstName,
    required this.lastName,
    required this.age,
    required this.position,
    required this.secondaryPositions,
    required this.dominantFoot,
    required this.status,
    this.statusDetail = '',
    this.suspensionDates = 0,
    this.expectedReturnDate = '',
    required this.attendanceRate,
    required this.trend,
    this.matchesPlayed = 0,
    this.minutesPlayed = 0,
    this.goals = 0,
    this.assists = 0,
    this.yellowCards = 0,
    this.redCards = 0,
    required this.note,
    this.developmentGoals = const [],
  });

  bool get hasLeagueStats =>
      matchesPlayed > 0 ||
      minutesPlayed > 0 ||
      goals > 0 ||
      assists > 0 ||
      yellowCards > 0 ||
      redCards > 0;

  String get fullName => '$firstName $lastName';

  List<String> get secondaryPositionList => secondaryPositions
      .split(RegExp(r'[,;/]'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();

  String get availabilityLabel {
    final detail = statusDetail.trim();
    final suspension = suspensionDates > 0 ? ' ($suspensionDates fechas)' : '';
    if (detail.isEmpty) return '$status$suspension';
    return '$status$suspension - $detail';
  }

  /// Canonical availability, normalized from the free-text [status]. See
  /// [normalizePlayerAvailability].
  PlayerAvailability get availability => normalizePlayerAvailability(status);

  /// True only when the player is fully available — the single check every
  /// screen should use instead of its own ad-hoc `status == '...'` string
  /// compare (several used to disagree with each other).
  bool get isAvailable => availability == PlayerAvailability.disponible;

  /// True for anything the DT should see before citing/lining up this
  /// player — never blocks the action, just flags it.
  bool get hasAvailabilityWarning => !isAvailable;

  Player copyWith({
    String? categoryId,
    String? firstName,
    String? lastName,
    int? age,
    String? position,
    String? secondaryPositions,
    String? dominantFoot,
    String? status,
    String? statusDetail,
    int? suspensionDates,
    String? expectedReturnDate,
    double? attendanceRate,
    String? trend,
    int? matchesPlayed,
    int? minutesPlayed,
    int? goals,
    int? assists,
    int? yellowCards,
    int? redCards,
    String? note,
    List<PlayerGoal>? developmentGoals,
  }) {
    return Player(
      id: id,
      categoryId: categoryId ?? this.categoryId,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      age: age ?? this.age,
      position: position ?? this.position,
      secondaryPositions: secondaryPositions ?? this.secondaryPositions,
      dominantFoot: dominantFoot ?? this.dominantFoot,
      status: status ?? this.status,
      statusDetail: statusDetail ?? this.statusDetail,
      suspensionDates: suspensionDates ?? this.suspensionDates,
      expectedReturnDate: expectedReturnDate ?? this.expectedReturnDate,
      attendanceRate: attendanceRate ?? this.attendanceRate,
      trend: trend ?? this.trend,
      matchesPlayed: matchesPlayed ?? this.matchesPlayed,
      minutesPlayed: minutesPlayed ?? this.minutesPlayed,
      goals: goals ?? this.goals,
      assists: assists ?? this.assists,
      yellowCards: yellowCards ?? this.yellowCards,
      redCards: redCards ?? this.redCards,
      note: note ?? this.note,
      developmentGoals: developmentGoals ?? this.developmentGoals,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'categoryId': categoryId,
      'firstName': firstName,
      'lastName': lastName,
      'age': age,
      'position': position,
      'secondaryPositions': secondaryPositions,
      'dominantFoot': dominantFoot,
      'status': status,
      'statusDetail': statusDetail,
      'suspensionDates': suspensionDates,
      'expectedReturnDate': expectedReturnDate,
      'attendanceRate': attendanceRate,
      'trend': trend,
      'matchesPlayed': matchesPlayed,
      'minutesPlayed': minutesPlayed,
      'goals': goals,
      'assists': assists,
      'yellowCards': yellowCards,
      'redCards': redCards,
      'note': note,
      'developmentGoals': developmentGoals.map((g) => g.toJson()).toList(),
    };
  }

  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      id:
          json['id'] as String? ??
          'player-${DateTime.now().millisecondsSinceEpoch}',
      categoryId: json['categoryId'] as String? ?? '',
      firstName: json['firstName'] as String? ?? '',
      lastName: json['lastName'] as String? ?? '',
      age: json['age'] as int? ?? 0,
      position: json['position'] as String? ?? '',
      secondaryPositions: json['secondaryPositions'] as String? ?? '',
      dominantFoot: json['dominantFoot'] as String? ?? '',
      status: json['status'] as String? ?? 'Activo',
      statusDetail: json['statusDetail'] as String? ?? '',
      suspensionDates: (json['suspensionDates'] as num?)?.toInt() ?? 0,
      expectedReturnDate: json['expectedReturnDate'] as String? ?? '',
      attendanceRate: (json['attendanceRate'] as num?)?.toDouble() ?? 0,
      trend: json['trend'] as String? ?? '',
      matchesPlayed: (json['matchesPlayed'] as num?)?.toInt() ?? 0,
      minutesPlayed: (json['minutesPlayed'] as num?)?.toInt() ?? 0,
      goals: (json['goals'] as num?)?.toInt() ?? 0,
      assists: (json['assists'] as num?)?.toInt() ?? 0,
      yellowCards: (json['yellowCards'] as num?)?.toInt() ?? 0,
      redCards: (json['redCards'] as num?)?.toInt() ?? 0,
      note: cleanVisiblePlayerNote(json['note'] as String? ?? ''),
      developmentGoals: (json['developmentGoals'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(PlayerGoal.fromJson)
          .toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Individual development goals — a small plan the DT tracks per player.
// ---------------------------------------------------------------------------

enum PlayerGoalArea { tecnica, tactica, fisica, mental, conducta, otra }

enum PlayerGoalPriority { baja, media, alta }

enum PlayerGoalStatus { pendiente, enProgreso, logrado, pausado }

extension PlayerGoalAreaLabel on PlayerGoalArea {
  String get label => switch (this) {
    PlayerGoalArea.tecnica => 'Técnica',
    PlayerGoalArea.tactica => 'Táctica',
    PlayerGoalArea.fisica => 'Física',
    PlayerGoalArea.mental => 'Mental',
    PlayerGoalArea.conducta => 'Conducta',
    PlayerGoalArea.otra => 'Otra',
  };
}

extension PlayerGoalPriorityLabel on PlayerGoalPriority {
  String get label => switch (this) {
    PlayerGoalPriority.baja => 'Baja',
    PlayerGoalPriority.media => 'Media',
    PlayerGoalPriority.alta => 'Alta',
  };
}

extension PlayerGoalStatusLabel on PlayerGoalStatus {
  String get label => switch (this) {
    PlayerGoalStatus.pendiente => 'Pendiente',
    PlayerGoalStatus.enProgreso => 'En progreso',
    PlayerGoalStatus.logrado => 'Logrado',
    PlayerGoalStatus.pausado => 'Pausado',
  };
}

/// One objective in a player's individual development plan.
class PlayerGoal {
  final String id;
  final String title;
  final PlayerGoalArea area;
  final String detail;
  final PlayerGoalPriority priority;
  final PlayerGoalStatus status;

  /// Free-text/ISO date — never parsed, just shown as a courtesy.
  final String reviewDate;
  final String createdAt;

  const PlayerGoal({
    required this.id,
    required this.title,
    this.area = PlayerGoalArea.otra,
    this.detail = '',
    this.priority = PlayerGoalPriority.media,
    this.status = PlayerGoalStatus.pendiente,
    this.reviewDate = '',
    this.createdAt = '',
  });

  PlayerGoal copyWith({
    String? title,
    PlayerGoalArea? area,
    String? detail,
    PlayerGoalPriority? priority,
    PlayerGoalStatus? status,
    String? reviewDate,
  }) {
    return PlayerGoal(
      id: id,
      title: title ?? this.title,
      area: area ?? this.area,
      detail: detail ?? this.detail,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      reviewDate: reviewDate ?? this.reviewDate,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'area': area.name,
    'detail': detail,
    'priority': priority.name,
    'status': status.name,
    'reviewDate': reviewDate,
    'createdAt': createdAt,
  };

  factory PlayerGoal.fromJson(Map<String, dynamic> json) {
    return PlayerGoal(
      id:
          json['id'] as String? ??
          'goal-${DateTime.now().microsecondsSinceEpoch}',
      title: json['title'] as String? ?? '',
      area: PlayerGoalArea.values.firstWhere(
        (item) => item.name == json['area'],
        orElse: () => PlayerGoalArea.otra,
      ),
      detail: json['detail'] as String? ?? '',
      priority: PlayerGoalPriority.values.firstWhere(
        (item) => item.name == json['priority'],
        orElse: () => PlayerGoalPriority.media,
      ),
      status: PlayerGoalStatus.values.firstWhere(
        (item) => item.name == json['status'],
        orElse: () => PlayerGoalStatus.pendiente,
      ),
      reviewDate: json['reviewDate'] as String? ?? '',
      createdAt: json['createdAt'] as String? ?? '',
    );
  }
}

// ---------------------------------------------------------------------------
// Player availability — one canonical status, normalized from the free-text
// [Player.status] field so every screen agrees on what "available" means.
// Never blocks a DT's decision, only flags it.
// ---------------------------------------------------------------------------

enum PlayerAvailability { disponible, tocado, lesionado, sancionado, ausente }

/// Maps free-text status — old presets ('Activo', 'Suspendido', 'Duda',
/// 'Viaje', 'Examen') and the current canonical labels alike — to one of
/// the 5 states. Unknown or empty text defaults to disponible: a player
/// never becomes invisible/unavailable just because older data used a
/// different word for "fine".
PlayerAvailability normalizePlayerAvailability(String rawStatus) {
  final s = rawStatus.trim().toLowerCase();
  if (s.contains('lesion')) return PlayerAvailability.lesionado;
  if (s.contains('sancion') || s.contains('suspend')) {
    return PlayerAvailability.sancionado;
  }
  if (s.contains('duda') || s.contains('tocado')) {
    return PlayerAvailability.tocado;
  }
  if (s.contains('ausente') || s.contains('viaje') || s.contains('examen')) {
    return PlayerAvailability.ausente;
  }
  return PlayerAvailability.disponible;
}

extension PlayerAvailabilityPresentation on PlayerAvailability {
  String get label => switch (this) {
    PlayerAvailability.disponible => 'Disponible',
    PlayerAvailability.tocado => 'Tocado',
    PlayerAvailability.lesionado => 'Lesionado',
    PlayerAvailability.sancionado => 'Sancionado',
    PlayerAvailability.ausente => 'Ausente avisado',
  };

  /// Mirrors CX.green/amber/red/faint from lib/ui — kept as literal hex here
  /// (not imported) since cantera_data.dart is the data layer main.dart
  /// itself depends on, and must not import back into the app shell.
  Color get color => switch (this) {
    PlayerAvailability.disponible => const Color(0xFF159463),
    PlayerAvailability.tocado => const Color(0xFFE0A11A),
    PlayerAvailability.lesionado => const Color(0xFFDC3D3D),
    PlayerAvailability.sancionado => const Color(0xFFDC3D3D),
    PlayerAvailability.ausente => const Color(0xFF8CA39B),
  };
}

class Methodology {
  final String playingStyle;
  final List<String> offensivePrinciples;
  final List<String> defensivePrinciples;
  final List<String> ageObjectives;
  final List<String> values;
  final List<String> evaluationCriteria;

  const Methodology({
    required this.playingStyle,
    required this.offensivePrinciples,
    required this.defensivePrinciples,
    required this.ageObjectives,
    required this.values,
    required this.evaluationCriteria,
  });

  Methodology copyWith({
    String? playingStyle,
    List<String>? offensivePrinciples,
    List<String>? defensivePrinciples,
    List<String>? ageObjectives,
    List<String>? values,
    List<String>? evaluationCriteria,
  }) {
    return Methodology(
      playingStyle: playingStyle ?? this.playingStyle,
      offensivePrinciples: offensivePrinciples ?? this.offensivePrinciples,
      defensivePrinciples: defensivePrinciples ?? this.defensivePrinciples,
      ageObjectives: ageObjectives ?? this.ageObjectives,
      values: values ?? this.values,
      evaluationCriteria: evaluationCriteria ?? this.evaluationCriteria,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'playingStyle': playingStyle,
      'offensivePrinciples': offensivePrinciples,
      'defensivePrinciples': defensivePrinciples,
      'ageObjectives': ageObjectives,
      'values': values,
      'evaluationCriteria': evaluationCriteria,
    };
  }

  factory Methodology.fromJson(Map<String, dynamic> json) {
    return Methodology(
      playingStyle: json['playingStyle'] as String? ?? '',
      offensivePrinciples: List<String>.from(
        json['offensivePrinciples'] as List<dynamic>? ?? [],
      ),
      defensivePrinciples: List<String>.from(
        json['defensivePrinciples'] as List<dynamic>? ?? [],
      ),
      ageObjectives: List<String>.from(
        json['ageObjectives'] as List<dynamic>? ?? [],
      ),
      values: List<String>.from(json['values'] as List<dynamic>? ?? []),
      evaluationCriteria: List<String>.from(
        json['evaluationCriteria'] as List<dynamic>? ?? [],
      ),
    );
  }
}

class ClubUserAccess {
  final String id;
  final String name;
  final String role;
  final String email;
  final String phone;

  const ClubUserAccess({
    required this.id,
    required this.name,
    required this.role,
    required this.email,
    required this.phone,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'role': role,
      'email': email,
      'phone': phone,
    };
  }

  factory ClubUserAccess.fromJson(Map<String, dynamic> json) {
    return ClubUserAccess(
      id:
          json['id'] as String? ??
          'user-${DateTime.now().millisecondsSinceEpoch}',
      name: json['name'] as String? ?? '',
      role: json['role'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
    );
  }
}

class TrainingSession {
  final String id;
  final String categoryId;
  final String title;
  final String objective;
  final int duration;
  final String space;
  final int playerCount;
  final bool generatedByAi;
  final String status;
  final String scheduledDate;
  final List<TrainingBlock> blocks;
  final List<String> coachCues;
  final List<String> successIndicators;
  final List<String> contextSources;
  final List<String> limitations;
  final String confidence;

  const TrainingSession({
    required this.id,
    required this.categoryId,
    required this.title,
    required this.objective,
    required this.duration,
    required this.space,
    required this.playerCount,
    required this.generatedByAi,
    required this.status,
    required this.scheduledDate,
    required this.blocks,
    required this.coachCues,
    required this.successIndicators,
    this.contextSources = const [],
    this.limitations = const [],
    this.confidence = '',
  });

  TrainingSession copyWith({String? status, String? scheduledDate}) {
    return TrainingSession(
      id: id,
      categoryId: categoryId,
      title: title,
      objective: objective,
      duration: duration,
      space: space,
      playerCount: playerCount,
      generatedByAi: generatedByAi,
      status: status ?? this.status,
      scheduledDate: scheduledDate ?? this.scheduledDate,
      blocks: blocks,
      coachCues: coachCues,
      successIndicators: successIndicators,
      contextSources: contextSources,
      limitations: limitations,
      confidence: confidence,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'categoryId': categoryId,
      'title': title,
      'objective': objective,
      'duration': duration,
      'space': space,
      'playerCount': playerCount,
      'generatedByAi': generatedByAi,
      'status': status,
      'scheduledDate': scheduledDate,
      'blocks': blocks.map((block) => block.toJson()).toList(),
      'coachCues': coachCues,
      'successIndicators': successIndicators,
      'contextSources': contextSources,
      'limitations': limitations,
      'confidence': confidence,
      'operationalReadinessScore': operationalReadinessScore,
      'operationalReadinessLabel': operationalReadinessLabel,
      'primaryOperationalRisk': primaryOperationalRisk,
      'operationalAuditItems': operationalAuditItems,
    };
  }

  factory TrainingSession.fromJson(Map<String, dynamic> json) {
    return TrainingSession(
      id:
          json['id'] as String? ??
          'session-${DateTime.now().millisecondsSinceEpoch}',
      categoryId: json['categoryId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      objective: json['objective'] as String? ?? '',
      duration: json['duration'] as int? ?? 0,
      space: json['space'] as String? ?? '',
      playerCount: json['playerCount'] as int? ?? 0,
      generatedByAi: json['generatedByAi'] as bool? ?? false,
      status: json['status'] as String? ?? 'planned',
      scheduledDate: json['scheduledDate'] as String? ?? '',
      blocks: (json['blocks'] as List<dynamic>? ?? [])
          .map((item) => TrainingBlock.fromJson(item as Map<String, dynamic>))
          .toList(),
      coachCues: List<String>.from(json['coachCues'] as List<dynamic>? ?? []),
      successIndicators: List<String>.from(
        json['successIndicators'] as List<dynamic>? ?? [],
      ),
      contextSources: List<String>.from(
        json['contextSources'] as List<dynamic>? ?? [],
      ),
      limitations: List<String>.from(
        json['limitations'] as List<dynamic>? ?? [],
      ),
      confidence: json['confidence'] as String? ?? '',
    );
  }

  int get operationalReadinessScore {
    var score = 30;
    if (blocks.length >= 3) score += 15;
    if (coachCues.length >= 3) score += 12;
    if (successIndicators.length >= 3) score += 12;
    if (contextSources.length >= 3) score += 16;
    if (scheduledDate.trim().isNotEmpty) score += 8;
    if (confidence == 'high') score += 12;
    if (confidence == 'medium') score += 6;
    score -= limitations.length * 8;
    if (confidence == 'low') score -= 10;
    return score.clamp(0, 100);
  }

  String get operationalReadinessLabel {
    final score = operationalReadinessScore;
    if (score >= 82) return 'Listo para cancha';
    if (score >= 62) return 'Revisar antes de ejecutar';
    return 'Completar datos clave';
  }

  String get primaryOperationalRisk {
    if (limitations.isNotEmpty) {
      return limitations.first;
    }
    if (contextSources.length < 3) {
      return 'Faltan fuentes suficientes para auditar el plan.';
    }
    if (coachCues.length < 3) {
      return 'Faltan consignas claras para el cuerpo tecnico.';
    }
    if (successIndicators.length < 3) {
      return 'Faltan indicadores para medir el trabajo.';
    }
    if (scheduledDate.trim().isEmpty) {
      return 'Falta fecha para ordenar la agenda.';
    }
    return 'Plan trazable con consignas e indicadores listos.';
  }

  List<String> get operationalAuditItems {
    final items = [
      'Bloques definidos: ${blocks.length}',
      'Consignas al DT: ${coachCues.length}',
      'Indicadores medibles: ${successIndicators.length}',
      'Fuentes usadas: ${contextSources.length}',
      'Limitaciones declaradas: ${limitations.length}',
      scheduledDate.trim().isEmpty
          ? 'Fecha pendiente'
          : 'Fecha planificada: $scheduledDate',
      confidence.trim().isEmpty
          ? 'Confianza no declarada'
          : 'Confianza: $confidence',
    ];
    return items;
  }

  List<String> get postTrainingReviewPrompts {
    final prompts = <String>[
      if (successIndicators.isNotEmpty)
        '¿Se observo ${successIndicators.first.toLowerCase()}?',
      if (coachCues.isNotEmpty)
        '¿La consigna "${coachCues.first}" fue entendida por el plantel?',
      if (blocks.isNotEmpty)
        '¿Que ajuste necesito el bloque ${blocks.first.name} durante la practica?',
      if (limitations.isNotEmpty)
        '¿La limitacion "${limitations.first}" afecto la ejecucion real?',
      '¿Que jugador o linea necesita seguimiento individual en la proxima sesion?',
      '¿Cual es el foco concreto que debe continuar la semana que viene?',
    ];
    final seen = <String>{};
    return prompts
        .map((prompt) => prompt.replaceAll('Â¿', '').replaceAll('¿', ''))
        .where((prompt) => seen.add(prompt))
        .take(5)
        .toList();
  }
}

class TrainingBlock {
  final String name;
  final String duration;
  final String description;
  final String intensity;
  final List<String> constraints;
  final List<String> coachingPoints;
  final String successMetric;

  /// Spatial representation of this block's exercise (pitch, players, ball,
  /// movements, zones). Null on sessions generated before this field existed —
  /// callers synthesize a fallback with [AnimationScene.fromBlockText].
  final AnimationScene? animationScene;

  const TrainingBlock(
    this.name,
    this.duration,
    this.description, {
    this.intensity = '',
    this.constraints = const [],
    this.coachingPoints = const [],
    this.successMetric = '',
    this.animationScene,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'duration': duration,
    'description': description,
    'intensity': intensity,
    'constraints': constraints,
    'coachingPoints': coachingPoints,
    'successMetric': successMetric,
    if (animationScene != null) 'animation_scene': animationScene!.toJson(),
  };

  factory TrainingBlock.fromJson(Map<String, dynamic> json) => TrainingBlock(
    json['name'] as String? ?? '',
    json['duration'] as String? ?? '',
    json['description'] as String? ?? '',
    intensity: json['intensity'] as String? ?? '',
    constraints: List<String>.from(
      (json['constraints'] ?? json['rules']) as List<dynamic>? ?? [],
    ),
    coachingPoints: List<String>.from(
      (json['coachingPoints'] ?? json['coaching_points']) as List<dynamic>? ??
          [],
    ),
    successMetric:
        (json['successMetric'] ?? json['success_metric']) as String? ?? '',
    animationScene: _sceneFromJson(
      json['animation_scene'] ?? json['animationScene'],
    ),
  );

  static AnimationScene? _sceneFromJson(dynamic raw) {
    if (raw is! Map) return null;
    final scene = AnimationScene.fromJson(Map<String, dynamic>.from(raw));
    return scene.hasContent ? scene : null;
  }

  /// This block's scene, synthesizing a text-based fallback when the AI did
  /// not provide one.
  AnimationScene sceneOrFallback({
    required String space,
    required int playerCount,
  }) {
    final scene = animationScene;
    if (scene != null && scene.hasContent) return scene;
    return AnimationScene.fromBlockText(
      text: '$name $description ${constraints.join(' ')}',
      space: space,
      playerCount: playerCount,
      cues: coachingPoints,
    );
  }
}

/// A reusable exercise in the club's library: saved from a generated session
/// block, or created by hand. [categoryId] empty means shared across every
/// category in the club (most exercises — a rondo works for any squad).
class Exercise {
  final String id;
  final String name;
  final String description;
  final String objective;
  final String space;
  final int players;
  final int duration; // minutes — structured so a session can sum it
  final String intensity;
  final List<String> coachingPoints;
  final List<String> constraints;
  final String successMetric;
  final String categoryId;
  final String source; // 'manual' | 'ai'
  final String createdAt; // ISO
  final AnimationScene? animationScene;

  const Exercise({
    required this.id,
    required this.name,
    this.description = '',
    this.objective = '',
    this.space = '',
    this.players = 0,
    this.duration = 0,
    this.intensity = '',
    this.coachingPoints = const [],
    this.constraints = const [],
    this.successMetric = '',
    this.categoryId = '',
    this.source = 'manual',
    this.createdAt = '',
    this.animationScene,
  });

  Exercise copyWith({
    String? name,
    String? description,
    String? objective,
    String? space,
    int? players,
    int? duration,
    String? intensity,
    List<String>? coachingPoints,
    List<String>? constraints,
    String? successMetric,
    String? categoryId,
    AnimationScene? animationScene,
  }) {
    return Exercise(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      objective: objective ?? this.objective,
      space: space ?? this.space,
      players: players ?? this.players,
      duration: duration ?? this.duration,
      intensity: intensity ?? this.intensity,
      coachingPoints: coachingPoints ?? this.coachingPoints,
      constraints: constraints ?? this.constraints,
      successMetric: successMetric ?? this.successMetric,
      categoryId: categoryId ?? this.categoryId,
      source: source,
      createdAt: createdAt,
      animationScene: animationScene ?? this.animationScene,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'objective': objective,
    'space': space,
    'players': players,
    'duration': duration,
    'intensity': intensity,
    'coachingPoints': coachingPoints,
    'constraints': constraints,
    'successMetric': successMetric,
    'categoryId': categoryId,
    'source': source,
    'createdAt': createdAt,
    if (animationScene != null) 'animation_scene': animationScene!.toJson(),
  };

  factory Exercise.fromJson(Map<String, dynamic> json) {
    final rawScene = json['animation_scene'] ?? json['animationScene'];
    AnimationScene? scene;
    if (rawScene is Map) {
      final parsed = AnimationScene.fromJson(
        Map<String, dynamic>.from(rawScene),
      );
      scene = parsed.hasContent ? parsed : null;
    }
    return Exercise(
      id:
          json['id'] as String? ??
          'exercise-${DateTime.now().microsecondsSinceEpoch}',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      objective: json['objective'] as String? ?? '',
      space: json['space'] as String? ?? '',
      players: json['players'] as int? ?? 0,
      duration: json['duration'] as int? ?? 0,
      intensity: json['intensity'] as String? ?? '',
      coachingPoints: List<String>.from(
        json['coachingPoints'] as List<dynamic>? ?? [],
      ),
      constraints: List<String>.from(
        json['constraints'] as List<dynamic>? ?? [],
      ),
      successMetric: json['successMetric'] as String? ?? '',
      categoryId: json['categoryId'] as String? ?? '',
      source: json['source'] as String? ?? 'manual',
      createdAt: json['createdAt'] as String? ?? '',
      animationScene: scene,
    );
  }

  /// Renders this exercise as a session block — the shape the pitch/list UI
  /// and the existing text/PNG exports already know how to draw.
  TrainingBlock toBlock() => TrainingBlock(
    name,
    duration > 0 ? '$duration min' : '',
    description,
    intensity: intensity,
    constraints: constraints,
    coachingPoints: coachingPoints,
    successMetric: successMetric,
    animationScene: animationScene,
  );

  /// Captures a session block (AI-generated or manual) into the library.
  factory Exercise.fromBlock(
    TrainingBlock block, {
    required String id,
    required int minutes,
    String objective = '',
    int players = 0,
    String space = '',
    String categoryId = '',
    String source = 'ai',
  }) {
    return Exercise(
      id: id,
      name: block.name,
      description: block.description,
      objective: objective,
      space: space,
      players: players,
      duration: minutes,
      intensity: block.intensity,
      coachingPoints: block.coachingPoints,
      constraints: block.constraints,
      successMetric: block.successMetric,
      categoryId: categoryId,
      source: source,
      createdAt: DateTime.now().toUtc().toIso8601String(),
      animationScene: block.animationScene,
    );
  }
}

double _clamp01(dynamic value) {
  final d = value is num ? value.toDouble() : double.tryParse('$value') ?? 0.5;
  if (d.isNaN) return 0.5;
  return d.clamp(0.0, 1.0);
}

double _sceneSeconds(dynamic value) {
  final raw = '$value'.replaceAll(RegExp(r'[^0-9.]'), '');
  final d = value is num ? value.toDouble() : double.tryParse(raw) ?? 0;
  return d.isNaN ? 0 : d;
}

class ScenePoint {
  final double x; // 0..1 across pitch width (0 left, 1 right)
  final double y; // 0..1 along pitch length (0 own goal, 1 rival goal)

  const ScenePoint(this.x, this.y);

  factory ScenePoint.fromJson(dynamic json) {
    if (json is Map) {
      return ScenePoint(_clamp01(json['x']), _clamp01(json['y']));
    }
    if (json is List && json.length >= 2) {
      return ScenePoint(_clamp01(json[0]), _clamp01(json[1]));
    }
    return const ScenePoint(0.5, 0.5);
  }

  Map<String, dynamic> toJson() => {'x': x, 'y': y};
}

class SceneActor {
  final String id;
  final String label;
  final String team; // own | rival | neutral
  final ScenePoint start;
  final ScenePoint end;
  final String role;

  const SceneActor({
    required this.id,
    required this.label,
    required this.team,
    required this.start,
    required this.end,
    required this.role,
  });

  factory SceneActor.fromJson(Map<String, dynamic> json) {
    final start = ScenePoint.fromJson(
      json['start'] ?? json['start_position'] ?? json['from'],
    );
    return SceneActor(
      id: '${json['id'] ?? json['label'] ?? ''}'.trim(),
      label: '${json['label'] ?? json['id'] ?? ''}'.trim(),
      team: _team('${json['team'] ?? 'own'}'),
      start: start,
      end: ScenePoint.fromJson(
        json['end'] ?? json['end_position'] ?? json['to'] ?? start.toJson(),
      ),
      role: '${json['role'] ?? ''}'.trim(),
    );
  }

  static String _team(String value) {
    final t = value.toLowerCase();
    if (t.startsWith('riv') || t.contains('opp') || t.contains('contra')) {
      return 'rival';
    }
    if (t.contains('neut') || t.contains('comod') || t.contains('joker')) {
      return 'neutral';
    }
    return 'own';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'team': team,
    'start': start.toJson(),
    'end': end.toJson(),
    'role': role,
  };
}

class SceneMovement {
  final String playerId;
  final ScenePoint from;
  final ScenePoint to;
  final double startS;
  final double endS;
  final String
  type; // pase | conduccion | desmarque | presion | cobertura | apoyo

  const SceneMovement({
    required this.playerId,
    required this.from,
    required this.to,
    required this.startS,
    required this.endS,
    required this.type,
  });

  factory SceneMovement.fromJson(Map<String, dynamic> json) {
    final start = _sceneSeconds(
      json['start_s'] ?? json['start'] ?? json['timing'],
    );
    final end = _sceneSeconds(json['end_s'] ?? json['end']);
    return SceneMovement(
      playerId: '${json['player'] ?? json['player_id'] ?? json['id'] ?? ''}'
          .trim(),
      from: ScenePoint.fromJson(json['from']),
      to: ScenePoint.fromJson(json['to']),
      startS: start.clamp(0.0, 60.0),
      endS: (end <= start ? start + 2 : end).clamp(0.0, 60.0),
      type: '${json['type'] ?? json['movement_type'] ?? 'movimiento'}'.trim(),
    );
  }

  Map<String, dynamic> toJson() => {
    'player': playerId,
    'from': from.toJson(),
    'to': to.toJson(),
    'start_s': startS,
    'end_s': endS,
    'type': type,
  };
}

class SceneZone {
  final String type; // target | forbidden | lane
  final String label;
  final double x;
  final double y;
  final double width;
  final double height;

  const SceneZone({
    required this.type,
    required this.label,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory SceneZone.fromJson(Map<String, dynamic> json) => SceneZone(
    type: _zoneType('${json['type'] ?? 'target'}'),
    label: '${json['label'] ?? ''}'.trim(),
    x: _clamp01(json['x']),
    y: _clamp01(json['y']),
    width: _clamp01(json['width'] ?? json['w'] ?? 0.3),
    height: _clamp01(json['height'] ?? json['h'] ?? 0.3),
  );

  static String _zoneType(String value) {
    final t = value.toLowerCase();
    if (t.contains('prohib') || t.contains('forbid') || t.contains('no-go')) {
      return 'forbidden';
    }
    if (t.contains('carril') || t.contains('lane') || t.contains('pasillo')) {
      return 'lane';
    }
    return 'target';
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'label': label,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };
}

class AnimationScene {
  final String pitchArea;
  final List<SceneActor> players;
  final List<ScenePoint> ballPath;
  final List<SceneMovement> movements;
  final List<SceneZone> zones;
  final List<String> coachingCues;
  final double durationSeconds;
  final bool isFallback;

  const AnimationScene({
    required this.pitchArea,
    required this.players,
    required this.ballPath,
    required this.movements,
    required this.zones,
    required this.coachingCues,
    required this.durationSeconds,
    this.isFallback = false,
  });

  bool get hasContent => players.isNotEmpty || ballPath.length >= 2;

  static const _pitchAreas = {
    'full',
    'half',
    'attacking_third',
    'middle_third',
    'defensive_third',
    'small_grid',
    'wide_channels',
  };

  static String normalizePitchArea(String value) {
    final t = value.toLowerCase().trim().replaceAll(RegExp(r'[\s-]+'), '_');
    if (_pitchAreas.contains(t)) return t;
    if (t.contains('cuadr') ||
        t.contains('reduc') ||
        t.contains('grid') ||
        t.contains('rombo') ||
        t.contains('rond')) {
      return 'small_grid';
    }
    if (t.contains('ofens') || t.contains('attack') || t.contains('final')) {
      return 'attacking_third';
    }
    if (t.contains('fondo') ||
        t.contains('salida') ||
        t.contains('propi') ||
        t.contains('defensiv')) {
      return 'defensive_third';
    }
    if (t.contains('banda') ||
        t.contains('ancho') ||
        t.contains('wide') ||
        t.contains('amplitud') ||
        t.contains('carril')) {
      return 'wide_channels';
    }
    if (t.contains('medio') || t.contains('middle') || t.contains('central')) {
      return 'middle_third';
    }
    if (t.contains('media') || t.contains('mitad') || t.contains('half')) {
      return 'half';
    }
    return 'full';
  }

  factory AnimationScene.fromJson(
    Map<String, dynamic> json, {
    bool isFallback = false,
  }) {
    List<T> parseList<T>(dynamic v, T Function(Map<String, dynamic>) f) =>
        (v is List ? v : const [])
            .whereType<Map>()
            .map((e) => f(Map<String, dynamic>.from(e)))
            .toList();
    final ball =
        (json['ball_path'] is List ? json['ball_path'] as List : const [])
            .map(ScenePoint.fromJson)
            .toList();
    return AnimationScene(
      pitchArea: normalizePitchArea(
        '${json['pitch_area'] ?? json['pitchArea'] ?? 'full'}',
      ),
      players: parseList(json['players'], SceneActor.fromJson),
      ballPath: ball,
      movements: parseList(json['movements'], SceneMovement.fromJson),
      zones: parseList(json['zones'], SceneZone.fromJson),
      coachingCues: List<String>.from(
        ((json['coaching_cues'] ?? json['coachingCues'] ?? const []) as List)
            .map((e) => '$e'.trim())
            .where((e) => e.isNotEmpty),
      ),
      durationSeconds: () {
        final s = _sceneSeconds(
          json['duration_seconds'] ?? json['durationSeconds'] ?? 8,
        );
        return (s < 3 ? 8.0 : s).clamp(3.0, 20.0);
      }(),
      isFallback: isFallback,
    );
  }

  Map<String, dynamic> toJson() => {
    'pitch_area': pitchArea,
    'players': players.map((p) => p.toJson()).toList(),
    'ball_path': ballPath.map((p) => p.toJson()).toList(),
    'movements': movements.map((m) => m.toJson()).toList(),
    'zones': zones.map((z) => z.toJson()).toList(),
    'coaching_cues': coachingCues,
    'duration_seconds': durationSeconds,
  };

  /// Deterministic scene synthesized from a block's own text plus session
  /// context. Distinct objectives / spaces / player counts produce visibly
  /// distinct scenes. Always flagged [isFallback].
  factory AnimationScene.fromBlockText({
    required String text,
    required String space,
    required int playerCount,
    List<String> cues = const [],
  }) {
    final t = '$text $space'.toLowerCase();
    final area = normalizePitchArea('$space $text');
    final total = playerCount.clamp(4, 12);
    final perSide = (total / 2).round().clamp(2, 6);

    bool has(List<String> keys) => keys.any(t.contains);
    final isPress = has([
      'presion',
      'presión',
      'recuper',
      'tras perdida',
      'tras pérdida',
      'marca',
      'robar',
    ]);
    final isBuildOut = has([
      'salida',
      'construccion',
      'construcción',
      'desde el fondo',
      'amplitud',
      'circulacion',
      'circulación',
      'posesion',
      'posesión',
    ]);
    final isFinish = has([
      'finaliz',
      'defin',
      'remate',
      'gol',
      'llegada al area',
      'llegada al área',
      'centro',
    ]);

    final players = <SceneActor>[];
    final movements = <SceneMovement>[];
    final zones = <SceneZone>[];
    List<ScenePoint> ball;
    const dur = 9.0;

    ScenePoint p(double x, double y) =>
        ScenePoint(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0));

    if (isPress) {
      // Rival keeps the ball low-centre, own players collapse onto it.
      final rivalBase = p(0.5, 0.32);
      players.add(
        SceneActor(
          id: 'r1',
          label: 'R',
          team: 'rival',
          start: rivalBase,
          end: p(0.42, 0.24),
          role: 'con balón',
        ),
      );
      for (var i = 1; i < perSide; i++) {
        final rx = 0.25 + (i / perSide) * 0.5;
        players.add(
          SceneActor(
            id: 'r${i + 1}',
            label: 'r',
            team: 'rival',
            start: p(rx, 0.18),
            end: p(rx, 0.14),
            role: 'apoyo rival',
          ),
        );
      }
      for (var i = 0; i < perSide; i++) {
        final sx = 0.2 + (i / perSide) * 0.6;
        final start = p(sx, 0.62 + (i.isEven ? 0.06 : 0));
        final end = p(
          rivalBase.x + (sx - rivalBase.x) * 0.35,
          rivalBase.y + 0.1,
        );
        players.add(
          SceneActor(
            id: 'o${i + 1}',
            label: '${i + 1}',
            team: 'own',
            start: start,
            end: end,
            role: i == 0 ? 'presiona al balón' : 'cierra línea de pase',
          ),
        );
        movements.add(
          SceneMovement(
            playerId: 'o${i + 1}',
            from: start,
            to: end,
            startS: 0,
            endS: 4 + i.toDouble(),
            type: i == 0 ? 'presion' : 'cobertura',
          ),
        );
      }
      ball = [p(0.5, 0.32), p(0.6, 0.28), p(0.55, 0.2), p(0.4, 0.16)];
      zones.add(
        const SceneZone(
          type: 'target',
          label: 'zona de recuperación',
          x: 0.28,
          y: 0.1,
          width: 0.44,
          height: 0.34,
        ),
      );
    } else if (isBuildOut) {
      // Wide back line + keeper play out; ball travels goal -> flank -> forward.
      players.add(
        SceneActor(
          id: 'gk',
          label: 'PO',
          team: 'own',
          start: p(0.5, 0.06),
          end: p(0.5, 0.1),
          role: 'inicia',
        ),
      );
      final laneXs = [0.12, 0.38, 0.62, 0.88];
      for (var i = 0; i < perSide; i++) {
        final lane = laneXs[i % laneXs.length];
        final start = p(lane, 0.2 + (i.isEven ? 0 : 0.08));
        final end = p(lane, 0.44 + i * 0.05);
        players.add(
          SceneActor(
            id: 'o${i + 1}',
            label: '${i + 1}',
            team: 'own',
            start: start,
            end: end,
            role: i == 0 ? 'recibe y orienta' : 'ofrece amplitud',
          ),
        );
        movements.add(
          SceneMovement(
            playerId: 'o${i + 1}',
            from: start,
            to: end,
            startS: 1 + i.toDouble(),
            endS: 5 + i.toDouble(),
            type: i == 0 ? 'conduccion' : 'apoyo',
          ),
        );
      }
      for (var i = 0; i < (perSide - 1).clamp(1, 4); i++) {
        final rx = 0.32 + (i / 3) * 0.36;
        players.add(
          SceneActor(
            id: 'r${i + 1}',
            label: 'r',
            team: 'rival',
            start: p(rx, 0.5),
            end: p(rx, 0.42),
            role: 'presiona salida',
          ),
        );
      }
      ball = [
        p(0.5, 0.08),
        p(0.14, 0.24),
        p(0.4, 0.4),
        p(0.82, 0.5),
        p(0.7, 0.68),
      ];
      zones.add(
        const SceneZone(
          type: 'lane',
          label: 'carril izquierdo',
          x: 0.0,
          y: 0.0,
          width: 0.28,
          height: 1.0,
        ),
      );
      zones.add(
        const SceneZone(
          type: 'lane',
          label: 'carril derecho',
          x: 0.72,
          y: 0.0,
          width: 0.28,
          height: 1.0,
        ),
      );
      zones.add(
        const SceneZone(
          type: 'target',
          label: 'zona de progresión',
          x: 0.2,
          y: 0.6,
          width: 0.6,
          height: 0.3,
        ),
      );
    } else if (isFinish) {
      for (var i = 0; i < perSide; i++) {
        final sx = 0.2 + (i / perSide) * 0.6;
        final start = p(sx, 0.55 - i * 0.03);
        final end = p(0.35 + (i / perSide) * 0.3, 0.86);
        players.add(
          SceneActor(
            id: 'o${i + 1}',
            label: '${i + 1}',
            team: 'own',
            start: start,
            end: end,
            role: i == 0 ? 'asiste' : 'ataca el área',
          ),
        );
        movements.add(
          SceneMovement(
            playerId: 'o${i + 1}',
            from: start,
            to: end,
            startS: i.toDouble(),
            endS: 4 + i.toDouble(),
            type: i == 0 ? 'pase' : 'desmarque',
          ),
        );
      }
      for (var i = 0; i < (perSide - 1).clamp(1, 4); i++) {
        players.add(
          SceneActor(
            id: 'r${i + 1}',
            label: 'r',
            team: 'rival',
            start: p(0.35 + i * 0.12, 0.82),
            end: p(0.35 + i * 0.12, 0.82),
            role: 'defiende área',
          ),
        );
      }
      ball = [p(0.2, 0.55), p(0.5, 0.7), p(0.62, 0.88)];
      zones.add(
        const SceneZone(
          type: 'target',
          label: 'área rival',
          x: 0.28,
          y: 0.78,
          width: 0.44,
          height: 0.22,
        ),
      );
    } else {
      // Generic small-sided progression: two rows, diagonal ball progression.
      for (var i = 0; i < perSide; i++) {
        final sx = 0.18 + (i / perSide) * 0.64;
        final start = p(sx, 0.3);
        final end = p(sx + 0.05, 0.7);
        players.add(
          SceneActor(
            id: 'o${i + 1}',
            label: '${i + 1}',
            team: 'own',
            start: start,
            end: end,
            role: 'progresa',
          ),
        );
        movements.add(
          SceneMovement(
            playerId: 'o${i + 1}',
            from: start,
            to: end,
            startS: i.toDouble(),
            endS: 5 + i.toDouble(),
            type: 'apoyo',
          ),
        );
      }
      for (var i = 0; i < (perSide - 1).clamp(1, 4); i++) {
        final rx = 0.3 + (i / 3) * 0.4;
        players.add(
          SceneActor(
            id: 'r${i + 1}',
            label: 'r',
            team: 'rival',
            start: p(rx, 0.55),
            end: p(rx, 0.5),
            role: 'defiende',
          ),
        );
      }
      ball = [p(0.2, 0.3), p(0.45, 0.45), p(0.7, 0.62), p(0.55, 0.8)];
      zones.add(
        const SceneZone(
          type: 'target',
          label: 'zona objetivo',
          x: 0.25,
          y: 0.62,
          width: 0.5,
          height: 0.3,
        ),
      );
    }

    return AnimationScene(
      pitchArea: area,
      players: players,
      ballPath: ball,
      movements: movements,
      zones: zones,
      coachingCues: cues
          .map((c) => c.trim())
          .where((c) => c.isNotEmpty)
          .take(3)
          .toList(),
      durationSeconds: dur,
      isFallback: true,
    );
  }
}

/// A match result a coach enters by hand. Persisted inside the club blob, so it
/// rides the existing cloud sync with no extra plumbing.
class MatchResult {
  /// 'oficial' | 'amistoso' | 'torneo' | 'practica'
  static const kinds = ['oficial', 'amistoso', 'torneo', 'practica'];

  /// 'home' | 'away' | 'neutral'
  static const venues = ['home', 'away', 'neutral'];

  final String id;
  final String categoryId;
  final String date; // ISO yyyy-MM-dd
  final String opponent;
  final String venue;
  final int goalsFor;
  final int goalsAgainst;
  final String kind;
  final String note;

  /// Set when the result was logged from a calendar Match event, so the two
  /// stay linked. Empty otherwise.
  final String calendarKey;

  /// Player ids who played this match — only for No-LUD/manual categories,
  /// where there's no league sync to source matchesPlayed from otherwise.
  final List<String> lineupIds;

  /// Player id per goal scored (a hat-trick is the same id three times) —
  /// same manual-only scope as [lineupIds].
  final List<String> scorerIds;

  const MatchResult({
    required this.id,
    required this.categoryId,
    required this.date,
    required this.opponent,
    this.venue = 'home',
    this.goalsFor = 0,
    this.goalsAgainst = 0,
    this.kind = 'oficial',
    this.note = '',
    this.calendarKey = '',
    this.lineupIds = const [],
    this.scorerIds = const [],
  });

  /// Counts toward points / % of points at stake. Friendlies and practice
  /// matches are logged but kept out of the standings-style maths.
  bool get isCompetitive => kind == 'oficial' || kind == 'torneo';

  /// 3 / 1 / 0 from the club's point of view.
  int get points =>
      goalsFor > goalsAgainst ? 3 : (goalsFor == goalsAgainst ? 1 : 0);

  /// 'G' | 'E' | 'P'
  String get outcome =>
      goalsFor > goalsAgainst ? 'G' : (goalsFor == goalsAgainst ? 'E' : 'P');

  String get venueLabel => switch (venue) {
    'away' => 'Visitante',
    'neutral' => 'Cancha neutral',
    _ => 'Local',
  };

  String get kindLabel => switch (kind) {
    'amistoso' => 'Amistoso',
    'torneo' => 'Torneo',
    'practica' => 'Práctica',
    _ => 'Oficial',
  };

  MatchResult copyWith({
    String? categoryId,
    String? date,
    String? opponent,
    String? venue,
    int? goalsFor,
    int? goalsAgainst,
    String? kind,
    String? note,
    String? calendarKey,
    List<String>? lineupIds,
    List<String>? scorerIds,
  }) {
    return MatchResult(
      id: id,
      categoryId: categoryId ?? this.categoryId,
      date: date ?? this.date,
      opponent: opponent ?? this.opponent,
      venue: venue ?? this.venue,
      goalsFor: goalsFor ?? this.goalsFor,
      goalsAgainst: goalsAgainst ?? this.goalsAgainst,
      kind: kind ?? this.kind,
      note: note ?? this.note,
      calendarKey: calendarKey ?? this.calendarKey,
      lineupIds: lineupIds ?? this.lineupIds,
      scorerIds: scorerIds ?? this.scorerIds,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'categoryId': categoryId,
    'date': date,
    'opponent': opponent,
    'venue': venue,
    'goalsFor': goalsFor,
    'goalsAgainst': goalsAgainst,
    'kind': kind,
    'note': note,
    'calendarKey': calendarKey,
    'lineupIds': lineupIds,
    'scorerIds': scorerIds,
  };

  factory MatchResult.fromJson(Map<String, dynamic> json) {
    final venue = json['venue'] as String? ?? 'home';
    final kind = json['kind'] as String? ?? 'oficial';
    return MatchResult(
      id:
          json['id'] as String? ??
          'result-${DateTime.now().microsecondsSinceEpoch}',
      categoryId: json['categoryId'] as String? ?? '',
      date: json['date'] as String? ?? '',
      opponent: json['opponent'] as String? ?? '',
      venue: MatchResult.venues.contains(venue) ? venue : 'home',
      goalsFor: (json['goalsFor'] as num?)?.toInt() ?? 0,
      goalsAgainst: (json['goalsAgainst'] as num?)?.toInt() ?? 0,
      kind: MatchResult.kinds.contains(kind) ? kind : 'oficial',
      note: json['note'] as String? ?? '',
      calendarKey: json['calendarKey'] as String? ?? '',
      lineupIds: List<String>.from(
        json['lineupIds'] as List<dynamic>? ?? const [],
      ),
      scorerIds: List<String>.from(
        json['scorerIds'] as List<dynamic>? ?? const [],
      ),
    );
  }
}

/// A match's full preparation: rival context, game plan, set pieces and
/// notes — one per upcoming/past match, optionally linked to a calendar
/// event via a stable [calendarEventId] (survives the event being renamed).
class MatchPreparation {
  final String id;
  final String categoryId;
  final String calendarEventId;
  final String rival;
  final String date;
  final String time;
  final String venue; // 'local' | 'visitante' | 'neutral' | ''
  final String opponentNotes; // manual, No-LUD only
  final String planIdea;
  final String planObjective;
  final String offensiveKeys;
  final String defensiveKeys;
  final String transitions;
  final String setPiecesFor;
  final String setPiecesAgainst;
  final String playersToWatch;
  final String staffNotes;
  final String linkedSessionId;
  final String createdAt;
  final String updatedAt;

  const MatchPreparation({
    required this.id,
    required this.categoryId,
    this.calendarEventId = '',
    this.rival = '',
    this.date = '',
    this.time = '',
    this.venue = '',
    this.opponentNotes = '',
    this.planIdea = '',
    this.planObjective = '',
    this.offensiveKeys = '',
    this.defensiveKeys = '',
    this.transitions = '',
    this.setPiecesFor = '',
    this.setPiecesAgainst = '',
    this.playersToWatch = '',
    this.staffNotes = '',
    this.linkedSessionId = '',
    this.createdAt = '',
    this.updatedAt = '',
  });

  MatchPreparation copyWith({
    String? rival,
    String? date,
    String? time,
    String? venue,
    String? opponentNotes,
    String? planIdea,
    String? planObjective,
    String? offensiveKeys,
    String? defensiveKeys,
    String? transitions,
    String? setPiecesFor,
    String? setPiecesAgainst,
    String? playersToWatch,
    String? staffNotes,
    String? linkedSessionId,
    String? updatedAt,
  }) {
    return MatchPreparation(
      id: id,
      categoryId: categoryId,
      calendarEventId: calendarEventId,
      rival: rival ?? this.rival,
      date: date ?? this.date,
      time: time ?? this.time,
      venue: venue ?? this.venue,
      opponentNotes: opponentNotes ?? this.opponentNotes,
      planIdea: planIdea ?? this.planIdea,
      planObjective: planObjective ?? this.planObjective,
      offensiveKeys: offensiveKeys ?? this.offensiveKeys,
      defensiveKeys: defensiveKeys ?? this.defensiveKeys,
      transitions: transitions ?? this.transitions,
      setPiecesFor: setPiecesFor ?? this.setPiecesFor,
      setPiecesAgainst: setPiecesAgainst ?? this.setPiecesAgainst,
      playersToWatch: playersToWatch ?? this.playersToWatch,
      staffNotes: staffNotes ?? this.staffNotes,
      linkedSessionId: linkedSessionId ?? this.linkedSessionId,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'categoryId': categoryId,
    'calendarEventId': calendarEventId,
    'rival': rival,
    'date': date,
    'time': time,
    'venue': venue,
    'opponentNotes': opponentNotes,
    'planIdea': planIdea,
    'planObjective': planObjective,
    'offensiveKeys': offensiveKeys,
    'defensiveKeys': defensiveKeys,
    'transitions': transitions,
    'setPiecesFor': setPiecesFor,
    'setPiecesAgainst': setPiecesAgainst,
    'playersToWatch': playersToWatch,
    'staffNotes': staffNotes,
    'linkedSessionId': linkedSessionId,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };

  factory MatchPreparation.fromJson(Map<String, dynamic> json) {
    return MatchPreparation(
      id:
          json['id'] as String? ??
          'matchprep-${DateTime.now().microsecondsSinceEpoch}',
      categoryId: json['categoryId'] as String? ?? '',
      calendarEventId: json['calendarEventId'] as String? ?? '',
      rival: json['rival'] as String? ?? '',
      date: json['date'] as String? ?? '',
      time: json['time'] as String? ?? '',
      venue: json['venue'] as String? ?? '',
      opponentNotes: json['opponentNotes'] as String? ?? '',
      planIdea: json['planIdea'] as String? ?? '',
      planObjective: json['planObjective'] as String? ?? '',
      offensiveKeys: json['offensiveKeys'] as String? ?? '',
      defensiveKeys: json['defensiveKeys'] as String? ?? '',
      transitions: json['transitions'] as String? ?? '',
      setPiecesFor: json['setPiecesFor'] as String? ?? '',
      setPiecesAgainst: json['setPiecesAgainst'] as String? ?? '',
      playersToWatch: json['playersToWatch'] as String? ?? '',
      staffNotes: json['staffNotes'] as String? ?? '',
      linkedSessionId: json['linkedSessionId'] as String? ?? '',
      createdAt: json['createdAt'] as String? ?? '',
      updatedAt: json['updatedAt'] as String? ?? '',
    );
  }
}

/// Standings-style summary computed from hand-logged [MatchResult]s for one
/// category. Only official / tournament matches feed the points maths;
/// friendlies and practice games are counted apart. Pure — no Flutter deps —
/// so it is covered by unit tests.
class MatchStats {
  final List<MatchResult> all; // newest first
  final List<MatchResult> competitive; // oficial + torneo, newest first

  const MatchStats._({required this.all, required this.competitive});

  factory MatchStats.forCategory(List<MatchResult> results, String categoryId) {
    final mine = results.where((r) => r.categoryId == categoryId).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return MatchStats._(
      all: mine,
      competitive: mine.where((r) => r.isCompetitive).toList(),
    );
  }

  int get played => competitive.length;
  int get wins => competitive.where((r) => r.outcome == 'G').length;
  int get draws => competitive.where((r) => r.outcome == 'E').length;
  int get losses => competitive.where((r) => r.outcome == 'P').length;
  int get goalsFor => competitive.fold(0, (s, r) => s + r.goalsFor);
  int get goalsAgainst => competitive.fold(0, (s, r) => s + r.goalsAgainst);
  int get goalDiff => goalsFor - goalsAgainst;
  int get points => wins * 3 + draws;
  double get pointsRate => played == 0 ? 0 : points / (played * 3);
  double get scoring => played == 0 ? 0 : goalsFor / played;
  double get conceding => played == 0 ? 0 : goalsAgainst / played;
  int get friendlies => all.length - competitive.length;

  List<String> get last5 => competitive.take(5).map((r) => r.outcome).toList();

  /// Leading run of the same kind of result from the newest match. "sin ganar"
  /// groups draws and losses.
  ({int count, String label}) get streak {
    if (competitive.isEmpty) return (count: 0, label: '');
    final winning = competitive.first.outcome == 'G';
    var n = 0;
    for (final r in competitive) {
      if ((r.outcome == 'G') == winning) {
        n++;
      } else {
        break;
      }
    }
    return (count: n, label: winning ? 'ganando' : 'sin ganar');
  }
}

class TrainingReport {
  final String categoryId;
  final String date;
  final int attendanceCount;
  final int totalPlayers;
  final String objectiveWorked;
  final String whatWentWell;
  final String whatWentWrong;
  final List<String> highlightedPlayers;
  final List<String> injuries;
  final String nextRecommendation;

  const TrainingReport({
    required this.categoryId,
    required this.date,
    required this.attendanceCount,
    required this.totalPlayers,
    required this.objectiveWorked,
    required this.whatWentWell,
    required this.whatWentWrong,
    required this.highlightedPlayers,
    required this.injuries,
    required this.nextRecommendation,
  });

  Map<String, dynamic> toJson() {
    return {
      'categoryId': categoryId,
      'date': date,
      'attendanceCount': attendanceCount,
      'totalPlayers': totalPlayers,
      'objectiveWorked': objectiveWorked,
      'whatWentWell': whatWentWell,
      'whatWentWrong': whatWentWrong,
      'highlightedPlayers': highlightedPlayers,
      'injuries': injuries,
      'nextRecommendation': nextRecommendation,
    };
  }

  factory TrainingReport.fromJson(Map<String, dynamic> json) {
    return TrainingReport(
      categoryId: json['categoryId'] as String? ?? '',
      date: json['date'] as String? ?? '',
      attendanceCount: json['attendanceCount'] as int? ?? 0,
      totalPlayers: json['totalPlayers'] as int? ?? 0,
      objectiveWorked: json['objectiveWorked'] as String? ?? '',
      whatWentWell: json['whatWentWell'] as String? ?? '',
      whatWentWrong: json['whatWentWrong'] as String? ?? '',
      highlightedPlayers: List<String>.from(
        json['highlightedPlayers'] as List<dynamic>? ?? [],
      ),
      injuries: List<String>.from(json['injuries'] as List<dynamic>? ?? []),
      nextRecommendation: json['nextRecommendation'] as String? ?? '',
    );
  }
}

class AttendanceRecord {
  final String categoryId;
  final String date;
  final List<String> presentIds;
  final List<String> rosterIds;
  final String note;

  const AttendanceRecord({
    required this.categoryId,
    required this.date,
    required this.presentIds,
    required this.rosterIds,
    this.note = '',
  });

  Map<String, dynamic> toJson() => {
    'categoryId': categoryId,
    'date': date,
    'presentIds': presentIds,
    'rosterIds': rosterIds,
    'note': note,
  };

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    return AttendanceRecord(
      categoryId: json['categoryId'] as String? ?? '',
      date: json['date'] as String? ?? '',
      presentIds: List<String>.from(
        json['presentIds'] as List<dynamic>? ?? const [],
      ),
      rosterIds: List<String>.from(
        json['rosterIds'] as List<dynamic>? ??
            json['presentIds'] as List<dynamic>? ??
            const [],
      ),
      note: json['note'] as String? ?? '',
    );
  }
}

class IntelligentAlert {
  final String type;
  final String severity;
  final String title;
  final String description;
  final String? categoryId;
  final String status;

  const IntelligentAlert({
    required this.type,
    required this.severity,
    required this.title,
    required this.description,
    this.categoryId,
    required this.status,
  });
}

class AiReport {
  final String title;
  final String reportType;
  final String categoryId;
  final String content;
  final String createdAt;

  const AiReport({
    required this.title,
    required this.reportType,
    required this.categoryId,
    required this.content,
    required this.createdAt,
  });
}

const canteraDemoClub = CanteraClub(
  id: 'club-demo-formativas',
  name: 'Club Demo',
  league: '',
  sportFocus: 'Futbol',
  primaryColor: Color(0xFF6EE7B7),
  secondaryColor: Color(0xFF10231D),
  methodology: Methodology(
    playingStyle: '',
    offensivePrinciples: [],
    defensivePrinciples: [],
    ageObjectives: [],
    values: [],
    evaluationCriteria: [],
  ),
  categories: [],
  players: [],
  sessions: [],
  trainingReports: [],
  alerts: [],
  aiReports: [],
  users: [],
);
