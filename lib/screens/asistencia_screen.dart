// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:convert';
import 'dart:html' as html;
import 'dart:async';

import 'package:flutter/material.dart';

import '../data/cantera_data.dart';
import '../main.dart';
import '../services/attendance_stats_service.dart';
import '../services/export_download_service.dart';
import '../services/export_text_service.dart';
import '../services/offline_mutation_service.dart';
import '../state/section_handoff.dart';
import '../ui/export_preview_dialog.dart';
import '../ui/ui_kit.dart';
import 'player_profile_screen.dart';

class AsistenciaScreen extends StatefulWidget {
  const AsistenciaScreen({super.key});

  @override
  State<AsistenciaScreen> createState() => _AsistenciaScreenState();
}

class _AsistenciaScreenState extends State<AsistenciaScreen> {
  final _scheduleController = TextEditingController();
  final Set<String> _presentIds = {};
  String? _loadedKey;

  @override
  void dispose() {
    _scheduleController.dispose();
    super.dispose();
  }

  String _key(CanteraClub club, CategorySquad category) {
    final day = DateTime.now().toIso8601String().substring(0, 10);
    return 'cantera_attendance_${club.id}_${category.id}_$day';
  }

  void _load(CanteraClub club, CategorySquad category, List<Player> players) {
    final key = _key(club, category);
    if (_loadedKey == key) return;
    _loadedKey = key;
    _scheduleController.text = category.practiceSchedule;
    _presentIds
      ..clear()
      ..addAll(players.map((player) => player.id));
    final raw = html.window.localStorage[key];
    if (raw == null || raw.isEmpty) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _presentIds
        ..clear()
        ..addAll(List<String>.from(data['presentIds'] as List<dynamic>? ?? []));
    } catch (_) {
      html.window.localStorage.remove(key);
    }
  }

  void _saveSchedule(CanteraClub club, CategorySquad category) {
    final scope = AppScope.of(context);
    final nextCategories = club.categories
        .map(
          (item) => item.id == category.id
              ? item.copyWith(practiceSchedule: _scheduleController.text.trim())
              : item,
        )
        .toList();
    scope.updateClub(club.copyWith(categories: nextCategories));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Horarios de práctica guardados.')),
    );
  }

  void _saveAttendance(CanteraClub club, CategorySquad category) {
    final payload = {
      'date': DateTime.now().toIso8601String(),
      'presentIds': _presentIds.toList(),
      'absentIds': club.players
          .where((player) => player.categoryId == category.id)
          .map((player) => player.id)
          .where((id) => !_presentIds.contains(id))
          .toList(),
    };
    html.window.localStorage[_key(club, category)] = jsonEncode(payload);
    unawaited(OfflineMutationService.instance.saveTacticalDataOfflineFirst(
      type: 'attendance',
      title: 'Asistencia ${category.name}',
      content: payload,
      categoryId: category.id,
    ));
    _recomputeAttendanceRates(club, category);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Asistencia guardada.')),
    );
  }

  /// Attendance taken here is the only real source of truth for
  /// manual/No-LUD categories, but it only ever landed in localStorage —
  /// player.attendanceRate (shown in the profile, Plantel, Perfil) never
  /// reflected it. LUD categories keep their rate from the league sync, so
  /// this never touches those.
  void _recomputeAttendanceRates(CanteraClub club, CategorySquad category) {
    if (isLudCategoryId(category.id)) return;
    final prefix = 'cantera_attendance_${club.id}_${category.id}_';
    final sessions = <AttendanceSession>[];
    for (final entry in html.window.localStorage.entries) {
      if (!entry.key.startsWith(prefix)) continue;
      try {
        final data = jsonDecode(entry.value) as Map<String, dynamic>;
        final present = List<String>.from(
          data['presentIds'] as List<dynamic>? ?? const [],
        );
        if (present.isEmpty) continue;
        sessions.add(AttendanceSession(presentIds: present.toSet()));
      } catch (_) {}
    }
    final categoryPlayerIds = club.players
        .where((player) => player.categoryId == category.id)
        .map((player) => player.id)
        .toList();
    final rates = computeAttendanceRates(
      sessions: sessions,
      playerIds: categoryPlayerIds,
    );
    if (rates.isEmpty) return;
    AppScope.of(context).updateClub(
      club.copyWith(
        players: [
          for (final player in club.players)
            if (rates.containsKey(player.id))
              player.copyWith(attendanceRate: rates[player.id])
            else
              player,
        ],
      ),
    );
  }

  void _shareAttendance(
    CanteraClub club,
    CategorySquad category,
    List<Player> players,
  ) {
    final present = <String>[];
    final absent = <String>[];
    for (final player in players) {
      (_presentIds.contains(player.id) ? present : absent)
          .add(player.fullName.trim());
    }
    final today = DateTime.now();
    final dateLabel = '${today.day.toString().padLeft(2, '0')}/'
        '${today.month.toString().padLeft(2, '0')}/${today.year}';
    final content = formatAttendanceText(
      categoryName: category.name,
      date: dateLabel,
      present: present,
      absent: absent,
    );
    final fileName = buildExportFileName(
      club: club.name,
      category: category.name,
      type: 'asistencia',
      extension: 'txt',
    );
    showExportPreviewDialog(
      context,
      title: 'Asistencia',
      content: content,
      fileName: fileName,
      onDownload: (name, text) {
        ExportDownloadService.downloadText(name, text);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Asistencia descargada: $name')),
        );
      },
    );
  }

  /// Reads past saved attendance sessions from local storage for this club +
  /// category. Never fabricates: returns an empty list when nothing is stored.
  List<_PastSession> _history(CanteraClub club, CategorySquad category) {
    final prefix = 'cantera_attendance_${club.id}_${category.id}_';
    final todayKey = _key(club, category);
    final sessions = <_PastSession>[];
    for (final entry in html.window.localStorage.entries) {
      if (!entry.key.startsWith(prefix) || entry.key == todayKey) continue;
      try {
        final data = jsonDecode(entry.value) as Map<String, dynamic>;
        final present = List<String>.from(
          data['presentIds'] as List<dynamic>? ?? const [],
        );
        final absent = List<String>.from(
          data['absentIds'] as List<dynamic>? ?? const [],
        );
        final date =
            DateTime.tryParse(data['date'] as String? ?? '') ??
            DateTime.tryParse(entry.key.substring(prefix.length)) ??
            DateTime(2000);
        if (present.isEmpty && absent.isEmpty) continue;
        sessions.add(_PastSession(date: date, present: present.toSet(), absent: absent.toSet()));
      } catch (_) {}
    }
    sessions.sort((a, b) => b.date.compareTo(a.date));
    return sessions.take(12).toList();
  }

  Future<void> _addPlayer(CanteraClub club, CategorySquad category) async {
    final player = await showDialog<Player>(
      context: context,
      builder: (context) => _ManualPlayerDialog(categoryId: category.id),
    );
    if (player == null) return;
    final nextPlayers = [...club.players, player];
    final nextCategories = club.categories
        .map(
          (item) => item.id == category.id
              ? item.copyWith(playerCount: nextPlayers
                    .where((candidate) => candidate.categoryId == category.id)
                    .length)
              : item,
        )
        .toList();
    AppScope.of(context).updateClub(
      club.copyWith(players: nextPlayers, categories: nextCategories),
    );
    setState(() => _presentIds.add(player.id));
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final club = scope.club;
    final category = club.categories.isEmpty ? null : club.categories.first;
    if (category == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Asistencia')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: EmptyStatePanel(
                icon: Icons.fact_check_outlined,
                title: 'Todavía no hay un plantel para pasar lista',
                message: 'Cargá el equipo en Mi equipo y volvé acá para '
                    'registrar la asistencia de cada práctica.',
                primaryLabel: 'Ir a Mi equipo',
                onPrimary: () => ShellActions.maybeOf(context)
                    ?.openSection(ShellSection.myTeam),
              ),
            ),
          ),
        ),
      );
    }
    final players = club.players
        .where((player) => player.categoryId == category.id)
        .toList();
    _load(club, category, players);
    final present = players
        .where((player) => _presentIds.contains(player.id))
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Asistencia'),
            Text(
              'Prácticas y control del plantel',
              style: TextStyle(color: CX.faint, fontSize: 10),
            ),
          ],
        ),
      ),
      body: players.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: EmptyStatePanel(
                    icon: Icons.groups_2_outlined,
                    title: 'Esta categoría todavía no tiene jugadores',
                    message: 'Sumá el plantel en Mi equipo y después pasás '
                        'lista en segundos cada práctica.',
                    primaryLabel: 'Ir a Mi equipo',
                    onPrimary: () => ShellActions.maybeOf(context)
                        ?.openSection(ShellSection.myTeam),
                  ),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 30),
              children: [
                _AttendanceSummary(present: present, total: players.length),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: present == players.length
                          ? null
                          : () => setState(() => _presentIds
                              ..clear()
                              ..addAll(players.map((p) => p.id))),
                      icon: const Icon(Icons.done_all, size: 17),
                      label: const Text('Todos presentes'),
                    ),
                    OutlinedButton.icon(
                      onPressed: present == 0
                          ? null
                          : () => setState(_presentIds.clear),
                      icon: const Icon(Icons.remove_done, size: 17),
                      label: const Text('Todos ausentes'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _addPlayer(club, category),
                      icon: const Icon(Icons.person_add_alt_outlined, size: 17),
                      label: const Text('Jugador'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _shareAttendance(club, category, players),
                      icon: const Icon(Icons.ios_share_outlined, size: 17),
                      label: const Text('Compartir'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Material(
                  type: MaterialType.transparency,
                  child: Container(
                  decoration: CX.panelDecoration(),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (final player in players)
                        _AttendanceRow(
                          player: player,
                          present: _presentIds.contains(player.id),
                          onChanged: (v) => setState(() {
                            if (v) {
                              _presentIds.add(player.id);
                            } else {
                              _presentIds.remove(player.id);
                            }
                          }),
                        ),
                    ],
                  ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _saveAttendance(club, category),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Guardar asistencia de hoy'),
                  ),
                ),
                Builder(
                  builder: (context) {
                    final history = _history(club, category);
                    if (history.length < 2) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: _AttendanceHistory(
                        history: history,
                        players: players,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),
                const PremiumSectionHeader(
                  eyebrow: 'Configuración',
                  title: 'Días y horarios de práctica',
                ),
                TextField(
                  controller: _scheduleController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'Ej: lunes y miércoles 19:30, sábado 10:00',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => _saveSchedule(club, category),
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Guardar horarios'),
                ),
              ],
            ),
    );
  }
}

class _PastSession {
  final DateTime date;
  final Set<String> present;
  final Set<String> absent;
  const _PastSession({
    required this.date,
    required this.present,
    required this.absent,
  });
}

class _AttendanceSummary extends StatelessWidget {
  final int present;
  final int total;
  const _AttendanceSummary({required this.present, required this.total});

  @override
  Widget build(BuildContext context) {
    final absent = total - present;
    final pct = total == 0 ? 0 : (present / total * 100).round();
    final color = pct >= 80
        ? CX.green
        : pct >= 55
            ? CX.amber
            : CX.red;
    return Row(
      children: [
        Expanded(child: _cell('$present', 'Presentes', CX.green)),
        const SizedBox(width: 8),
        Expanded(child: _cell('$absent', 'Ausentes', absent == 0 ? CX.faint : CX.amber)),
        const SizedBox(width: 8),
        Expanded(child: _cell('$pct%', 'Asistencia', color)),
      ],
    );
  }

  Widget _cell(String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: CX.panel,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: CX.line),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: CX.muted,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AttendanceRow extends StatelessWidget {
  final Player player;
  final bool present;
  final ValueChanged<bool> onChanged;
  const _AttendanceRow({
    required this.player,
    required this.present,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final availability = player.availability;
    return InkWell(
      onTap: () => onChanged(!present),
      child: Container(
        color: present ? null : CX.red.withValues(alpha: .05),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Icon(
              present ? Icons.check_circle : Icons.circle_outlined,
              color: present ? CX.green : CX.faint,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    player.fullName.trim(),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (player.position.trim().isNotEmpty)
                    Text(
                      player.position,
                      style: const TextStyle(color: CX.faint, fontSize: 11),
                    ),
                ],
              ),
            ),
            if (player.hasAvailabilityWarning) ...[
              AvailabilityChip(availability, compact: true),
              const SizedBox(width: 8),
            ],
            if (!present)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Text(
                  'Falta',
                  style: TextStyle(
                    color: CX.red,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            IconButton(
              tooltip: 'Ver perfil',
              visualDensity: VisualDensity.compact,
              onPressed: () => openPlayerProfile(context, player),
              icon: const Icon(Icons.person_outline, size: 18, color: CX.faint),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttendanceHistory extends StatelessWidget {
  final List<_PastSession> history;
  final List<Player> players;
  const _AttendanceHistory({required this.history, required this.players});

  @override
  Widget build(BuildContext context) {
    // Average present rate across stored sessions.
    var rateSum = 0.0;
    var counted = 0;
    for (final s in history) {
      final total = s.present.length + s.absent.length;
      if (total == 0) continue;
      rateSum += s.present.length / total;
      counted++;
    }
    final avg = counted == 0 ? 0 : (rateSum / counted * 100).round();

    // Players absent in the 2+ most recent stored sessions in a row.
    final repeated = <String>[];
    for (final p in players) {
      var streak = 0;
      for (final s in history) {
        if (s.absent.contains(p.id)) {
          streak++;
        } else if (s.present.contains(p.id)) {
          break;
        } else {
          break;
        }
      }
      if (streak >= 2) repeated.add(p.fullName.trim());
    }

    final lines = <String>[
      'Promedio $avg% en las últimas $counted prácticas guardadas.',
      if (repeated.isEmpty)
        'Nadie acumula faltas seguidas.'
      else
        'Faltas seguidas: ${repeated.take(4).join(', ')}'
            '${repeated.length > 4 ? ' y ${repeated.length - 4} más' : ''}.',
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: CX.panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history, size: 16, color: CX.green),
              const SizedBox(width: 8),
              const Text(
                'Cómo viene la asistencia',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 6, right: 9),
                    width: 4,
                    height: 4,
                    decoration: const BoxDecoration(
                      color: CX.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      line,
                      style: const TextStyle(fontSize: 12.5, height: 1.4),
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

class _ManualPlayerDialog extends StatefulWidget {
  final String categoryId;

  const _ManualPlayerDialog({required this.categoryId});

  @override
  State<_ManualPlayerDialog> createState() => _ManualPlayerDialogState();
}

class _ManualPlayerDialogState extends State<_ManualPlayerDialog> {
  final _name = TextEditingController();
  final _position = TextEditingController();
  final _secondary = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _position.dispose();
    _secondary.dispose();
    super.dispose();
  }

  void _save() {
    final fullName = _name.text.trim();
    if (fullName.length < 3) return;
    final parts = fullName.split(RegExp(r'\s+'));
    Navigator.pop(
      context,
      Player(
        id: 'manual-player-${DateTime.now().microsecondsSinceEpoch}',
        categoryId: widget.categoryId,
        firstName: parts.first,
        lastName: parts.skip(1).join(' '),
        age: 0,
        position: _position.text.trim(),
        secondaryPositions: _secondary.text.trim(),
        dominantFoot: '',
        status: 'Activo',
        attendanceRate: 0,
        trend: '',
        note: '',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Agregar jugador'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Nombre completo'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _position,
            decoration: const InputDecoration(labelText: 'Posición principal'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _secondary,
            decoration: const InputDecoration(
              labelText: 'Posiciones secundarias',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Guardar'),
        ),
      ],
    );
  }
}
