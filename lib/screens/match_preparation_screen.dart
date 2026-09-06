// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;

import 'package:flutter/material.dart';

import '../data/cantera_data.dart';
import '../main.dart';
import '../services/alignment_history_service.dart';
import '../services/club_access_service.dart';
import '../services/export_download_service.dart';
import '../services/export_text_service.dart';
import '../services/player_match_stats_service.dart';
import '../state/section_handoff.dart';
import '../ui/export_preview_dialog.dart';
import '../ui/ui_kit.dart';
import 'match_result_dialog.dart';
import 'player_profile_screen.dart';

/// Opens the match-preparation panel. If [calendarEventId] matches an
/// existing [MatchPreparation] for the active category, that one opens for
/// editing; otherwise a new one is seeded with whatever context is passed in
/// (from a calendar event, a fixture row, or opened blank).
void openMatchPreparation(
  BuildContext context, {
  String? calendarEventId,
  String? rival,
  String? date,
  String? time,
}) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => MatchPreparationScreen(
        calendarEventId: calendarEventId ?? '',
        initialRival: rival ?? '',
        initialDate: date ?? '',
        initialTime: time ?? '',
      ),
    ),
  );
}

class MatchPreparationScreen extends StatefulWidget {
  final String calendarEventId;
  final String initialRival;
  final String initialDate;
  final String initialTime;

  const MatchPreparationScreen({
    super.key,
    this.calendarEventId = '',
    this.initialRival = '',
    this.initialDate = '',
    this.initialTime = '',
  });

  @override
  State<MatchPreparationScreen> createState() => _MatchPreparationScreenState();
}

class _MatchPreparationScreenState extends State<MatchPreparationScreen> {
  late final TextEditingController _rival;
  late final TextEditingController _date;
  late final TextEditingController _time;
  late final TextEditingController _opponentNotes;
  late final TextEditingController _planIdea;
  late final TextEditingController _planObjective;
  late final TextEditingController _offensiveKeys;
  late final TextEditingController _defensiveKeys;
  late final TextEditingController _transitions;
  late final TextEditingController _setPiecesFor;
  late final TextEditingController _setPiecesAgainst;
  late final TextEditingController _playersToWatch;
  late final TextEditingController _staffNotes;
  String _venue = '';
  String _id = '';
  String _createdAt = '';
  String _linkedSessionId = '';
  bool _hydrated = false;

  LudStandingsTable? _standings;
  bool _loadingRival = false;

  @override
  void initState() {
    super.initState();
    _rival = TextEditingController(text: widget.initialRival);
    _date = TextEditingController(text: widget.initialDate);
    _time = TextEditingController(text: widget.initialTime);
    _opponentNotes = TextEditingController();
    _planIdea = TextEditingController();
    _planObjective = TextEditingController();
    _offensiveKeys = TextEditingController();
    _defensiveKeys = TextEditingController();
    _transitions = TextEditingController();
    _setPiecesFor = TextEditingController();
    _setPiecesAgainst = TextEditingController();
    _playersToWatch = TextEditingController();
    _staffNotes = TextEditingController();
  }

  @override
  void dispose() {
    _rival.dispose();
    _date.dispose();
    _time.dispose();
    _opponentNotes.dispose();
    _planIdea.dispose();
    _planObjective.dispose();
    _offensiveKeys.dispose();
    _defensiveKeys.dispose();
    _transitions.dispose();
    _setPiecesFor.dispose();
    _setPiecesAgainst.dispose();
    _playersToWatch.dispose();
    _staffNotes.dispose();
    super.dispose();
  }

  void _hydrate(CanteraClub club) {
    if (_hydrated) return;
    _hydrated = true;
    if (widget.calendarEventId.isEmpty) return;
    MatchPreparation? existing;
    for (final item in club.matchPreparations) {
      if (item.calendarEventId == widget.calendarEventId) {
        existing = item;
        break;
      }
    }
    if (existing == null) return;
    _id = existing.id;
    _createdAt = existing.createdAt;
    _linkedSessionId = existing.linkedSessionId;
    _rival.text = existing.rival;
    _date.text = existing.date;
    _time.text = existing.time;
    _venue = existing.venue;
    _opponentNotes.text = existing.opponentNotes;
    _planIdea.text = existing.planIdea;
    _planObjective.text = existing.planObjective;
    _offensiveKeys.text = existing.offensiveKeys;
    _defensiveKeys.text = existing.defensiveKeys;
    _transitions.text = existing.transitions;
    _setPiecesFor.text = existing.setPiecesFor;
    _setPiecesAgainst.text = existing.setPiecesAgainst;
    _playersToWatch.text = existing.playersToWatch;
    _staffNotes.text = existing.staffNotes;
  }

  Future<void> _loadRivalContext(CategorySquad category) async {
    if (_loadingRival || _standings != null) return;
    final membership = await ClubAccessService.activeMembership();
    if (membership == null || !mounted) return;
    setState(() => _loadingRival = true);
    try {
      final table = await ClubAccessService.loadStandings(
        membership: membership,
        category: category,
      );
      if (!mounted) return;
      setState(() {
        _standings = table;
        _loadingRival = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingRival = false);
    }
  }

  LudStandingRow? _rivalRow() {
    final table = _standings;
    final rivalName = _rival.text.trim().toLowerCase();
    if (table == null || rivalName.isEmpty) return null;
    for (final row in table.rows) {
      if (row.teamName.toLowerCase().contains(rivalName) ||
          rivalName.contains(row.teamName.toLowerCase())) {
        return row;
      }
    }
    return null;
  }

  void _save(CanteraClub club, CategorySquad category) =>
      _persistPrep(club, category);

  void _persistPrep(
    CanteraClub club,
    CategorySquad category, {
    bool silent = false,
  }) {
    final id = _id.isEmpty ? 'matchprep-${DateTime.now().millisecondsSinceEpoch}' : _id;
    _id = id;
    final now = DateTime.now().toUtc().toIso8601String();
    final prep = MatchPreparation(
      id: id,
      categoryId: category.id,
      calendarEventId: widget.calendarEventId,
      rival: _rival.text.trim(),
      date: _date.text.trim(),
      time: _time.text.trim(),
      venue: _venue,
      opponentNotes: _opponentNotes.text.trim(),
      planIdea: _planIdea.text.trim(),
      planObjective: _planObjective.text.trim(),
      offensiveKeys: _offensiveKeys.text.trim(),
      defensiveKeys: _defensiveKeys.text.trim(),
      transitions: _transitions.text.trim(),
      setPiecesFor: _setPiecesFor.text.trim(),
      setPiecesAgainst: _setPiecesAgainst.text.trim(),
      playersToWatch: _playersToWatch.text.trim(),
      staffNotes: _staffNotes.text.trim(),
      linkedSessionId: _linkedSessionId,
      createdAt: _createdAt.isEmpty ? now : _createdAt,
      updatedAt: now,
    );
    _createdAt = prep.createdAt;
    final scope = AppScope.of(context);
    scope.updateClub(
      club.copyWith(
        matchPreparations: [
          prep,
          ...club.matchPreparations.where((item) => item.id != id),
        ],
      ),
    );
    if (!silent) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Plan de partido guardado${_rival.text.trim().isEmpty ? '' : ' vs ${_rival.text.trim()}'}.')),
      );
    }
  }

  /// Same log-result flow the calendar offers, but reachable from the prep
  /// itself — no need to leave to Calendario just to close out a match this
  /// screen already has all the context for. Recomputes matchesPlayed/goals
  /// for the category the same way calendario_screen and estadisticas_screen
  /// do, so all three entry points stay consistent (never double-counts).
  Future<void> _logResult(
    CanteraClub club,
    CategorySquad category,
    bool categoryIsLud,
    MatchResult? existing,
  ) async {
    final categoryPlayers = categoryIsLud
        ? const <Player>[]
        : club.players.where((p) => p.categoryId == category.id).toList();
    final historyRaw = html.window.localStorage[
        'cantera_alignment_history_${club.id}_${category.id}'] ??
        '';
    final suggestedLineupIds = findLineupForRival(
          historyJson: historyRaw,
          rivalName: _rival.text.trim(),
        ) ??
        const [];
    final result = await showMatchResultDialog(
      context,
      categoryId: category.id,
      existing: existing,
      initialDate: DateTime.tryParse(_date.text.trim()),
      initialOpponent: _rival.text.trim(),
      calendarKey: widget.calendarEventId,
      players: categoryPlayers,
      suggestedLineupIds: suggestedLineupIds,
    );
    if (result == null || !mounted) return;
    final nextResults = [
      for (final r in club.matchResults)
        if (r.id != result.id) r,
      result,
    ];
    var players = club.players;
    if (categoryPlayers.isNotEmpty) {
      final categoryResults =
          nextResults.where((r) => r.categoryId == category.id).toList();
      final stats = computePlayerMatchStats(
        lineups: [for (final r in categoryResults) r.lineupIds],
        scorers: [for (final r in categoryResults) r.scorerIds],
        playerIds: categoryPlayers.map((p) => p.id).toList(),
      );
      players = [
        for (final player in club.players)
          if (stats.containsKey(player.id))
            player.copyWith(
              matchesPlayed: stats[player.id]!.matchesPlayed,
              goals: stats[player.id]!.goals,
            )
          else
            player,
      ];
    }
    AppScope.of(context).updateClub(
      club.copyWith(matchResults: nextResults, players: players),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Resultado guardado.')),
    );
  }

  void _goToLineup() {
    ShellActions.of(context).openLineup(LineupHint(
      rival: _rival.text.trim(),
      date: _date.text.trim(),
      time: _time.text.trim(),
    ));
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _goToPlanificar(CanteraClub club, CategorySquad category) {
    // If this prep came from a calendar event but was never saved, persist
    // it now (silently) so the session the planner generates has a real
    // MatchPreparation to write linkedSessionId back onto.
    if (widget.calendarEventId.isNotEmpty &&
        !club.matchPreparations
            .any((p) => p.calendarEventId == widget.calendarEventId)) {
      _persistPrep(club, category, silent: true);
    }
    final planSummary = [
      if (_planObjective.text.trim().isNotEmpty) _planObjective.text.trim(),
      if (_offensiveKeys.text.trim().isNotEmpty) 'Claves ofensivas: ${_offensiveKeys.text.trim()}',
      if (_defensiveKeys.text.trim().isNotEmpty) 'Claves defensivas: ${_defensiveKeys.text.trim()}',
    ].join(' ');
    ShellActions.of(context).openMatchPrep(
      MatchPrepHandoff(
        rivalName: _rival.text.trim(),
        rivalContext: [_opponentNotes.text.trim(), planSummary].where((s) => s.isNotEmpty).join(' — '),
        note: _staffNotes.text.trim(),
        origin: 'Panel de partido',
        calendarEventId: widget.calendarEventId,
      ),
    );
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// Title of the session generated from this prep via "Preparar
  /// entrenamiento para este partido", if it still exists. Never guessed —
  /// only resolved from the real linkedSessionId written back by Planificar.
  String? _linkedSessionTitle(CanteraClub club) {
    if (_linkedSessionId.isEmpty) return null;
    for (final session in club.sessions) {
      if (session.id == _linkedSessionId) return session.title;
    }
    return null;
  }

  void _shareSummary(CanteraClub club, CategorySquad category, List<String> warnings) {
    final content = formatMatchPreparationText(
      categoryName: category.name,
      rival: _rival.text.trim(),
      date: _date.text.trim(),
      time: _time.text.trim(),
      venue: _venue,
      opponentNotes: _opponentNotes.text.trim(),
      planIdea: _planIdea.text.trim(),
      planObjective: _planObjective.text.trim(),
      offensiveKeys: _offensiveKeys.text.trim(),
      defensiveKeys: _defensiveKeys.text.trim(),
      transitions: _transitions.text.trim(),
      setPiecesFor: _setPiecesFor.text.trim(),
      setPiecesAgainst: _setPiecesAgainst.text.trim(),
      playersToWatch: _playersToWatch.text.trim(),
      staffNotes: _staffNotes.text.trim(),
      availabilityNotes: warnings,
      linkedSessionTitle: _linkedSessionTitle(club) ?? '',
    );
    final fileName = buildExportFileName(
      club: club.name,
      category: category.name,
      type: 'plan-partido',
      extension: 'txt',
    );
    showExportPreviewDialog(
      context,
      title: 'Plan de partido',
      content: content,
      fileName: fileName,
      onDownload: (name, text) {
        ExportDownloadService.downloadText(name, text);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Plan descargado: $name')),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final club = scope.club;
    if (club.categories.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Panel de partido')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: EmptyStatePanel(
              icon: Icons.account_tree_outlined,
              title: 'Primero cargá una categoría',
              message: 'Creá una categoría para poder preparar un partido.',
            ),
          ),
        ),
      );
    }
    final category = club.categories.first;
    _hydrate(club);
    final categoryIsLud = LudCategoryRef.teamIdOf(category.id) != null;
    if (categoryIsLud) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadRivalContext(category));
    }
    final rivalRow = _rivalRow();
    final warningPlayers = club.players
        .where((player) => player.categoryId == category.id && player.hasAvailabilityWarning)
        .toList();
    final warningNotes = [
      for (final player in warningPlayers)
        '${player.fullName.trim()}: ${player.availability.label.toLowerCase()}, confirmar antes del partido.',
    ];
    MatchResult? existingResult;
    if (widget.calendarEventId.isNotEmpty) {
      for (final result in club.matchResults) {
        if (result.calendarKey == widget.calendarEventId) {
          existingResult = result;
          break;
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _rival.text.trim().isEmpty ? 'Panel de partido' : 'Vs ${_rival.text.trim()}',
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
              children: [
                const PremiumSectionHeader(eyebrow: 'Partido', title: 'Datos del compromiso'),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: CX.panelDecoration(),
                  child: Column(
                    children: [
                      TextField(
                        controller: _rival,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(labelText: 'Rival'),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _date,
                              decoration: const InputDecoration(labelText: 'Fecha'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _time,
                              decoration: const InputDecoration(labelText: 'Hora', hintText: 'Ej: 16:00'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: _venue,
                        decoration: const InputDecoration(labelText: 'Condición'),
                        items: const [
                          DropdownMenuItem(value: '', child: Text('Sin definir')),
                          DropdownMenuItem(value: 'local', child: Text('Local')),
                          DropdownMenuItem(value: 'visitante', child: Text('Visitante')),
                          DropdownMenuItem(value: 'neutral', child: Text('Cancha neutral')),
                        ],
                        onChanged: (value) => setState(() => _venue = value ?? ''),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const PremiumSectionHeader(eyebrow: 'Rival', title: 'Lo que sabemos'),
                if (categoryIsLud) ...[
                  if (rivalRow != null)
                    MetricGrid(
                      tiles: [
                        MetricTile(
                          icon: Icons.emoji_events_outlined,
                          value: '${rivalRow.rank}°',
                          label: 'Posición',
                          context: 'en la tabla',
                          accent: CX.amber,
                        ),
                        MetricTile(
                          icon: Icons.stars,
                          value: '${rivalRow.points}',
                          label: 'Puntos',
                          context: '${rivalRow.won}G ${rivalRow.drawn}E ${rivalRow.lost}P',
                          accent: CX.blue,
                        ),
                        MetricTile(
                          icon: Icons.sports_soccer,
                          value: '${rivalRow.goalsFor}',
                          label: 'Goles a favor',
                          context: '${rivalRow.played} PJ',
                          accent: CX.green,
                        ),
                        MetricTile(
                          icon: Icons.shield_outlined,
                          value: '${rivalRow.goalsAgainst}',
                          label: 'Goles en contra',
                          context: 'en la liga',
                          accent: CX.red,
                        ),
                      ],
                    )
                  else
                    EmptyStatePanel(
                      icon: Icons.query_stats_outlined,
                      title: _loadingRival ? 'Buscando al rival en la tabla…' : 'Sin datos confiables del rival todavía',
                      message: _rival.text.trim().isEmpty
                          ? 'Escribí el nombre del rival para buscarlo en la tabla de la liga.'
                          : 'No lo encontramos en la tabla con ese nombre — puede ser de otra categoría o liga.',
                    ),
                  const SizedBox(height: 10),
                ],
                TextField(
                  controller: _opponentNotes,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: categoryIsLud ? 'Notas propias sobre el rival' : 'Notas del rival',
                    hintText: 'Sistema, presión, salida, zonas fuertes y débiles vistas',
                  ),
                ),
                const SizedBox(height: 20),
                const PremiumSectionHeader(eyebrow: 'Plan', title: 'Idea de juego'),
                TextField(
                  controller: _planObjective,
                  decoration: const InputDecoration(labelText: 'Objetivo del partido'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _planIdea,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Idea de juego'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _offensiveKeys,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Claves ofensivas'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _defensiveKeys,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Claves defensivas'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _transitions,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Transiciones'),
                ),
                const SizedBox(height: 20),
                const PremiumSectionHeader(eyebrow: 'Pelota quieta', title: 'A favor y en contra'),
                TextField(
                  controller: _setPiecesFor,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'A favor'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _setPiecesAgainst,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'En contra'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _playersToWatch,
                  minLines: 1,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Jugadores a observar'),
                ),
                const SizedBox(height: 20),
                const PremiumSectionHeader(eyebrow: 'Citación', title: 'Disponibilidad del plantel'),
                if (warningPlayers.isEmpty)
                  const EmptyStatePanel(
                    icon: Icons.verified_outlined,
                    title: 'Sin alertas de disponibilidad',
                    message: 'Todo el plantel de esta categoría figura disponible.',
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: CX.amber.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: CX.amber.withValues(alpha: .25)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          warningPlayers.length == 1
                              ? '1 jugador con estado a confirmar'
                              : '${warningPlayers.length} jugadores con estado a confirmar',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final player in warningPlayers)
                              InkWell(
                                borderRadius: BorderRadius.circular(999),
                                onTap: () => openPlayerProfile(context, player),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: CX.panel,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(color: player.availability.color.withValues(alpha: .4)),
                                  ),
                                  child: Text(
                                    '${player.fullName.trim()} · ${player.availability.label}',
                                    style: TextStyle(color: player.availability.color, fontSize: 11, fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                if (widget.calendarEventId.isNotEmpty) ...[
                  OutlinedButton.icon(
                    onPressed: () => _logResult(
                      club,
                      category,
                      categoryIsLud,
                      existingResult,
                    ),
                    icon: Icon(
                      existingResult == null
                          ? Icons.scoreboard_outlined
                          : Icons.edit_outlined,
                      size: 17,
                    ),
                    label: Text(
                      existingResult == null
                          ? 'Cargar resultado'
                          : 'Editar resultado (${existingResult.goalsFor}-${existingResult.goalsAgainst})',
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _goToLineup,
                  icon: const Icon(Icons.groups_2_outlined, size: 17),
                  label: const Text('Ir a Alineación & citaciones'),
                ),
                const SizedBox(height: 20),
                const PremiumSectionHeader(eyebrow: 'Entrenamiento', title: 'Preparación asociada'),
                if (_linkedSessionTitle(club) case final title?) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: CX.greenDark.withValues(alpha: .3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: CX.green.withValues(alpha: .24)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_outline, color: CX.green, size: 17),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Entrenamiento vinculado: $title',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                OutlinedButton.icon(
                  onPressed: () => _goToPlanificar(club, category),
                  icon: const Icon(Icons.auto_awesome, size: 17),
                  label: Text(
                    _linkedSessionId.isEmpty
                        ? 'Preparar entrenamiento para este partido'
                        : 'Preparar otro entrenamiento para este partido',
                  ),
                ),
                const SizedBox(height: 20),
                const PremiumSectionHeader(eyebrow: 'Seguimiento', title: 'Notas'),
                TextField(
                  controller: _staffNotes,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Notas del cuerpo técnico'),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SizedBox(
                      width: 190,
                      child: ElevatedButton.icon(
                        onPressed: () => _save(club, category),
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Guardar plan'),
                      ),
                    ),
                    SizedBox(
                      width: 190,
                      child: OutlinedButton.icon(
                        onPressed: () => _shareSummary(club, category, warningNotes),
                        icon: const Icon(Icons.notes_outlined),
                        label: const Text('Compartir texto'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
