import 'package:flutter/material.dart';

enum UserRole { coordinator, coach, viewer }

String cleanVisiblePlayerNote(String value) {
  return value
      .replaceAll(RegExp(r'Importado desde LUD Stats', caseSensitive: false), 'Importado desde la liga')
      .replaceAll(RegExp(r'LUD\s*player_id\s*:?\s*\d+', caseSensitive: false), '')
      .replaceAll(RegExp(r'player_id\s*:?\s*\d+', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
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
  final double attendanceRate;
  final String trend;
  final String note;

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
    required this.attendanceRate,
    required this.trend,
    required this.note,
  });

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
    double? attendanceRate,
    String? trend,
    String? note,
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
      attendanceRate: attendanceRate ?? this.attendanceRate,
      trend: trend ?? this.trend,
      note: note ?? this.note,
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
      'attendanceRate': attendanceRate,
      'trend': trend,
      'note': note,
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
      attendanceRate: (json['attendanceRate'] as num?)?.toDouble() ?? 0,
      trend: json['trend'] as String? ?? '',
      note: cleanVisiblePlayerNote(json['note'] as String? ?? ''),
    );
  }
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

  const TrainingBlock(
    this.name,
    this.duration,
    this.description, {
    this.intensity = '',
    this.constraints = const [],
    this.coachingPoints = const [],
    this.successMetric = '',
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'duration': duration,
    'description': description,
    'intensity': intensity,
    'constraints': constraints,
    'coachingPoints': coachingPoints,
    'successMetric': successMetric,
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
  );
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
