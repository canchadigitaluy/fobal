// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:async';
import 'dart:html' as html;

import 'package:flutter/material.dart';
import '../data/cantera_data.dart';
import '../main.dart';
import '../services/club_access_service.dart';
import '../services/export_download_service.dart';
import '../services/export_text_service.dart';
import '../services/offline_mutation_service.dart';
import '../services/training_ai_service.dart';
import '../ui/exercise_animation_preview.dart';
import '../ui/export_preview_dialog.dart';
import 'exercise_library_screen.dart';
import 'session_builder_screen.dart';

const _fixtureStylePlaceholder =
    'Fixture detectado desde la liga. Completar observaciones del rival sin inventar: sistema, presion, salida, zonas fuertes y debilidades vistas.';

class ReservasScreen extends StatefulWidget {
  const ReservasScreen({super.key});

  @override
  State<ReservasScreen> createState() => _ReservasScreenState();
}

class _ReservasScreenState extends State<ReservasScreen> {
  String _objective = '';
  String _problem = '';
  String _space = '';
  String _rivalName = '';
  String _rivalTableContext = '';
  String _rivalStyle = '';
  String _squadProfile = '';
  String _rivalMemory = '';
  String _rivalDangerPlayers = '';
  String _previousMatchNotes = '';
  int _duration = 75;
  int _players = 18;
  DateTime _sessionDate = DateTime.now().add(const Duration(days: 1));
  DateTime _matchDate = DateTime.now().add(const Duration(days: 7));
  bool _generating = false;
  bool _generatingTactic = false;
  bool _fixtureLoading = false;
  bool _opponentLoading = false;
  String? _selectedCategoryId;
  String? _fixtureKey;
  TrainingSession? _generatedSession;
  TrainingSession? _generatedTactic;
  String? _sessionError;
  String? _tacticError;
  String? _fixtureError;
  String? _opponentError;
  String _fixtureContext = '';
  List<LudFixtureMatch> _fixtureMatches = const [];
  final Map<String, _FixtureMemory> _fixtureMemoryByCategory = {};
  final Set<String> _draftHydratedKeys = {};

  final TextEditingController _transcriptController = TextEditingController(
    text: '',
  );

  bool _handoffApplied = false;
  String _handoffOrigin = '';
  String _handoffContext = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_handoffApplied) return;
    final actions = ShellActions.maybeOf(context);
    if (actions == null) return;
    final focus = actions.takeSessionFocus();
    final prep = actions.takeMatchPrep();
    if (focus == null && prep == null) return;
    _handoffApplied = true;
    if (focus != null) {
      _objective = focus.objective;
      _problem = focus.problem;
      _handoffOrigin = focus.origin.isEmpty ? 'Estadísticas' : focus.origin;
      _handoffContext = focus.context;
    }
    if (prep != null) {
      if (prep.rivalName.trim().isNotEmpty) _rivalName = prep.rivalName.trim();
      if (prep.rivalContext.trim().isNotEmpty) {
        _rivalStyle = prep.rivalContext.trim();
      }
      if (prep.note.trim().isNotEmpty) _rivalMemory = prep.note.trim();
      _handoffOrigin = prep.origin.isEmpty ? 'Estadísticas' : prep.origin;
      _handoffContext = prep.rivalContext.trim();
    }
  }

  @override
  void dispose() {
    _transcriptController.dispose();
    super.dispose();
  }

  Future<void> _generateSession(
    CanteraClub club,
    CategorySquad category,
  ) async {
    if (club.categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Creá una categoría en Configurar antes de planificar.'),
        ),
      );
      return;
    }
    if (_objective.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Escribí un objetivo para la sesión.'),
        ),
      );
      return;
    }
    final manualClub = club.isManualClub;
    final available = club.players
        .where(
          (player) => player.categoryId == category.id && _isAvailable(player),
        )
        .length;
    // No hard block on squad size: a thin plan is still useful and the
    // assistant fills the gaps. Just size the session sensibly.
    final plannedPlayers = manualClub
        ? _players.clamp(1, 99).toInt()
        : (available > 0 && _players > available ? available : _players);
    final categoryPlayers = club.players
        .where((player) => player.categoryId == category.id)
        .toList();
    final squadProfile = _effectiveSquadProfile(
      manual: _squadProfile,
      automatic: _buildSquadProfile(category, categoryPlayers),
    );
    final fixtureContext = _fixtureContextFor(category);

    setState(() {
      _generating = true;
      _sessionError = null;
      _generatedSession = null;
    });
    final request = TrainingAiRequest(
      club: club,
      category: category,
      objective: _objective,
      problem: _problem,
      space: _space,
      duration: _duration,
      players: plannedPlayers,
      rivalName: _rivalName,
      rivalTableContext: _rivalTableContext,
      rivalStyle: _cleanRivalStyle(_rivalStyle),
      squadProfile: squadProfile,
      rivalMemory: _rivalMemory,
      rivalDangerPlayers: _rivalDangerPlayers,
      previousMatchNotes: _previousMatchNotes,
      scheduledDate: _isoDate(_sessionDate),
      fixtureContext: fixtureContext,
    );

    try {
      final generated = await TrainingAiService().generateSession(request);
      final session = generated.copyWith(scheduledDate: _isoDate(_sessionDate));
      if (!mounted) return;
      final sessions = [
        session,
        ...club.sessions.where((item) => item.id != session.id),
      ];
      AppScope.of(context).updateClub(club.copyWith(sessions: sessions));
      final writeResult =
          await OfflineMutationService.instance.saveTacticalDataOfflineFirst(
        type: 'session',
        title: session.title,
        content: session.toJson(),
        relatedLudTeamId: _ludTeamIdFromLeague(club.league),
        categoryId: category.id,
      );
      if (!mounted) return;
      _markDraftResolved(category.id);
      setState(() {
        _generatedSession = session;
        _generating = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            writeResult.synced
                ? 'Sesión agregada y guardada para el club.'
                : 'Sesión agregada. Se guardará cuando vuelva la conexión.',
          ),
        ),
      );
    } on TrainingAiException catch (error) {
      if (!mounted) return;
      setState(() {
        _sessionError = error.message;
        _generating = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sessionError = 'No pudimos generar la sesión. Ajustá el objetivo y probá de nuevo.';
        _generating = false;
      });
    }
  }

  Future<void> _generateTactic(CanteraClub club, CategorySquad category) async {
    if (club.categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Creá una categoría en Configurar antes de preparar el partido.'),
        ),
      );
      return;
    }
    final categoryPlayers = club.players
        .where((player) => player.categoryId == category.id)
        .toList();
    final squadProfile = _effectiveSquadProfile(
      manual: _squadProfile,
      automatic: _buildSquadProfile(category, categoryPlayers),
    );
    final fixtureContext = _fixtureContextFor(category);
    if (_rivalName.trim().isEmpty ||
        !_hasManualRivalStyle(_rivalStyle) ||
        squadProfile.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Completa rival, como juega de verdad y nuestro plantel.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _generatingTactic = true;
      _tacticError = null;
      _generatedTactic = null;
    });
    final request = TrainingAiRequest(
      club: club,
      category: category,
      objective: 'Preparar táctica de partido',
      problem: 'Enfrentar al rival segun sus caracteristicas',
      space: 'Cancha completa',
      duration: _duration,
      players: _players,
      rivalName: _rivalName,
      rivalTableContext: _rivalTableContext,
      rivalStyle: _cleanRivalStyle(_rivalStyle),
      squadProfile: squadProfile,
      rivalMemory: _rivalMemory,
      rivalDangerPlayers: _rivalDangerPlayers,
      previousMatchNotes: _previousMatchNotes,
      scheduledDate: _isoDate(_matchDate),
      fixtureContext: fixtureContext,
    );

    try {
      final generated = await TrainingAiService().generateTactic(request);
      final tactic = generated.copyWith(scheduledDate: _isoDate(_matchDate));
      if (!mounted) return;
      final writeResult =
          await OfflineMutationService.instance.saveTacticalDataOfflineFirst(
        type: 'match_plan',
        title: tactic.title,
        content: tactic.toJson(),
        relatedLudTeamId: _ludTeamIdFromLeague(club.league),
        categoryId: category.id,
      );
      if (!mounted) return;
      _markDraftResolved(category.id);
      setState(() {
        _generatedTactic = tactic;
        _generatingTactic = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              writeResult.synced
                  ? 'Plan de partido guardado para el club.'
                  : 'Plan de partido agregado. Se guardará cuando vuelva la conexión.',
            ),
          ),
        );
      }
    } on TrainingAiException catch (error) {
      if (!mounted) return;
      setState(() {
        _tacticError = error.message;
        _generatingTactic = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _tacticError = 'No pudimos generar la táctica. Sumá contexto del rival y probá de nuevo.';
        _generatingTactic = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final club = scope.fullClub;
    final canGenerate = scope.role != UserRole.viewer;
    final scopeSelectedId = scope.selectedCategoryId;
    final selectedId = club.categories.any((item) => item.id == scopeSelectedId)
        ? scopeSelectedId
        : club.categories.any((item) => item.id == _selectedCategoryId)
        ? _selectedCategoryId
        : club.categories.isEmpty
        ? null
        : club.categories.first.id;
    if (_selectedCategoryId != selectedId && selectedId != null) {
      _selectedCategoryId = selectedId;
    }
    final category = club.categories.isEmpty
        ? const CategorySquad(
            id: 'categoria-demo',
            name: 'Categoría sin cargar',
            sport: '',
            ageGroup: '',
            coachName: '',
            playerCount: 0,
            attendanceRate: 0,
            objectives: [],
            currentFocus: '',
            lastRegistered: '',
          )
        : club.categories.firstWhere((item) => item.id == selectedId);
    _hydrateLocalDraft(category);
    final categoryPlayers = club.players
        .where((player) => player.categoryId == category.id)
        .toList();
    final availablePlayers = categoryPlayers.where(_isAvailable).length;
    final suggestedSquadProfile = _buildSquadProfile(category, categoryPlayers);
    final effectiveSquadProfile = _effectiveSquadProfile(
      manual: _squadProfile,
      automatic: suggestedSquadProfile,
    );
    final activeFixtureContext = _fixtureContextFor(category);
    _ensureFixtureLoaded(category);

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Táctica'),
            Text(
              'Partidos, entrenamientos y registro',
              style: TextStyle(
                color: CX.faint,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
              children: CanteraMotion.stagger([
                if (_handoffOrigin.isNotEmpty) ...[
                  _HandoffBanner(
                    origin: _handoffOrigin,
                    context: _handoffContext,
                    onDismiss: () => setState(() {
                      _handoffOrigin = '';
                      _handoffContext = '';
                    }),
                  ),
                  const SizedBox(height: 12),
                ],
                if (club.categories.isNotEmpty) ...[
                  DropdownButtonFormField<String>(
                    key: ValueKey('tactical-category-$selectedId'),
                    initialValue: selectedId,
                    decoration: const InputDecoration(
                      labelText: 'Categoría de trabajo',
                      prefixIcon: Icon(Icons.groups_2_outlined),
                    ),
                    items: club.categories
                        .map(
                          (item) => DropdownMenuItem(
                            value: item.id,
                            child: Text(item.name),
                          ),
                        )
                        .toList(),
                    onChanged: _selectCategory,
                  ),
                ],
                const SizedBox(height: 16),
                _SectionTitle('Próximo partido'),
                const SizedBox(height: 10),
                _MatchPrepForm(
                  rivalName: _rivalName,
                  rivalTableContext: _rivalTableContext,
                  rivalStyle: _rivalStyle,
                  squadProfile: _squadProfile,
                  rivalMemory: _rivalMemory,
                  rivalDangerPlayers: _rivalDangerPlayers,
                  previousMatchNotes: _previousMatchNotes,
                  suggestedSquadProfile: suggestedSquadProfile,
                  effectiveSquadProfile: effectiveSquadProfile,
                  matchDate: _matchDate,
                  fixtureLoading: _fixtureLoading,
                  fixtureError: _fixtureError,
                  opponentLoading: _opponentLoading,
                  opponentError: _opponentError,
                  fixtureMatches: _fixtureMatches,
                  fixtureContext: activeFixtureContext,
                  categoryName: category.name,
                  canGenerate: canGenerate,
                  onMatchDate: (date) => _updateMatchPrep(matchDate: date),
                  onRivalName: (v) => _updateMatchPrep(rivalName: v),
                  onRivalTableContext: (v) =>
                      _updateMatchPrep(rivalTableContext: v),
                  onRivalStyle: (v) => _updateMatchPrep(rivalStyle: v),
                  onSquadProfile: (v) => _updateMatchPrep(squadProfile: v),
                  onRivalMemory: (v) => _updateMatchPrep(rivalMemory: v),
                  onRivalDangerPlayers: (v) =>
                      _updateMatchPrep(rivalDangerPlayers: v),
                  onPreviousMatchNotes: (v) =>
                      _updateMatchPrep(previousMatchNotes: v),
                  onFixtureRefresh: () => _loadFixture(category, force: true),
                  onUseFixture: _applyFixtureMatch,
                  generating: _generatingTactic,
                  onGenerateTactic: () => _generateTactic(club, category),
                ),
                if (_tacticError != null) ...[
                  const SizedBox(height: 10),
                  _GenerationFeedback(message: _tacticError!),
                ],
                if (_generatedTactic != null && !_generatingTactic) ...[
                  const SizedBox(height: 18),
                  _SectionTitle('Plan de partido'),
                  const SizedBox(height: 10),
                  _GeneratedSessionCard(
                    session: _generatedTactic!,
                    clubName: club.name,
                    categoryName: category.name,
                  ),
                ],
                const SizedBox(height: 16),
                _SectionTitle('Preparar entrenamiento'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ExerciseLibraryScreen(
                            initialCategoryId: category.id,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.auto_awesome_motion_outlined, size: 17),
                      label: const Text('Biblioteca de ejercicios'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SessionBuilderScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.view_agenda_outlined, size: 17),
                      label: const Text('Armar sesión a mano'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _GeneratorForm(
                  objective: _objective,
                  problem: _problem,
                  space: _space,
                  duration: _duration,
                  players: _players,
                  suggestedPlayers: availablePlayers,
                  scheduledDate: _sessionDate,
                  automaticSquadContext: suggestedSquadProfile
                      .trim()
                      .isNotEmpty,
                  canGenerate: canGenerate,
                  onScheduledDate: (date) =>
                      _updateSessionPrep(sessionDate: date),
                  onObjective: (v) => _updateSessionPrep(objective: v),
                  onProblem: (v) => _updateSessionPrep(problem: v),
                  onSpace: (v) => _updateSessionPrep(space: v),
                  onDuration: (v) => _updateSessionPrep(duration: v),
                  onPlayers: (v) => _updateSessionPrep(players: v),
                  generating: _generating,
                  onGenerate: () => _generateSession(club, category),
                ),
                if (_sessionError != null) ...[
                  const SizedBox(height: 10),
                  _GenerationFeedback(message: _sessionError!),
                ],
                if (_generating) ...[
                  const SizedBox(height: 18),
                  const _ThinkingCard(),
                ],
                if (_generatedSession != null && !_generating) ...[
                  const SizedBox(height: 18),
                  _SectionTitle('Sesión generada'),
                  const SizedBox(height: 10),
                  _GeneratedSessionCard(
                    session: _generatedSession!,
                    clubName: club.name,
                    categoryName: category.name,
                  ),
                ],
                const SizedBox(height: 18),
                _SectionTitle('Registro rapido post-entreno'),
                const SizedBox(height: 10),
                _TranscriptCard(
                  controller: _transcriptController,
                  category: category,
                  totalPlayers: category.playerCount > 0
                      ? category.playerCount
                      : categoryPlayers.length,
                  onSave: (report) => _saveTrainingReport(club, report),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  String _buildSquadProfile(CategorySquad category, List<Player> players) {
    final notes = players
        .where((player) => player.note.trim().isNotEmpty)
        .take(5)
        .map((player) => '${player.fullName.trim()}: ${player.note.trim()}')
        .toList();
    final positions = players
        .where((player) => player.position.trim().isNotEmpty)
        .map((player) => player.position.trim())
        .toSet()
        .take(6)
        .join(', ');
    final trends = players
        .where((player) => player.trend.trim().isNotEmpty)
        .take(4)
        .map((player) => '${player.fullName.trim()} (${player.trend.trim()})')
        .toList();
    return [
      if (category.currentFocus.trim().isNotEmpty)
        'Foco actual: ${category.currentFocus.trim()}',
      if (category.playerCount > 0)
        'Cantidad registrada: ${category.playerCount}',
      if (positions.isNotEmpty) 'Posiciones cargadas: $positions',
      if (notes.isNotEmpty) 'Notas: ${notes.map(_cleanStaffNote).join('; ')}',
      if (trends.isNotEmpty) 'Tendencias de la liga: ${trends.join('; ')}',
      if (players.where(_isAvailable).length != players.length)
        'Disponibles: ${players.where(_isAvailable).length} de ${players.length}',
    ].join('\n');
  }

  String _effectiveSquadProfile({
    required String manual,
    required String automatic,
  }) {
    final manualText = manual.trim();
    final automaticText = automatic.trim();
    if (manualText.isEmpty) return automaticText;
    if (automaticText.isEmpty) return manualText;
    return [
      'Lectura del entrenador:',
      manualText,
      'Contexto de fobal:',
      automaticText,
    ].join('\n');
  }

  String _cleanStaffNote(String value) {
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
        .replaceAll(RegExp(r'\s*;\s*;'), ';')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  void _selectCategory(String? value) {
    if (value == _selectedCategoryId) return;
    AppScope.of(context).selectCategory(value);
    _rememberFixtureState(_selectedCategoryId);
    final nextKey = _fixtureMemoryKey(value);
    final remembered = _fixtureMemoryByCategory[nextKey];
    setState(() {
      _selectedCategoryId = value;
      _fixtureKey = remembered == null ? null : nextKey;
      _fixtureMatches = remembered?.matches ?? const [];
      _fixtureContext = remembered?.fixtureContext ?? '';
      _fixtureError = remembered?.error;
      _fixtureLoading = false;
      _rivalName = remembered?.rivalName ?? '';
      _rivalTableContext = remembered?.rivalTableContext ?? '';
      _rivalStyle = remembered?.rivalStyle ?? '';
      _squadProfile = remembered?.squadProfile ?? '';
      _rivalMemory = remembered?.rivalMemory ?? '';
      _rivalDangerPlayers = remembered?.rivalDangerPlayers ?? '';
      _previousMatchNotes = remembered?.previousMatchNotes ?? '';
      _objective = remembered?.objective ?? '';
      _problem = remembered?.problem ?? '';
      _space = remembered?.space ?? '';
      _duration = remembered?.duration ?? 75;
      _players = remembered?.players ?? 18;
      _sessionDate =
          remembered?.sessionDate ??
          DateTime.now().add(const Duration(days: 1));
      _matchDate =
          remembered?.matchDate ?? DateTime.now().add(const Duration(days: 7));
      _generatedTactic = null;
      _tacticError = null;
    });
    final scope = AppScope.of(context);
    final category = scope.fullClub.categories
        .cast<CategorySquad?>()
        .firstWhere((item) => item?.id == value, orElse: () => null);
    if (category != null) {
      _fixtureKey = '${scope.fullClub.id}|${category.id}';
      Future.microtask(() => _loadFixture(category, force: true));
    }
  }

  String _fixtureMemoryKey(String? categoryId) {
    if (categoryId == null || categoryId.isEmpty) return '';
    return '${AppScope.of(context).fullClub.id}|$categoryId';
  }

  void _rememberFixtureState(String? categoryId) {
    final key = _fixtureMemoryKey(categoryId);
    if (key.isEmpty) return;
    _fixtureMemoryByCategory[key] = _FixtureMemory(
      matches: _fixtureMatches,
      error: _fixtureError,
      fixtureContext: _fixtureContext,
      rivalName: _rivalName,
      rivalTableContext: _rivalTableContext,
      rivalStyle: _rivalStyle,
      squadProfile: _squadProfile,
      rivalMemory: _rivalMemory,
      rivalDangerPlayers: _rivalDangerPlayers,
      previousMatchNotes: _previousMatchNotes,
      objective: _objective,
      problem: _problem,
      space: _space,
      duration: _duration,
      players: _players,
      sessionDate: _sessionDate,
      matchDate: _matchDate,
    );
    _saveLocalDraft(categoryId);
  }

  void _hydrateLocalDraft(CategorySquad category) {
    final key = _fixtureMemoryKey(category.id);
    if (key.isEmpty || _draftHydratedKeys.contains(key)) return;
    _draftHydratedKeys.add(key);
    final raw = html.window.localStorage[_draftStorageKey(key)];
    if (raw == null || raw.isEmpty) return;
    try {
      final draft = _FixtureMemory.fromDraftJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      _fixtureMemoryByCategory[key] = draft;
      if (_fixtureMemoryKey(_selectedCategoryId) == key &&
          _fixtureContext.trim().isEmpty &&
          _rivalName.trim().isEmpty &&
          _rivalStyle.trim().isEmpty &&
          _squadProfile.trim().isEmpty &&
          _rivalMemory.trim().isEmpty &&
          _rivalDangerPlayers.trim().isEmpty &&
          _previousMatchNotes.trim().isEmpty &&
          _objective.trim().isEmpty &&
          _problem.trim().isEmpty &&
          _space.trim().isEmpty) {
        _fixtureContext = draft.fixtureContext;
        _rivalName = draft.rivalName;
        _rivalTableContext = draft.rivalTableContext;
        _rivalStyle = draft.rivalStyle;
        _squadProfile = draft.squadProfile;
        _rivalMemory = draft.rivalMemory;
        _rivalDangerPlayers = draft.rivalDangerPlayers;
        _previousMatchNotes = draft.previousMatchNotes;
        _objective = draft.objective;
        _problem = draft.problem;
        _space = draft.space;
        _duration = draft.duration;
        _players = draft.players;
        _sessionDate = draft.sessionDate;
        _matchDate = draft.matchDate;
        if (draft.fixtureContext.trim().isNotEmpty) {
          _fixtureKey = key;
        }
      }
    } catch (_) {
      html.window.localStorage.remove(_draftStorageKey(key));
    }
  }

  void _saveLocalDraft(String? categoryId) {
    final key = _fixtureMemoryKey(categoryId);
    if (key.isEmpty) return;
    final memory = _fixtureMemoryByCategory[key];
    if (memory == null || !memory.hasDraftContent) {
      html.window.localStorage.remove(_draftStorageKey(key));
      return;
    }
    html.window.localStorage[_draftStorageKey(key)] = jsonEncode(
      memory.toDraftJson(),
    );
  }

  String _draftStorageKey(String key) => 'cantera_os_tactical_draft_$key';

  void _markDraftResolved(String? categoryId) {
    final key = _fixtureMemoryKey(categoryId);
    if (key.isEmpty) return;
    html.window.localStorage.remove(_draftStorageKey(key));
    _fixtureMemoryByCategory.remove(key);
  }

  void _updateMatchPrep({
    String? rivalName,
    String? rivalTableContext,
    String? rivalStyle,
    String? squadProfile,
    String? rivalMemory,
    String? rivalDangerPlayers,
    String? previousMatchNotes,
    DateTime? matchDate,
  }) {
    setState(() {
      if (rivalName != null) _rivalName = rivalName;
      if (rivalTableContext != null) _rivalTableContext = rivalTableContext;
      if (rivalStyle != null) _rivalStyle = rivalStyle;
      if (squadProfile != null) _squadProfile = squadProfile;
      if (rivalMemory != null) _rivalMemory = rivalMemory;
      if (rivalDangerPlayers != null) {
        _rivalDangerPlayers = rivalDangerPlayers;
      }
      if (previousMatchNotes != null) {
        _previousMatchNotes = previousMatchNotes;
      }
      if (matchDate != null) _matchDate = matchDate;
    });
    _rememberFixtureState(_selectedCategoryId);
  }

  void _updateSessionPrep({
    String? objective,
    String? problem,
    String? space,
    int? duration,
    int? players,
    DateTime? sessionDate,
  }) {
    setState(() {
      if (objective != null) _objective = objective;
      if (problem != null) _problem = problem;
      if (space != null) _space = space;
      if (duration != null) _duration = duration;
      if (players != null) _players = players;
      if (sessionDate != null) _sessionDate = sessionDate;
    });
    _rememberFixtureState(_selectedCategoryId);
  }

  String _fixtureContextFor(CategorySquad category) {
    final expectedKey = '${AppScope.of(context).fullClub.id}|${category.id}';
    if (_fixtureKey != expectedKey) return '';
    return _fixtureContext;
  }

  void _ensureFixtureLoaded(CategorySquad category) {
    final scope = AppScope.of(context);
    final key = '${scope.fullClub.id}|${category.id}';
    if ((_fixtureKey == key &&
            (_fixtureMatches.isNotEmpty || _fixtureLoading)) ||
        category.id == 'categoria-demo') {
      return;
    }
    _fixtureKey = key;
    Future.microtask(() => _loadFixture(category));
  }

  Future<void> _loadFixture(
    CategorySquad category, {
    bool force = false,
  }) async {
    if (_fixtureLoading && !force) return;
    final scope = AppScope.of(context);
    final club = scope.fullClub;
    final requestKey = '${club.id}|${category.id}';
    final activeMembership = await ClubAccessService.activeMembership();
    final categoryTeamId =
        _ludTeamIdFromCategory(category.id) ?? _ludTeamIdFromLeague(club.league);
    final membership =
        activeMembership != null && activeMembership.clubId == club.id
            ? activeMembership
            : null;
    if (!mounted || _fixtureKey != requestKey) return;
    final effectiveMembership = membership ??
        ClubMembership(
          clubId: club.id,
          clubName: club.name,
          ludTeamId: categoryTeamId?.toString(),
          role: 'coach',
          status: 'active',
          categoryIds: [category.id],
        );
    if (effectiveMembership.ludTeamId == null) {
      setState(() {
        _fixtureMatches = const [];
        _fixtureError = null;
        _fixtureLoading = false;
      });
      _rememberFixtureState(category.id);
      return;
    }

    setState(() {
      _fixtureLoading = true;
      _fixtureError = null;
    });

    try {
      final matches = await ClubAccessService.loadFixture(
        membership: effectiveMembership,
        category: category,
        forceRefresh: force,
      );
      if (!mounted || _fixtureKey != requestKey) return;
      setState(() {
        _fixtureMatches = matches;
        _fixtureLoading = false;
        _fixtureError = matches.isEmpty
            ? 'No hay próximos partidos publicados para ${category.name}. No se usarán rivales de otra categoría.'
            : null;
      });
      _rememberFixtureState(category.id);
      LudFixtureMatch? nextMatch;
      for (final match in matches) {
        if (match.isUpcoming) {
          nextMatch = match;
          break;
        }
      }
      if (nextMatch != null &&
          (_rivalName.trim().isEmpty ||
              _fixtureContext.trim().isEmpty ||
              force)) {
        _applyFixtureMatch(nextMatch, forceOpponent: force);
      }
    } on ClubContextLoadException catch (_) {
      if (!mounted || _fixtureKey != requestKey) return;
      setState(() {
        _fixtureLoading = false;
        _fixtureError = 'No pudimos cargar el fixture. Probá actualizar.';
      });
      _rememberFixtureState(category.id);
    } catch (_) {
      if (!mounted || _fixtureKey != requestKey) return;
      setState(() {
        _fixtureLoading = false;
        _fixtureError = 'No pudimos cargar el fixture. Probá actualizar.';
      });
      _rememberFixtureState(category.id);
    }
  }

  void _applyFixtureMatch(LudFixtureMatch match, {bool forceOpponent = false}) {
    setState(() {
      _matchDate = match.date;
      _rivalName = match.opponentName;
      _rivalTableContext = match.tacticalContext;
      _fixtureContext = '${match.dateLabel} / ${match.tacticalContext}';
      if (_rivalStyle.trim().isEmpty ||
          _rivalStyle.trim() == _fixtureStylePlaceholder) {
        _rivalStyle = _fixtureStylePlaceholder;
      }
    });
    _rememberFixtureState(_selectedCategoryId);
    Future.microtask(() => _loadOpponentAnalysis(match, force: forceOpponent));
  }

  Future<void> _loadOpponentAnalysis(
    LudFixtureMatch match, {
    bool force = false,
  }) async {
    final scope = AppScope.of(context);
    CategorySquad? category;
    for (final item in scope.fullClub.categories) {
      if (item.id == _selectedCategoryId) {
        category = item;
        break;
      }
    }
    if (category == null || match.opponentTeamId == null) return;
    setState(() {
      _opponentLoading = true;
      _opponentError = null;
    });
    try {
      final analysis = await ClubAccessService.loadOpponentAnalysis(
        match: match,
        category: category,
        forceRefresh: force,
      );
      if (!mounted) return;
      if (analysis == null || _rivalName != match.opponentName) {
        setState(() => _opponentLoading = false);
        return;
      }
      setState(() {
        _rivalTableContext = analysis.tableContext;
        _rivalStyle = analysis.styleSummary;
        _rivalDangerPlayers = analysis.dangerPlayers;
        _rivalMemory = analysis.memorySummary;
        _opponentLoading = false;
      });
      _rememberFixtureState(category.id);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _opponentLoading = false;
        _opponentError =
            'Se cargó el rival, pero sus estadísticas no están disponibles ahora.';
      });
    }
  }

  bool _hasManualRivalStyle(String value) =>
      _ScoutingQuality.fromText(_cleanRivalStyle(value)).ready;

  String _cleanRivalStyle(String value) =>
      value.trim() == _fixtureStylePlaceholder ? '' : value.trim();

  bool _isAvailable(Player player) {
    final status = player.status.toLowerCase();
    return !status.contains('lesion') &&
        !status.contains('baja') &&
        !status.contains('suspend');
  }

  String _isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  int? _ludTeamIdFromLeague(String league) {
    final match = RegExp(
      r'LUD\s+(\d+)',
      caseSensitive: false,
    ).firstMatch(league);
    return int.tryParse(match?.group(1) ?? '');
  }

  int? _ludTeamIdFromCategory(String categoryId) =>
      LudCategoryRef.teamIdOf(categoryId);

  Future<void> _saveTrainingReport(
    CanteraClub club,
    TrainingReport report,
  ) async {
    final reports = [
      report,
      ...club.trainingReports.where(
        (item) =>
            item.categoryId != report.categoryId || item.date != report.date,
      ),
    ];
    AppScope.of(context).updateClub(club.copyWith(trainingReports: reports));
    final writeResult =
        await OfflineMutationService.instance.saveTacticalDataOfflineFirst(
      type: 'staff_note',
      title: 'Post-entreno ${report.date}',
      content: report.toJson(),
      relatedLudTeamId: _ludTeamIdFromLeague(club.league),
      categoryId: report.categoryId,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          writeResult.synced
              ? 'Registro guardado para el club.'
              : 'Registro agregado. Se guardará cuando vuelva la conexión.',
        ),
      ),
    );
  }

}

class _TacticalHistory extends StatefulWidget {
  final Future<List<ClubTacticalRecord>> future;
  final List<CategorySquad> categories;
  final VoidCallback onRefresh;
  final ValueChanged<ClubTacticalRecord> onOpen;

  const _TacticalHistory({
    required this.future,
    required this.categories,
    required this.onRefresh,
    required this.onOpen,
  });

  @override
  State<_TacticalHistory> createState() => _TacticalHistoryState();
}

class _TacticalHistoryState extends State<_TacticalHistory> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ClubTacticalRecord>>(
      future: widget.future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LinearProgressIndicator(minHeight: 2);
        }
        final visibleCategoryIds = widget.categories
            .map((item) => item.id)
            .toSet();
        final records = (snapshot.data ?? const <ClubTacticalRecord>[]).where((
          record,
        ) {
          final categoryId = record.content['categoryId']?.toString() ?? '';
          final title = record.title.toLowerCase();
          return visibleCategoryIds.contains(categoryId) &&
              !title.contains('seminario');
        }).toList();
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: CX.panel,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: CX.line),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      const Icon(Icons.history, color: CX.green, size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Actividad reciente del club',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Actualizar actividad',
                        onPressed: widget.onRefresh,
                        icon: const Icon(Icons.refresh, size: 20),
                      ),
                      AnimatedRotation(
                        turns: _expanded ? .25 : 0,
                        duration: CX.motion,
                        curve: CX.curve,
                        child: const Icon(Icons.chevron_right, color: CX.muted),
                      ),
                    ],
                  ),
                ),
              ),
              if (_expanded) ...[
                const SizedBox(height: 8),
                if (snapshot.hasError)
                  const Text(
                    'No se pudo consultar el historial del club. La planificacion local sigue disponible.',
                    style: TextStyle(color: CX.muted, fontSize: 12),
                  )
                else if (records.isEmpty)
                  const Text(
                    'Todavía no hay sesiones, planes ni registros compartidos para este club.',
                    style: TextStyle(color: CX.muted, fontSize: 12),
                  )
                else ...[
                  _HistoryHealthStrip(records: records),
                  const SizedBox(height: 10),
                  ...records
                      .take(5)
                      .map(
                        (record) => _HistoryTile(
                          record,
                          categoryName: _categoryName(record),
                          onOpen: () => widget.onOpen(record),
                        ),
                      ),
                ],
              ],
            ],
          ),
          ),
        );
      },
    );
  }

  String _categoryName(ClubTacticalRecord record) {
    final categoryId = record.content['categoryId']?.toString() ?? '';
    for (final category in widget.categories) {
      if (category.id == categoryId) return category.name;
    }
    return '';
  }
}

class _HistoryHealthStrip extends StatelessWidget {
  final List<ClubTacticalRecord> records;

  const _HistoryHealthStrip({required this.records});

  @override
  Widget build(BuildContext context) {
    final sessions = records.where((record) => record.type == 'session').length;
    final plans = records.where((record) => record.type == 'match_plan').length;
    final notes = records.where((record) => record.type == 'staff_note').length;
    final own = records.where((record) => record.createdByCurrentUser).length;
    final last = records
        .where((record) => record.createdAt != null)
        .map((record) => record.createdAt!)
        .fold<DateTime?>(null, (latest, date) {
          if (latest == null || date.isAfter(latest)) return date;
          return latest;
        });
    final hasContinuity = sessions > 0 && notes > 0;
    final color = hasContinuity ? CX.green : CX.amber;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: .22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_done_outlined, color: color, size: 17),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hasContinuity
                      ? 'Historial compartido con continuidad'
                      : 'Historial compartido por completar',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _HistoryMetric('$sessions sesiones'),
              _HistoryMetric('$plans planes'),
              _HistoryMetric('$notes registros'),
              _HistoryMetric('$own tuyos'),
              if (last != null) _HistoryMetric('Ultimo ${_dateLabel(last)}'),
            ],
          ),
        ],
      ),
    );
  }

  String _dateLabel(DateTime value) {
    final date = value.toLocal();
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
  }
}

class _HistoryMetric extends StatelessWidget {
  final String label;

  const _HistoryMetric(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: CX.panel2.withValues(alpha: .7),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: CX.line),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final ClubTacticalRecord record;
  final String categoryName;
  final VoidCallback onOpen;

  const _HistoryTile(
    this.record, {
    required this.categoryName,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final objective = record.content['objective']?.toString().trim() ?? '';
    final quality = _qualityLabel;
    final date = record.createdAt?.toLocal();
    final dateLabel = date == null
        ? ''
        : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      onTap: onOpen,
      leading: Icon(_icon, color: CX.green, size: 20),
      title: Text(record.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          _label,
          if (categoryName.isNotEmpty) categoryName,
          if (objective.isNotEmpty) objective,
          if (quality.isNotEmpty) quality,
          dateLabel,
          if (record.createdByCurrentUser) 'Creado por vos',
        ].where((item) => item.isNotEmpty).join(' / '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: CX.muted, fontSize: 11),
      ),
      trailing: const Icon(Icons.chevron_right, color: CX.faint, size: 20),
    );
  }

  String get _label => switch (record.type) {
    'session' => 'Sesión',
    'match_plan' => 'Plan de partido',
    'rival_report' => 'Informe de rival',
    'staff_note' => 'Registro tecnico',
    _ => 'Actividad',
  };

  String get _qualityLabel {
    if (record.type == 'session' || record.type == 'match_plan') {
      final session = TrainingSession.fromJson(record.content);
      return '${session.operationalReadinessScore}% operativo';
    }
    if (record.type == 'staff_note') {
      final report = TrainingReport.fromJson(record.content);
      final prompts = [
        report.objectiveWorked,
        report.whatWentWell,
        report.whatWentWrong,
        report.nextRecommendation,
      ].where((item) => item.trim().isNotEmpty).length;
      return '$prompts campos tecnicos';
    }
    return '';
  }

  IconData get _icon => switch (record.type) {
    'session' => Icons.fitness_center,
    'match_plan' => Icons.sports_soccer,
    'rival_report' => Icons.analytics_outlined,
    'staff_note' => Icons.assignment_outlined,
    _ => Icons.description_outlined,
  };
}

class _MatchPrepForm extends StatefulWidget {
  final String rivalName;
  final String rivalTableContext;
  final String rivalStyle;
  final String squadProfile;
  final String rivalMemory;
  final String rivalDangerPlayers;
  final String previousMatchNotes;
  final String suggestedSquadProfile;
  final String effectiveSquadProfile;
  final DateTime matchDate;
  final bool fixtureLoading;
  final String? fixtureError;
  final bool opponentLoading;
  final String? opponentError;
  final List<LudFixtureMatch> fixtureMatches;
  final String fixtureContext;
  final String categoryName;
  final bool canGenerate;
  final ValueChanged<String> onRivalName;
  final ValueChanged<String> onRivalTableContext;
  final ValueChanged<String> onRivalStyle;
  final ValueChanged<String> onSquadProfile;
  final ValueChanged<String> onRivalMemory;
  final ValueChanged<String> onRivalDangerPlayers;
  final ValueChanged<String> onPreviousMatchNotes;
  final ValueChanged<DateTime> onMatchDate;
  final VoidCallback onFixtureRefresh;
  final ValueChanged<LudFixtureMatch> onUseFixture;
  final bool generating;
  final VoidCallback onGenerateTactic;

  const _MatchPrepForm({
    required this.rivalName,
    required this.rivalTableContext,
    required this.rivalStyle,
    required this.squadProfile,
    required this.rivalMemory,
    required this.rivalDangerPlayers,
    required this.previousMatchNotes,
    required this.suggestedSquadProfile,
    required this.effectiveSquadProfile,
    required this.matchDate,
    required this.fixtureLoading,
    required this.fixtureError,
    required this.opponentLoading,
    required this.opponentError,
    required this.fixtureMatches,
    required this.fixtureContext,
    required this.categoryName,
    required this.canGenerate,
    required this.onRivalName,
    required this.onRivalTableContext,
    required this.onRivalStyle,
    required this.onSquadProfile,
    required this.onRivalMemory,
    required this.onRivalDangerPlayers,
    required this.onPreviousMatchNotes,
    required this.onMatchDate,
    required this.onFixtureRefresh,
    required this.onUseFixture,
    required this.generating,
    required this.onGenerateTactic,
  });

  @override
  State<_MatchPrepForm> createState() => _MatchPrepFormState();
}

class _MatchPrepFormState extends State<_MatchPrepForm> {
  late final TextEditingController _rivalNameController;
  late final TextEditingController _tableContextController;
  late final TextEditingController _rivalStyleController;
  late final TextEditingController _squadProfileController;
  late final TextEditingController _rivalMemoryController;
  late final TextEditingController _rivalDangerPlayersController;
  late final TextEditingController _previousMatchNotesController;

  @override
  void initState() {
    super.initState();
    _rivalNameController = TextEditingController(text: widget.rivalName);
    _tableContextController = TextEditingController(
      text: widget.rivalTableContext,
    );
    _rivalStyleController = TextEditingController(text: widget.rivalStyle);
    _squadProfileController = TextEditingController(text: widget.squadProfile);
    _rivalMemoryController = TextEditingController(text: widget.rivalMemory);
    _rivalDangerPlayersController = TextEditingController(
      text: widget.rivalDangerPlayers,
    );
    _previousMatchNotesController = TextEditingController(
      text: widget.previousMatchNotes,
    );
  }

  @override
  void didUpdateWidget(covariant _MatchPrepForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncController(_rivalNameController, widget.rivalName);
    _syncController(_tableContextController, widget.rivalTableContext);
    _syncController(_rivalStyleController, widget.rivalStyle);
    _syncController(_squadProfileController, widget.squadProfile);
    _syncController(_rivalMemoryController, widget.rivalMemory);
    _syncController(_rivalDangerPlayersController, widget.rivalDangerPlayers);
    _syncController(_previousMatchNotesController, widget.previousMatchNotes);
  }

  @override
  void dispose() {
    _rivalNameController.dispose();
    _tableContextController.dispose();
    _rivalStyleController.dispose();
    _squadProfileController.dispose();
    _rivalMemoryController.dispose();
    _rivalDangerPlayersController.dispose();
    _previousMatchNotesController.dispose();
    super.dispose();
  }

  void _syncController(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final readiness = _MatchReadiness.fromValues(
      fixtureContext: widget.fixtureContext,
      rivalName: widget.rivalName,
      rivalStyle: widget.rivalStyle,
      squadProfile: widget.effectiveSquadProfile,
    );
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: CX.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CX.line),
      ),
      child: Column(
        children: [
          const SizedBox(height: 2),
          _PlanningDateField(
            label: 'Fecha del partido',
            date: widget.matchDate,
            onChanged: widget.onMatchDate,
          ),
          const SizedBox(height: 10),
          _FixturePanel(
            loading: widget.fixtureLoading,
            error: widget.fixtureError,
            matches: widget.fixtureMatches,
            selectedContext: widget.fixtureContext,
            categoryName: widget.categoryName,
            onRefresh: widget.onFixtureRefresh,
            onUse: widget.onUseFixture,
          ),
          if (widget.opponentLoading || widget.opponentError != null) ...[
            const SizedBox(height: 10),
            _AutopilotNotice(
              title: widget.opponentLoading
                  ? 'Analizando al rival'
                  : 'Datos parciales del rival',
              message: widget.opponentLoading
                  ? 'Completando tabla, forma reciente, jugadores, goles y minutos.'
                  : widget.opponentError!,
            ),
          ],
          const SizedBox(height: 10),
          TextFormField(
            controller: _rivalNameController,
            decoration: const InputDecoration(labelText: 'Nombre del rival'),
            onChanged: widget.onRivalName,
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _tableContextController,
            decoration: const InputDecoration(
              labelText: 'Como viene en la tabla o momento actual',
              hintText:
                  'Ej: tercero, cuatro triunfos seguidos, recibe pocos goles',
            ),
            onChanged: widget.onRivalTableContext,
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _rivalStyleController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Como juega: fortalezas y debilidades',
              hintText:
                  'Sistema, salida, presion, zonas fuertes y espacios que concede',
              alignLabelWithHint: true,
            ),
            onChanged: widget.onRivalStyle,
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _rivalMemoryController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Memoria del rival',
              hintText:
                  'Ej: en la ida sufrimos al 4 en el juego aereo; nos costaron sus cambios de frente',
              alignLabelWithHint: true,
            ),
            onChanged: widget.onRivalMemory,
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _rivalDangerPlayersController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Jugadores o patrones rivales a vigilar',
              hintText:
                  'Ej: el 11 ataca espalda del lateral; el 9 descarga bien de espaldas',
              alignLabelWithHint: true,
            ),
            onChanged: widget.onRivalDangerPlayers,
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _previousMatchNotesController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Notas del ultimo cruce o partido observado',
              hintText:
                  'Que funciono, que fallo, como fue el partido y que no queres repetir',
              alignLabelWithHint: true,
            ),
            onChanged: widget.onPreviousMatchNotes,
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _squadProfileController,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Caracteristicas individuales y grupales del plantel',
              hintText:
                  'Virtudes, limitaciones, jugadores clave, velocidad, juego aereo y perfiles',
              alignLabelWithHint: true,
            ),
            onChanged: widget.onSquadProfile,
          ),
          if (widget.suggestedSquadProfile.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            _ContextSuggestion(
              title: 'Contexto del plantel',
              text: widget.suggestedSquadProfile,
              onUse: () => widget.onSquadProfile(widget.suggestedSquadProfile),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed:
                  widget.generating || !widget.canGenerate || !readiness.ready
                  ? null
                  : widget.onGenerateTactic,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: widget.generating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Icon(Icons.sports_soccer),
              label: Text(
                widget.generating
                    ? 'Pensando la táctica…'
                    : 'Generar táctica de partido',
              ),
            ),
          ),
          if (!widget.canGenerate) ...[
            const SizedBox(height: 9),
            const _ReadOnlyNotice(),
          ] else if (!readiness.ready) ...[
            const SizedBox(height: 9),
            _GenerationFeedback(message: readiness.nextAction),
          ],
        ],
      ),
    );
  }
}

class _MatchReadiness {
  final bool hasFixtureOrDate;
  final bool hasRival;
  final bool hasRivalStyle;
  final bool hasSquadProfile;
  final _ScoutingQuality scouting;

  const _MatchReadiness({
    required this.hasFixtureOrDate,
    required this.hasRival,
    required this.hasRivalStyle,
    required this.hasSquadProfile,
    required this.scouting,
  });

  factory _MatchReadiness.fromValues({
    required String fixtureContext,
    required String rivalName,
    required String rivalStyle,
    required String squadProfile,
  }) {
    final cleanStyle = rivalStyle.trim() == _fixtureStylePlaceholder
        ? ''
        : rivalStyle.trim();
    final scouting = _ScoutingQuality.fromText(cleanStyle);
    return _MatchReadiness(
      hasFixtureOrDate: fixtureContext.trim().isNotEmpty,
      hasRival: rivalName.trim().length >= 3,
      hasRivalStyle: scouting.ready,
      hasSquadProfile: squadProfile.trim().length >= 18,
      scouting: scouting,
    );
  }

  int get completed => [
    hasFixtureOrDate,
    hasRival,
    hasRivalStyle,
    hasSquadProfile,
  ].where((item) => item).length;

  bool get ready => hasRival && hasRivalStyle && hasSquadProfile;

  double get progress => completed / 4;

  String get nextAction {
    if (!hasRival) return 'Elegi un partido de la liga o escribi el rival.';
    if (DateTime.now().year < 0 && !hasRivalStyle) {
      return 'Agrega como juega el rival: sistema, presion, salida, fortalezas y espacios que concede.';
    }
    if (!hasRivalStyle) return scouting.nextAction;
    if (!hasSquadProfile) {
      return 'Usá el contexto automático del plantel o describí virtudes, limitaciones y jugadores clave.';
    }
    return 'Listo para generar una táctica trazable.';
  }
}

class _ScoutingQuality {
  final bool hasSystem;
  final bool hasPressing;
  final bool hasBuildUp;
  final bool hasStrength;
  final bool hasWeakness;

  const _ScoutingQuality({
    required this.hasSystem,
    required this.hasPressing,
    required this.hasBuildUp,
    required this.hasStrength,
    required this.hasWeakness,
  });

  factory _ScoutingQuality.fromText(String value) {
    final text = _normalize(value);
    bool hasAny(List<String> words) => words.any(text.contains);
    return _ScoutingQuality(
      hasSystem:
          RegExp(r'\b[1-5]-[1-5]-[1-5]\b').hasMatch(text) ||
          hasAny(['sistema', 'linea de ', 'formacion', 'estructura']),
      hasPressing: hasAny([
        'presion',
        'presiona',
        'bloque',
        'marca',
        'aprieta',
      ]),
      hasBuildUp: hasAny(['salida', 'inicia', 'construye', 'primer pase']),
      hasStrength: hasAny(['fuerte', 'fortaleza', 'peligro', 'amenaza']),
      hasWeakness: hasAny([
        'debil',
        'debilidad',
        'espacio',
        'concede',
        'sufre',
        'pierde',
      ]),
    );
  }

  int get completed => [
    hasSystem,
    hasPressing,
    hasBuildUp,
    hasStrength,
    hasWeakness,
  ].where((item) => item).length;

  bool get ready => completed >= 3 && hasWeakness;

  String get nextAction {
    if (!hasWeakness) {
      return 'Agregá una debilidad o un espacio que concede el rival; sin eso la táctica queda demasiado genérica.';
    }
    if (!hasSystem) return 'Agrega sistema o estructura del rival.';
    if (!hasPressing) return 'Agrega como presiona o en que bloque defiende.';
    if (!hasBuildUp) return 'Agrega como inicia o progresa desde el fondo.';
    if (!hasStrength) return 'Agrega una fortaleza o amenaza principal.';
    return 'Datos suficientes para una táctica útil.';
  }

  static String _normalize(String value) {
    const replacements = {
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'Á': 'a',
      'É': 'e',
      'Í': 'i',
      'Ó': 'o',
      'Ú': 'u',
    };
    var text = value.toLowerCase();
    for (final entry in replacements.entries) {
      text = text.replaceAll(entry.key, entry.value);
    }
    return text;
  }
}

class _AutopilotNotice extends StatelessWidget {
  final String title;
  final String message;

  const _AutopilotNotice({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: CX.motion,
      curve: CX.curve,
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: CX.blue.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CX.blue.withValues(alpha: .2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.hub_outlined, color: CX.blue, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(
                    color: CX.muted,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FixturePanel extends StatelessWidget {
  final bool loading;
  final String? error;
  final List<LudFixtureMatch> matches;
  final String selectedContext;
  final String categoryName;
  final VoidCallback onRefresh;
  final ValueChanged<LudFixtureMatch> onUse;

  const _FixturePanel({
    required this.loading,
    required this.error,
    required this.matches,
    required this.selectedContext,
    required this.categoryName,
    required this.onRefresh,
    required this.onUse,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CX.panel2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CX.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                matches.isNotEmpty
                    ? Icons.event_available_outlined
                    : Icons.event_busy_outlined,
                color: matches.isNotEmpty ? CX.green : CX.amber,
                size: 19,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Fixture de la categoría',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              _FixtureScopePill(
                label: categoryName,
                ready: matches.isNotEmpty || selectedContext.trim().isNotEmpty,
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Actualizar fixture',
                onPressed: loading ? null : onRefresh,
                icon: loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 19),
              ),
            ],
          ),
          if (selectedContext.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              selectedContext,
              style: const TextStyle(color: CX.green, fontSize: 12),
            ),
          ],
          if (error != null && matches.isEmpty) ...[
            const SizedBox(height: 6),
            Text(error!, style: const TextStyle(color: CX.muted, fontSize: 12)),
          ],
          if (matches.isNotEmpty) ...[
            const SizedBox(height: 8),
            _FixtureQualityNotice(match: matches.first),
            const SizedBox(height: 8),
            ...matches
                .take(4)
                .map(
                  (match) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: OutlinedButton(
                      onPressed: match.isUpcoming ? () => onUse(match) : null,
                      child: Row(
                        children: [
                          Icon(
                            match.isUpcoming
                                ? Icons.sports_soccer
                                : Icons.history,
                            size: 17,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${match.isUpcoming ? match.dateLabel : 'Jugado ${match.dateLabel}'} vs ${match.opponentName}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (match.fixtureDetail.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    match.fixtureDetail,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: CX.faint,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

class _FixtureQualityNotice extends StatelessWidget {
  final LudFixtureMatch match;

  const _FixtureQualityNotice({required this.match});

  @override
  Widget build(BuildContext context) {
    final color = match.categoryVerified ? CX.green : CX.amber;
    final icon = match.categoryVerified
        ? Icons.verified_outlined
        : Icons.warning_amber_outlined;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: .22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  match.fixtureTrustLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  match.fixtureTrustDetail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: CX.muted,
                    fontSize: 10,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FixtureMemory {
  final List<LudFixtureMatch> matches;
  final String? error;
  final String fixtureContext;
  final String rivalName;
  final String rivalTableContext;
  final String rivalStyle;
  final String squadProfile;
  final String rivalMemory;
  final String rivalDangerPlayers;
  final String previousMatchNotes;
  final String objective;
  final String problem;
  final String space;
  final int duration;
  final int players;
  final DateTime sessionDate;
  final DateTime matchDate;

  const _FixtureMemory({
    required this.matches,
    required this.error,
    required this.fixtureContext,
    required this.rivalName,
    required this.rivalTableContext,
    required this.rivalStyle,
    required this.squadProfile,
    required this.rivalMemory,
    required this.rivalDangerPlayers,
    required this.previousMatchNotes,
    required this.objective,
    required this.problem,
    required this.space,
    required this.duration,
    required this.players,
    required this.sessionDate,
    required this.matchDate,
  });

  factory _FixtureMemory.fromDraftJson(Map<String, dynamic> json) {
    final parsedDate = DateTime.tryParse(json['matchDate'] as String? ?? '');
    return _FixtureMemory(
      matches: const [],
      error: null,
      fixtureContext: json['fixtureContext'] as String? ?? '',
      rivalName: json['rivalName'] as String? ?? '',
      rivalTableContext: json['rivalTableContext'] as String? ?? '',
      rivalStyle: json['rivalStyle'] as String? ?? '',
      squadProfile: json['squadProfile'] as String? ?? '',
      rivalMemory: json['rivalMemory'] as String? ?? '',
      rivalDangerPlayers: json['rivalDangerPlayers'] as String? ?? '',
      previousMatchNotes: json['previousMatchNotes'] as String? ?? '',
      objective: json['objective'] as String? ?? '',
      problem: json['problem'] as String? ?? '',
      space: json['space'] as String? ?? '',
      duration: (json['duration'] as num?)?.toInt() ?? 75,
      players: (json['players'] as num?)?.toInt() ?? 18,
      sessionDate:
          DateTime.tryParse(json['sessionDate'] as String? ?? '') ??
          DateTime.now().add(const Duration(days: 1)),
      matchDate: parsedDate ?? DateTime.now().add(const Duration(days: 7)),
    );
  }

  bool get hasDraftContent =>
      fixtureContext.trim().isNotEmpty ||
      rivalName.trim().isNotEmpty ||
      rivalTableContext.trim().isNotEmpty ||
      rivalStyle.trim().isNotEmpty ||
      squadProfile.trim().isNotEmpty ||
      rivalMemory.trim().isNotEmpty ||
      rivalDangerPlayers.trim().isNotEmpty ||
      previousMatchNotes.trim().isNotEmpty ||
      objective.trim().isNotEmpty ||
      problem.trim().isNotEmpty ||
      space.trim().isNotEmpty;

  Map<String, dynamic> toDraftJson() => {
    'fixtureContext': fixtureContext,
    'rivalName': rivalName,
    'rivalTableContext': rivalTableContext,
    'rivalStyle': rivalStyle,
    'squadProfile': squadProfile,
    'rivalMemory': rivalMemory,
    'rivalDangerPlayers': rivalDangerPlayers,
    'previousMatchNotes': previousMatchNotes,
    'objective': objective,
    'problem': problem,
    'space': space,
    'duration': duration,
    'players': players,
    'sessionDate': sessionDate.toUtc().toIso8601String(),
    'matchDate': matchDate.toUtc().toIso8601String(),
  };
}

class _FixtureScopePill extends StatelessWidget {
  final String label;
  final bool ready;

  const _FixtureScopePill({required this.label, required this.ready});

  @override
  Widget build(BuildContext context) {
    final cleanLabel = label.trim().isEmpty ? 'Categoria' : label.trim();
    return AnimatedContainer(
      duration: CX.motionFast,
      curve: CX.curve,
      constraints: const BoxConstraints(maxWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: ready
            ? CX.green.withValues(alpha: .1)
            : CX.amber.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: ready
              ? CX.green.withValues(alpha: .25)
              : CX.amber.withValues(alpha: .2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ready ? Icons.verified_outlined : Icons.sync_problem_outlined,
            color: ready ? CX.green : CX.amber,
            size: 13,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              cleanLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: CX.muted,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContextSuggestion extends StatelessWidget {
  final String title;
  final String text;
  final VoidCallback onUse;

  const _ContextSuggestion({
    required this.title,
    required this.text,
    required this.onUse,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CX.greenDark.withValues(alpha: .34),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CX.green.withValues(alpha: .22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: CX.green, size: 17),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              TextButton(onPressed: onUse, child: const Text('Usar')),
            ],
          ),
          Text(
            text,
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: CX.muted, fontSize: 12, height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _GeneratorForm extends StatefulWidget {
  final String objective;
  final String problem;
  final String space;
  final int duration;
  final int players;
  final int suggestedPlayers;
  final DateTime scheduledDate;
  final bool automaticSquadContext;
  final bool canGenerate;
  final ValueChanged<String> onObjective;
  final ValueChanged<String> onProblem;
  final ValueChanged<String> onSpace;
  final ValueChanged<int> onDuration;
  final ValueChanged<int> onPlayers;
  final ValueChanged<DateTime> onScheduledDate;
  final bool generating;
  final VoidCallback onGenerate;

  const _GeneratorForm({
    required this.objective,
    required this.problem,
    required this.space,
    required this.duration,
    required this.players,
    required this.suggestedPlayers,
    required this.scheduledDate,
    required this.automaticSquadContext,
    required this.canGenerate,
    required this.onObjective,
    required this.onProblem,
    required this.onSpace,
    required this.onDuration,
    required this.onPlayers,
    required this.onScheduledDate,
    required this.generating,
    required this.onGenerate,
  });

  @override
  State<_GeneratorForm> createState() => _GeneratorFormState();
}

class _GeneratorFormState extends State<_GeneratorForm> {
  // Opens itself if the coach already put context in on a previous visit, or a
  // handoff seeded a problem, so a half-filled plan is never hidden.
  late bool _showContext = widget.problem.trim().isNotEmpty;

  // Controllers (not initialValue) so a seeded focus from Estadísticas shows
  // up in the fields without a cursor jump when the coach types.
  late final TextEditingController _objectiveCtrl =
      TextEditingController(text: widget.objective);
  late final TextEditingController _spaceCtrl =
      TextEditingController(text: widget.space);
  late final TextEditingController _problemCtrl =
      TextEditingController(text: widget.problem);

  @override
  void didUpdateWidget(covariant _GeneratorForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync(_objectiveCtrl, widget.objective);
    _sync(_spaceCtrl, widget.space);
    _sync(_problemCtrl, widget.problem);
    if (widget.problem.trim().isNotEmpty && !_showContext) {
      _showContext = true;
    }
  }

  void _sync(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  @override
  void dispose() {
    _objectiveCtrl.dispose();
    _spaceCtrl.dispose();
    _problemCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: CX.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CX.line),
      ),
      child: Column(
        children: [
          TextFormField(
            controller: _objectiveCtrl,
            decoration: const InputDecoration(
              labelText: 'Objetivo principal',
              hintText: 'Que comportamiento concreto queres mejorar',
            ),
            onChanged: w.onObjective,
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _spaceCtrl,
            decoration: const InputDecoration(labelText: 'Espacio disponible'),
            onChanged: w.onSpace,
          ),
          const SizedBox(height: 12),
          _StepperBox(
            'Duracion',
            w.duration,
            w.onDuration,
            min: 45,
            max: 120,
            step: 5,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _showContext = !_showContext),
              icon: Icon(
                _showContext ? Icons.expand_less : Icons.expand_more,
                size: 18,
              ),
              label: Text(
                _showContext ? 'Ocultar contexto' : 'Agregar contexto (opcional)',
              ),
            ),
          ),
          AnimatedSize(
            duration: CX.motion,
            curve: CX.curve,
            alignment: Alignment.topCenter,
            child: _showContext
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      const Text(
                        'CONTEXTO OPCIONAL — MEJORA LA SESIÓN, NO ES OBLIGATORIO',
                        style: TextStyle(
                          color: CX.faint,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _PlanningDateField(
                        label: 'Fecha de la sesión',
                        date: w.scheduledDate,
                        onChanged: w.onScheduledDate,
                      ),
                      if (w.automaticSquadContext) ...[
                        const SizedBox(height: 10),
                        const _AutopilotNotice(
                          title: 'Sesión con plantel contextual',
                          message:
                              'fobal cruza el objetivo con las posiciones reales, la disponibilidad y las notas guardadas de la categoría.',
                        ),
                      ],
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _problemCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Problema detectado',
                          hintText:
                              'Que observaste, cuando ocurre y que consecuencia genera',
                        ),
                        onChanged: w.onProblem,
                      ),
                      const SizedBox(height: 12),
                      _StepperBox(
                        'Jugadores',
                        w.players,
                        w.onPlayers,
                        min: 6,
                        max: 28,
                      ),
                      if (w.suggestedPlayers > 0 &&
                          w.suggestedPlayers != w.players) ...[
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () => w.onPlayers(
                              w.suggestedPlayers.clamp(6, 28).toInt(),
                            ),
                            icon: const Icon(Icons.groups_2_outlined, size: 17),
                            label: Text(
                              'Usar plantel cargado (${w.suggestedPlayers})',
                            ),
                          ),
                        ),
                      ],
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: w.generating || !w.canGenerate ? null : w.onGenerate,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: w.generating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Icon(Icons.auto_awesome),
              label: Text(
                w.generating ? 'Pensando la sesión…' : 'Generar sesión',
              ),
            ),
          ),
          if (!w.canGenerate) ...[
            const SizedBox(height: 9),
            const _ReadOnlyNotice(),
          ],
        ],
      ),
    );
  }
}

class _PlanningDateField extends StatelessWidget {
  final String label;
  final DateTime date;
  final ValueChanged<DateTime> onChanged;

  const _PlanningDateField({
    required this.label,
    required this.date,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final formatted =
        '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final selected = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime.now().subtract(const Duration(days: 1)),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (selected != null) onChanged(selected);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.calendar_month_outlined),
          suffixIcon: const Icon(Icons.edit_calendar_outlined, size: 19),
        ),
        child: Text(
          formatted,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _ReadOnlyNotice extends StatelessWidget {
  const _ReadOnlyNotice();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Icon(Icons.visibility_outlined, size: 16, color: CX.faint),
        SizedBox(width: 7),
        Expanded(
          child: Text(
            'Tu acceso es de lectura. Un tecnico o coordinador puede generar y guardar planes.',
            style: TextStyle(color: CX.faint, fontSize: 11),
          ),
        ),
      ],
    );
  }
}

class _ThinkingCard extends StatelessWidget {
  const _ThinkingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CX.green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CX.green.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: CX.green),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Leyendo patrones tácticos, problema, espacio, plantel y forma de jugar del club…',
              style: TextStyle(color: CX.muted, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _GenerationFeedback extends StatelessWidget {
  final String message;

  const _GenerationFeedback({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CX.amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CX.amber.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: CX.amber, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: CX.muted,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepperBox extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;
  final int step;

  const _StepperBox(
    this.label,
    this.value,
    this.onChanged, {
    required this.min,
    required this.max,
    this.step = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CX.panel2,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: CX.muted, fontSize: 12)),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                onPressed: value <= min ? null : () => onChanged(value - step),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Expanded(
                child: Text(
                  '$value',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ),
              IconButton(
                onPressed: value >= max ? null : () => onChanged(value + step),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GeneratedSessionCard extends StatelessWidget {
  final TrainingSession session;
  final String clubName;
  final String categoryName;

  const _GeneratedSessionCard({
    required this.session,
    this.clubName = '',
    this.categoryName = '',
  });

  void _shareText(BuildContext context) {
    final content = formatSessionText(
      title: session.title,
      categoryName: categoryName,
      scheduledDate: session.scheduledDate,
      duration: session.duration,
      playerCount: session.playerCount,
      space: session.space,
      objective: session.objective,
      blocks: [
        for (final block in session.blocks)
          (name: block.name, duration: block.duration, description: block.description),
      ],
      coachCues: session.coachCues,
      successIndicators: session.successIndicators,
      limitations: session.limitations,
    );
    final fileName = buildExportFileName(
      club: clubName,
      category: categoryName,
      type: 'sesion',
      extension: 'txt',
    );
    showExportPreviewDialog(
      context,
      title: 'Sesión de entrenamiento',
      content: content,
      fileName: fileName,
      onDownload: (name, text) {
        ExportDownloadService.downloadText(name, text);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sesión descargada: $name')),
        );
      },
    );
  }

  Future<void> _exportPng(BuildContext context) async {
    final escape = const HtmlEscape().convert;
    const width = 1400;
    final body = StringBuffer();
    var y = 340;
    var index = 1;
    for (final block in session.blocks) {
      final chunks = _wrapLine(block.description, 92).take(4).toList();
      final cardHeight = 92 + chunks.length * 30;
      body.writeln(
        '<rect x="70" y="$y" width="1260" height="$cardHeight" rx="18" fill="#FFFFFF" stroke="#DCE7E1"/>',
      );
      body.writeln(
        '<circle cx="112" cy="${y + 44}" r="23" fill="#159463"/><text x="112" y="${y + 52}" text-anchor="middle" font-size="22" font-weight="800" fill="#FFFFFF">$index</text>',
      );
      body.writeln(
        '<text x="154" y="${y + 40}" font-size="25" font-weight="800" fill="#102019">${escape(block.name)}</text>',
      );
      body.writeln(
        '<rect x="1136" y="${y + 20}" width="160" height="42" rx="21" fill="#E4F7EF"/><text x="1216" y="${y + 48}" text-anchor="middle" font-size="19" font-weight="800" fill="#087A52">${escape(block.duration)}</text>',
      );
      var textY = y + 82;
      for (final chunk in chunks) {
        body.writeln(
          '<text x="154" y="$textY" font-size="21" fill="#40534A">${escape(chunk)}</text>',
        );
        textY += 30;
      }
      y += cardHeight + 18;
      index++;
    }
    final detailY = y + 14;
    final cues = session.coachCues.take(5).toList();
    final indicators = session.successIndicators.take(5).toList();
    final detailRows = cues.length > indicators.length
        ? cues.length
        : indicators.length;
    final detailHeight = 120 + detailRows * 36;
    String detailColumn(String title, List<String> values, int x) {
      final column = StringBuffer(
        '<text x="$x" y="${detailY + 46}" font-size="24" font-weight="800" fill="#102019">${escape(title)}</text>',
      );
      var rowY = detailY + 88;
      for (final value in values) {
        final wrapped = _wrapLine(value, 48);
        final line = wrapped.isEmpty ? '' : wrapped.first;
        column.writeln(
          '<circle cx="${x + 8}" cy="${rowY - 7}" r="5" fill="#159463"/><text x="${x + 25}" y="$rowY" font-size="19" fill="#40534A">${escape(line)}</text>',
        );
        rowY += 36;
      }
      return column.toString();
    }

    final height = detailY + detailHeight + 105;
    final svg =
        '''
<svg xmlns="http://www.w3.org/2000/svg" width="$width" height="$height" viewBox="0 0 $width $height">
  <rect width="100%" height="100%" fill="#F4F8F6"/>
  <rect width="100%" height="230" fill="#0D1F18"/>
  <circle cx="92" cy="72" r="30" fill="#63DBA5"/><text x="92" y="82" text-anchor="middle" font-size="25" font-weight="900" fill="#0D1F18">C</text>
  <text x="140" y="82" font-size="28" font-weight="300" fill="#FFFFFF">fobal</text>
  <text x="70" y="154" font-size="43" font-weight="900" fill="#FFFFFF">${escape(session.title)}</text>
  <text x="70" y="198" font-size="21" fill="#B7C9C0">${escape(session.scheduledDate)} · ${session.duration} min · ${session.playerCount} jugadores · ${escape(session.space)}</text>
  <rect x="70" y="255" width="1260" height="64" rx="16" fill="#E4F7EF"/>
  <text x="94" y="280" font-size="16" font-weight="800" fill="#087A52">OBJETIVO</text>
  <text x="94" y="306" font-size="21" fill="#102019">${escape(_wrapLine(session.objective, 105).isEmpty ? session.objective : _wrapLine(session.objective, 105).first)}</text>
  $body
  <rect x="70" y="$detailY" width="615" height="$detailHeight" rx="18" fill="#FFFFFF" stroke="#DCE7E1"/>
  <rect x="715" y="$detailY" width="615" height="$detailHeight" rx="18" fill="#FFFFFF" stroke="#DCE7E1"/>
  ${detailColumn('Consignas del entrenador', cues, 100)}
  ${detailColumn('Indicadores de éxito', indicators, 745)}
  <text x="70" y="${height - 42}" font-size="17" fill="#72837B">Plan generado y organizado en fobal</text>
</svg>
''';
    final svgData =
        'data:image/svg+xml;charset=utf-8,${Uri.encodeComponent(svg)}';
    final image = html.ImageElement(src: svgData);
    final loaded = Completer<void>();
    image.onLoad.first.then((_) => loaded.complete());
    image.onError.first.then((_) => loaded.completeError(StateError('export')));
    await loaded.future;
    final canvas = html.CanvasElement(width: width * 2, height: height * 2);
    canvas.context2D
      ..scale(2, 2)
      ..drawImage(image, 0, 0);
    final png = canvas.toDataUrl('image/png');
    final fileName = buildExportFileName(
      club: clubName,
      category: categoryName,
      type: 'sesion',
      extension: 'png',
    );
    html.AnchorElement(href: png)
      ..download = fileName
      ..click();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Sesión exportada: $fileName')),
    );
  }

  List<String> _wrapLine(String value, int max) {
    final words = value.split(RegExp(r'\s+'));
    final lines = <String>[];
    var current = '';
    for (final word in words) {
      final next = current.isEmpty ? word : '$current $word';
      if (next.length > max && current.isNotEmpty) {
        lines.add(current);
        current = word;
      } else {
        current = next;
      }
    }
    if (current.isNotEmpty) lines.add(current);
    return lines;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CX.green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CX.green.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            session.title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          const Text(
            'OBJETIVO',
            style: TextStyle(
              color: CX.faint,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: .5,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            session.objective,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          _GeneratedSessionBrief(session: session),
          const SizedBox(height: 12),
          _WhySessionPanel(session: session),
          const SizedBox(height: 12),
          _OperationalScoreBanner(session: session),
          const SizedBox(height: 12),
          _PreFieldChecklist(session: session),
          const SizedBox(height: 12),
          _ExecutionFlowPanel(session: session),
          const SizedBox(height: 12),
          _PostTrainingReviewPanel(session: session),
          const SizedBox(height: 12),
          for (final (i, block) in session.blocks.indexed)
            _GeneratedBlockTile(
              block: block,
              session: session,
              index: i + 1,
              total: session.blocks.length,
            ),
          const SizedBox(height: 12),
          _DetailBlock('Consignas del entrenador', session.coachCues),
          const SizedBox(height: 10),
          _DetailBlock('Indicadores de exito', session.successIndicators),
          const SizedBox(height: 10),
          _DetailBlock('Auditoria operativa', session.operationalAuditItems),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: () => _exportPng(context),
                icon: const Icon(Icons.image_outlined),
                label: const Text('Exportar PNG'),
              ),
              OutlinedButton.icon(
                onPressed: () => _shareText(context),
                icon: const Icon(Icons.notes_outlined),
                label: const Text('Compartir texto'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One generated block: text + its exercise animation (real scene from the
/// AI, or a text-derived fallback marked "aproximada").
class _GeneratedBlockTile extends StatefulWidget {
  final TrainingBlock block;
  final TrainingSession session;
  final int index;
  final int total;

  const _GeneratedBlockTile({
    required this.block,
    required this.session,
    required this.index,
    required this.total,
  });

  @override
  State<_GeneratedBlockTile> createState() => _GeneratedBlockTileState();
}

class _GeneratedBlockTileState extends State<_GeneratedBlockTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final block = widget.block;
    final scene = block.sceneOrFallback(
      space: widget.session.space,
      playerCount: widget.session.playerCount,
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CX.panel,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: CX.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: CX.greenDark,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${widget.index}',
                  style: const TextStyle(
                    color: CX.green,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  block.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13.5,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: CX.greenDark,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  block.duration,
                  style: const TextStyle(
                    color: CX.green,
                    fontWeight: FontWeight.w900,
                    fontSize: 10.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            block.description,
            style: const TextStyle(color: CX.muted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _open = !_open),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: const Size(0, 32),
              ),
              icon: Icon(
                _open ? Icons.expand_less : Icons.play_circle_outline,
                size: 17,
              ),
              label: Text(_open ? 'Ocultar cómo se ve en cancha' : 'Ver cómo se ve en cancha'),
            ),
          ),
          AnimatedSize(
            duration: CX.motion,
            curve: CX.curve,
            alignment: Alignment.topCenter,
            child: _open
                ? Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: ExerciseAnimationPreview(
                      scene: scene,
                      title: '${widget.session.title} ${block.name}',
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _OperationalScoreBanner extends StatelessWidget {
  final TrainingSession session;

  const _OperationalScoreBanner({required this.session});

  @override
  Widget build(BuildContext context) {
    final score = session.operationalReadinessScore;
    final color = score >= 82
        ? CX.green
        : score >= 62
        ? CX.amber
        : CX.red;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: .24)),
      ),
      child: Row(
        children: [
          Icon(Icons.speed_outlined, color: color, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.operationalReadinessLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  session.primaryOperationalRisk,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: CX.muted,
                    fontSize: 10,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '$score%',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

class _PostTrainingReviewPanel extends StatelessWidget {
  final TrainingSession session;

  const _PostTrainingReviewPanel({required this.session});

  @override
  Widget build(BuildContext context) {
    final prompts = session.postTrainingReviewPrompts;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CX.blue.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CX.blue.withValues(alpha: .22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.assignment_turned_in_outlined,
                color: CX.blue,
                size: 18,
              ),
              SizedBox(width: 8),
              Text(
                'Devolucion post-entreno',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...prompts.map(
            (prompt) => Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.radio_button_unchecked,
                    color: CX.blue,
                    size: 14,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      prompt,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: CX.muted,
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExecutionFlowPanel extends StatelessWidget {
  final TrainingSession session;

  const _ExecutionFlowPanel({required this.session});

  @override
  Widget build(BuildContext context) {
    final mainBlock = session.blocks.isEmpty
        ? null
        : session.blocks.reduce((best, block) {
            final bestMinutes = _minutesFrom(best.duration);
            final blockMinutes = _minutesFrom(block.duration);
            return blockMinutes > bestMinutes ? block : best;
          });
    final closingCue = session.successIndicators.isEmpty
        ? 'Cerrar con una pregunta concreta al plantel sobre lo que se logro.'
        : session.successIndicators.first;
    final items = [
      _ExecutionStep(
        Icons.campaign_outlined,
        'Abrir',
        session.coachCues.isEmpty
            ? 'Explicar objetivo, regla principal y comportamiento esperado.'
            : session.coachCues.first,
      ),
      _ExecutionStep(
        Icons.account_tree_outlined,
        'Bloque clave',
        mainBlock == null
            ? 'Elegir una tarea central y sostener el foco de correccion.'
            : '${mainBlock.name}: ${mainBlock.description}',
      ),
      _ExecutionStep(Icons.analytics_outlined, 'Medir', closingCue),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CX.greenDark.withValues(alpha: .32),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CX.green.withValues(alpha: .2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.route_outlined, color: CX.green, size: 18),
              SizedBox(width: 8),
              Text(
                'Guia de conduccion',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: CX.green.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: CX.green.withValues(alpha: .18),
                      ),
                    ),
                    child: Icon(item.icon, color: CX.green, size: 15),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.detail,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: CX.muted,
                            fontSize: 11,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  int _minutesFrom(String value) {
    final match = RegExp(r'\d+').firstMatch(value);
    return int.tryParse(match?.group(0) ?? '') ?? 0;
  }
}

class _ExecutionStep {
  final IconData icon;
  final String title;
  final String detail;

  const _ExecutionStep(this.icon, this.title, this.detail);
}

class _WhySessionPanel extends StatelessWidget {
  final TrainingSession session;

  const _WhySessionPanel({required this.session});

  @override
  Widget build(BuildContext context) {
    final (label, color, blurb) = switch (session.confidence) {
      'high' => (
        'Confianza alta',
        CX.green,
        'La sesión se armó con datos suficientes y trazables.',
      ),
      'low' => (
        'Confianza baja',
        CX.red,
        'Faltan datos clave: tomala como punto de partida y ajustá en cancha.',
      ),
      _ => (
        'Confianza media',
        CX.amber,
        'Sirve como base. Sumá contexto para que quede más fina.',
      ),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CX.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: .32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights_outlined, size: 16, color: color),
              const SizedBox(width: 7),
              const Expanded(
                child: Text(
                  'Por qué esta sesión',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            blurb,
            style: const TextStyle(color: CX.muted, fontSize: 11.5, height: 1.4),
          ),
          if (session.contextSources.isNotEmpty) ...[
            const SizedBox(height: 10),
            _WhyList(
              title: 'En qué se basó',
              icon: Icons.check_circle_outline,
              color: CX.green,
              items: session.contextSources,
            ),
          ],
          if (session.limitations.isNotEmpty) ...[
            const SizedBox(height: 8),
            _WhyList(
              title: 'Qué le faltó',
              icon: Icons.error_outline,
              color: CX.amber,
              items: session.limitations,
            ),
          ],
        ],
      ),
    );
  }
}

class _WhyList extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<String> items;

  const _WhyList({
    required this.title,
    required this.icon,
    required this.color,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w900,
            color: CX.faint,
            letterSpacing: .4,
          ),
        ),
        const SizedBox(height: 4),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(icon, size: 13, color: color),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    item,
                    style: const TextStyle(fontSize: 12, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _GeneratedSessionBrief extends StatelessWidget {
  final TrainingSession session;

  const _GeneratedSessionBrief({required this.session});

  @override
  Widget build(BuildContext context) {
    final totalBlockMinutes = session.blocks.fold<int>(
      0,
      (total, block) => total + _minutesFrom(block.duration),
    );
    final plannedMinutes = totalBlockMinutes > 0
        ? totalBlockMinutes
        : session.duration;
    final density = session.playerCount <= 12
        ? 'grupo reducido'
        : session.playerCount <= 20
        ? 'grupo medio'
        : 'grupo amplio';
    final riskLabel = session.limitations.isEmpty
        ? 'sin alertas de datos'
        : '${session.limitations.length} alertas de datos';
    final confidenceColor = switch (session.confidence) {
      'high' => CX.green,
      'medium' => CX.amber,
      'low' => CX.red,
      _ => CX.blue,
    };

    final items = [
      _BriefItem(Icons.timer_outlined, '$plannedMinutes min', 'duracion'),
      _BriefItem(
        Icons.view_timeline_outlined,
        '${session.blocks.length}',
        'bloques',
      ),
      _BriefItem(Icons.groups_2_outlined, '${session.playerCount}', density),
      _BriefItem(Icons.fact_check_outlined, riskLabel, 'contexto'),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CX.panel2.withValues(alpha: .78),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: confidenceColor.withValues(alpha: .22)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 680;
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: compact ? 2 : 4,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: compact ? 2.7 : 2.35,
            ),
            itemBuilder: (context, index) {
              final item = items[index];
              final highlighted = index == 3 && session.limitations.isNotEmpty;
              return _BriefTile(
                item: item,
                color: highlighted ? CX.amber : confidenceColor,
              );
            },
          );
        },
      ),
    );
  }

  int _minutesFrom(String value) {
    final match = RegExp(r'\d+').firstMatch(value);
    return int.tryParse(match?.group(0) ?? '') ?? 0;
  }
}

class _PreFieldChecklist extends StatelessWidget {
  final TrainingSession session;

  const _PreFieldChecklist({required this.session});

  @override
  Widget build(BuildContext context) {
    final items = [
      _ChecklistItem(
        Icons.record_voice_over_outlined,
        'Mensaje inicial',
        session.coachCues.isEmpty
            ? 'Definir una consigna simple antes de empezar.'
            : session.coachCues.first,
        CX.green,
      ),
      _ChecklistItem(
        Icons.track_changes_outlined,
        'Medir durante',
        session.successIndicators.isEmpty
            ? 'Elegir un indicador observable para corregir en vivo.'
            : session.successIndicators.first,
        CX.blue,
      ),
      _ChecklistItem(
        session.limitations.isEmpty
            ? Icons.verified_outlined
            : Icons.warning_amber_outlined,
        session.limitations.isEmpty ? 'Datos suficientes' : 'Cuidar supuesto',
        session.limitations.isEmpty
            ? 'La propuesta no declaro limitaciones criticas de datos.'
            : session.limitations.first,
        session.limitations.isEmpty ? CX.green : CX.amber,
      ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CX.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CX.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.checklist_rtl, color: CX.green, size: 18),
              SizedBox(width: 8),
              Text(
                'Checklist antes de cancha',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ChecklistRow(item: item),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChecklistItem {
  final IconData icon;
  final String title;
  final String detail;
  final Color color;

  const _ChecklistItem(this.icon, this.title, this.detail, this.color);
}

class _ChecklistRow extends StatelessWidget {
  final _ChecklistItem item;

  const _ChecklistRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: item.color.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: item.color.withValues(alpha: .18)),
          ),
          child: Icon(item.icon, color: item.color, size: 15),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                item.detail,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: CX.muted,
                  fontSize: 11,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BriefItem {
  final IconData icon;
  final String value;
  final String label;

  const _BriefItem(this.icon, this.value, this.label);
}

class _BriefTile extends StatelessWidget {
  final _BriefItem item;
  final Color color;

  const _BriefTile({required this.item, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: .18)),
      ),
      child: Row(
        children: [
          Icon(item.icon, color: color, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: CX.faint, fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailBlock extends StatelessWidget {
  final String title;
  final List<String> items;

  const _DetailBlock(this.title, this.items);

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('- '),
                Expanded(
                  child: Text(
                    item,
                    style: TextStyle(color: CX.muted, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TranscriptCard extends StatelessWidget {
  final TextEditingController controller;
  final CategorySquad category;
  final int totalPlayers;
  final ValueChanged<TrainingReport> onSave;

  const _TranscriptCard({
    required this.controller,
    required this.category,
    required this.totalPlayers,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: CX.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CX.line),
      ),
      child: Column(
        children: [
          TextField(
            controller: controller,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Texto o audio transcripto',
              hintText:
                  'Ej: asistieron 16 de 20, trabajamos salida, destaco Juan, lesion Pedro...',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final hasText = controller.text.trim().isNotEmpty;
              return Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Grabacion preparada. Si el navegador no abre microfono, pega la transcripcion y confirmala.',
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.mic_none),
                      label: const Text('Grabar audio'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: hasText
                          ? () => ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Texto confirmado. Ahora podes guardar.',
                                ),
                              ),
                            )
                          : null,
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Confirmar escrito'),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final note = _ParsedTrainingNote.fromText(controller.text);
              return Column(
                children: [
                  _StructuredResult(note: note),
                  if (!note.isEmpty) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: note.canSave
                            ? () => onSave(
                                note.toReport(
                                  categoryId: category.id,
                                  totalPlayers: totalPlayers,
                                ),
                              )
                            : null,
                        icon: const Icon(Icons.save_outlined, size: 18),
                        label: Text(
                          note.canSave
                              ? 'Guardar lectura post-entreno'
                              : 'Agrega asistencia u objetivo para guardar',
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StructuredResult extends StatelessWidget {
  final _ParsedTrainingNote note;

  const _StructuredResult({required this.note});

  @override
  Widget build(BuildContext context) {
    if (note.isEmpty) {
      return const _GenerationFeedback(
        message:
            'Pega una nota o transcripcion del entrenamiento. fobal ordenara solo lo que encuentre, sin inventar asistencia, lesiones ni destacados.',
      );
    }

    final rows = {
      if (note.attendance.isNotEmpty) 'Asistencia': note.attendance,
      if (note.objective.isNotEmpty) 'Objetivo trabajado': note.objective,
      if (note.positive.isNotEmpty) 'Aspecto positivo': note.positive,
      if (note.toImprove.isNotEmpty) 'A mejorar': note.toImprove,
      if (note.highlighted.isNotEmpty) 'Destacados': note.highlighted,
      if (note.injuries.isNotEmpty) 'Lesion': note.injuries,
      if (note.nextFocus.isNotEmpty) 'Proximo foco': note.nextFocus,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows.entries.map((entry) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 118,
                child: Text(
                  entry.key,
                  style: TextStyle(color: CX.muted, fontSize: 12),
                ),
              ),
              Expanded(
                child: Text(
                  entry.value,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _ParsedTrainingNote {
  final String attendance;
  final String objective;
  final String positive;
  final String toImprove;
  final String highlighted;
  final String injuries;
  final String nextFocus;

  const _ParsedTrainingNote({
    required this.attendance,
    required this.objective,
    required this.positive,
    required this.toImprove,
    required this.highlighted,
    required this.injuries,
    required this.nextFocus,
  });

  bool get isEmpty =>
      attendance.isEmpty &&
      objective.isEmpty &&
      positive.isEmpty &&
      toImprove.isEmpty &&
      highlighted.isEmpty &&
      injuries.isEmpty &&
      nextFocus.isEmpty;

  bool get canSave => attendance.isNotEmpty || objective.isNotEmpty;

  TrainingReport toReport({
    required String categoryId,
    required int totalPlayers,
  }) {
    final attendanceCount = _firstNumber(attendance);
    return TrainingReport(
      categoryId: categoryId,
      date: _todayLabel(),
      attendanceCount: attendanceCount,
      totalPlayers: totalPlayers > 0 ? totalPlayers : attendanceCount,
      objectiveWorked: objective,
      whatWentWell: positive,
      whatWentWrong: toImprove,
      highlightedPlayers: _splitNames(highlighted),
      injuries: _splitNames(injuries),
      nextRecommendation: nextFocus,
    );
  }

  static int _firstNumber(String value) {
    final match = RegExp(r'\d+').firstMatch(value);
    return int.tryParse(match?.group(0) ?? '') ?? 0;
  }

  static List<String> _splitNames(String value) {
    return value
        .split(RegExp(r',| y '))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  static String _todayLabel() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(now.day)}/${two(now.month)}/${now.year}';
  }

  factory _ParsedTrainingNote.fromText(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return const _ParsedTrainingNote(
        attendance: '',
        objective: '',
        positive: '',
        toImprove: '',
        highlighted: '',
        injuries: '',
        nextFocus: '',
      );
    }

    String find(List<RegExp> patterns) {
      for (final pattern in patterns) {
        final match = pattern.firstMatch(text);
        if (match != null) {
          return (match.group(1) ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
        }
      }
      return '';
    }

    final attendance = find([
      RegExp(
        r'(?:asistieron|asistencia|presentes?)\s*:?\s*([^.;\n]+)',
        caseSensitive: false,
      ),
      RegExp(
        r'(\d+\s*(?:de|/)\s*\d+)\s*(?:presentes|asistieron|jugadores)?',
        caseSensitive: false,
      ),
    ]);

    return _ParsedTrainingNote(
      attendance: attendance,
      objective: find([
        RegExp(
          r'(?:objetivo|trabajamos|se trabajo)\s*:?\s*([^.;\n]+)',
          caseSensitive: false,
        ),
      ]),
      positive: find([
        RegExp(
          r'(?:positivo|bien|fortaleza)\s*:?\s*([^.;\n]+)',
          caseSensitive: false,
        ),
      ]),
      toImprove: find([
        RegExp(
          r'(?:a mejorar|mejorar|debilidad|problema)\s*:?\s*([^.;\n]+)',
          caseSensitive: false,
        ),
      ]),
      highlighted: find([
        RegExp(
          r'(?:destacados?|destaco|destacaron)\s*:?\s*([^.;\n]+)',
          caseSensitive: false,
        ),
      ]),
      injuries: find([
        RegExp(
          r'(?:lesion|lesionado|molestia)\s*:?\s*([^.;\n]+)',
          caseSensitive: false,
        ),
      ]),
      nextFocus: find([
        RegExp(
          r'(?:proximo foco|siguiente foco|proxima sesion)\s*:?\s*([^.;\n]+)',
          caseSensitive: false,
        ),
      ]),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 3,
          height: 18,
          decoration: BoxDecoration(
            color: CX.green,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: .1,
            ),
          ),
        ),
      ],
    );
  }
}

class _HandoffBanner extends StatelessWidget {
  final String origin;
  final String context;
  final VoidCallback onDismiss;

  const _HandoffBanner({
    required this.origin,
    required this.context,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final ctx = this.context.trim();
    return Container(
      decoration: BoxDecoration(
        color: CX.green.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: CX.green, width: 3),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(13, 10, 6, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.auto_awesome, size: 15, color: CX.green),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(
                        text: 'Sugerido desde ',
                        style: TextStyle(color: CX.muted, fontSize: 12),
                      ),
                      TextSpan(
                        text: origin,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (ctx.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    ctx,
                    style: const TextStyle(
                      color: CX.muted,
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ],
                const SizedBox(height: 3),
                const Text(
                  'Ya cargamos lo que se pudo. Revisá y ajustá antes de generar.',
                  style: TextStyle(color: CX.faint, fontSize: 10, height: 1.3),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Ocultar',
            onPressed: onDismiss,
            icon: const Icon(Icons.close, size: 16),
          ),
        ],
      ),
    );
  }
}
