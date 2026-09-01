import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/cantera_data.dart';
import 'supabase_auth_service.dart';
import 'preview_access_service.dart';

class TrainingAiRequest {
  final CanteraClub club;
  final CategorySquad category;
  final String objective;
  final String problem;
  final String space;
  final int duration;
  final int players;
  final String rivalName;
  final String rivalTableContext;
  final String rivalStyle;
  final String squadProfile;
  final String rivalMemory;
  final String rivalDangerPlayers;
  final String previousMatchNotes;
  final String scheduledDate;
  final String fixtureContext;

  const TrainingAiRequest({
    required this.club,
    required this.category,
    required this.objective,
    required this.problem,
    required this.space,
    required this.duration,
    required this.players,
    this.rivalName = '',
    this.rivalTableContext = '',
    this.rivalStyle = '',
    this.squadProfile = '',
    this.rivalMemory = '',
    this.rivalDangerPlayers = '',
    this.previousMatchNotes = '',
    this.scheduledDate = '',
    this.fixtureContext = '',
  });

  Map<String, Object?> toJson() {
    final playersInCategory = club.players
        .where((player) => player.categoryId == category.id)
        .toList();
    final categoryPlayers = playersInCategory
        .map(
          (player) => {
            'name': player.fullName,
            'age': player.age,
            'position': player.position,
            'secondary_positions': player.secondaryPositions,
            'dominant_foot': player.dominantFoot,
            'status': player.status,
            'attendance_rate': player.attendanceRate,
            'trend': player.trend,
            'coach_note': player.note,
          },
        )
        .toList();
    final ludPlayers = playersInCategory
        .where(
          (player) =>
              player.id.startsWith('lud-player-') ||
              player.note.contains('Importado desde LUD Stats'),
        )
        .length;
    final aiReadyPlayers = playersInCategory
        .where(_hasAiReadyPlayerProfile)
        .length;
    final incompleteAiProfiles = playersInCategory
        .where((player) => !_hasAiReadyPlayerProfile(player))
        .take(8)
        .map(
          (player) => {
            'name': player.fullName,
            'missing': _missingAiProfileFields(player),
          },
        )
        .toList();
    final manualClub =
        club.dataSource == 'manual' || club.league == 'Trabajo independiente';
    final missingProfileFields = <String>[
      if (category.currentFocus.trim().isEmpty) 'foco actual de categoria',
      if (club.methodology.playingStyle.trim().isEmpty)
        'idea de juego del club',
      if (playersInCategory.every((player) => player.position.trim().isEmpty))
        'posiciones del plantel',
      if (playersInCategory.every((player) => player.note.trim().isEmpty))
        'notas tecnicas individuales',
      if (playersInCategory.isNotEmpty &&
          aiReadyPlayers < playersInCategory.length)
        'perfiles individuales completos',
      if (!manualClub && ludPlayers == 0) 'datos de liga del plantel',
    ];
    final recentReports = club.trainingReports
        .where((report) => report.categoryId == category.id)
        .take(2)
        .map((report) => report.toJson())
        .toList();
    final unavailablePlayers = playersInCategory
        .where((player) {
          final status = player.status.toLowerCase();
          return status.contains('lesion') ||
              status.contains('baja') ||
              status.contains('suspend');
        })
        .map(
          (player) => {
            'name': player.fullName,
            'status': player.status,
            'position': player.position,
          },
        )
        .toList();
    final positionMap = _positionMap(playersInCategory);
    final evidenceContract = _evidenceContract(
      club: club,
      category: category,
      playerCount: playersInCategory.length,
      ludPlayers: ludPlayers,
      aiReadyPlayers: aiReadyPlayers,
      scheduledDate: scheduledDate,
      fixtureContext: fixtureContext,
    );
    final contextScore = _contextScore(
      club: club,
      category: category,
      playerCount: playersInCategory.length,
      ludPlayers: ludPlayers,
      aiReadyPlayers: aiReadyPlayers,
      objective: objective,
      problem: problem,
      space: space,
      squadProfile: squadProfile,
      rivalMemory: rivalMemory,
      rivalDangerPlayers: rivalDangerPlayers,
      previousMatchNotes: previousMatchNotes,
      fixtureContext: fixtureContext,
      recentReports: recentReports.length,
    );

    return {
      'club': {
        'id': club.id,
        'name': club.name,
        'league': club.league,
        'data_source': club.dataSource,
        'methodology': {
          'playing_style': club.methodology.playingStyle,
          'offensive_principles': club.methodology.offensivePrinciples,
          'defensive_principles': club.methodology.defensivePrinciples,
          'age_objectives': club.methodology.ageObjectives,
          'values': club.methodology.values,
          'evaluation_criteria': club.methodology.evaluationCriteria,
        },
      },
      'category': {
        'id': category.id,
        'name': category.name,
        'age_group': category.ageGroup,
        'coach_name': category.coachName,
        'registered_player_count': category.playerCount,
        'attendance_rate': category.attendanceRate,
        'objectives': category.objectives,
        'current_focus': category.currentFocus,
        'players': categoryPlayers,
        'position_map': positionMap,
      },
      'data_quality': {
        'category_players_loaded': categoryPlayers.length,
        'lud_traced_players': ludPlayers,
        'ai_ready_player_profiles': aiReadyPlayers,
        'incomplete_ai_player_profiles':
            playersInCategory.length - aiReadyPlayers,
        'incomplete_ai_profile_examples': incompleteAiProfiles,
        'missing_profile_fields': missingProfileFields,
        'must_not_invent_missing_data': true,
      },
      'session_request': {
        'objective': objective.trim(),
        'problem': problem.trim(),
        'space': space.trim(),
        'duration_minutes': duration,
        'available_players': players,
        'scheduled_date': scheduledDate,
      },
      'recent_field_reports': recentReports,
      'unavailable_players': unavailablePlayers,
      'match_context': {
        'rival_name': rivalName.trim(),
        'table_and_moment': rivalTableContext.trim(),
        'rival_game_model_strengths_and_weaknesses': rivalStyle.trim(),
        'own_squad_individual_and_collective_profile': squadProfile.trim(),
        'rival_memory_from_staff': rivalMemory.trim(),
        'rival_danger_players_and_patterns': rivalDangerPlayers.trim(),
        'previous_match_notes': previousMatchNotes.trim(),
        'fixture_context_from_lud': fixtureContext.trim(),
      },
      'generation_quality': {
        'context_score': contextScore,
        'evidence_contract': evidenceContract,
        'must_reference_at_least_three_evidence_items': true,
        'must_downgrade_confidence_below_70': contextScore < 70,
      },
    };
  }
}

List<String> _evidenceContract({
  required CanteraClub club,
  required CategorySquad category,
  required int playerCount,
  required int ludPlayers,
  required int aiReadyPlayers,
  required String scheduledDate,
  required String fixtureContext,
}) {
  return [
    if (club.name.trim().isNotEmpty) 'Club: ${club.name.trim()}',
    if (club.league.trim().isNotEmpty) 'Liga: ${club.league.trim()}',
    if (category.name.trim().isNotEmpty) 'Categoria: ${category.name.trim()}',
    if (category.currentFocus.trim().isNotEmpty)
      'Foco actual: ${category.currentFocus.trim()}',
    if (club.methodology.playingStyle.trim().isNotEmpty)
      'Modelo del club: ${club.methodology.playingStyle.trim()}',
    'Plantel cargado: $playerCount jugadores',
    'Perfiles individuales completos: $aiReadyPlayers/$playerCount',
    if (ludPlayers > 0) 'Jugadores con datos de liga: $ludPlayers',
    if (scheduledDate.trim().isNotEmpty) 'Fecha objetivo: $scheduledDate',
    if (fixtureContext.trim().isNotEmpty)
      'Fixture de la liga seleccionado: ${fixtureContext.trim()}',
  ];
}

int _contextScore({
  required CanteraClub club,
  required CategorySquad category,
  required int playerCount,
  required int ludPlayers,
  required int aiReadyPlayers,
  required String objective,
  required String problem,
  required String space,
  required String squadProfile,
  required String rivalMemory,
  required String rivalDangerPlayers,
  required String previousMatchNotes,
  required String fixtureContext,
  required int recentReports,
}) {
  var score = 0;
  if (objective.trim().length >= 12) score += 12;
  if (problem.trim().length >= 12) score += 12;
  if (space.trim().isNotEmpty) score += 6;
  if (club.methodology.playingStyle.trim().isNotEmpty) score += 12;
  if (category.currentFocus.trim().isNotEmpty) score += 8;
  if (playerCount > 0) score += 10;
  if (playerCount > 0) score += (aiReadyPlayers / playerCount * 18).round();
  if (ludPlayers > 0) score += 8;
  if (squadProfile.trim().length >= 24) score += 8;
  if (rivalMemory.trim().length >= 24) score += 4;
  if (rivalDangerPlayers.trim().length >= 16) score += 4;
  if (previousMatchNotes.trim().length >= 24) score += 4;
  if (fixtureContext.trim().isNotEmpty) score += 4;
  if (recentReports > 0) score += 2;
  return score.clamp(0, 100);
}

Map<String, Object> _positionMap(List<Player> players) {
  final lines = {
    'goalkeepers': <String>[],
    'defenders': <String>[],
    'midfielders': <String>[],
    'attackers': <String>[],
    'without_position': <String>[],
  };
  for (final player in players) {
    final line = _playerLine(player.position);
    lines[line]!.add(player.fullName.trim());
  }
  return {
    ...lines,
    'must_use_for_roles': true,
    'missing_position_profiles': lines['without_position']!.length,
  };
}

bool _hasAiReadyPlayerProfile(Player player) =>
    player.position.trim().isNotEmpty &&
    player.secondaryPositions.trim().isNotEmpty &&
    player.dominantFoot.trim().isNotEmpty &&
    player.status.trim().isNotEmpty &&
    player.note.trim().length >= 12;

List<String> _missingAiProfileFields(Player player) => [
  if (player.position.trim().isEmpty) 'position',
  if (player.secondaryPositions.trim().isEmpty) 'secondary_positions',
  if (player.dominantFoot.trim().isEmpty) 'dominant_foot',
  if (player.status.trim().isEmpty) 'status',
  if (player.note.trim().length < 12) 'coach_note',
];

String _playerLine(String position) {
  final text = position.toLowerCase();
  if (text.trim().isEmpty) return 'without_position';
  if (text.contains('arquero') || text.contains('golero')) {
    return 'goalkeepers';
  }
  if (text.contains('def') ||
      text.contains('zaguero') ||
      text.contains('lateral')) {
    return 'defenders';
  }
  if (text.contains('vol') ||
      text.contains('medio') ||
      text.contains('interior') ||
      text.contains('enganche')) {
    return 'midfielders';
  }
  if (text.contains('del') ||
      text.contains('punta') ||
      text.contains('extremo') ||
      text.contains('9')) {
    return 'attackers';
  }
  return 'without_position';
}

class TrainingAiException implements Exception {
  final String message;
  const TrainingAiException(this.message);

  @override
  String toString() => message;
}

class TrainingAiService {
  static const _endpoint = String.fromEnvironment(
    'CANTERA_AI_ENDPOINT',
    defaultValue: '/api/generate-training-session',
  );

  Future<TrainingSession> generateSession(TrainingAiRequest request) {
    return _generateRemote(request, mode: 'training_session');
  }

  Future<TrainingSession> generateTactic(TrainingAiRequest request) {
    return _generateRemote(request, mode: 'match_tactic');
  }

  Future<TrainingSession> _generateRemote(
    TrainingAiRequest request, {
    required String mode,
  }) async {
    http.Response response;
    try {
      final body = request.toJson()..['mode'] = mode;
      response = await http
          .post(
            Uri.base.resolve(_endpoint),
            headers: {
              'content-type': 'application/json',
              if (SupabaseAuthService.currentSession?.accessToken
                  case final token?)
                'authorization': 'Bearer $token',
              if (PreviewAccessService.token case final previewToken?)
                'x-cantera-preview-token': previewToken,
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 55));
    } catch (_) {
      throw const TrainingAiException(
        'No se pudo conectar con el asistente. Intenta nuevamente en unos segundos.',
      );
    }

    Map<String, dynamic> data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const TrainingAiException(
        'El asistente devolvio una respuesta incompleta. Intenta nuevamente.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = data['message'] as String?;
      if (message != null && message.trim().isNotEmpty) {
        throw TrainingAiException(message);
      }
      throw const TrainingAiException(
        'No se pudo generar una respuesta confiable. Revisa los datos e intenta nuevamente.',
      );
    }

    final blocks = (data['blocks'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(
          (item) => TrainingBlock(
            item['name'] as String? ?? '',
            item['duration'] as String? ?? '',
            item['description'] as String? ?? '',
            intensity: item['intensity'] as String? ?? '',
            constraints: List<String>.from(
              item['constraints'] as List<dynamic>? ?? [],
            ),
            coachingPoints: List<String>.from(
              item['coaching_points'] as List<dynamic>? ?? [],
            ),
            successMetric: item['success_metric'] as String? ?? '',
          ),
        )
        .where(
          (block) =>
              block.name.trim().isNotEmpty &&
              block.description.trim().isNotEmpty,
        )
        .toList();

    final minimumBlocks = mode == 'match_tactic' ? 6 : 4;
    if (blocks.length < minimumBlocks) {
      throw const TrainingAiException(
        'La IA no produjo un plan suficientemente detallado. Vuelve a intentarlo con mas contexto.',
      );
    }

    final title = data['title'] as String? ?? '';
    final diagnosis = data['objective'] as String? ?? '';
    final coachCues = List<String>.from(
      data['coach_cues'] as List<dynamic>? ?? [],
    );
    final successIndicators = List<String>.from(
      data['success_indicators'] as List<dynamic>? ?? [],
    );
    final contextSources = List<String>.from(
      data['context_used'] as List<dynamic>? ?? [],
    );
    final limitations = List<String>.from(
      data['limitations'] as List<dynamic>? ?? [],
    );
    final confidence = data['confidence'] as String? ?? '';

    if (title.trim().isEmpty ||
        diagnosis.trim().isEmpty ||
        coachCues.length < 2 ||
        successIndicators.length < 2) {
      throw const TrainingAiException(
        'La respuesta no alcanzo el nivel de detalle necesario. Agrega informacion concreta e intenta nuevamente.',
      );
    }
    if (contextSources.isEmpty ||
        !const {'high', 'medium', 'low'}.contains(confidence)) {
      throw const TrainingAiException(
        'La respuesta no explico que datos utilizo. Vuelve a intentarlo para obtener un plan trazable.',
      );
    }

    return TrainingSession(
      id: 'gemini-${DateTime.now().millisecondsSinceEpoch}',
      categoryId: request.category.id,
      title: title,
      objective: diagnosis,
      duration: request.duration,
      space: request.space,
      playerCount: request.players,
      generatedByAi: true,
      status: 'planned',
      scheduledDate: '',
      blocks: blocks,
      coachCues: coachCues,
      successIndicators: successIndicators,
      contextSources: contextSources,
      limitations: limitations,
      confidence: confidence,
    );
  }
}
