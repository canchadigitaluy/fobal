import 'package:flutter/material.dart';

import '../data/cantera_data.dart';
import '../main.dart';
import '../services/club_access_service.dart';
import '../services/offline_mutation_service.dart';
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
  String? _hydratedClubId;
  bool _syncing = false;

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
      final records = await ClubAccessService.loadTacticalData(
        limit: 100,
        type: 'staff_note',
      );
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

    final writeResult =
        await OfflineMutationService.instance.saveTacticalDataOfflineFirst(
        type: 'staff_note',
        title: 'Perfil jugador ${updated.fullName.trim()}',
        content: {
          'kind': 'player_profile_update',
          'player': updated.toJson(),
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        },
        categoryId: updated.categoryId,
      );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          writeResult.synced
              ? 'Perfil del jugador guardado para futuras tacticas.'
              : 'Perfil actualizado en este dispositivo.',
        ),
      ),
    );
  }

  /// Opens the same edit dialog one player after another for everyone still
  /// missing a position, instead of making the DT hunt each one down in the
  /// list — completing 26 profiles one dialog at a time is the real friction
  /// the "Posición pendiente" tags create.
  Future<void> _completePendingPositions(
    CanteraClub club,
    List<Player> players,
  ) async {
    final pending = players.where((p) => p.position.trim().isEmpty).toList();
    for (final player in pending) {
      if (!mounted) return;
      final freshClub = AppScope.of(context).club;
      final current = freshClub.players.firstWhere(
        (item) => item.id == player.id,
        orElse: () => player,
      );
      if (current.position.trim().isNotEmpty) continue;
      await _editPlayer(freshClub, current);
    }
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

  @override
  Widget build(BuildContext context) {
    final club = AppScope.of(context).club;
    final globalCategoryId = AppScope.of(context).selectedCategoryId;
    final selectedId =
        club.categories.any((item) => item.id == globalCategoryId)
        ? globalCategoryId
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
                fontSize: 12,
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
                    _UncategorizedPlayersPanel(
                      players: uncategorizedPlayers,
                      categories: club.categories,
                      onAssign: (player, categoryId) =>
                          _assignPlayerCategory(club, player, categoryId),
                    ),
                  ],
                ] else ...[
                  if (uncategorizedPlayers.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _UncategorizedPlayersPanel(
                      players: uncategorizedPlayers,
                      categories: club.categories,
                      onAssign: (player, categoryId) =>
                          _assignPlayerCategory(club, player, categoryId),
                    ),
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
                                'Situación del plantel',
                                'JUGADORES',
                              ),
                            ),
                            Builder(
                              builder: (context) {
                                final pendingCount = players
                                    .where((p) => p.position.trim().isEmpty)
                                    .length;
                                if (pendingCount == 0) {
                                  return const SizedBox.shrink();
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: OutlinedButton.icon(
                                    onPressed: () => _completePendingPositions(
                                      club,
                                      players,
                                    ),
                                    icon: const Icon(
                                      Icons.playlist_add_check,
                                      size: 17,
                                    ),
                                    label: Text(
                                      'Completar posiciones ($pendingCount)',
                                    ),
                                  ),
                                );
                              },
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

  Future<void> _assignPlayerCategory(
    CanteraClub club,
    Player player,
    String categoryId,
  ) async {
    if (!club.categories.any((category) => category.id == categoryId)) return;
    final updated = player.copyWith(categoryId: categoryId);
    final players = [
      for (final item in club.players)
        if (item.id == updated.id) updated else item,
    ];
    final categories = [
      for (final category in club.categories)
        category.copyWith(
          playerCount: players
              .where((candidate) => candidate.categoryId == category.id)
              .length,
        ),
    ];
    AppScope.of(context).updateClub(
      club.copyWith(players: players, categories: categories),
    );
    final writeResult =
        await OfflineMutationService.instance.saveTacticalDataOfflineFirst(
      type: 'staff_note',
      title: 'Perfil jugador ${updated.fullName.trim()}',
      content: {
        'kind': 'player_profile_update',
        'player': updated.toJson(),
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      },
      categoryId: updated.categoryId,
    );
    if (!mounted) return;
    final category = club.categories.firstWhere(
      (item) => item.id == categoryId,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          writeResult.synced
              ? '${updated.fullName.trim()} asignado a ${category.name}.'
              : '${updated.fullName.trim()} asignado en este dispositivo.',
        ),
      ),
    );
  }
}

class _UncategorizedPlayersPanel extends StatelessWidget {
  final List<Player> players;
  final List<CategorySquad> categories;
  final void Function(Player player, String categoryId) onAssign;

  const _UncategorizedPlayersPanel({
    required this.players,
    required this.categories,
    required this.onAssign,
  });

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
                  trailing: categories.isEmpty
                      ? null
                      : OutlinedButton.icon(
                          onPressed: () => _showAssignDialog(context, player),
                          icon: const Icon(Icons.drive_file_move_outline, size: 16),
                          label: const Text('Asignar'),
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

  Future<void> _showAssignDialog(BuildContext context, Player player) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) {
        var value = categories.first.id;
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text(player.fullName.trim()),
            content: DropdownButtonFormField<String>(
              initialValue: value,
              decoration: const InputDecoration(labelText: 'Categoría'),
              items: [
                for (final category in categories)
                  DropdownMenuItem(
                    value: category.id,
                    child: Text(category.name),
                  ),
              ],
              onChanged: (next) => setState(() => value = next ?? value),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, value),
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Asignar'),
              ),
            ],
          ),
        );
      },
    );
    if (selected == null) return;
    onAssign(player, selected);
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
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
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: CX.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      category.name,
                      style: const TextStyle(
                        fontSize: 17,
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
        Text(label, style: const TextStyle(color: CX.faint, fontSize: 11)),
      ],
    ),
  );
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

/// Etiqueta de dato del jugador (posicion, disponibilidad, pie). Las tres
/// comparten forma, alto y tipografia; solo la disponibilidad suma un punto
/// de color, para que el estado se lea sin gritar.
class _PlayerTag extends StatelessWidget {
  final String label;
  final Color? dot;

  const _PlayerTag(this.label, {this.dot});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: CX.panel2,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot != null) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: const TextStyle(
              color: CX.muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
        ],
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
            _PlayerTag(
              player.position.trim().isEmpty
                  ? 'Posición pendiente'
                  : player.position.trim(),
            ),
            _PlayerTag(
              player.availability.label,
              dot: player.availability.color,
            ),
            if (player.dominantFoot.trim().isNotEmpty)
              _PlayerTag(player.dominantFoot.trim()),
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
                  fontSize: 11,
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
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Posición principal (tocá una)',
                  style: TextStyle(color: CX.faint, fontSize: 11),
                ),
              ),
              const SizedBox(height: 6),
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
              style: const TextStyle(color: CX.faint, fontSize: 12),
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
