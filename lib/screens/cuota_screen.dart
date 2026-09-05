import 'package:flutter/material.dart';

import '../data/cantera_data.dart';
import '../main.dart';
import '../services/club_access_service.dart';
import '../state/section_handoff.dart';
import '../ui/exercise_animation_preview.dart';
import '../ui/ui_kit.dart';
import 'add_player_dialog.dart';
import 'match_preparation_screen.dart';
import 'player_profile_screen.dart';

class CuotaScreen extends StatefulWidget {
  const CuotaScreen({super.key});

  @override
  State<CuotaScreen> createState() => _CuotaScreenState();
}

class _CuotaScreenState extends State<CuotaScreen> {
  final _squadMapKey = GlobalKey();
  final _sessionsKey = GlobalKey();
  String? _categoryId;
  String? _hydratedClubId;
  bool _syncing = false;
  List<TrainingSession> _matchPlans = const [];

  void _scrollTo(GlobalKey key) {
    final target = key.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: .08,
    );
  }

  Future<void> _editCategoryFocus(
    CanteraClub club,
    CategorySquad category,
  ) async {
    final value = await promptForText(
      context,
      title: 'Objetivo de la semana',
      initialValue: category.currentFocus,
      hintText: 'Ej: mejorar la defensa de centros laterales',
      minLines: 3,
      maxLines: 6,
    );
    if (value == null || !mounted) return;
    final categories = club.categories
        .map(
          (item) => item.id == category.id
              ? item.copyWith(currentFocus: value)
              : item,
        )
        .toList();
    AppScope.of(context).updateClub(club.copyWith(categories: categories));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final clubId = AppScope.of(context).club.id;
    if (_hydratedClubId == clubId) return;
    _hydratedClubId = clubId;
    Future<void>.microtask(_syncClubPlanning);
  }

  Future<void> _syncClubPlanning() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final records = await ClubAccessService.loadTacticalData(limit: 100);
      if (!mounted) return;
      final scope = AppScope.of(context);
      final club = scope.club;
      final remoteSessions = <TrainingSession>[];
      final remoteReports = <TrainingReport>[];
      final remoteMatchPlans = <TrainingSession>[];
      for (final record in records) {
        try {
          if (record.type == 'session') {
            final session = TrainingSession.fromJson(record.content);
            if (session.id.isNotEmpty && session.categoryId.isNotEmpty) {
              remoteSessions.add(session);
            }
          } else if (record.type == 'match_plan') {
            final plan = TrainingSession.fromJson(record.content);
            if (plan.id.isNotEmpty && plan.categoryId.isNotEmpty) {
              remoteMatchPlans.add(plan);
            }
          } else if (record.type == 'staff_note') {
            final report = TrainingReport.fromJson(record.content);
            if (report.categoryId.isNotEmpty && report.date.isNotEmpty) {
              remoteReports.add(report);
            }
          }
        } catch (_) {
          // Ignore an isolated legacy record without losing the club agenda.
        }
      }
      final sessionIds = remoteSessions.map((item) => item.id).toSet();
      final reportKeys = remoteReports
          .map((item) => '${item.categoryId}|${item.date}')
          .toSet();
      final profiledPlayers = applyRemotePlayerProfiles(
        players: club.players,
        records: records,
      );
      scope.updateClub(
        club.copyWith(
          players: profiledPlayers,
          sessions: [
            ...remoteSessions,
            ...club.sessions.where((item) => !sessionIds.contains(item.id)),
          ],
          trainingReports: [
            ...remoteReports,
            ...club.trainingReports.where(
              (item) => !reportKeys.contains('${item.categoryId}|${item.date}'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      setState(() {
        _syncing = false;
        _matchPlans = remoteMatchPlans;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _syncing = false);
    }
  }

  Future<void> _updateSession(CanteraClub club, TrainingSession session) async {
    final updated = club.sessions
        .map((item) => item.id == session.id ? session : item)
        .toList();
    AppScope.of(context).updateClub(club.copyWith(sessions: updated));
    var synced = false;
    try {
      synced = await ClubAccessService.updateSession(session);
    } catch (_) {
      synced = false;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          synced
              ? 'Planificacion actualizada para el club.'
              : 'Planificacion actualizada en este dispositivo.',
        ),
      ),
    );
  }

  Future<void> _editPlayer(CanteraClub club, Player player) async {
    final scope = AppScope.of(context);
    final updated = await showDialog<Player>(
      context: context,
      builder: (context) => _PlayerEditDialog(player: player),
    );
    if (updated == null) return;

    final players = club.players
        .map((item) => item.id == updated.id ? updated : item)
        .toList();
    scope.updateClub(club.copyWith(players: players));

    var synced = false;
    try {
      synced = await ClubAccessService.saveTacticalData(
        type: 'staff_note',
        title: 'Perfil jugador ${updated.fullName.trim()}',
        content: {
          'kind': 'player_profile_update',
          'player': updated.toJson(),
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        },
        relatedLudPlayerIds: [_ludPlayerId(updated)].whereType<int>().toList(),
        categoryId: updated.categoryId,
      );
    } catch (_) {
      synced = false;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          synced
              ? 'Perfil del jugador guardado para futuras tacticas.'
              : 'Perfil actualizado en este dispositivo.',
        ),
      ),
    );
  }

  Future<void> _addManualPlayer(CanteraClub club, CategorySquad category) async {
    final player = await showAddPlayerDialog(
      context,
      categoryId: category.id,
      existingNames: normalizedPlayerNames(
        club.players.where((p) => p.categoryId == category.id),
      ),
    );
    if (player == null) return;
    final nextPlayers = [...club.players, player];
    final nextCategories = club.categories
        .map(
          (item) => item.id == category.id
              ? item.copyWith(
                  playerCount: nextPlayers
                      .where((candidate) => candidate.categoryId == category.id)
                      .length,
                )
              : item,
        )
        .toList();
    AppScope.of(context).updateClub(
      club.copyWith(players: nextPlayers, categories: nextCategories),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${player.fullName.trim()} agregado al plantel.')),
    );
  }

  int? _ludPlayerId(Player player) {
    final match = RegExp(r'lud-player-(\d+)$').firstMatch(player.id);
    return int.tryParse(match?.group(1) ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final club = AppScope.of(context).club;
    final selectedId = club.categories.any((item) => item.id == _categoryId)
        ? _categoryId
        : club.categories.isEmpty
        ? null
        : club.categories.first.id;
    final category = selectedId == null
        ? null
        : club.categories.firstWhere((item) => item.id == selectedId);
    final players = category == null
        ? <Player>[]
        : club.players.where((item) => item.categoryId == category.id).toList();
    final sessions = category == null
        ? <TrainingSession>[]
        : club.sessions
              .where((item) => item.categoryId == category.id)
              .toList();
    final plannedSessions = sessions
        .where((session) => session.status != 'completed')
        .toList();
    final matchPlans = category == null
        ? <TrainingSession>[]
        : _matchPlans.where((item) => item.categoryId == category.id).toList();
    final matchPreparations = category == null
        ? <MatchPreparation>[]
        : club.matchPreparations
            .where((item) => item.categoryId == category.id)
            .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    // Prefer the earliest prep dated today-or-later; fall back to the most
    // recently saved one so the card is never blank when there's real data.
    final today = DateTime.now().toIso8601String().substring(0, 10);
    MatchPreparation? nextPreparation;
    for (final item in matchPreparations) {
      if (item.date.isEmpty || item.date.compareTo(today) >= 0) {
        nextPreparation = item;
        break;
      }
    }
    nextPreparation ??= matchPreparations.isEmpty ? null : matchPreparations.last;
    final completedSessions = sessions
        .where((session) => session.status == 'completed')
        .toList();
    final reports = category == null
        ? <TrainingReport>[]
        : club.trainingReports
              .where((item) => item.categoryId == category.id)
              .toList();
    final uncategorizedPlayers = club.players
        .where(
          (player) =>
              player.categoryId.isEmpty ||
              !club.categories.any(
                (category) => category.id == player.categoryId,
              ),
        )
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Táctica'),
            Text(
              'Plantel y seguimiento',
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
            constraints: const BoxConstraints(maxWidth: 1120),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
              children: CanteraMotion.stagger([
                if (club.categories.isEmpty) ...[
                  const _EmptyWorkspace(),
                  if (uncategorizedPlayers.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _UncategorizedPlayersPanel(players: uncategorizedPlayers),
                  ],
                ] else ...[
                  _CategorySelector(
                    categories: club.categories,
                    selectedId: selectedId!,
                    onChanged: (value) => setState(() => _categoryId = value),
                  ),
                  if (uncategorizedPlayers.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _UncategorizedPlayersPanel(players: uncategorizedPlayers),
                  ],
                  const SizedBox(height: 12),
                  _CategoryOverview(
                    category: category!,
                    players: players,
                    sessions: sessions,
                  ),
                  const SizedBox(height: 12),
                  _CategoryReadinessPanel(
                    category: category,
                    players: players,
                    sessions: sessions,
                    onPlantel: () => _scrollTo(_squadMapKey),
                    onFocus: () => _editCategoryFocus(club, category),
                    onPlan: () => _scrollTo(_sessionsKey),
                  ),
                  const SizedBox(height: 24),
                  KeyedSubtree(
                    key: _squadMapKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: _SectionTitle(
                                'Situación del plantel',
                                'JUGADORES',
                              ),
                            ),
                            if (club.dataSource == 'manual')
                              OutlinedButton.icon(
                                onPressed: () =>
                                    _addManualPlayer(club, category),
                                icon: const Icon(
                                  Icons.person_add_alt_outlined,
                                  size: 17,
                                ),
                                label: const Text('Agregar jugador'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (players.isEmpty)
                          _ActionEmpty(
                            icon: Icons.person_add_alt_outlined,
                            title: 'Plantel pendiente',
                            description: uncategorizedPlayers.isEmpty
                                ? club.dataSource == 'manual'
                                    ? 'Agregá jugadores manualmente para usar asistencia, alineaciones y planificación.'
                                    : 'La liga todavía no devolvió jugadores vinculados a esta categoría.'
                                : 'Hay jugadores recibidos desde la liga pendientes de vincular a una categoría real.',
                            primaryLabel: club.dataSource == 'manual'
                                ? 'Agregar jugador'
                                : null,
                            onPrimary: club.dataSource == 'manual'
                                ? () => _addManualPlayer(club, category)
                                : null,
                          )
                        else ...[
                          _SquadPositionMap(
                            players: players,
                            canEdit:
                                AppScope.of(context).role != UserRole.viewer,
                            onEdit: (player) => _editPlayer(club, player),
                          ),
                          const SizedBox(height: 14),
                          _PlayerGrid(
                            players: players,
                            canEdit:
                                AppScope.of(context).role != UserRole.viewer,
                            onEdit: (player) => _editPlayer(club, player),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (matchPlans.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const _SectionTitle('Proximo partido', 'TACTICA'),
                    const SizedBox(height: 10),
                    _MatchPlanPanel(plans: matchPlans),
                  ] else if (nextPreparation != null) ...[
                    const SizedBox(height: 24),
                    const _SectionTitle('Proximo partido', 'PLAN'),
                    const SizedBox(height: 10),
                    _MatchPreparationSummaryPanel(prep: nextPreparation),
                  ],
                  KeyedSubtree(
                    key: _sessionsKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 24),
                        const _SectionTitle('Proxima sesion', 'PLANIFICACION'),
                        const SizedBox(height: 10),
                        if (plannedSessions.isEmpty)
                          _ActionEmpty(
                            icon: Icons.event_note_outlined,
                            title: 'Sin sesiones planificadas',
                            description:
                                'Usá Planificar para construir una sesión y guardarla en esta categoría.',
                            primaryLabel: 'Ir a Planificar',
                            onPrimary: () => ShellActions.maybeOf(context)
                                ?.openSection(ShellSection.planner),
                          )
                        else
                          _SessionTimeline(
                            sessions: plannedSessions,
                            canEdit:
                                AppScope.of(context).role != UserRole.viewer,
                            onChanged: (session) =>
                                _updateSession(club, session),
                          ),
                      ],
                    ),
                  ),
                  if (completedSessions.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const _SectionTitle('Sesiones completadas', 'HISTORIAL'),
                    const SizedBox(height: 10),
                    _CompletedSessionsList(
                      sessions: completedSessions,
                      canEdit: AppScope.of(context).role != UserRole.viewer,
                      onReopen: (session) => _updateSession(
                        club,
                        session.copyWith(status: 'planned'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  const _SectionTitle(
                    'Ultima lectura de campo',
                    'POST ENTRENO',
                  ),
                  const SizedBox(height: 10),
                  if (reports.isEmpty)
                    const _ActionEmpty(
                      icon: Icons.mic_none_outlined,
                      title: 'Todavía no hay registros',
                      description:
                          'Despues de entrenar, registra lo que paso para alimentar la continuidad deportiva.',
                    )
                  else
                    _ReportCard(report: reports.first),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _UncategorizedPlayersPanel extends StatelessWidget {
  final List<Player> players;

  const _UncategorizedPlayersPanel({required this.players});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFF211C12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CX.amber.withValues(alpha: .35)),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.link_off_outlined, color: CX.amber, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${players.length} jugadores pendientes de categoria',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          const Text(
            'fobal los conserva sin asignarlos automaticamente. Revisa la vinculacion de categorias en la liga para mantener planteles confiables.',
            style: TextStyle(color: CX.muted, fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 10),
          ...players
              .take(6)
              .map(
                (player) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.person_outline,
                    color: CX.amber,
                    size: 19,
                  ),
                  title: Text(player.fullName),
                  subtitle: Text(
                    [
                      player.position,
                      player.trend,
                      player.note,
                    ].where((value) => value.trim().isNotEmpty).join(' / '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: CX.muted, fontSize: 11),
                  ),
                ),
              ),
          if (players.length > 6)
            Text(
              'Y ${players.length - 6} jugadores mas pendientes.',
              style: const TextStyle(color: CX.amber, fontSize: 11),
            ),
        ],
        ),
      ),
    );
  }
}

class _CategorySelector extends StatelessWidget {
  final List<CategorySquad> categories;
  final String selectedId;
  final ValueChanged<String> onChanged;
  const _CategorySelector({
    required this.categories,
    required this.selectedId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 7),
        itemBuilder: (context, index) {
          final category = categories[index];
          final selected = category.id == selectedId;
          return ChoiceChip(
            label: Text(category.name),
            selected: selected,
            onSelected: (_) => onChanged(category.id),
            showCheckmark: false,
            avatar: Icon(
              Icons.shield_outlined,
              size: 15,
              color: selected ? CX.green : CX.faint,
            ),
            selectedColor: CX.greenDark,
            backgroundColor: CX.panel,
            side: BorderSide(
              color: selected ? CX.green.withValues(alpha: .4) : CX.line,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
            labelStyle: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: selected ? CX.white : CX.muted,
            ),
          );
        },
      ),
    );
  }
}

class _CategoryOverview extends StatelessWidget {
  final CategorySquad category;
  final List<Player> players;
  final List<TrainingSession> sessions;
  const _CategoryOverview({
    required this.category,
    required this.players,
    required this.sessions,
  });

  @override
  Widget build(BuildContext context) {
    final available = players.where((item) => item.isAvailable).length;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: CX.panelDecoration(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 680;
          final info = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: CX.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      category.name,
                      style: const TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                [
                  category.ageGroup,
                  category.coachName,
                ].where((item) => item.trim().isNotEmpty).join('  -  '),
                style: const TextStyle(color: CX.muted, fontSize: 12),
              ),
            ],
          );
          final metrics = Row(
            children: [
              Expanded(child: _CompactMetric('${players.length}', 'Plantel')),
              const SizedBox(width: 8),
              Expanded(child: _CompactMetric('$available', 'Disponibles')),
            ],
          );
          if (narrow) {
            return Column(
              children: [info, const SizedBox(height: 18), metrics],
            );
          }
          return Row(
            children: [
              Expanded(flex: 6, child: info),
              const SizedBox(width: 24),
              Expanded(flex: 4, child: metrics),
            ],
          );
        },
      ),
    );
  }
}

class _CompactMetric extends StatelessWidget {
  final String value;
  final String label;
  const _CompactMetric(this.value, this.label);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
    decoration: BoxDecoration(
      color: CX.panel2,
      borderRadius: BorderRadius.circular(7),
    ),
    child: Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
        ),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: CX.faint, fontSize: 9)),
      ],
    ),
  );
}

class _CategoryReadinessPanel extends StatelessWidget {
  final CategorySquad category;
  final List<Player> players;
  final List<TrainingSession> sessions;
  final VoidCallback onPlantel;
  final VoidCallback onFocus;
  final VoidCallback onPlan;

  const _CategoryReadinessPanel({
    required this.category,
    required this.players,
    required this.sessions,
    required this.onPlantel,
    required this.onFocus,
    required this.onPlan,
  });

  @override
  Widget build(BuildContext context) {
    final available = players.where((player) => player.isAvailable).length;
    final checks = [
      _ReadinessCheck(
        'Plantel cargado',
        players.isNotEmpty,
        players.isEmpty
            ? 'Agregar jugadores reales antes de planificar.'
            : '${players.length} jugadores vinculados.',
      ),
      _ReadinessCheck(
        'Disponibilidad',
        available >= 8,
        available >= 8
            ? '$available disponibles para tareas con oposición.'
            : 'Pocos disponibles: ajustar formato y carga.',
      ),
      _ReadinessCheck(
        'Foco semanal',
        category.currentFocus.trim().isNotEmpty,
        category.currentFocus.trim().isEmpty
            ? 'Definir objetivo de categoría.'
            : category.currentFocus,
      ),
      _ReadinessCheck(
        'Plan activo',
        sessions.isNotEmpty,
        sessions.isEmpty
            ? 'Crear una sesión en Planificar.'
            : '${sessions.length} sesiones planificadas.',
      ),
    ];
    final actions = [onPlantel, onPlantel, onFocus, onPlan];
    final readyCount = checks.where((check) => check.ready).length;

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: CX.panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fact_check_outlined, color: CX.green, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Preparación de la categoría',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
              Text(
                '$readyCount/${checks.length}',
                style: const TextStyle(
                  color: CX.green,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(
              checks.length,
              (index) => Tooltip(
                message: checks[index].detail,
                child: _ReadinessChip(checks[index], onTap: actions[index]),
              ),
            ).map((chip) => chip).toList(),
          ),
        ],
      ),
    );
  }
}

class _ReadinessChip extends StatelessWidget {
  final _ReadinessCheck check;
  final VoidCallback onTap;
  const _ReadinessChip(this.check, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = check.ready ? CX.green : CX.amber;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: .22)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              check.ready ? Icons.check_circle_outline : Icons.error_outline,
              color: color,
              size: 15,
            ),
            const SizedBox(width: 6),
            Text(
              check.label,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _SquadPositionMap extends StatelessWidget {
  final List<Player> players;
  final bool canEdit;
  final ValueChanged<Player> onEdit;

  const _SquadPositionMap({
    required this.players,
    required this.canEdit,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final groups = {
      'Arco': players.where((p) => _lineOf(p.position) == 'Arco').toList(),
      'Defensa': players
          .where((p) => _lineOf(p.position) == 'Defensa')
          .toList(),
      'Medios': players.where((p) => _lineOf(p.position) == 'Medios').toList(),
      'Ataque': players.where((p) => _lineOf(p.position) == 'Ataque').toList(),
      'Sin posicion': players
          .where((p) => _lineOf(p.position) == 'Sin posicion')
          .toList(),
    };
    final profiled = players.length - groups['Sin posicion']!.length;
    final completeness = players.isEmpty
        ? 0
        : (profiled / players.length * 100).round();
    final aiReadyPlayers = players.where(_isAiReady).length;
    final aiCompleteness = players.isEmpty
        ? 0
        : (aiReadyPlayers / players.length * 100).round();
    final incompleteAiPlayers = players
        .where((player) => !_isAiReady(player))
        .toList();
    final emptyLines = groups.entries
        .where((entry) => entry.key != 'Sin posicion' && entry.value.isEmpty)
        .map((entry) => entry.key)
        .toList();
    final diagnosisColor = completeness >= 85 && emptyLines.isEmpty
        ? CX.green
        : completeness >= 60
        ? CX.amber
        : CX.red;
    final diagnosis = groups['Sin posicion']!.isNotEmpty
        ? 'Completar ${groups['Sin posicion']!.length} posiciones principales.'
        : emptyLines.isNotEmpty
        ? 'Revisar profundidad en ${emptyLines.join(', ')}.'
        : 'Mapa balanceado para alimentar tacticas y sesiones.';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CX.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CX.green.withValues(alpha: .18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PositionBalanceHeader(
            completeness: completeness,
            aiCompleteness: aiCompleteness,
            color: diagnosisColor,
            diagnosis: diagnosis,
          ),
          if (players.any((p) => p.hasAvailabilityWarning)) ...[
            const SizedBox(height: 12),
            _AvailabilityAlerts(
              players: players.where((p) => p.hasAvailabilityWarning).toList(),
              canEdit: canEdit,
              onEdit: onEdit,
            ),
          ],
          if (groups['Sin posicion']!.isNotEmpty) ...[
            const SizedBox(height: 12),
            _MissingPositionQueue(
              players: groups['Sin posicion']!,
              canEdit: canEdit,
              onEdit: onEdit,
            ),
          ],
          if (incompleteAiPlayers.isNotEmpty &&
              groups['Sin posicion']!.isEmpty) ...[
            const SizedBox(height: 12),
            _MissingAiProfileQueue(
              players: incompleteAiPlayers,
              canEdit: canEdit,
              onEdit: onEdit,
            ),
          ],
          const SizedBox(height: 14),
          ...groups.entries.map((entry) {
            final color = entry.key == 'Sin posicion' ? CX.amber : CX.green;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 92,
                    child: Row(
                      children: [
                        Icon(_lineIcon(entry.key), color: color, size: 17),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            entry.key,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: entry.value.isEmpty
                        ? Text(
                            entry.key == 'Sin posicion'
                                ? 'Todos tienen posicion principal.'
                                : 'Sin jugadores cargados en esta linea.',
                            style: const TextStyle(
                              color: CX.faint,
                              fontSize: 11,
                            ),
                          )
                        : Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              ...entry.value
                                  .take(8)
                                  .map(
                                    (player) => _PositionPlayerChip(
                                      player: player,
                                      color: color,
                                      canEdit: canEdit,
                                      onEdit: () => onEdit(player),
                                    ),
                                  ),
                              if (entry.value.length > 8)
                                _OverflowChip(
                                  count: entry.value.length - 8,
                                  color: color,
                                ),
                            ],
                          ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  static String _lineOf(String position) {
    final text = position.toLowerCase();
    if (text.trim().isEmpty) return 'Sin posicion';
    if (text.contains('arquero') || text.contains('golero')) return 'Arco';
    if (text.contains('def') ||
        text.contains('zaguero') ||
        text.contains('lateral')) {
      return 'Defensa';
    }
    if (text.contains('vol') ||
        text.contains('medio') ||
        text.contains('interior') ||
        text.contains('enganche')) {
      return 'Medios';
    }
    if (text.contains('del') ||
        text.contains('punta') ||
        text.contains('extremo') ||
        text.contains('9')) {
      return 'Ataque';
    }
    return 'Sin posicion';
  }

  IconData _lineIcon(String line) => switch (line) {
    'Arco' => Icons.sports_handball_outlined,
    'Defensa' => Icons.shield_outlined,
    'Medios' => Icons.hub_outlined,
    'Ataque' => Icons.sports_soccer,
    _ => Icons.help_outline,
  };

  bool _isAiReady(Player player) =>
      player.position.trim().isNotEmpty &&
      player.secondaryPositions.trim().isNotEmpty &&
      player.dominantFoot.trim().isNotEmpty &&
      player.status.trim().isNotEmpty &&
      player.note.trim().length >= 12;
}

/// Short, sober list of players who aren't plain "disponible" — a heads-up
/// for the DT, never a block. Tapping a chip opens the same availability
/// editor as the squad grid below.
class _AvailabilityAlerts extends StatelessWidget {
  final List<Player> players;
  final bool canEdit;
  final ValueChanged<Player> onEdit;

  const _AvailabilityAlerts({
    required this.players,
    required this.canEdit,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: CX.amber.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CX.amber.withValues(alpha: .22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.health_and_safety_outlined, color: CX.amber, size: 17),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  players.length == 1
                      ? '1 jugador no disponible o en duda'
                      : '${players.length} jugadores no disponibles o en duda',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final player in players)
                OutlinedButton.icon(
                  onPressed: canEdit ? () => onEdit(player) : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: player.availability.color,
                    side: BorderSide(color: player.availability.color.withValues(alpha: .4)),
                  ),
                  icon: const Icon(Icons.info_outline, size: 15),
                  label: Text(
                    '${player.fullName.trim()} · ${player.availability.label}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PositionPlayerChip extends StatelessWidget {
  final Player player;
  final Color color;
  final bool canEdit;
  final VoidCallback onEdit;

  const _PositionPlayerChip({
    required this.player,
    required this.color,
    required this.canEdit,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final tooltip = [
      if (player.position.trim().isEmpty)
        'Completar posicion principal'
      else
        player.position,
      player.secondaryPositions,
      player.dominantFoot,
      player.note,
    ].where((item) => item.trim().isNotEmpty).join(' / ');
    return Tooltip(
      message: canEdit ? '$tooltip / Click para editar' : tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: canEdit ? onEdit : null,
        child: AnimatedContainer(
          duration: CX.motionFast,
          curve: CX.curve,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: .22)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canEdit) ...[
                Icon(Icons.edit_outlined, color: color, size: 12),
                const SizedBox(width: 4),
              ],
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 145),
                child: Text(
                  player.fullName.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MissingPositionQueue extends StatelessWidget {
  final List<Player> players;
  final bool canEdit;
  final ValueChanged<Player> onEdit;

  const _MissingPositionQueue({
    required this.players,
    required this.canEdit,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: CX.amber.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CX.amber.withValues(alpha: .22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.playlist_add_check, color: CX.amber, size: 17),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${players.length} perfiles pendientes',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
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
              ...players
                  .take(6)
                  .map(
                    (player) => OutlinedButton.icon(
                      onPressed: canEdit ? () => onEdit(player) : null,
                      icon: const Icon(
                        Icons.edit_location_alt_outlined,
                        size: 15,
                      ),
                      label: Text(
                        player.fullName.trim(),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
              if (players.length > 6)
                _OverflowChip(count: players.length - 6, color: CX.amber),
            ],
          ),
        ],
      ),
    );
  }
}

class _OverflowChip extends StatelessWidget {
  final int count;
  final Color color;

  const _OverflowChip({required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: CX.panel2,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: .16)),
      ),
      child: Text(
        '+$count',
        style: const TextStyle(
          color: CX.muted,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _MissingAiProfileQueue extends StatelessWidget {
  final List<Player> players;
  final bool canEdit;
  final ValueChanged<Player> onEdit;

  const _MissingAiProfileQueue({
    required this.players,
    required this.canEdit,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: CX.blue.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CX.blue.withValues(alpha: .22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.psychology_alt_outlined,
                color: CX.blue,
                size: 17,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${players.length} perfiles incompletos',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const Text(
                'roles futuros',
                style: TextStyle(
                  color: CX.faint,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              ...players
                  .take(6)
                  .map(
                    (player) => Tooltip(
                      message: _missingFields(player),
                      child: OutlinedButton.icon(
                        onPressed: canEdit ? () => onEdit(player) : null,
                        icon: const Icon(Icons.tune_outlined, size: 15),
                        label: Text(
                          player.fullName.trim(),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
              if (players.length > 6)
                _OverflowChip(count: players.length - 6, color: CX.blue),
            ],
          ),
        ],
      ),
    );
  }

  String _missingFields(Player player) {
    final fields = [
      if (player.secondaryPositions.trim().isEmpty) 'rol alternativo',
      if (player.dominantFoot.trim().isEmpty) 'pie habil',
      if (player.status.trim().isEmpty) 'estado',
      if (player.note.trim().length < 12) 'nota tecnica',
    ];
    return fields.isEmpty ? 'Perfil listo' : 'Falta: ${fields.join(', ')}';
  }
}

class _PositionBalanceHeader extends StatelessWidget {
  final int completeness;
  final int aiCompleteness;
  final Color color;
  final String diagnosis;

  const _PositionBalanceHeader({
    required this.completeness,
    required this.aiCompleteness,
    required this.color,
    required this.diagnosis,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: .2)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            height: 42,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: completeness / 100,
                  strokeWidth: 4,
                  strokeCap: StrokeCap.round,
                  backgroundColor: CX.panel3,
                  color: color,
                ),
                Text(
                  '$completeness%',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Estado de los perfiles del plantel',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  '$completeness% con posicion / $aiCompleteness% completos',
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  diagnosis,
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
      ),
    );
  }
}

class _SessionTimeline extends StatelessWidget {
  final List<TrainingSession> sessions;
  final bool canEdit;
  final ValueChanged<TrainingSession> onChanged;

  const _SessionTimeline({
    required this.sessions,
    required this.canEdit,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final ordered = [...sessions]
      ..sort((a, b) {
        final aDate = DateTime.tryParse(a.scheduledDate);
        final bDate = DateTime.tryParse(b.scheduledDate);
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return aDate.compareTo(bDate);
      });
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: CX.greenDark.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CX.green.withValues(alpha: .24)),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
        children: ordered
            .take(3)
            .map(
              (session) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _SessionTimelineItem(
                  session: session,
                  overdue: _isOverdue(session),
                  formattedDate: _formatDate(session.scheduledDate),
                  canEdit: canEdit,
                  onChanged: onChanged,
                ),
              ),
            )
            .toList(),
        ),
      ),
    );
  }

  String _formatDate(String value) {
    final date = DateTime.tryParse(value);
    if (date == null) return value;
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  bool _isOverdue(TrainingSession session) {
    final date = DateTime.tryParse(session.scheduledDate);
    if (date == null) return false;
    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    return date.isBefore(startOfToday);
  }
}

class _SessionTimelineItem extends StatelessWidget {
  final TrainingSession session;
  final bool overdue;
  final String formattedDate;
  final bool canEdit;
  final ValueChanged<TrainingSession> onChanged;

  const _SessionTimelineItem({
    required this.session,
    required this.overdue,
    required this.formattedDate,
    required this.canEdit,
    required this.onChanged,
  });

  void _showBlockAnimation(
    BuildContext context,
    TrainingSession session,
    TrainingBlock block,
  ) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        block.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ExerciseAnimationPreview(
                  scene: block.sceneOrFallback(
                    space: session.space,
                    playerCount: session.playerCount,
                  ),
                  title: '${session.title} ${block.name}',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          session.objective,
          style: const TextStyle(color: CX.muted, fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 13),
        _SessionActionHint(session: session),
        if (session.coachCues.isNotEmpty ||
            session.successIndicators.isNotEmpty ||
            session.limitations.isNotEmpty) ...[
          const SizedBox(height: 10),
          _SessionStaffBrief(session: session),
        ],
        const SizedBox(height: 13),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            _Tag('${session.duration} min'),
            _Tag(session.space),
            _Tag('${session.playerCount} jugadores'),
            if (session.scheduledDate.isNotEmpty) _Tag(formattedDate),
            _Tag(overdue ? 'Pasada' : 'Planificada'),
          ],
        ),
        if (session.blocks.isNotEmpty) ...[
          const SizedBox(height: 16),
          ...session.blocks
              .take(4)
              .map(
                (block) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        margin: const EdgeInsets.only(top: 6),
                        decoration: const BoxDecoration(
                          color: CX.green,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          '${block.name}  -  ${block.duration}\n${block.description}',
                          style: const TextStyle(fontSize: 11, height: 1.45),
                        ),
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 30),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: const Icon(Icons.animation, size: 15),
                        label: const Text(
                          'Animación',
                          style: TextStyle(fontSize: 11),
                        ),
                        onPressed: () =>
                            _showBlockAnimation(context, session, block),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ],
    );
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 8),
        initiallyExpanded: !overdue,
        leading: const Icon(
          Icons.event_note_outlined,
          color: CX.green,
          size: 18,
        ),
        title: Text(
          session.title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        subtitle: overdue
            ? Text(
                session.objective,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: CX.faint, fontSize: 11),
              )
            : null,
        trailing: canEdit
            ? PopupMenuButton<String>(
                tooltip: 'Gestionar sesion',
                icon: const Icon(Icons.more_vert, size: 20),
                onSelected: (action) async {
                  if (action == 'date') {
                    final initial =
                        DateTime.tryParse(session.scheduledDate) ??
                        DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: initial,
                      firstDate: DateTime.now().subtract(
                        const Duration(days: 30),
                      ),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      onChanged(
                        session.copyWith(
                          scheduledDate: picked
                              .toIso8601String()
                              .split('T')
                              .first,
                          status: 'planned',
                        ),
                      );
                    }
                  } else if (action == 'complete') {
                    onChanged(session.copyWith(status: 'completed'));
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'date', child: Text('Elegir fecha')),
                  PopupMenuItem(
                    value: 'complete',
                    child: Text('Marcar completada'),
                  ),
                ],
              )
            : null,
        children: [body],
      ),
    );
  }
}

class _SessionStaffBrief extends StatelessWidget {
  final TrainingSession session;

  const _SessionStaffBrief({required this.session});

  @override
  Widget build(BuildContext context) {
    final cue = session.coachCues.isEmpty ? '' : session.coachCues.first;
    final indicator = session.successIndicators.isEmpty
        ? ''
        : session.successIndicators.first;
    final limitation = session.limitations.isEmpty
        ? ''
        : session.limitations.first;
    final items = [
      if (cue.isNotEmpty)
        _StaffBriefItem(Icons.record_voice_over_outlined, 'Decir', cue),
      if (indicator.isNotEmpty)
        _StaffBriefItem(Icons.track_changes_outlined, 'Mirar', indicator),
      if (limitation.isNotEmpty)
        _StaffBriefItem(Icons.warning_amber_outlined, 'Cuidar', limitation),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: CX.panel2.withValues(alpha: .65),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CX.line),
      ),
      child: Column(
        children: items
            .map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(item.icon, color: CX.green, size: 15),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 44,
                      child: Text(
                        item.label,
                        style: const TextStyle(
                          color: CX.faint,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        item.text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: CX.muted,
                          fontSize: 10,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _StaffBriefItem {
  final IconData icon;
  final String label;
  final String text;

  const _StaffBriefItem(this.icon, this.label, this.text);
}

class _SessionActionHint extends StatelessWidget {
  final TrainingSession session;

  const _SessionActionHint({required this.session});

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(session.scheduledDate);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateOnly = date == null
        ? null
        : DateTime(date.year, date.month, date.day);
    final overdue = dateOnly != null && dateOnly.isBefore(today);
    final todaySession = dateOnly != null && dateOnly.isAtSameMomentAs(today);
    final missingDate = session.scheduledDate.trim().isEmpty || date == null;
    final color = overdue || missingDate
        ? CX.amber
        : todaySession
        ? CX.green
        : CX.blue;
    final icon = overdue
        ? Icons.update_outlined
        : missingDate
        ? Icons.event_busy_outlined
        : todaySession
        ? Icons.play_circle_outline
        : Icons.event_available_outlined;
    final title = overdue
        ? 'Reprogramar o cerrar'
        : missingDate
        ? 'Asignar fecha'
        : todaySession
        ? 'Ejecutar hoy'
        : 'Preparada';
    final detail = overdue
        ? 'Esta sesion quedo vencida; conviene marcarla completada o elegir una nueva fecha.'
        : missingDate
        ? 'Sin fecha clara, la agenda no puede ordenar prioridades del cuerpo tecnico.'
        : todaySession
        ? 'Abrir consignas y checklist antes de salir a cancha.'
        : 'La sesion esta ordenada para una fecha futura.';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: .2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 17),
          const SizedBox(width: 8),
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
                const SizedBox(height: 2),
                Text(
                  detail,
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

class _MatchPreparationSummaryPanel extends StatelessWidget {
  final MatchPreparation prep;

  const _MatchPreparationSummaryPanel({required this.prep});

  @override
  Widget build(BuildContext context) {
    final rival = prep.rival.isEmpty ? 'Rival a definir' : prep.rival;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: CX.greenDark.withValues(alpha: .36),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CX.green.withValues(alpha: .24)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.assignment_outlined, color: CX.green, size: 20),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'vs $rival',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          if (prep.planObjective.isNotEmpty) ...[
            const SizedBox(height: 9),
            Text(
              prep.planObjective,
              style: const TextStyle(color: CX.muted, fontSize: 12, height: 1.4),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              if (prep.date.isNotEmpty) _Tag(prep.date),
              if (prep.time.isNotEmpty) _Tag(prep.time),
              if (prep.venue.isNotEmpty)
                _Tag(prep.venue == 'local' ? 'Local' : 'Visitante'),
            ],
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => openMatchPreparation(
                context,
                calendarEventId: prep.calendarEventId,
                rival: prep.rival,
                date: prep.date,
                time: prep.time,
              ),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Ver panel de partido'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MatchPlanPanel extends StatelessWidget {
  final List<TrainingSession> plans;

  const _MatchPlanPanel({required this.plans});

  @override
  Widget build(BuildContext context) {
    final ordered = [...plans]
      ..sort((a, b) {
        final aDate = DateTime.tryParse(a.scheduledDate);
        final bDate = DateTime.tryParse(b.scheduledDate);
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return aDate.compareTo(bDate);
      });
    final plan = ordered.first;
    final keyBlocks = plan.blocks.take(4).toList();
    final firstCue = plan.coachCues.isEmpty ? '' : plan.coachCues.first;
    final firstIndicator = plan.successIndicators.isEmpty
        ? ''
        : plan.successIndicators.first;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: CX.greenDark.withValues(alpha: .36),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CX.green.withValues(alpha: .24)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sports_soccer, color: CX.green, size: 20),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  plan.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (plans.length > 1) _Tag('${plans.length} planes'),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            plan.objective,
            style: const TextStyle(color: CX.muted, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              if (plan.scheduledDate.isNotEmpty)
                _Tag(_formatDate(plan.scheduledDate)),
              _Tag('${plan.playerCount} jugadores'),
              if (plan.confidence.isNotEmpty)
                _Tag(_confidenceLabel(plan.confidence)),
              _Tag('${plan.operationalReadinessScore}% preparado'),
              if (plan.limitations.isNotEmpty)
                _Tag('${plan.limitations.length} alertas'),
              if (plan.contextSources.isNotEmpty)
                _Tag('${plan.contextSources.length} fuentes'),
            ],
          ),
          const SizedBox(height: 12),
          _PlanReadinessStrip(plan: plan),
          const SizedBox(height: 8),
          _PlanAuditTrail(plan: plan),
          if (firstCue.isNotEmpty || firstIndicator.isNotEmpty) ...[
            const SizedBox(height: 12),
            _MatchDayMicroBrief(
              cue: firstCue,
              indicator: firstIndicator,
              limitation: plan.limitations.isEmpty
                  ? ''
                  : plan.limitations.first,
            ),
          ],
          if (keyBlocks.isNotEmpty) ...[
            const SizedBox(height: 16),
            ...keyBlocks.map(
              (block) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(top: 6),
                      decoration: const BoxDecoration(
                        color: CX.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            block.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            block.description,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
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
              ),
            ),
          ],
          if (plan.contextSources.isNotEmpty) ...[
            const SizedBox(height: 8),
            _PlanSources(sources: plan.contextSources),
          ],
          if (plan.limitations.isNotEmpty) ...[
            const SizedBox(height: 8),
            _PlanLimitations(limitations: plan.limitations),
          ],
        ],
      ),
    );
  }

  String _formatDate(String value) {
    final date = DateTime.tryParse(value);
    if (date == null) return value;
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _confidenceLabel(String value) => switch (value) {
    'high' => 'Confianza alta',
    'medium' => 'Confianza media',
    _ => 'Confianza baja',
  };
}

class _PlanAuditTrail extends StatelessWidget {
  final TrainingSession plan;

  const _PlanAuditTrail({required this.plan});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: plan.operationalAuditItems
          .take(5)
          .map((item) => _MiniAuditPill(item))
          .toList(),
    );
  }
}

class _MiniAuditPill extends StatelessWidget {
  final String label;

  const _MiniAuditPill(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: CX.panel2.withValues(alpha: .78),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: CX.line),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: CX.muted,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _PlanReadinessStrip extends StatelessWidget {
  final TrainingSession plan;

  const _PlanReadinessStrip({required this.plan});

  @override
  Widget build(BuildContext context) {
    final hasSources = plan.contextSources.isNotEmpty;
    final hasLimitations = plan.limitations.isNotEmpty;
    final confidenceColor = switch (plan.confidence) {
      'high' => CX.green,
      'medium' => CX.amber,
      'low' => CX.red,
      _ => CX.blue,
    };
    final status = plan.confidence == 'high' && !hasLimitations
        ? plan.operationalReadinessLabel
        : hasSources
        ? plan.operationalReadinessLabel
        : 'Faltan datos del plantel';
    final detail = [
      '${plan.operationalReadinessScore}% preparado',
      if (hasSources) '${plan.contextSources.length} fuentes verificables',
      if (hasLimitations) '${plan.limitations.length} limitaciones',
      if (!hasSources) 'sin fuentes declaradas',
    ].join(' / ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: confidenceColor.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: confidenceColor.withValues(alpha: .24)),
      ),
      child: Row(
        children: [
          Icon(Icons.verified_user_outlined, color: confidenceColor, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
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

class _MatchDayMicroBrief extends StatelessWidget {
  final String cue;
  final String indicator;
  final String limitation;

  const _MatchDayMicroBrief({
    required this.cue,
    required this.indicator,
    required this.limitation,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      if (cue.isNotEmpty)
        _MicroBriefItem(Icons.record_voice_over_outlined, 'Consigna', cue),
      if (indicator.isNotEmpty)
        _MicroBriefItem(Icons.track_changes_outlined, 'Medir', indicator),
      if (limitation.isNotEmpty)
        _MicroBriefItem(Icons.warning_amber_outlined, 'Cuidar', limitation),
    ];
    return Column(
      children: items
          .map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(item.icon, color: CX.green, size: 16),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 58,
                    child: Text(
                      item.label,
                      style: const TextStyle(
                        color: CX.faint,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      item.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: CX.muted,
                        fontSize: 10,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _MicroBriefItem {
  final IconData icon;
  final String label;
  final String text;

  const _MicroBriefItem(this.icon, this.label, this.text);
}

class _PlanSources extends StatelessWidget {
  final List<String> sources;

  const _PlanSources({required this.sources});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: CX.panel2.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CX.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.fact_check_outlined, color: CX.green, size: 16),
              SizedBox(width: 7),
              Text(
                'Datos usados',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ...sources
              .take(3)
              .map(
                (source) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    source,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: CX.muted,
                      fontSize: 10,
                      height: 1.3,
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _PlanLimitations extends StatelessWidget {
  final List<String> limitations;

  const _PlanLimitations({required this.limitations});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: CX.amber.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CX.amber.withValues(alpha: .22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_outlined, color: CX.amber, size: 16),
              SizedBox(width: 7),
              Text(
                'Revisar antes de ejecutar',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ...limitations
              .take(3)
              .map(
                (limitation) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    limitation,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: CX.muted,
                      fontSize: 10,
                      height: 1.3,
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _CompletedSessionsList extends StatelessWidget {
  final List<TrainingSession> sessions;
  final bool canEdit;
  final ValueChanged<TrainingSession> onReopen;

  const _CompletedSessionsList({
    required this.sessions,
    required this.canEdit,
    required this.onReopen,
  });

  @override
  Widget build(BuildContext context) {
    final ordered = [...sessions]
      ..sort((a, b) => b.scheduledDate.compareTo(a.scheduledDate));
    return Container(
      decoration: CX.panelDecoration(),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
        children: ordered.take(4).map((session) {
          final date = DateTime.tryParse(session.scheduledDate);
          final dateLabel = date == null
              ? 'Sin fecha registrada'
              : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
          return ListTile(
            leading: const Icon(Icons.check_circle_outline, color: CX.green),
            title: Text(
              session.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '$dateLabel / ${session.duration} min',
              style: const TextStyle(color: CX.muted, fontSize: 11),
            ),
            trailing: canEdit
                ? IconButton(
                    tooltip: 'Reabrir sesion',
                    onPressed: () => onReopen(session),
                    icon: const Icon(Icons.replay_outlined, size: 20),
                  )
                : null,
          );
        }).toList(),
        ),
      ),
    );
  }
}

class _PlayerGrid extends StatelessWidget {
  final List<Player> players;
  final bool canEdit;
  final ValueChanged<Player> onEdit;

  const _PlayerGrid({
    required this.players,
    required this.canEdit,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 820
            ? 3
            : constraints.maxWidth >= 520
            ? 2
            : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: players.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 9,
            mainAxisSpacing: 9,
            childAspectRatio: columns == 1 ? 2.65 : 1.8,
          ),
          itemBuilder: (context, index) => _PlayerTile(
            player: players[index],
            canEdit: canEdit,
            onEdit: () => onEdit(players[index]),
          ),
        );
      },
    );
  }
}

class _PlayerTile extends StatelessWidget {
  final Player player;
  final bool canEdit;
  final VoidCallback onEdit;

  const _PlayerTile({
    required this.player,
    required this.canEdit,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final warning = player.hasAvailabilityWarning;
    final warningColor = player.availability.color;
    return InkWell(
      onTap: canEdit ? onEdit : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: CX.panelDecoration(
          borderColor: warning ? warningColor.withValues(alpha: .3) : null,
        ),
        child: Row(
          children: [
            InkWell(
              onTap: () => openPlayerProfile(context, player),
              borderRadius: BorderRadius.circular(7),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: warning ? warningColor.withValues(alpha: .1) : CX.panel2,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(
                  _positionIcon(player.position),
                  color: warning ? warningColor : CX.green,
                  size: 19,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    player.fullName.trim().isEmpty
                        ? 'Jugador sin nombre'
                        : player.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      player.position.isEmpty
                          ? 'Posicion pendiente'
                          : player.position,
                      player.availabilityLabel,
                    ].where((item) => item.isNotEmpty).join('  -  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: player.position.isEmpty ? CX.amber : CX.faint,
                      fontSize: 9,
                    ),
                  ),
                  if (player.secondaryPositionList.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      children: player.secondaryPositionList
                          .take(3)
                          .map(
                            (position) => ActionChip(
                              label: Text(position),
                              visualDensity: VisualDensity.compact,
                              onPressed: () =>
                                  _showPositionMatches(context, position),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
            if (canEdit)
              const Icon(Icons.edit_outlined, color: CX.faint, size: 18)
            else
              Text(
                '${(player.attendanceRate * 100).round()}%',
                style: const TextStyle(
                  color: CX.muted,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showPositionMatches(BuildContext context, String position) {
    final scope = AppScope.of(context);
    final players = scope.club.players.where((candidate) {
      final haystack = '${candidate.position} ${candidate.secondaryPositions}'
          .toLowerCase();
      return haystack.contains(position.toLowerCase());
    }).toList();
    showModalBottomSheet(
      context: context,
      backgroundColor: CX.panel,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Jugadores que pueden jugar de $position',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              if (players.isEmpty)
                Text(
                  'No hay otros jugadores marcados con ese rol.',
                  style: TextStyle(color: CX.muted),
                )
              else
                ...players
                    .take(12)
                    .map(
                      (item) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.person_outline),
                        title: Text(item.fullName.trim()),
                        subtitle: Text(
                          [
                            item.position,
                            item.secondaryPositions,
                            item.availabilityLabel,
                          ].where((v) => v.trim().isNotEmpty).join(' - '),
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _positionIcon(String value) {
    final text = value.toLowerCase();
    if (text.contains('arquero') || text.contains('golero')) {
      return Icons.sports_handball_outlined;
    }
    if (text.contains('def') ||
        text.contains('zaguero') ||
        text.contains('lat')) {
      return Icons.shield_outlined;
    }
    if (text.contains('vol') ||
        text.contains('medio') ||
        text.contains('int')) {
      return Icons.hub_outlined;
    }
    if (text.contains('del') || text.contains('punta') || text.contains('9')) {
      return Icons.sports_soccer;
    }
    return Icons.person_outline;
  }
}

class _PlayerEditDialog extends StatefulWidget {
  final Player player;

  const _PlayerEditDialog({required this.player});

  @override
  State<_PlayerEditDialog> createState() => _PlayerEditDialogState();
}

class _PlayerEditDialogState extends State<_PlayerEditDialog> {
  late final TextEditingController _position = TextEditingController(
    text: widget.player.position,
  );
  late final TextEditingController _secondary = TextEditingController(
    text: widget.player.secondaryPositions,
  );
  late final TextEditingController _foot = TextEditingController(
    text: widget.player.dominantFoot,
  );
  late final TextEditingController _status = TextEditingController(
    text: widget.player.status,
  );
  late final TextEditingController _statusDetail = TextEditingController(
    text: widget.player.statusDetail,
  );
  late final TextEditingController _suspensionDates = TextEditingController(
    text: widget.player.suspensionDates == 0
        ? ''
        : widget.player.suspensionDates.toString(),
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.player.note,
  );

  @override
  void initState() {
    super.initState();
    for (final controller in [
      _position,
      _secondary,
      _foot,
      _status,
      _statusDetail,
      _suspensionDates,
      _note,
    ]) {
      controller.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _position,
      _secondary,
      _foot,
      _status,
      _statusDetail,
      _suspensionDates,
      _note,
    ]) {
      controller.removeListener(_refresh);
    }
    _position.dispose();
    _secondary.dispose();
    _foot.dispose();
    _status.dispose();
    _statusDetail.dispose();
    _suspensionDates.dispose();
    _note.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  int get _profileScore {
    final checks = [
      _position.text.trim().isNotEmpty,
      _secondary.text.trim().isNotEmpty,
      _foot.text.trim().isNotEmpty,
      _status.text.trim().isNotEmpty,
      _note.text.trim().length >= 12,
    ];
    return (checks.where((item) => item).length / checks.length * 100).round();
  }

  List<String> get _missingFields => [
    if (_position.text.trim().isEmpty) 'posicion principal',
    if (_secondary.text.trim().isEmpty) 'rol alternativo',
    if (_foot.text.trim().isEmpty) 'pie habil',
    if (_status.text.trim().isEmpty) 'estado',
    if (_note.text.trim().length < 12) 'nota tecnica',
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.player.fullName.trim()),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PositionPresetRow(
                onSelected: (value) => setState(() => _position.text = value),
              ),
              const SizedBox(height: 10),
              _PlayerProfileQuality(
                score: _profileScore,
                missing: _missingFields,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _position,
                decoration: const InputDecoration(
                  labelText: 'Posición principal en cancha',
                  hintText: 'Ej: lateral derecho, volante central, punta',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _secondary,
                decoration: const InputDecoration(
                  labelText: 'Posiciones secundarias',
                  hintText: 'Ej: interior derecho, extremo',
                ),
              ),
              const SizedBox(height: 8),
              _SecondaryPositionPresetRow(
                selected: _secondaryValues,
                onToggle: _toggleSecondaryPosition,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _foot,
                decoration: const InputDecoration(labelText: 'Pie habil'),
              ),
              const SizedBox(height: 8),
              QuickValueRow(
                values: const ['Derecho', 'Izquierdo', 'Ambidiestro'],
                onSelected: (value) => _foot.text = value,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _status,
                decoration: const InputDecoration(
                  labelText: 'Estado',
                  hintText: 'Activo, lesionado, suspendido, baja',
                ),
              ),
              const SizedBox(height: 8),
              QuickValueRow(
                values: const [
                  'Disponible',
                  'Tocado',
                  'Lesionado',
                  'Sancionado',
                  'Ausente avisado',
                ],
                onSelected: (value) => _status.text = value,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _suspensionDates,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Fechas de suspension',
                  hintText: 'Solo si esta suspendido',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _statusDetail,
                decoration: const InputDecoration(
                  labelText: 'Detalle de disponibilidad',
                  hintText:
                      'Lesion, viaje, examen, vuelve tal dia, cuidado fisico',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _note,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Nota tecnica del jugador',
                  hintText:
                      'Perfil, virtudes, limitaciones, rol ideal o cuidados de carga',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.pop(
              context,
              widget.player.copyWith(
                position: _position.text.trim(),
                secondaryPositions: _secondary.text.trim(),
                dominantFoot: _foot.text.trim(),
                status: _status.text.trim().isEmpty
                    ? 'Activo'
                    : _status.text.trim(),
                statusDetail: _statusDetail.text.trim(),
                suspensionDates:
                    int.tryParse(_suspensionDates.text.trim()) ?? 0,
                note: _note.text.trim(),
              ),
            );
          },
          icon: const Icon(Icons.save_outlined, size: 18),
          label: const Text('Guardar perfil'),
        ),
      ],
    );
  }

  Set<String> get _secondaryValues => _secondary.text
      .split(',')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet();

  void _toggleSecondaryPosition(String value) {
    final selected = _secondaryValues;
    final existing = selected.where(
      (item) => item.toLowerCase() == value.toLowerCase(),
    );
    if (existing.isNotEmpty) {
      selected.remove(existing.first);
    } else {
      selected.add(value);
    }
    _secondary.text = selected.join(', ');
  }
}

class _SecondaryPositionPresetRow extends StatelessWidget {
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  const _SecondaryPositionPresetRow({
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    const presets = [
      'Arquero',
      'Lateral derecho',
      'Zaguero',
      'Lateral izquierdo',
      'Volante central',
      'Interior',
      'Extremo',
      'Delantero',
    ];
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: presets.map((preset) {
          final active = selected.any(
            (item) => item.toLowerCase() == preset.toLowerCase(),
          );
          return FilterChip(
            label: Text(preset),
            selected: active,
            onSelected: (_) => onToggle(preset),
            selectedColor: CX.greenDark,
            checkmarkColor: CX.green,
            backgroundColor: CX.panel2,
            side: BorderSide(color: active ? CX.green : CX.line),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _PositionPresetRow extends StatelessWidget {
  final ValueChanged<String> onSelected;

  const _PositionPresetRow({required this.onSelected});

  @override
  Widget build(BuildContext context) {
    const presets = [
      'Arquero',
      'Lateral derecho',
      'Zaguero',
      'Lateral izquierdo',
      'Volante central',
      'Interior',
      'Extremo',
      'Delantero',
    ];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: presets
          .map(
            (preset) => ActionChip(
              label: Text(preset),
              onPressed: () => onSelected(preset),
              avatar: const Icon(Icons.add, size: 15),
              backgroundColor: CX.panel2,
              side: const BorderSide(color: CX.line),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _PlayerProfileQuality extends StatelessWidget {
  final int score;
  final List<String> missing;

  const _PlayerProfileQuality({required this.score, required this.missing});

  @override
  Widget build(BuildContext context) {
    final color = score >= 80
        ? CX.green
        : score >= 50
        ? CX.amber
        : CX.red;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: .2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.psychology_alt_outlined, color: color, size: 17),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Perfil deportivo completo: $score%',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: score / 100,
              minHeight: 4,
              color: color,
              backgroundColor: CX.panel3,
            ),
          ),
          if (missing.isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(
              'Falta: ${missing.take(3).join(', ')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: CX.faint, fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final TrainingReport report;
  const _ReportCard({required this.report});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: CX.panelDecoration(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${report.attendanceCount}/${report.totalPlayers} presentes  -  ${report.date}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Text(
          report.objectiveWorked,
          style: const TextStyle(color: CX.muted, fontSize: 12),
        ),
        const SizedBox(height: 14),
        const Text(
          'SIGUIENTE DECISION',
          style: TextStyle(
            color: CX.green,
            fontSize: 9,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          report.nextRecommendation,
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
      ],
    ),
  );
}

class _EmptyWorkspace extends StatelessWidget {
  const _EmptyWorkspace();
  @override
  Widget build(BuildContext context) => const EmptyStatePanel(
    icon: Icons.account_tree_outlined,
    title: 'El campo necesita una categoría',
    message: 'Completá la estructura del club en Configuración. Cuando '
        'exista una categoría, este espacio muestra su planificación, '
        'plantel y seguimiento.',
  );
}

class _ActionEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  const _ActionEmpty({
    required this.icon,
    required this.title,
    required this.description,
    this.primaryLabel,
    this.onPrimary,
  });
  @override
  Widget build(BuildContext context) => EmptyStatePanel(
    icon: icon,
    title: title,
    message: description,
    primaryLabel: primaryLabel,
    onPrimary: onPrimary,
  );
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String eyebrow;
  const _SectionTitle(this.title, this.eyebrow);
  @override
  Widget build(BuildContext context) =>
      PremiumSectionHeader(eyebrow: eyebrow, title: title);
}

class _Tag extends StatelessWidget {
  final String text;
  const _Tag(this.text);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: CX.panel2,
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: CX.muted,
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _ReadinessCheck {
  final String label;
  final bool ready;
  final String detail;

  const _ReadinessCheck(this.label, this.ready, this.detail);
}
