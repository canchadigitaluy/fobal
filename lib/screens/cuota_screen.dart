import 'package:flutter/material.dart';

import '../data/cantera_data.dart';
import '../main.dart';
import '../services/club_access_service.dart';
import '../services/plantel_service.dart';
import '../ui/ui_kit.dart';
import 'add_player_dialog.dart';
import 'player_profile_screen.dart';

class CuotaScreen extends StatefulWidget {
  const CuotaScreen({super.key});

  @override
  State<CuotaScreen> createState() => _CuotaScreenState();
}

class _CuotaScreenState extends State<CuotaScreen> {
  final _squadMapKey = GlobalKey();
  String? _categoryId;
  String? _hydratedClubId;
  bool _syncing = false;

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
      final remoteReports = <TrainingReport>[];
      for (final record in records) {
        try {
          if (record.type == 'staff_note') {
            final report = TrainingReport.fromJson(record.content);
            if (report.categoryId.isNotEmpty && report.date.isNotEmpty) {
              remoteReports.add(report);
            }
          }
        } catch (_) {
          // Ignore an isolated legacy record without losing the club agenda.
        }
      }
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
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _syncing = false);
    }
  }

  Future<void> _editPlayer(CanteraClub club, Player player) async {
    final scope = AppScope.of(context);
    final updated = await showDialog<Player>(
      context: context,
      builder: (context) => _PlayerEditDialog(
        player: player,
        planteles: club.isManualClub
            ? plantelesForCategory(club, player.categoryId)
            : const [],
      ),
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
                  const SizedBox(height: 16),
                  KeyedSubtree(
                    key: _squadMapKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: _SectionTitle(
                                'SituaciÃ³n del plantel',
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
                                    ? 'AgregÃ¡ jugadores manualmente para usar asistencia, alineaciones y planificaciÃ³n.'
                                    : 'La liga todavÃ­a no devolviÃ³ jugadores vinculados a esta categorÃ­a.'
                                : 'Hay jugadores recibidos desde la liga pendientes de vincular a una categorÃ­a real.',
                            primaryLabel: club.dataSource == 'manual'
                                ? 'Agregar jugador'
                                : null,
                            onPrimary: club.dataSource == 'manual'
                                ? () => _addManualPlayer(club, category)
                                : null,
                          )
                        else ...[
                          _SquadHealthStrip(
                            players: players,
                            sessions: sessions,
                            canEdit:
                                AppScope.of(context).role != UserRole.viewer,
                            onFocus: () => _editCategoryFocus(club, category),
                            onEdit: (player) => _editPlayer(club, player),
                          ),
                          const SizedBox(height: 10),
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

class _SquadHealthStrip extends StatelessWidget {
  final List<Player> players;
  final List<TrainingSession> sessions;
  final bool canEdit;
  final VoidCallback onFocus;
  final ValueChanged<Player> onEdit;

  const _SquadHealthStrip({
    required this.players,
    required this.sessions,
    required this.canEdit,
    required this.onFocus,
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
    final unavailable = players.where((p) => p.hasAvailabilityWarning).toList();
    final missingPositions = groups['Sin posicion']!;
    final planned = sessions.where((session) => session.status != 'completed');

    return Container(
      decoration: CX.panelDecoration(),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          leading: Icon(Icons.health_and_safety_outlined,
              color: diagnosisColor, size: 20),
          title: Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _HealthSummaryChip(
                '$completeness% posiciones',
                diagnosisColor,
                Icons.radar_outlined,
              ),
              _HealthSummaryChip(
                unavailable.isEmpty
                    ? 'Todos disponibles'
                    : '${unavailable.length} alertas',
                unavailable.isEmpty ? CX.green : CX.amber,
                Icons.medical_information_outlined,
              ),
              _HealthSummaryChip(
                missingPositions.isEmpty
                    ? 'Sin pendientes'
                    : '${missingPositions.length} sin posicion',
                missingPositions.isEmpty ? CX.green : CX.amber,
                Icons.playlist_add_check,
              ),
              _HealthSummaryChip(
                incompleteAiPlayers.isEmpty
                    ? 'IA completa'
                    : '${incompleteAiPlayers.length} perfiles IA',
                incompleteAiPlayers.isEmpty ? CX.green : CX.blue,
                Icons.psychology_alt_outlined,
              ),
              _HealthSummaryChip(
                planned.isEmpty ? 'Sin plan activo' : '${planned.length} planes',
                planned.isEmpty ? CX.faint : CX.green,
                Icons.event_note_outlined,
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              diagnosis,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: CX.muted, fontSize: 11),
            ),
          ),
          trailing: IconButton(
            tooltip: 'Editar foco semanal',
            onPressed: onFocus,
            icon: const Icon(Icons.flag_outlined, size: 18),
          ),
          children: [
            _PositionBalanceHeader(
              completeness: completeness,
              aiCompleteness: aiCompleteness,
              color: diagnosisColor,
              diagnosis: diagnosis,
            ),
            if (unavailable.isNotEmpty) ...[
              const SizedBox(height: 10),
              _AvailabilityAlerts(
                players: unavailable,
                canEdit: canEdit,
                onEdit: onEdit,
              ),
            ],
            if (missingPositions.isNotEmpty) ...[
              const SizedBox(height: 10),
              _MissingPositionQueue(
                players: missingPositions,
                canEdit: canEdit,
                onEdit: onEdit,
              ),
            ],
            if (incompleteAiPlayers.isNotEmpty) ...[
              const SizedBox(height: 10),
              _MissingAiProfileQueue(
                players: incompleteAiPlayers,
                canEdit: canEdit,
                onEdit: onEdit,
              ),
            ],
            const SizedBox(height: 12),
            ...groups.entries.map((entry) {
              final color = entry.key == 'Sin posicion' ? CX.amber : CX.green;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 520;
                    final label = Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_lineIcon(entry.key), color: color, size: 17),
                        const SizedBox(width: 6),
                        Text(
                          entry.key,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    );
                    final chips = entry.value.isEmpty
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
                              ...entry.value.take(8).map(
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
                          );
                    if (narrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [label, const SizedBox(height: 7), chips],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 104, child: label),
                        Expanded(child: chips),
                      ],
                    );
                  },
                ),
              );
            }),
          ],
        ),
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

class _HealthSummaryChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const _HealthSummaryChip(this.label, this.color, this.icon);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
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
    return Container(
      decoration: CX.panelDecoration(),
      child: Material(
        type: MaterialType.transparency,
        child: ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: players.length,
          separatorBuilder: (_, _) => const Divider(height: 1, color: CX.line),
          itemBuilder: (context, index) => _PlayerTile(
            player: players[index],
            canEdit: canEdit,
            onEdit: () => onEdit(players[index]),
          ),
        ),
      ),
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
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        leading: InkWell(
          onTap: () => openPlayerProfile(context, player),
          borderRadius: BorderRadius.circular(7),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: warning ? warningColor.withValues(alpha: .1) : CX.panel2,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(
              _positionIcon(player.position),
              color: warning ? warningColor : CX.green,
              size: 18,
            ),
          ),
        ),
        title: Text(
          player.fullName.trim().isEmpty ? 'Jugador sin nombre' : player.fullName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
        ),
        subtitle: Wrap(
          spacing: 6,
          runSpacing: 5,
          children: [
            MetaTag(
              player.position.trim().isEmpty
                  ? 'Posicion pendiente'
                  : player.position.trim(),
            ),
            AvailabilityChip(player.availability, compact: true),
            if (player.dominantFoot.trim().isNotEmpty)
              MetaTag(player.dominantFoot.trim()),
          ],
        ),
        trailing: canEdit
            ? IconButton(
                tooltip: 'Editar jugador',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
              )
            : Text(
                '${(player.attendanceRate * 100).round()}%',
                style: const TextStyle(
                  color: CX.muted,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 620;
              final details = [
                if (player.secondaryPositionList.isNotEmpty)
                  _PlayerDetailLine(
                    icon: Icons.swap_horiz_outlined,
                    label: 'Roles',
                    child: Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      children: player.secondaryPositionList
                          .take(4)
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
                  ),
                if (player.statusDetail.trim().isNotEmpty)
                  _PlayerDetailLine(
                    icon: Icons.info_outline,
                    label: 'Estado',
                    child: Text(
                      player.statusDetail.trim(),
                      style: const TextStyle(color: CX.muted, fontSize: 11),
                    ),
                  ),
                if (player.note.trim().isNotEmpty)
                  _PlayerDetailLine(
                    icon: Icons.notes_outlined,
                    label: 'Nota',
                    child: Text(
                      player.note.trim(),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: CX.muted,
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                  ),
              ];
              if (details.isEmpty) {
                return const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Sin detalle adicional cargado.',
                    style: TextStyle(color: CX.faint, fontSize: 11),
                  ),
                );
              }
              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: details
                      .map(
                        (detail) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: detail,
                        ),
                      )
                      .toList(),
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: details
                    .map(
                      (detail) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: detail,
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
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

class _PlayerDetailLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget child;

  const _PlayerDetailLine({
    required this.icon,
    required this.label,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: CX.green, size: 15),
        const SizedBox(width: 7),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  color: CX.faint,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              child,
            ],
          ),
        ),
      ],
    );
  }
}

class _PlayerEditDialog extends StatefulWidget {
  final Player player;
  final List<Plantel> planteles;

  const _PlayerEditDialog({required this.player, required this.planteles});

  @override
  State<_PlayerEditDialog> createState() => _PlayerEditDialogState();
}

class _PlayerEditDialogState extends State<_PlayerEditDialog> {
  late String _plantelId = widget.player.plantelId;
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
              if (widget.planteles.isNotEmpty) ...[
                DropdownButtonFormField<String>(
                  initialValue: widget.planteles.any((p) => p.id == _plantelId)
                      ? _plantelId
                      : '',
                  decoration: const InputDecoration(labelText: 'Plantel'),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Sin plantel específico'),
                    ),
                    for (final plantel in widget.planteles)
                      DropdownMenuItem(
                        value: plantel.id,
                        child: Text(plantel.name),
                      ),
                  ],
                  onChanged: (value) => setState(() => _plantelId = value ?? ''),
                ),
                const SizedBox(height: 12),
              ],
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
                plantelId: _plantelId,
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
