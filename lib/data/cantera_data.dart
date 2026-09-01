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
    if (json is Map) return ScenePoint(_clamp01(json['x']), _clamp01(json['y']));
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
  final String type; // pase | conduccion | desmarque | presion | cobertura | apoyo

  const SceneMovement({
    required this.playerId,
    required this.from,
    required this.to,
    required this.startS,
    required this.endS,
    required this.type,
  });

  factory SceneMovement.fromJson(Map<String, dynamic> json) {
    final start = _sceneSeconds(json['start_s'] ?? json['start'] ?? json['timing']);
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
    final ball = (json['ball_path'] is List
            ? json['ball_path'] as List
            : const [])
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

    ScenePoint p(double x, double y) => ScenePoint(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0));

    if (isPress) {
      // Rival keeps the ball low-centre, own players collapse onto it.
      final rivalBase = p(0.5, 0.32);
      players.add(SceneActor(
        id: 'r1',
        label: 'R',
        team: 'rival',
        start: rivalBase,
        end: p(0.42, 0.24),
        role: 'con balón',
      ));
      for (var i = 1; i < perSide; i++) {
        final rx = 0.25 + (i / perSide) * 0.5;
        players.add(SceneActor(
          id: 'r${i + 1}',
          label: 'r',
          team: 'rival',
          start: p(rx, 0.18),
          end: p(rx, 0.14),
          role: 'apoyo rival',
        ));
      }
      for (var i = 0; i < perSide; i++) {
        final sx = 0.2 + (i / perSide) * 0.6;
        final start = p(sx, 0.62 + (i.isEven ? 0.06 : 0));
        final end = p(
          rivalBase.x + (sx - rivalBase.x) * 0.35,
          rivalBase.y + 0.1,
        );
        players.add(SceneActor(
          id: 'o${i + 1}',
          label: '${i + 1}',
          team: 'own',
          start: start,
          end: end,
          role: i == 0 ? 'presiona al balón' : 'cierra línea de pase',
        ));
        movements.add(SceneMovement(
          playerId: 'o${i + 1}',
          from: start,
          to: end,
          startS: 0,
          endS: 4 + i.toDouble(),
          type: i == 0 ? 'presion' : 'cobertura',
        ));
      }
      ball = [p(0.5, 0.32), p(0.6, 0.28), p(0.55, 0.2), p(0.4, 0.16)];
      zones.add(const SceneZone(
        type: 'target',
        label: 'zona de recuperación',
        x: 0.28,
        y: 0.1,
        width: 0.44,
        height: 0.34,
      ));
    } else if (isBuildOut) {
      // Wide back line + keeper play out; ball travels goal -> flank -> forward.
      players.add(SceneActor(
        id: 'gk',
        label: 'PO',
        team: 'own',
        start: p(0.5, 0.06),
        end: p(0.5, 0.1),
        role: 'inicia',
      ));
      final laneXs = [0.12, 0.38, 0.62, 0.88];
      for (var i = 0; i < perSide; i++) {
        final lane = laneXs[i % laneXs.length];
        final start = p(lane, 0.2 + (i.isEven ? 0 : 0.08));
        final end = p(lane, 0.44 + i * 0.05);
        players.add(SceneActor(
          id: 'o${i + 1}',
          label: '${i + 1}',
          team: 'own',
          start: start,
          end: end,
          role: i == 0 ? 'recibe y orienta' : 'ofrece amplitud',
        ));
        movements.add(SceneMovement(
          playerId: 'o${i + 1}',
          from: start,
          to: end,
          startS: 1 + i.toDouble(),
          endS: 5 + i.toDouble(),
          type: i == 0 ? 'conduccion' : 'apoyo',
        ));
      }
      for (var i = 0; i < (perSide - 1).clamp(1, 4); i++) {
        final rx = 0.32 + (i / 3) * 0.36;
        players.add(SceneActor(
          id: 'r${i + 1}',
          label: 'r',
          team: 'rival',
          start: p(rx, 0.5),
          end: p(rx, 0.42),
          role: 'presiona salida',
        ));
      }
      ball = [p(0.5, 0.08), p(0.14, 0.24), p(0.4, 0.4), p(0.82, 0.5), p(0.7, 0.68)];
      zones.add(const SceneZone(
        type: 'lane',
        label: 'carril izquierdo',
        x: 0.0,
        y: 0.0,
        width: 0.28,
        height: 1.0,
      ));
      zones.add(const SceneZone(
        type: 'lane',
        label: 'carril derecho',
        x: 0.72,
        y: 0.0,
        width: 0.28,
        height: 1.0,
      ));
      zones.add(const SceneZone(
        type: 'target',
        label: 'zona de progresión',
        x: 0.2,
        y: 0.6,
        width: 0.6,
        height: 0.3,
      ));
    } else if (isFinish) {
      for (var i = 0; i < perSide; i++) {
        final sx = 0.2 + (i / perSide) * 0.6;
        final start = p(sx, 0.55 - i * 0.03);
        final end = p(0.35 + (i / perSide) * 0.3, 0.86);
        players.add(SceneActor(
          id: 'o${i + 1}',
          label: '${i + 1}',
          team: 'own',
          start: start,
          end: end,
          role: i == 0 ? 'asiste' : 'ataca el área',
        ));
        movements.add(SceneMovement(
          playerId: 'o${i + 1}',
          from: start,
          to: end,
          startS: i.toDouble(),
          endS: 4 + i.toDouble(),
          type: i == 0 ? 'pase' : 'desmarque',
        ));
      }
      for (var i = 0; i < (perSide - 1).clamp(1, 4); i++) {
        players.add(SceneActor(
          id: 'r${i + 1}',
          label: 'r',
          team: 'rival',
          start: p(0.35 + i * 0.12, 0.82),
          end: p(0.35 + i * 0.12, 0.82),
          role: 'defiende área',
        ));
      }
      ball = [p(0.2, 0.55), p(0.5, 0.7), p(0.62, 0.88)];
      zones.add(const SceneZone(
        type: 'target',
        label: 'área rival',
        x: 0.28,
        y: 0.78,
        width: 0.44,
        height: 0.22,
      ));
    } else {
      // Generic small-sided progression: two rows, diagonal ball progression.
      for (var i = 0; i < perSide; i++) {
        final sx = 0.18 + (i / perSide) * 0.64;
        final start = p(sx, 0.3);
        final end = p(sx + 0.05, 0.7);
        players.add(SceneActor(
          id: 'o${i + 1}',
          label: '${i + 1}',
          team: 'own',
          start: start,
          end: end,
          role: 'progresa',
        ));
        movements.add(SceneMovement(
          playerId: 'o${i + 1}',
          from: start,
          to: end,
          startS: i.toDouble(),
          endS: 5 + i.toDouble(),
          type: 'apoyo',
        ));
      }
      for (var i = 0; i < (perSide - 1).clamp(1, 4); i++) {
        final rx = 0.3 + (i / 3) * 0.4;
        players.add(SceneActor(
          id: 'r${i + 1}',
          label: 'r',
          team: 'rival',
          start: p(rx, 0.55),
          end: p(rx, 0.5),
          role: 'defiende',
        ));
      }
      ball = [p(0.2, 0.3), p(0.45, 0.45), p(0.7, 0.62), p(0.55, 0.8)];
      zones.add(const SceneZone(
        type: 'target',
        label: 'zona objetivo',
        x: 0.25,
        y: 0.62,
        width: 0.5,
        height: 0.3,
      ));
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
