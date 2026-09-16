// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:convert';
import 'dart:html' as html;

import 'package:flutter/material.dart';

import '../data/cantera_data.dart';
import '../main.dart';
import '../services/club_access_service.dart';
import '../services/attendance_stats_service.dart';
import '../services/export_download_service.dart';
import '../services/export_text_service.dart';
import '../services/player_profile_service.dart';
import '../state/section_handoff.dart';
import '../ui/export_preview_dialog.dart';
import '../ui/ui_kit.dart';
import 'player_availability_dialog.dart';

/// Opens the 360° profile for [player]. Safe to call from any screen inside
/// the shell — pushes a route on top, so the caller's own state is untouched.
void openPlayerProfile(BuildContext context, Player player) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => PlayerProfileScreen(playerId: player.id),
    ),
  );
}

class PlayerProfileScreen extends StatefulWidget {
  final String playerId;
  const PlayerProfileScreen({super.key, required this.playerId});

  @override
  State<PlayerProfileScreen> createState() => _PlayerProfileScreenState();
}

class _PlayerProfileScreenState extends State<PlayerProfileScreen> {
  void _updatePlayer(CanteraClub club, Player updated) {
    final scope = AppScope.of(context);
    scope.updateClub(
      club.copyWith(
        players: [
          for (final item in club.players)
            if (item.id == updated.id) updated else item,
        ],
      ),
    );
  }

  Future<void> _editAvailability(CanteraClub club, Player player) async {
    final updated = await showPlayerAvailabilityDialog(context, player: player);
    if (updated == null || !mounted) return;
    _updatePlayer(club, updated);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Disponibilidad actualizada: ${updated.availability.label}',
        ),
      ),
    );
  }

  Future<void> _editNote(CanteraClub club, Player player) async {
    final controller = TextEditingController(text: player.note);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Notas del cuerpo técnico'),
        content: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: 'Observaciones, seguimiento, contexto personal relevante',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;
    _updatePlayer(club, player.copyWith(note: result));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Notas guardadas.')));
  }

  Future<void> _addOrEditGoal(
    CanteraClub club,
    Player player, {
    PlayerGoal? existing,
  }) async {
    final result = await showDialog<PlayerGoal>(
      context: context,
      builder: (context) => _PlayerGoalDialog(existing: existing),
    );
    if (result == null || !mounted) return;
    final next = [
      result,
      ...player.developmentGoals.where((item) => item.id != result.id),
    ];
    _updatePlayer(club, player.copyWith(developmentGoals: next));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          existing == null ? 'Objetivo creado.' : 'Objetivo actualizado.',
        ),
      ),
    );
  }

  Future<void> _deleteGoal(
    CanteraClub club,
    Player player,
    PlayerGoal goal,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Borrar objetivo'),
        content: Text('Vas a borrar "${goal.title}". No se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _updatePlayer(
      club,
      player.copyWith(
        developmentGoals: player.developmentGoals
            .where((item) => item.id != goal.id)
            .toList(),
      ),
    );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Borrado: ${goal.title}')));
  }

  void _prepareSessionFocus(Player player) {
    final activeGoals = activePlayerGoals(player.developmentGoals);
    final focus = SessionFocusHandoff(
      objective: 'Trabajo individual con ${player.fullName.trim()}',
      problem: activeGoals.isEmpty
          ? 'Foco general en su desarrollo (${player.position.trim().isEmpty ? 'sin posición cargada' : player.position.trim()}).'
          : 'Objetivos activos: ${activeGoals.map((g) => g.title).join(', ')}.',
      context: player.note.trim(),
      origin: 'Perfil de ${player.fullName.trim()}',
    );
    ShellActions.of(context).openPlannerWithFocus(focus);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _shareProfile(
    CanteraClub club,
    CategorySquad category,
    Player player,
    bool reliableLeague,
    bool manualMatchStats,
  ) {
    final citations = _citationCounts(club, category, player.id);
    final content = formatPlayerProfileText(
      fullName: player.fullName,
      categoryName: category.name,
      position: player.position,
      secondaryPositions: player.secondaryPositionList,
      dominantFoot: player.dominantFoot,
      availabilityLabel: player.availability.label,
      availabilityNote: player.statusDetail,
      expectedReturnDate: player.expectedReturnDate,
      hasLeagueStats: reliableLeague,
      hasManualMatchStats: manualMatchStats,
      matchesPlayed: player.matchesPlayed,
      minutesPlayed: player.minutesPlayed,
      goalsScored: player.goals,
      assists: player.assists,
      yellowCards: player.yellowCards,
      redCards: player.redCards,
      attendanceRate: player.attendanceRate,
      citationsTotal: citations.total,
      citationsTitular: citations.titular,
      goalLines: formatPlayerGoalLines(player.developmentGoals),
      staffNote: player.note,
    );
    final fileName = buildExportFileName(
      club: club.name,
      category: category.name,
      type: 'perfil-${player.fullName}',
      extension: 'txt',
    );
    showExportPreviewDialog(
      context,
      title: 'Perfil del jugador',
      content: content,
      fileName: fileName,
      onDownload: (name, text) {
        ExportDownloadService.downloadText(name, text);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Perfil descargado: $name')));
      },
    );
  }

  /// Reads the alignment-history localStorage key alineacion_screen.dart
  /// already writes (`cantera_alignment_history_<club>_<cat>`) to count how
  /// many saved lineups cited this player — real data, never invented.
  ({int total, int titular}) _citationCounts(
    CanteraClub club,
    CategorySquad category,
    String playerId,
  ) {
    final raw = html
        .window
        .localStorage['cantera_alignment_history_${club.id}_${category.id}'];
    if (raw == null || raw.isEmpty) return (total: 0, titular: 0);
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      var total = 0;
      var titular = 0;
      for (final item in list) {
        final map = item as Map<String, dynamic>;
        final xi = List<String?>.from(map['xi'] as List<dynamic>? ?? const []);
        final subs = List<String?>.from(
          map['subs'] as List<dynamic>? ?? const [],
        );
        if (xi.contains(playerId)) {
          total++;
          titular++;
        } else if (subs.contains(playerId)) {
          total++;
        }
      }
      return (total: total, titular: titular);
    } catch (_) {
      return (total: 0, titular: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final club = scope.fullClub;
    Player? player;
    for (final item in club.players) {
      if (item.id == widget.playerId) {
        player = item;
        break;
      }
    }
    if (player == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Jugador')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: EmptyStatePanel(
              icon: Icons.person_off_outlined,
              title: 'Este jugador ya no está en el plantel',
              message: 'Puede que lo hayan borrado o movido de categoría.',
            ),
          ),
        ),
      );
    }
    final resolvedPlayer = player;
    CategorySquad? matchedCategory;
    for (final item in club.categories) {
      if (item.id == player.categoryId) {
        matchedCategory = item;
        break;
      }
    }
    final category =
        matchedCategory ??
        (club.categories.isEmpty
            ? const CategorySquad(
                id: '',
                name: 'Sin categoría',
                sport: '',
                ageGroup: '',
                coachName: '',
                playerCount: 0,
                attendanceRate: 0,
                objectives: [],
                currentFocus: '',
                lastRegistered: '',
              )
            : club.categories.first);
    final categoryIsLud = LudCategoryRef.teamIdOf(category.id) != null;
    final reliableLeague = hasReliableLeagueStats(
      categoryIsLud: categoryIsLud,
      player: resolvedPlayer,
    );
    final manualMatchStats = hasManualMatchStats(
      categoryIsLud: categoryIsLud,
      player: resolvedPlayer,
    );
    final citations = _citationCounts(club, category, resolvedPlayer.id);
    final attendanceRecords =
        club.attendanceRecords
            .where(
              (record) =>
                  record.categoryId == category.id &&
                  record.rosterIds.contains(resolvedPlayer.id),
            )
            .toList()
          ..sort(
            (a, b) => attendanceRecordDate(
              b.date,
            ).compareTo(attendanceRecordDate(a.date)),
          );
    final playerAttendance = computeAttendanceRatesFromRecords(
      records: attendanceRecords,
      playerIds: [resolvedPlayer.id],
    )[resolvedPlayer.id];

    final narrow = MediaQuery.sizeOf(context).width < 700;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          resolvedPlayer.fullName.trim().isEmpty
              ? 'Jugador'
              : resolvedPlayer.fullName,
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                narrow ? 12 : 18,
                narrow ? 8 : 12,
                narrow ? 12 : 18,
                narrow ? 20 : 30,
              ),
              children: [
                _ProfileHeader(
                  player: resolvedPlayer,
                  categoryName: category.name,
                  onEditAvailability: () =>
                      _editAvailability(club, resolvedPlayer),
                ),
                SizedBox(height: narrow ? 14 : 20),
                PremiumSectionHeader(
                  compact: narrow,
                  eyebrow: 'Rendimiento',
                  title: 'Cómo viene jugando',
                ),
                if (reliableLeague)
                  MetricGrid(
                    tiles: [
                      MetricTile(
                        icon: Icons.event_available_outlined,
                        value: '${resolvedPlayer.matchesPlayed}',
                        label: 'Partidos',
                        context: 'jugados en la liga',
                        accent: CX.blue,
                      ),
                      MetricTile(
                        icon: Icons.timer_outlined,
                        value: '${resolvedPlayer.minutesPlayed}',
                        label: 'Minutos',
                        context: 'sumados en la liga',
                        accent: CX.green,
                      ),
                      MetricTile(
                        icon: Icons.sports_soccer,
                        value: '${resolvedPlayer.goals}',
                        label: 'Goles',
                        context: '${resolvedPlayer.assists} asistencias',
                        accent: CX.amber,
                      ),
                      MetricTile(
                        icon: Icons.style_outlined,
                        value:
                            '${resolvedPlayer.yellowCards}/${resolvedPlayer.redCards}',
                        label: 'Amarillas/Rojas',
                        context: resolvedPlayer.suspensionDates > 0
                            ? '${resolvedPlayer.suspensionDates} fechas de sanción'
                            : 'sin sanción activa',
                        accent: resolvedPlayer.redCards > 0 ? CX.red : CX.muted,
                      ),
                    ],
                  )
                else if (manualMatchStats)
                  MetricGrid(
                    tiles: [
                      MetricTile(
                        icon: Icons.event_available_outlined,
                        value: '${resolvedPlayer.matchesPlayed}',
                        label: 'Partidos',
                        context: 'cargados a mano',
                        accent: CX.blue,
                      ),
                      MetricTile(
                        icon: Icons.sports_soccer,
                        value: '${resolvedPlayer.goals}',
                        label: 'Goles',
                        context: 'en resultados cargados',
                        accent: CX.amber,
                      ),
                    ],
                  )
                else
                  EmptyStatePanel(
                    icon: Icons.query_stats_outlined,
                    title: categoryIsLud
                        ? 'Todavía sin datos de liga para este jugador'
                        : 'Todavía no hay partidos cargados para este jugador',
                    message: categoryIsLud
                        ? 'La liga no publicó minutos/goles para este jugador todavía.'
                        : 'Al cargar un resultado en Estadísticas o Calendario, marcá quién jugó y quién anotó.',
                  ),
                SizedBox(height: narrow ? 14 : 20),
                PremiumSectionHeader(
                  compact: narrow,
                  eyebrow: 'Participación',
                  title: 'Asistencia y citaciones',
                ),
                MetricGrid(
                  tiles: [
                    MetricTile(
                      icon: Icons.fact_check_outlined,
                      value: playerAttendance == null
                          ? '—'
                          : '${(playerAttendance * 100).round()}%',
                      label: 'Asistencia',
                      context: playerAttendance == null
                          ? 'Sin registros'
                          : '${attendanceRecords.length} prácticas',
                      accent: CX.green,
                    ),
                    MetricTile(
                      icon: Icons.bookmark_added_outlined,
                      value: '${citations.total}',
                      label: 'Citaciones',
                      context: citations.total == 0
                          ? 'en alineaciones guardadas'
                          : '${citations.titular} como titular',
                      accent: CX.blue,
                    ),
                  ],
                ),
                if (attendanceRecords.isNotEmpty) ...[
                  SizedBox(height: narrow ? 6 : 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final record in attendanceRecords.take(8))
                        Builder(
                          builder: (context) {
                            final status = record.effectiveStatus(
                              resolvedPlayer.id,
                            );
                            return Tooltip(
                              message: '${record.date}: ${status.label}',
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: attendanceStatusColor(status),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ],
                SizedBox(height: narrow ? 14 : 20),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: narrow ? double.infinity : 430,
                      child: PremiumSectionHeader(
                        compact: narrow,
                        eyebrow: 'Plan individual',
                        title: 'Objetivos',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _addOrEditGoal(club, resolvedPlayer),
                      icon: const Icon(Icons.add, size: 17),
                      label: const Text('Nuevo objetivo'),
                    ),
                  ],
                ),
                if (resolvedPlayer.developmentGoals.isEmpty)
                  const EmptyStatePanel(
                    icon: Icons.flag_outlined,
                    title: 'Todavía no hay objetivos cargados',
                    message:
                        'Definí una meta concreta (técnica, táctica, física, mental o de conducta) y hacele seguimiento acá.',
                  )
                else
                  for (final goal in resolvedPlayer.developmentGoals)
                    _GoalTile(
                      goal: goal,
                      onEdit: () =>
                          _addOrEditGoal(club, resolvedPlayer, existing: goal),
                      onDelete: () => _deleteGoal(club, resolvedPlayer, goal),
                    ),
                SizedBox(height: narrow ? 14 : 20),
                Row(
                  children: [
                    Expanded(
                      child: PremiumSectionHeader(
                        compact: narrow,
                        eyebrow: 'Seguimiento',
                        title: 'Notas del cuerpo técnico',
                      ),
                    ),
                    IconButton(
                      tooltip: 'Editar notas',
                      onPressed: () => _editNote(club, resolvedPlayer),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                    ),
                  ],
                ),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(narrow ? 10 : 14),
                  decoration: CX.panelDecoration(),
                  child: Text(
                    resolvedPlayer.note.trim().isEmpty
                        ? 'Sin notas todavía.'
                        : resolvedPlayer.note.trim(),
                    style: TextStyle(
                      color: resolvedPlayer.note.trim().isEmpty
                          ? CX.faint
                          : CX.white,
                      height: 1.4,
                    ),
                  ),
                ),
                SizedBox(height: narrow ? 14 : 20),
                ActionStrip(
                  actions: [
                    ActionSpec(
                      label: 'Editar disponibilidad',
                      icon: Icons.health_and_safety_outlined,
                      onTap: (_) => _editAvailability(club, resolvedPlayer),
                    ),
                    ActionSpec(
                      label: 'Preparar sesión con foco en él',
                      icon: Icons.auto_awesome,
                      primary: true,
                      onTap: (_) => _prepareSessionFocus(resolvedPlayer),
                    ),
                    ActionSpec(
                      label: 'Compartir perfil',
                      icon: Icons.ios_share_outlined,
                      onTap: (_) => _shareProfile(
                        club,
                        category,
                        resolvedPlayer,
                        reliableLeague,
                        manualMatchStats,
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

class _ProfileHeader extends StatelessWidget {
  final Player player;
  final String categoryName;
  final VoidCallback onEditAvailability;

  const _ProfileHeader({
    required this.player,
    required this.categoryName,
    required this.onEditAvailability,
  });

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 700;
    final initials = [
      if (player.firstName.isNotEmpty) player.firstName[0],
      if (player.lastName.isNotEmpty) player.lastName[0],
    ].join().toUpperCase();
    return Container(
      padding: EdgeInsets.all(narrow ? 11 : 16),
      decoration: CX.panelDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Hero(
            tag: 'player-avatar-${player.id}',
            child: CircleAvatar(
              radius: narrow ? 28 : 32,
              backgroundColor: CX.greenDark,
              child: Text(
                initials.isEmpty ? '?' : initials,
                style: const TextStyle(
                  color: CX.green,
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              ),
            ),
          ),
          SizedBox(width: narrow ? 11 : 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  player.fullName.trim().isEmpty
                      ? 'Jugador sin nombre'
                      : player.fullName,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  categoryName,
                  style: const TextStyle(
                    color: CX.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: narrow ? 7 : 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (player.position.trim().isNotEmpty)
                      _tag(player.position),
                    for (final pos in player.secondaryPositionList.take(3))
                      _tag(pos),
                    if (player.dominantFoot.trim().isNotEmpty)
                      _tag('Pie ${player.dominantFoot.toLowerCase()}'),
                  ],
                ),
                SizedBox(height: narrow ? 7 : 10),
                InkWell(
                  onTap: onEditAvailability,
                  borderRadius: BorderRadius.circular(999),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AvailabilityChip(player.availability),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.edit_outlined,
                        size: 13,
                        color: CX.faint,
                      ),
                    ],
                  ),
                ),
                if (player.statusDetail.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    player.statusDetail,
                    style: const TextStyle(
                      color: CX.faint,
                      fontSize: 11.5,
                      height: 1.3,
                    ),
                  ),
                ],
                if (player.expectedReturnDate.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Regreso estimado: ${player.expectedReturnDate.trim()}',
                    style: const TextStyle(color: CX.faint, fontSize: 11.5),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tag(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: CX.panel2,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: CX.muted,
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _GoalTile extends StatelessWidget {
  final PlayerGoal goal;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _GoalTile({
    required this.goal,
    required this.onEdit,
    required this.onDelete,
  });

  Color get _statusColor => switch (goal.status) {
    PlayerGoalStatus.logrado => CX.green,
    PlayerGoalStatus.enProgreso => CX.blue,
    PlayerGoalStatus.pausado => CX.faint,
    PlayerGoalStatus.pendiente => CX.amber,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CX.panel2,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: CX.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  goal.title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _statusColor.withValues(alpha: .14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        goal.status.label,
                        style: TextStyle(
                          color: _statusColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: CX.panel,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${goal.area.label} · Prioridad ${goal.priority.label.toLowerCase()}',
                        style: const TextStyle(
                          color: CX.muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                if (goal.detail.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    goal.detail,
                    style: const TextStyle(
                      color: CX.muted,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
                if (goal.reviewDate.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Builder(
                    builder: (context) {
                      final review = goalReviewStatus(goal.reviewDate);
                      final (Color color, String prefix) = switch (review) {
                        GoalReviewStatus.overdue => (
                          CX.red,
                          'Revisión vencida',
                        ),
                        GoalReviewStatus.upcoming => (
                          CX.amber,
                          'Revisar pronto',
                        ),
                        GoalReviewStatus.none => (CX.faint, 'Revisión'),
                      };
                      return Text(
                        '$prefix: ${goal.reviewDate.trim()}',
                        style: TextStyle(
                          color: color,
                          fontSize: 10.5,
                          fontWeight: review == GoalReviewStatus.none
                              ? FontWeight.w400
                              : FontWeight.w800,
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Editar',
            visualDensity: VisualDensity.compact,
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 17, color: CX.muted),
          ),
          IconButton(
            tooltip: 'Borrar',
            visualDensity: VisualDensity.compact,
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, size: 17, color: CX.red),
          ),
        ],
      ),
    );
  }
}

class _PlayerGoalDialog extends StatefulWidget {
  final PlayerGoal? existing;
  const _PlayerGoalDialog({this.existing});

  @override
  State<_PlayerGoalDialog> createState() => _PlayerGoalDialogState();
}

class _PlayerGoalDialogState extends State<_PlayerGoalDialog> {
  late final TextEditingController _title;
  late final TextEditingController _detail;
  late final TextEditingController _reviewDate;
  late PlayerGoalArea _area;
  late PlayerGoalPriority _priority;
  late PlayerGoalStatus _status;

  @override
  void initState() {
    super.initState();
    final g = widget.existing;
    _title = TextEditingController(text: g?.title ?? '');
    _detail = TextEditingController(text: g?.detail ?? '');
    _reviewDate = TextEditingController(text: g?.reviewDate ?? '');
    _area = g?.area ?? PlayerGoalArea.tecnica;
    _priority = g?.priority ?? PlayerGoalPriority.media;
    _status = g?.status ?? PlayerGoalStatus.pendiente;
  }

  @override
  void dispose() {
    _title.dispose();
    _detail.dispose();
    _reviewDate.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    Navigator.pop(
      context,
      PlayerGoal(
        id: widget.existing?.id ?? newPlayerGoalId(),
        title: title,
        area: _area,
        detail: _detail.text.trim(),
        priority: _priority,
        status: _status,
        reviewDate: _reviewDate.text.trim(),
        createdAt:
            widget.existing?.createdAt ??
            DateTime.now().toUtc().toIso8601String(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.existing == null ? 'Nuevo objetivo' : 'Editar objetivo',
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Título'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _detail,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Detalle (opcional)',
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<PlayerGoalArea>(
                initialValue: _area,
                decoration: const InputDecoration(labelText: 'Área'),
                items: [
                  for (final area in PlayerGoalArea.values)
                    DropdownMenuItem(value: area, child: Text(area.label)),
                ],
                onChanged: (value) => setState(() => _area = value ?? _area),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<PlayerGoalPriority>(
                      initialValue: _priority,
                      decoration: const InputDecoration(labelText: 'Prioridad'),
                      items: [
                        for (final priority in PlayerGoalPriority.values)
                          DropdownMenuItem(
                            value: priority,
                            child: Text(priority.label),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _priority = value ?? _priority),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<PlayerGoalStatus>(
                      initialValue: _status,
                      decoration: const InputDecoration(labelText: 'Estado'),
                      items: [
                        for (final status in PlayerGoalStatus.values)
                          DropdownMenuItem(
                            value: status,
                            child: Text(status.label),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _status = value ?? _status),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () async {
                        final base =
                            DateTime.tryParse(_reviewDate.text.trim()) ??
                            DateTime.now().add(const Duration(days: 14));
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: base,
                          firstDate: DateTime.now().subtract(
                            const Duration(days: 30),
                          ),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (picked != null) {
                          setState(
                            () => _reviewDate.text = picked
                                .toIso8601String()
                                .split('T')
                                .first,
                          );
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Fecha de revisión (opcional)',
                          prefixIcon: Icon(Icons.event_outlined),
                        ),
                        child: Text(
                          _reviewDate.text.trim().isEmpty
                              ? 'Sin fecha'
                              : _reviewDate.text.trim(),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                  if (_reviewDate.text.trim().isNotEmpty)
                    TextButton(
                      onPressed: () => setState(() => _reviewDate.text = ''),
                      child: const Text('Quitar'),
                    ),
                ],
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
        FilledButton(onPressed: _submit, child: const Text('Guardar')),
      ],
    );
  }
}
