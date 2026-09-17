// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:convert';
import 'dart:html' as html;
import 'dart:async';

import 'package:flutter/material.dart';

import '../data/cantera_data.dart';
import '../main.dart';
import '../services/attendance_stats_service.dart';
import '../services/club_access_service.dart';
import '../services/export_download_service.dart';
import '../services/export_text_service.dart';
import '../services/offline_mutation_service.dart';
import '../services/plantel_service.dart';
import '../state/section_handoff.dart';
import '../ui/export_preview_dialog.dart';
import '../ui/ui_kit.dart';
import 'add_player_dialog.dart';
import 'player_profile_screen.dart';

class AsistenciaScreen extends StatefulWidget {
  const AsistenciaScreen({super.key});

  @override
  State<AsistenciaScreen> createState() => _AsistenciaScreenState();
}

class _AsistenciaScreenState extends State<AsistenciaScreen> {
  final _scheduleController = TextEditingController();
  final _noteController = TextEditingController();
  final Map<String, AttendanceStatus> _statusById = {};
  DateTime _selectedDate = DateTime.now();
  String? _loadedKey;
  String _search = '';
  final Set<String> _migrationChecked = {};
  final Set<String> _remoteHydrationChecked = {};
  final Set<String> _selectedPlantelIds = {};
  bool _savedFlash = false;
  // Attendance defaults every player to presente (marking exceptions is
  // faster than marking everyone). But that means a save nobody actually
  // reviewed silently records 100% attendance. Track whether the coach
  // touched anything today and confirm before saving blind.
  bool _touchedToday = false;

  @override
  void dispose() {
    _scheduleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  AttendanceStatus _statusOf(String id) =>
      _statusById[id] ?? AttendanceStatus.ausenteSinAviso;

  DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

  String _isoDay(DateTime date) => _dateOnly(date).toIso8601String().substring(
    0,
    10,
  );

  bool get _selectedDateIsToday {
    final today = _dateOnly(DateTime.now());
    return !_dateOnly(_selectedDate).isBefore(today);
  }

  String _selectedDateLabel() {
    const weekdays = [
      'Lunes',
      'Martes',
      'Miercoles',
      'Jueves',
      'Viernes',
      'Sabado',
      'Domingo',
    ];
    final date = _dateOnly(_selectedDate);
    final day =
        '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
    final label = '${weekdays[date.weekday - 1]} $day';
    return _selectedDateIsToday ? 'Hoy · $label' : label;
  }

  void _moveSelectedDate(int days) {
    final next = _dateOnly(_selectedDate).add(Duration(days: days));
    final today = _dateOnly(DateTime.now());
    if (next.isAfter(today)) return;
    setState(() {
      _selectedDate = next;
      _loadedKey = null;
    });
  }

  void _goToToday() {
    setState(() {
      _selectedDate = DateTime.now();
      _loadedKey = null;
    });
  }

  String _key(CanteraClub club, CategorySquad category) {
    final day = _isoDay(_selectedDate);
    return 'cantera_attendance_${club.id}_${category.id}_$day';
  }

  void _load(CanteraClub club, CategorySquad category, List<Player> players) {
    final key = _key(club, category);
    if (_loadedKey == key) return;
    _loadedKey = key;
    _touchedToday = false;
    _scheduleController.text = category.practiceSchedule;
    _noteController.text = '';
    // Default: everyone present until the coach says otherwise.
    _statusById
      ..clear()
      ..addEntries(
        players.map((p) => MapEntry(p.id, AttendanceStatus.presente)),
      );
    final day = _isoDay(_selectedDate);
    AttendanceRecord? stored;
    for (final record in club.attendanceRecords) {
      if (record.categoryId == category.id && record.date == day) {
        stored = record;
        break;
      }
    }
    final remoteKey = '${club.id}|${category.id}';
    if (_remoteHydrationChecked.add(remoteKey)) {
      unawaited(_loadRemoteAttendance(club, category, players, key));
    }
    if (stored != null) {
      // Already has a real saved record for today — re-saving isn't a blind
      // first save.
      _touchedToday = true;
      _selectedPlantelIds
        ..clear()
        ..addAll(stored.plantelIds);
      _noteController.text = stored.note;
      for (final player in players) {
        _statusById[player.id] = stored.effectiveStatus(player.id);
      }
      return;
    }
    final raw = html.window.localStorage[key];
    if (raw == null || raw.isEmpty) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final present = List<String>.from(
        data['presentIds'] as List<dynamic>? ?? [],
      ).toSet();
      for (final player in players) {
        _statusById[player.id] = present.contains(player.id)
            ? AttendanceStatus.presente
            : AttendanceStatus.ausenteSinAviso;
      }
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

  Future<void> _saveAttendance(CanteraClub club, CategorySquad category) async {
    if (!_touchedToday) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('¿Todos presentes?'),
          content: const Text(
            'No marcaste ninguna ausencia hoy. Se va a guardar el plantel completo como presente.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Revisar de nuevo'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Sí, guardar'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      _touchedToday = true;
    }
    final day = _isoDay(_selectedDate);
    final rosterIds = club.players
        .where(
          (player) =>
              player.categoryId == category.id &&
              (_selectedPlantelIds.isEmpty ||
                  _selectedPlantelIds.contains(player.plantelId)),
        )
        .map((player) => player.id)
        .toList();
    final statusByPlayer = {
      for (final id in rosterIds) id: _statusOf(id),
    };
    // Merge into any existing same-day record for this category instead of
    // replacing it wholesale — saving one plantel must not wipe another
    // plantel's statuses already saved today for the same category.
    AttendanceRecord? existingToday;
    for (final existing in club.attendanceRecords) {
      if (existing.categoryId == category.id && existing.date == day) {
        existingToday = existing;
        break;
      }
    }
    final mergedStatus = {...?existingToday?.statusByPlayer, ...statusByPlayer};
    final mergedRoster = {...?existingToday?.rosterIds, ...rosterIds}.toList();
    final mergedPlantelIds = isLudCategoryId(category.id)
        ? const <String>[]
        : {
            ...?existingToday?.plantelIds,
            ..._selectedPlantelIds,
          }.toList();
    final record = AttendanceRecord(
      categoryId: category.id,
      date: day,
      plantelIds: mergedPlantelIds,
      presentIds: [
        for (final id in mergedRoster)
          if ((mergedStatus[id] ?? AttendanceStatus.ausenteSinAviso).attended)
            id,
      ],
      rosterIds: mergedRoster,
      statusByPlayer: mergedStatus,
      note: _noteController.text.trim(),
    );
    final records = [
      for (final existing in club.attendanceRecords)
        if (!(existing.categoryId == category.id && existing.date == day))
          existing,
      record,
    ];
    unawaited(
      OfflineMutationService.instance.saveTacticalDataOfflineFirst(
        type: 'attendance',
        title: 'Asistencia ${category.name}',
        content: record.toJson(),
        categoryId: category.id,
      ),
    );
    _persistAttendance(club, category, records);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Asistencia guardada.')));
    setState(() => _savedFlash = true);
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _savedFlash = false);
    });
  }

  Future<void> _loadRemoteAttendance(
    CanteraClub club,
    CategorySquad category,
    List<Player> players,
    String activeKey,
  ) async {
    try {
      final records = await ClubAccessService.loadTacticalData(
        limit: 100,
        type: 'attendance',
      );
      if (!mounted) return;
      final remoteByKey = <String, AttendanceRecord>{};
      for (final record in records) {
        if (record.type != 'attendance') continue;
        try {
          final attendance = AttendanceRecord.fromJson(record.content);
          if (attendance.categoryId == category.id &&
              attendance.date.trim().isNotEmpty) {
            remoteByKey.putIfAbsent(
              '${attendance.categoryId}|${attendance.date}',
              () => attendance,
            );
          }
        } catch (_) {}
      }
      if (remoteByKey.isEmpty) return;
      final byKey = {
        ...remoteByKey,
        for (final item in club.attendanceRecords)
          if (!remoteByKey.containsKey('${item.categoryId}|${item.date}'))
            '${item.categoryId}|${item.date}': item,
      };
      final nextRecords = byKey.values.toList();
      _persistAttendance(club, category, nextRecords);
      if (_loadedKey == activeKey) {
        _loadedKey = null;
        _load(club.copyWith(attendanceRecords: nextRecords), category, players);
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  void _persistAttendance(
    CanteraClub club,
    CategorySquad category,
    List<AttendanceRecord> records,
  ) {
    final categoryRecords = records
        .where((record) => record.categoryId == category.id)
        .toList();
    final categoryPlayerIds = club.players
        .where((player) => player.categoryId == category.id)
        .map((player) => player.id)
        .toList();
    final rates = computeAttendanceRatesFromRecords(
      records: categoryRecords,
      playerIds: categoryPlayerIds,
    );
    AppScope.of(context).updateClub(
      club.copyWith(
        attendanceRecords: records,
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

  void _migrateLegacy(CanteraClub club, CategorySquad category) {
    final migrationKey = '${club.id}|${category.id}';
    if (!_migrationChecked.add(migrationKey)) return;
    if (club.attendanceRecords.any((r) => r.categoryId == category.id)) return;
    final prefix = 'cantera_attendance_${club.id}_${category.id}_';
    final rosterIds = club.players
        .where((player) => player.categoryId == category.id)
        .map((player) => player.id)
        .toList();
    final imported = <AttendanceRecord>[];
    for (final entry in html.window.localStorage.entries) {
      if (!entry.key.startsWith(prefix)) continue;
      try {
        final data = jsonDecode(entry.value) as Map<String, dynamic>;
        final present = List<String>.from(
          data['presentIds'] as List<dynamic>? ?? const [],
        );
        final absent = List<String>.from(
          data['absentIds'] as List<dynamic>? ?? const [],
        );
        final savedRoster = <String>{...present, ...absent}.toList();
        final rawDate =
            data['date'] as String? ?? entry.key.substring(prefix.length);
        final parsedDate = DateTime.tryParse(rawDate);
        imported.add(
          AttendanceRecord(
            categoryId: category.id,
            date:
                parsedDate?.toIso8601String().substring(0, 10) ??
                entry.key.substring(prefix.length),
            presentIds: present,
            rosterIds: savedRoster.isEmpty ? rosterIds : savedRoster,
          ),
        );
      } catch (_) {}
    }
    if (imported.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _persistAttendance(club, category, [
          ...club.attendanceRecords,
          ...imported,
        ]);
      }
    });
  }

  void _shareAttendance(
    CanteraClub club,
    CategorySquad category,
    List<Player> players,
  ) {
    final present = <String>[];
    final absent = <String>[];
    for (final player in players) {
      final status = _statusOf(player.id);
      final name = status == AttendanceStatus.presente
          ? player.fullName.trim()
          : '${player.fullName.trim()} (${status.shortLabel})';
      (status.attended ? present : absent).add(name);
    }
    final today = _selectedDate;
    final dateLabel =
        '${today.day.toString().padLeft(2, '0')}/'
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Asistencia descargada: $name')));
      },
    );
  }

  void _showHistory(
    CanteraClub club,
    CategorySquad category,
    List<Player> players,
  ) {
    final records =
        club.attendanceRecords
            .where((record) => record.categoryId == category.id)
            .toList()
          ..sort(
            (a, b) => attendanceRecordDate(
              b.date,
            ).compareTo(attendanceRecordDate(a.date)),
          );
    showDialog<void>(
      context: context,
      builder: (_) => _AttendanceHistoryDialog(
        categoryName: category.name,
        records: records,
        players: players,
      ),
    );
  }

  /// Reads past saved attendance sessions from local storage for this club +
  /// category. Never fabricates: returns an empty list when nothing is stored.
  List<_PastSession> _history(CanteraClub club, CategorySquad category) {
    final selectedDay = _isoDay(_selectedDate);
    final selectedDate = _dateOnly(_selectedDate);
    final sessions = club.attendanceRecords
        .where(
          (record) =>
              record.categoryId == category.id &&
              record.date != selectedDay &&
              attendanceRecordDate(record.date).isBefore(selectedDate),
        )
        .map((record) {
          final present = <String>{};
          final absent = <String>{};
          for (final id in record.rosterIds) {
            final status = record.effectiveStatus(id);
            if (status.attended) {
              present.add(id);
            } else if (status.expected) {
              absent.add(id);
            }
          }
          return _PastSession(
            date: attendanceRecordDate(record.date),
            present: present,
            absent: absent,
          );
        })
        .toList();
    sessions.sort((a, b) => b.date.compareTo(a.date));
    return sessions.take(12).toList();
  }

  int _absenceStreak(
    String playerId,
    AttendanceStatus currentStatus,
    List<_PastSession> history,
  ) {
    if (currentStatus.attended || !currentStatus.expected) return 0;
    var streak = 1;
    for (final session in history) {
      if (session.absent.contains(playerId)) {
        streak++;
      } else if (session.present.contains(playerId)) {
        break;
      } else {
        break;
      }
    }
    return streak;
  }

  Future<void> _addPlayer(CanteraClub club, CategorySquad category) async {
    final player = await showAddPlayerDialog(
      context,
      categoryId: category.id,
      existingNames: normalizedPlayerNames(
        club.players.where((p) => p.categoryId == category.id),
      ),
      planteles: plantelesForCategory(club, category.id),
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
    setState(() => _statusById[player.id] = AttendanceStatus.presente);
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.of(context).size.width < 700;
    final scope = AppScope.of(context);
    final club = scope.club;
    final selectedCategoryId = club.categories.any(
      (category) => category.id == scope.selectedCategoryId,
    )
        ? scope.selectedCategoryId
        : club.categories.isEmpty
        ? null
        : club.categories.first.id;
    final category = selectedCategoryId == null
        ? null
        : club.categories.firstWhere(
            (category) => category.id == selectedCategoryId,
          );
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
                message:
                    'Cargá el equipo en Mi equipo y volvé acá para '
                    'registrar la asistencia de cada práctica.',
                primaryLabel: 'Ir a Mi equipo',
                onPrimary: () => ShellActions.maybeOf(
                  context,
                )?.openSection(ShellSection.myTeam),
              ),
            ),
          ),
        ),
      );
    }
    final categoryPlayers = club.players
        .where((player) => player.categoryId == category.id)
        .toList();
    final planteles = club.isManualClub
        ? plantelesForCategory(club, category.id)
        : const <Plantel>[];
    _migrateLegacy(club, category);
    _load(club, category, categoryPlayers);
    _selectedPlantelIds.removeWhere(
      (id) => !planteles.any((plantel) => plantel.id == id),
    );
    final players = rosterForSelectedPlanteles(
      categoryPlayers: categoryPlayers,
      selectedPlantelIds: _selectedPlantelIds,
    ).map((id) => categoryPlayers.firstWhere((p) => p.id == id)).toList();
    final present = players
        .where((player) => _statusOf(player.id).attended)
        .length;
    final history = _history(club, category);
    final saveLabel = _selectedDateIsToday
        ? 'Guardar asistencia de hoy'
        : 'Guardar asistencia del ${_selectedDate.day.toString().padLeft(2, '0')}/${_selectedDate.month.toString().padLeft(2, '0')}';

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
      bottomNavigationBar: categoryPlayers.isEmpty
          ? null
          : SafeArea(
              minimum: EdgeInsets.fromLTRB(
                18,
                narrow ? 6 : 8,
                18,
                narrow ? 10 : 14,
              ),
              child: ElevatedButton.icon(
                onPressed: () => _saveAttendance(club, category),
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: narrow ? 11 : 14),
                  backgroundColor: _savedFlash ? CX.green : null,
                ),
                icon: AnimatedSwitcher(
                  duration: CX.motionFast,
                  transitionBuilder: (child, animation) =>
                      ScaleTransition(scale: animation, child: child),
                  child: Icon(
                    _savedFlash
                        ? Icons.check_circle
                        : Icons.check_circle_outline,
                    key: ValueKey(_savedFlash),
                  ),
                ),
                label: Text(_savedFlash ? '¡Guardado!' : saveLabel),
              ),
            ),
      body: categoryPlayers.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: EmptyStatePanel(
                    icon: Icons.groups_2_outlined,
                    title: 'Esta categoría todavía no tiene jugadores',
                    message:
                        'Sumá el plantel en Mi equipo y después pasás '
                        'lista en segundos cada práctica.',
                    primaryLabel: 'Ir a Mi equipo',
                    onPrimary: () => ShellActions.maybeOf(
                      context,
                    )?.openSection(ShellSection.myTeam),
                  ),
                ),
              ),
            )
          : ListView(
              padding: EdgeInsets.fromLTRB(
                18,
                narrow ? 8 : 10,
                18,
                narrow ? 14 : 18,
              ),
              children: [
                _DateSelector(
                  label: _selectedDateLabel(),
                  canGoForward: !_selectedDateIsToday,
                  onPrevious: () => _moveSelectedDate(-1),
                  onNext: () => _moveSelectedDate(1),
                  onToday: _selectedDateIsToday ? null : _goToToday,
                ),
                SizedBox(height: narrow ? 9 : 12),
                if (planteles.isNotEmpty) ...[
                  PremiumSectionHeader(
                    eyebrow: 'GRUPO DE HOY',
                    title: 'Planteles convocados',
                    compact: narrow,
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilterChip(
                        label: const Text('Toda la categoría'),
                        selected: _selectedPlantelIds.isEmpty,
                        onSelected: (_) => setState(_selectedPlantelIds.clear),
                      ),
                      for (final plantel in planteles)
                        FilterChip(
                          label: Text(plantel.name),
                          selected: _selectedPlantelIds.contains(plantel.id),
                          onSelected: (selected) => setState(() {
                            if (selected) {
                              _selectedPlantelIds.add(plantel.id);
                            } else {
                              _selectedPlantelIds.remove(plantel.id);
                            }
                          }),
                        ),
                    ],
                  ),
                  SizedBox(height: narrow ? 9 : 12),
                ],
                _AttendanceSummary(
                  statuses: [for (final player in players) _statusOf(player.id)],
                  compact: narrow,
                ),
                SizedBox(height: narrow ? 9 : 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: present == players.length
                          ? null
                          : () => setState(() {
                              _touchedToday = true;
                              for (final p in players) {
                                _statusById[p.id] = AttendanceStatus.presente;
                              }
                            }),
                      icon: const Icon(Icons.done_all, size: 17),
                      label: const Text('Todos presentes'),
                    ),
                    OutlinedButton.icon(
                      onPressed: present == 0
                          ? null
                          : () => setState(() {
                              _touchedToday = true;
                              for (final p in players) {
                                _statusById[p.id] =
                                    AttendanceStatus.ausenteSinAviso;
                              }
                            }),
                      icon: const Icon(Icons.remove_done, size: 17),
                      label: const Text('Todos ausentes'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _addPlayer(club, category),
                      icon: const Icon(Icons.person_add_alt_outlined, size: 17),
                      label: const Text('Jugador'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () =>
                          _shareAttendance(club, category, players),
                      icon: const Icon(Icons.ios_share_outlined, size: 17),
                      label: const Text('Compartir'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _showHistory(club, category, players),
                      icon: const Icon(Icons.history, size: 17),
                      label: const Text('Ver historial'),
                    ),
                  ],
                ),
                SizedBox(height: narrow ? 6 : 8),
                if (players.length > 8) ...[
                  TextField(
                    onChanged: (v) => setState(() => _search = v),
                    decoration: const InputDecoration(
                      hintText: 'Buscar jugador',
                      prefixIcon: Icon(Icons.search, size: 18),
                      isDense: true,
                    ),
                  ),
                  SizedBox(height: narrow ? 6 : 8),
                ],
                Builder(
                  builder: (context) {
                    final query = _search.trim().toLowerCase();
                    final visible = query.isEmpty
                        ? players
                        : players
                              .where(
                                (p) => p.fullName.toLowerCase().contains(query),
                              )
                              .toList();
                    return Material(
                      type: MaterialType.transparency,
                      child: Container(
                        decoration: CX.panelDecoration(),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            if (query.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  8,
                                  12,
                                  0,
                                ),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Mostrando ${visible.length} de ${players.length}',
                                    style: const TextStyle(
                                      color: CX.faint,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ),
                            for (final player in visible)
                              _AttendanceRow(
                                player: player,
                                status: _statusOf(player.id),
                                absenceStreak: _absenceStreak(
                                  player.id,
                                  _statusOf(player.id),
                                  history,
                                ),
                                onChanged: (status) => setState(() {
                                  _touchedToday = true;
                                  _statusById[player.id] = status;
                                }),
                                compact: narrow,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                SizedBox(height: narrow ? 10 : 14),
                TextField(
                  controller: _noteController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Comentario de la práctica (opcional)',
                    hintText:
                        'Ej: sesión de fuerza, faltaron los del turno tarde…',
                    alignLabelWithHint: true,
                  ),
                ),
                Builder(
                  builder: (context) {
                    if (history.length < 2) return const SizedBox.shrink();
                    return Padding(
                      padding: EdgeInsets.only(top: narrow ? 14 : 20),
                      child: _AttendanceHistory(
                        history: history,
                        players: players,
                      ),
                    );
                  },
                ),
                SizedBox(height: narrow ? 14 : 20),
                PremiumSectionHeader(
                  eyebrow: 'Configuración',
                  title: 'Días y horarios de práctica',
                  compact: narrow,
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
                SizedBox(height: narrow ? 7 : 10),
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

class _DateSelector extends StatelessWidget {
  final String label;
  final bool canGoForward;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback? onToday;

  const _DateSelector({
    required this.label,
    required this.canGoForward,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: CX.panelDecoration(),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Dia anterior',
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
          ),
          TextButton(onPressed: onToday, child: const Text('Hoy')),
          IconButton(
            tooltip: 'Dia siguiente',
            onPressed: canGoForward ? onNext : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

class _AttendanceSummary extends StatelessWidget {
  final List<AttendanceStatus> statuses;
  final bool compact;
  const _AttendanceSummary({required this.statuses, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final total = statuses.length;
    final present = statuses.where((status) => status.attended).length;
    final green = statuses
        .where((status) => status == AttendanceStatus.presente)
        .length;
    final amber = statuses
        .where(
          (status) =>
              status == AttendanceStatus.tarde ||
              status == AttendanceStatus.ausenteAvisado,
        )
        .length;
    final red = statuses
        .where((status) => status == AttendanceStatus.ausenteSinAviso)
        .length;
    final absent = total - present;
    final pct = total == 0 ? 0 : (present / total * 100).round();
    final color = pct >= 80
        ? CX.green
        : pct >= 55
        ? CX.amber
        : CX.red;
    return Container(
      padding: EdgeInsets.all(compact ? 10 : 12),
      decoration: CX.panelDecoration(),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  _segment(green, total, CX.green),
                  _segment(amber, total, CX.amber),
                  _segment(red, total, CX.red),
                  _segment(total - green - amber - red, total, CX.line),
                ],
              ),
            ),
          ),
          SizedBox(height: compact ? 8 : 10),
          Row(
            children: [
              Expanded(child: _cell('$present', 'Presentes', CX.green)),
              SizedBox(width: compact ? 6 : 8),
              Expanded(
                child: _cell(
                  '$absent',
                  'Ausentes',
                  absent == 0 ? CX.faint : CX.amber,
                ),
              ),
              SizedBox(width: compact ? 6 : 8),
              Expanded(child: _cell('$pct%', 'Asistencia', color)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _segment(int value, int total, Color color) {
    if (total == 0 || value <= 0) return const SizedBox.shrink();
    return Expanded(flex: value, child: ColoredBox(color: color));
  }

  Widget _cell(String value, String label, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: compact ? 9 : 12,
        horizontal: compact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: compact ? 19 : 22,
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
  final AttendanceStatus status;
  final int absenceStreak;
  final ValueChanged<AttendanceStatus> onChanged;
  final bool compact;
  const _AttendanceRow({
    required this.player,
    required this.status,
    required this.absenceStreak,
    required this.onChanged,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final availability = player.availability;
    final color = attendanceStatusColor(status);
    final position = player.position.trim();
    final subtitle = [
      if (position.isNotEmpty) position,
      if (absenceStreak >= 2) '$absenceStreakª falta seguida',
    ].join(' · ');
    return TappableScale(
      onTap: () => onChanged(
        status.attended
            ? AttendanceStatus.ausenteSinAviso
            : AttendanceStatus.presente,
      ),
      child: Container(
        color: status.attended ? null : color.withValues(alpha: .05),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 16,
          vertical: compact ? 10 : 13,
        ),
        child: Row(
          children: [
            PopupMenuButton<AttendanceStatus>(
              tooltip: 'Cambiar estado',
              onSelected: onChanged,
              itemBuilder: (context) => [
                for (final option in AttendanceStatus.values)
                  PopupMenuItem(
                    value: option,
                    child: Row(
                      children: [
                        Icon(
                          attendanceStatusIcon(option),
                          size: 16,
                          color: attendanceStatusColor(option),
                        ),
                        const SizedBox(width: 10),
                        Text(option.label),
                      ],
                    ),
                  ),
              ],
              child: Container(
                width: compact ? 32 : 40,
                height: compact ? 32 : 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(compact ? 10 : 12),
                  border: Border.all(color: color.withValues(alpha: .30)),
                ),
                child: Icon(
                  attendanceStatusIcon(status),
                  size: compact ? 17 : 20,
                  color: color,
                ),
              ),
            ),
            SizedBox(width: compact ? 10 : 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    player.fullName.trim(),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(color: CX.muted, fontSize: 12.5),
                    ),
                  ],
                ],
              ),
            ),
            if (player.hasAvailabilityWarning) ...[
              AvailabilityChip(availability, compact: true),
              const SizedBox(width: 8),
            ],
            if (player.attendanceRate > 0) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: (player.attendanceRate < .7 ? CX.amber : CX.green)
                      .withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${(player.attendanceRate * 100).round()}%',
                  style: TextStyle(
                    color: player.attendanceRate < .7 ? CX.amber : CX.green,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
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

class _AttendanceHistoryDialog extends StatelessWidget {
  final String categoryName;
  final List<AttendanceRecord> records;
  final List<Player> players;

  const _AttendanceHistoryDialog({
    required this.categoryName,
    required this.records,
    required this.players,
  });

  @override
  Widget build(BuildContext context) {
    final summary = summarizeAttendance(records);
    final names = {
      for (final player in players) player.id: player.fullName.trim(),
    };
    return AlertDialog(
      title: Text('Historial de asistencia · $categoryName'),
      content: SizedBox(
        width: 620,
        child: records.isEmpty
            ? const EmptyStatePanel(
                icon: Icons.fact_check_outlined,
                title: 'Todavía no hay registros',
                message: 'El primer pase de lista va a aparecer acá.',
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  MetricGrid(
                    tiles: [
                      MetricTile(
                        icon: Icons.event_available_outlined,
                        value: '${summary.sessions}',
                        label: 'Prácticas',
                        context: 'con asistencia guardada',
                        accent: CX.blue,
                      ),
                      MetricTile(
                        icon: Icons.fact_check_outlined,
                        value: '${(summary.average! * 100).round()}%',
                        label: 'Promedio',
                        context: summary.trend == null
                            ? 'del período'
                            : summary.trend! >= 0
                            ? 'tendencia en mejora'
                            : 'tendencia en descenso',
                        accent: summary.average! >= .8 ? CX.green : CX.amber,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  for (final record in records)
                    _AttendanceHistoryTile(record: record, names: names),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

String _attendanceDateLabel(String value) {
  final date = attendanceRecordDate(value);
  if (date.millisecondsSinceEpoch == 0) return 'Fecha desconocida';
  return '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';
}

class _AttendanceHistoryTile extends StatelessWidget {
  final AttendanceRecord record;
  final Map<String, String> names;
  const _AttendanceHistoryTile({required this.record, required this.names});

  @override
  Widget build(BuildContext context) {
    final rate = attendanceRecordRate(record);
    final breakdown = attendanceStatusBreakdown(record);
    final attended = record.rosterIds
        .where((id) => record.effectiveStatus(id).attended)
        .length;
    final grouped = <AttendanceStatus, List<String>>{};
    for (final id in record.rosterIds) {
      grouped
          .putIfAbsent(record.effectiveStatus(id), () => [])
          .add(names[id] ?? 'Jugador no disponible');
    }
    return ExpansionTile(
      title: Text(_attendanceDateLabel(record.date)),
      subtitle: Text(
        '$attended/${record.rosterIds.length} asistieron · '
        '${rate == null ? 'Sin base' : '${(rate * 100).round()}%'}'
        '${record.note.trim().isEmpty ? '' : ' · con comentario'}',
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final status in AttendanceStatus.values)
              if ((breakdown[status] ?? 0) > 0)
                StatusPill(
                  '${status.shortLabel} ${breakdown[status]}',
                  attendanceStatusColor(status),
                  compact: true,
                ),
          ],
        ),
        const SizedBox(height: 8),
        for (final status in AttendanceStatus.values)
          if (grouped[status] != null && grouped[status]!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${status.label}: ${grouped[status]!.join(', ')}',
                  style: TextStyle(
                    color: status.attended ? CX.white : CX.muted,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ),
            ),
        if (record.note.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Comentario: ${record.note.trim()}',
              style: const TextStyle(
                color: CX.muted,
                fontSize: 12.5,
                height: 1.4,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
