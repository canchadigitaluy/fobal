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
  bool _attendanceHandoffApplied = false;
  // Attendance defaults every player to presente (marking exceptions is
  // faster than marking everyone). But that means a save nobody actually
  // reviewed silently records 100% attendance. Track whether the coach
  // touched anything today and confirm before saving blind.
  bool _touchedToday = false;
  // Solo en pantallas angostas: 0 = Pasar lista, 1 = Historial.
  int _tab = 0;

  @override
  void dispose() {
    _scheduleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_attendanceHandoffApplied) return;
    final isoDate = ShellActions.maybeOf(context)?.takeAttendanceDate();
    if (isoDate == null) return;
    _attendanceHandoffApplied = true;
    final parsed = DateTime.tryParse(isoDate);
    if (parsed == null) return;
    final today = _dateOnly(DateTime.now());
    final target = _dateOnly(parsed);
    _selectedDate = target.isAfter(today) ? today : target;
    _loadedKey = null;
  }

  AttendanceStatus _statusOf(String id) =>
      _statusById[id] ?? AttendanceStatus.ausenteSinAviso;

  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  String _isoDay(DateTime date) =>
      _dateOnly(date).toIso8601String().substring(0, 10);

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
    final statusByPlayer = {for (final id in rosterIds) id: _statusOf(id)};
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
        : {...?existingToday?.plantelIds, ..._selectedPlantelIds}.toList();
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
    final selectedCategoryId =
        club.categories.any(
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
        ? 'Guardar asistencia · $present de ${players.length}'
        : 'Guardar asistencia del ${_selectedDate.day.toString().padLeft(2, '0')}/${_selectedDate.month.toString().padLeft(2, '0')} · $present de ${players.length}';

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Asistencia'),
            Text(
              'Prácticas y control del plantel',
              style: TextStyle(color: CX.faint, fontSize: 12),
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
                  padding: EdgeInsets.symmetric(vertical: narrow ? 13 : 15),
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
          : LayoutBuilder(
              builder: (context, box) {
                final wide = box.maxWidth >= 900;
                final pad = EdgeInsets.fromLTRB(
                  18,
                  narrow ? 8 : 10,
                  18,
                  narrow ? 14 : 18,
                );
                final roll = _rollCallItems(
                  club: club,
                  category: category,
                  players: players,
                  planteles: planteles,
                  history: history,
                  narrow: narrow,
                  showStrip: !wide,
                  present: present,
                );
                final hist = _historyItems(
                  club: club,
                  category: category,
                  categoryPlayers: categoryPlayers,
                  players: players,
                );
                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 6,
                        child: ListView(
                          padding: pad.copyWith(right: 12),
                          children: roll,
                        ),
                      ),
                      Expanded(
                        flex: 4,
                        child: ListView(
                          padding: pad.copyWith(left: 12),
                          children: hist,
                        ),
                      ),
                    ],
                  );
                }
                return ListView(
                  padding: pad,
                  children: [
                    _TabSwitch(
                      index: _tab,
                      onChanged: (value) => setState(() => _tab = value),
                    ),
                    SizedBox(height: narrow ? 9 : 12),
                    ...(_tab == 0 ? roll : hist),
                  ],
                );
              },
            ),
    );
  }

  void _openSession(DateTime date) {
    final today = _dateOnly(DateTime.now());
    final target = _dateOnly(date);
    setState(() {
      _selectedDate = target.isAfter(today) ? today : target;
      _loadedKey = null;
      _tab = 0;
    });
  }

  List<AttendanceRecord> _categoryRecords(
    CanteraClub club,
    CategorySquad category,
  ) {
    return club.attendanceRecords
        .where((record) => record.categoryId == category.id)
        .toList()
      ..sort(
        (a, b) => attendanceRecordDate(
          b.date,
        ).compareTo(attendanceRecordDate(a.date)),
      );
  }

  List<Widget> _rollCallItems({
    required CanteraClub club,
    required CategorySquad category,
    required List<Player> players,
    required List<Plantel> planteles,
    required List<_PastSession> history,
    required bool narrow,
    required bool showStrip,
    required int present,
  }) {
    final expectedNow = players
        .where((player) => _statusOf(player.id).expected)
        .length;
    final liveRate = expectedNow == 0
        ? 0
        : (present / expectedNow * 100).round();
    final query = _search.trim().toLowerCase();
    final visible = query.isEmpty
        ? players
        : players
              .where((p) => p.fullName.toLowerCase().contains(query))
              .toList();
    return [
      _DateSelector(
        label: _selectedDateLabel(),
        canGoForward: !_selectedDateIsToday,
        onPrevious: () => _moveSelectedDate(-1),
        onNext: () => _moveSelectedDate(1),
        onToday: _selectedDateIsToday ? null : _goToToday,
      ),
      SizedBox(height: narrow ? 9 : 12),
      if (showStrip) ...[
        _SessionStrip(
          records: _categoryRecords(club, category).take(5).toList(),
          selectedDay: _isoDay(_selectedDate),
          todaySelected: _selectedDateIsToday,
          todayRate: liveRate,
          onPick: _openSession,
          onToday: _goToToday,
        ),
        SizedBox(height: narrow ? 9 : 12),
      ],
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
          FilledButton.icon(
            onPressed: present == players.length
                ? null
                : () => setState(() {
                    _touchedToday = true;
                    for (final p in players) {
                      _statusById[p.id] = AttendanceStatus.presente;
                    }
                  }),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 44),
              backgroundColor: CX.green,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.done_all, size: 18),
            label: const Text('Todos presentes'),
          ),
          OutlinedButton.icon(
            onPressed: () => _addPlayer(club, category),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            icon: const Icon(Icons.person_add_alt_outlined, size: 17),
            label: const Text('Jugador'),
          ),
          OutlinedButton.icon(
            onPressed: () => _shareAttendance(club, category, players),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            icon: const Icon(Icons.ios_share_outlined, size: 17),
            label: const Text('Compartir'),
          ),
        ],
      ),
      SizedBox(height: narrow ? 8 : 10),
      if (players.length > 8) ...[
        TextField(
          onChanged: (v) => setState(() => _search = v),
          decoration: const InputDecoration(
            hintText: 'Buscar jugador',
            prefixIcon: Icon(Icons.search, size: 18),
            isDense: true,
          ),
        ),
        SizedBox(height: narrow ? 8 : 10),
      ],
      Material(
        type: MaterialType.transparency,
        child: Container(
          decoration: CX.panelDecoration(),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              if (query.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Mostrando ${visible.length} de ${players.length}',
                      style: const TextStyle(color: CX.faint, fontSize: 12),
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
      ),
      SizedBox(height: narrow ? 10 : 14),
      TextField(
        controller: _noteController,
        minLines: 2,
        maxLines: 4,
        decoration: const InputDecoration(
          labelText: 'Comentario de la práctica (opcional)',
          hintText: 'Ej: sesión de fuerza, faltaron los del turno tarde…',
          alignLabelWithHint: true,
        ),
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
    ];
  }

  /// Faltas seguidas en las prácticas más recientes (records: newest first).
  int _recordStreak(String playerId, List<AttendanceRecord> records) {
    var streak = 0;
    for (final record in records) {
      if (!record.rosterIds.contains(playerId)) break;
      final status = record.effectiveStatus(playerId);
      if (status.attended || !status.expected) break;
      streak++;
    }
    return streak;
  }

  List<Widget> _historyItems({
    required CanteraClub club,
    required CategorySquad category,
    required List<Player> categoryPlayers,
    required List<Player> players,
  }) {
    final records = _categoryRecords(club, category);
    final header = Row(
      children: [
        const Expanded(
          child: Text(
            'Historial',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
        ),
        if (records.isNotEmpty)
          TextButton(
            onPressed: () => _showHistory(club, category, players),
            child: const Text('Ver detalle'),
          ),
      ],
    );
    if (records.isEmpty) {
      return [
        header,
        const SizedBox(height: 8),
        const EmptyStatePanel(
          icon: Icons.fact_check_outlined,
          title: 'Todavía no hay prácticas guardadas',
          message: 'La primera asistencia que guardes va a aparecer acá.',
        ),
      ];
    }
    final recent = records.take(7).toList();
    final rates = [
      for (final record in recent)
        if (attendanceRecordRate(record) != null) attendanceRecordRate(record)!,
    ];
    final average = rates.isEmpty
        ? null
        : (rates.reduce((a, b) => a + b) / rates.length * 100).round();
    final best = rates.isEmpty
        ? null
        : (rates.reduce((a, b) => a > b ? a : b) * 100).round();

    final alerts = <({String name, String label, int streak})>[];
    for (final player in categoryPlayers) {
      final streak = _recordStreak(player.id, records);
      if (streak >= 2) {
        alerts.add((
          name: player.fullName.trim(),
          label: '$streak faltas seguidas',
          streak: streak,
        ));
      } else if (player.attendanceRate > 0 && player.attendanceRate < .7) {
        alerts.add((
          name: player.fullName.trim(),
          label: '${(player.attendanceRate * 100).round()}% de asistencia',
          streak: 0,
        ));
      }
    }
    alerts.sort((a, b) => b.streak.compareTo(a.streak));

    final chartRecords = recent.reversed
        .where((record) => attendanceRecordRate(record) != null)
        .toList();
    final selectedDay = _isoDay(_selectedDate);

    return [
      header,
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: _KpiTile(
              label: 'Promedio',
              value: average == null ? '—' : '$average%',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _KpiTile(
              label: 'Mejor práctica',
              value: best == null ? '—' : '$best%',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _KpiTile(
              label: 'En alerta',
              value: '${alerts.length}',
              color: alerts.isEmpty ? CX.green : _amberDark,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (chartRecords.length >= 2) ...[
        Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          decoration: CX.panelDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Últimas ${chartRecords.length} prácticas',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 150,
                width: double.infinity,
                child: CustomPaint(
                  painter: _TrendPainter(
                    rates: [
                      for (final record in chartRecords)
                        attendanceRecordRate(record)!,
                    ],
                    labels: [
                      for (final record in chartRecords)
                        () {
                          final d = attendanceRecordDate(record.date);
                          return '${d.day}/${d.month}';
                        }(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
      if (alerts.isNotEmpty) ...[
        Container(
          padding: const EdgeInsets.all(14),
          decoration: CX.panelDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Para atender esta semana',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              for (final alert in alerts.take(6))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          alert.name,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF0C7),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          alert.label,
                          style: const TextStyle(
                            color: _amberDark,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (alerts.length > 6)
                Text(
                  'y ${alerts.length - 6} más',
                  style: const TextStyle(color: CX.muted, fontSize: 12),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
      Container(
        decoration: CX.panelDecoration(),
        clipBehavior: Clip.antiAlias,
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Prácticas',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const Text(
                      'Tocá una para editarla',
                      style: TextStyle(color: CX.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              for (var i = 0; i < records.take(20).length; i++) ...[
                if (i == 0 ||
                    attendanceRecordDate(records[i].date).month !=
                        attendanceRecordDate(records[i - 1].date).month)
                  _MonthHeader(date: attendanceRecordDate(records[i].date)),
                _SessionRow(
                  record: records[i],
                  selected: records[i].date == selectedDay,
                  onTap: () =>
                      _openSession(attendanceRecordDate(records[i].date)),
                ),
              ],
            ],
          ),
        ),
      ),
    ];
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
      // Nivel 3: navegar fechas es secundario al checklist en si.
      decoration: CX.auxiliaryDecoration(),
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

const _blueFill = Color(0xFF1F5FBF);
const _redFill = Color(0xFFB42318);
const _grayFill = Color(0xFF475467);
const _amberDark = Color(0xFF93370D);

const _weekdayShort = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
const _monthNames = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

bool _isAbsentGroup(AttendanceStatus status) =>
    status == AttendanceStatus.ausenteAvisado ||
    status == AttendanceStatus.ausenteSinAviso ||
    status == AttendanceStatus.lesionado ||
    status == AttendanceStatus.permiso;

/// Pasar lista | Historial (solo en pantallas angostas; en ancho van lado a
/// lado).
class _TabSwitch extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  const _TabSwitch({required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget tab(int value, String label) {
      final selected = index == value;
      return Expanded(
        child: InkWell(
          onTap: () => onChanged(value),
          borderRadius: BorderRadius.circular(9),
          child: AnimatedContainer(
            duration: CX.motionFast,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? CX.panel : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              boxShadow: selected
                  ? const [
                      BoxShadow(
                        color: Color(0x1A0D1A14),
                        blurRadius: 3,
                        offset: Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              label,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                color: selected ? CX.white : CX.muted,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: CX.panel3,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [tab(0, 'Pasar lista'), tab(1, 'Historial')]),
    );
  }
}

/// Últimas prácticas guardadas como chips (día + %), para saltar a una
/// práctica pasada y editarla; "Hoy" vuelve a la lista de hoy.
class _SessionStrip extends StatelessWidget {
  final List<AttendanceRecord> records; // newest first
  final String selectedDay;
  final bool todaySelected;
  final int todayRate;
  final ValueChanged<DateTime> onPick;
  final VoidCallback onToday;

  const _SessionStrip({
    required this.records,
    required this.selectedDay,
    required this.todaySelected,
    required this.todayRate,
    required this.onPick,
    required this.onToday,
  });

  @override
  Widget build(BuildContext context) {
    Widget chip({
      required String top,
      required String bottom,
      required bool selected,
      required VoidCallback onTap,
      double width = 66,
    }) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: width,
          height: 60,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? CX.white : CX.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? CX.white : CX.line),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                top.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white70 : CX.muted,
                ),
              ),
              Text(
                bottom,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: selected ? Colors.white : CX.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final ordered = records.reversed.toList();
    return SizedBox(
      height: 60,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final record in ordered) ...[
            () {
              final date = attendanceRecordDate(record.date);
              final rate = attendanceRecordRate(record);
              return chip(
                top: '${_weekdayShort[date.weekday - 1]} ${date.day}',
                bottom: rate == null ? '—' : '${(rate * 100).round()}%',
                selected: record.date == selectedDay && !todaySelected,
                onTap: () => onPick(date),
              );
            }(),
            const SizedBox(width: 8),
          ],
          chip(
            top: 'Hoy',
            bottom: '$todayRate%',
            selected: todaySelected,
            onTap: onToday,
            width: 76,
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
    final presentes = statuses
        .where((s) => s == AttendanceStatus.presente)
        .length;
    final tarde = statuses.where((s) => s == AttendanceStatus.tarde).length;
    final excused = statuses
        .where(
          (s) =>
              s == AttendanceStatus.lesionado || s == AttendanceStatus.permiso,
        )
        .length;
    final ausentes = total - presentes - tarde - excused;
    final expected = total - excused;
    final attended = presentes + tarde;
    final pct = expected == 0 ? 0 : (attended / expected * 100).round();
    Widget stat(String value, String label, Color color) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: CX.muted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
    final stats = [
      stat('$presentes', 'Presentes', CX.green),
      stat('$tarde', 'Tarde', _blueFill),
      stat('$ausentes', 'Ausentes', _redFill),
      stat('$excused', 'Lesión / permiso', _grayFill),
    ];
    return Container(
      padding: EdgeInsets.all(compact ? 14 : 18),
      decoration: CX.panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$pct%',
                style: TextStyle(
                  fontSize: compact ? 32 : 40,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  color: CX.white,
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '$attended de $expected esperados',
                  style: const TextStyle(
                    color: CX.muted,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  _segment(presentes, total, CX.green),
                  _segment(tarde, total, _blueFill),
                  _segment(ausentes, total, _redFill),
                  _segment(excused, total, _grayFill),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: stats,
          ),
        ],
      ),
    );
  }

  Widget _segment(int value, int total, Color color) {
    if (total == 0 || value <= 0) return const SizedBox.shrink();
    return Expanded(
      flex: value,
      child: Padding(
        padding: const EdgeInsets.only(right: 2),
        child: ColoredBox(color: color),
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

  String get _initials {
    final parts = player.fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    return parts.take(2).map((part) => part[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    final position = player.position.trim();
    final rate = player.attendanceRate > 0
        ? '${(player.attendanceRate * 100).round()}% asistencia'
        : null;
    final meta = [if (position.isNotEmpty) position, ?rate].join(' · ');
    final (avatarBg, avatarFg) = status == AttendanceStatus.presente
        ? (CX.greenDark, const Color(0xFF075C3A))
        : status == AttendanceStatus.tarde
        ? (const Color(0xFFE3ECFA), const Color(0xFF173F86))
        : (const Color(0xFFFBE7E5), const Color(0xFF912018));
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0x140D1A14))),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 16,
        vertical: compact ? 8 : 10,
      ),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, box) {
              final labels = box.maxWidth >= 520;
              return Row(
                children: [
                  InkWell(
                    onTap: () => openPlayerProfile(context, player),
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: avatarBg,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        _initials,
                        style: TextStyle(
                          color: avatarFg,
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          player.fullName.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Wrap(
                          spacing: 6,
                          runSpacing: 2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (meta.isNotEmpty)
                              Text(
                                meta,
                                style: const TextStyle(
                                  color: CX.muted,
                                  fontSize: 12.5,
                                ),
                              ),
                            if (absenceStreak >= 2)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF0C7),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '$absenceStreak faltas seguidas',
                                  style: const TextStyle(
                                    color: _amberDark,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            if (player.hasAvailabilityWarning)
                              AvailabilityChip(
                                player.availability,
                                compact: true,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _StatusSegment(
                    status: status,
                    showLabels: labels,
                    onChanged: onChanged,
                  ),
                ],
              );
            },
          ),
          if (_isAbsentGroup(status))
            Padding(
              padding: const EdgeInsets.only(left: 52, top: 8, bottom: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text(
                      'Motivo',
                      style: TextStyle(
                        color: CX.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    _ReasonChip(
                      label: 'Con aviso',
                      color: _amberDark,
                      selected: status == AttendanceStatus.ausenteAvisado,
                      onTap: () => onChanged(AttendanceStatus.ausenteAvisado),
                    ),
                    _ReasonChip(
                      label: 'Sin aviso',
                      color: _redFill,
                      selected: status == AttendanceStatus.ausenteSinAviso,
                      onTap: () => onChanged(AttendanceStatus.ausenteSinAviso),
                    ),
                    _ReasonChip(
                      label: 'Lesión',
                      color: _grayFill,
                      selected: status == AttendanceStatus.lesionado,
                      onTap: () => onChanged(AttendanceStatus.lesionado),
                    ),
                    _ReasonChip(
                      label: 'Permiso',
                      color: _grayFill,
                      selected: status == AttendanceStatus.permiso,
                      onTap: () => onChanged(AttendanceStatus.permiso),
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

/// Presente / Tarde / Ausente: tres botones grandes en vez de un menú de seis
/// opciones. "Ausente" abre el motivo debajo de la fila.
class _StatusSegment extends StatelessWidget {
  final AttendanceStatus status;
  final bool showLabels;
  final ValueChanged<AttendanceStatus> onChanged;
  const _StatusSegment({
    required this.status,
    required this.showLabels,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    Widget button({
      required IconData icon,
      required String label,
      required bool active,
      required Color color,
      required VoidCallback onTap,
    }) {
      final child = AnimatedContainer(
        duration: CX.motionFast,
        height: 44,
        width: showLabels ? null : 44,
        padding: showLabels ? const EdgeInsets.symmetric(horizontal: 10) : null,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: active ? Colors.white : CX.muted),
            if (showLabels) ...[
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: active ? Colors.white : CX.muted,
                ),
              ),
            ],
          ],
        ),
      );
      return Tooltip(
        message: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: showLabels ? SizedBox(width: 96, child: child) : child,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: CX.panel3,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(
            icon: Icons.check,
            label: 'Presente',
            active: status == AttendanceStatus.presente,
            color: CX.green,
            onTap: () => onChanged(AttendanceStatus.presente),
          ),
          const SizedBox(width: 3),
          button(
            icon: Icons.schedule,
            label: 'Tarde',
            active: status == AttendanceStatus.tarde,
            color: _blueFill,
            onTap: () => onChanged(AttendanceStatus.tarde),
          ),
          const SizedBox(width: 3),
          button(
            icon: Icons.close,
            label: 'Ausente',
            active: _isAbsentGroup(status),
            color: _redFill,
            onTap: () {
              if (!_isAbsentGroup(status)) {
                onChanged(AttendanceStatus.ausenteSinAviso);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _ReasonChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _ReasonChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? color : CX.panel,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? color : CX.lineStrong),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : CX.white,
          ),
        ),
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _KpiTile({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: CX.panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: CX.muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: color ?? CX.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  final DateTime date;
  const _MonthHeader({required this.date});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: CX.panel2,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Text(
        '${_monthNames[date.month - 1]} ${date.year}'.toUpperCase(),
        style: const TextStyle(
          color: CX.muted,
          fontSize: 11,
          letterSpacing: .6,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  final AttendanceRecord record;
  final bool selected;
  final VoidCallback onTap;
  const _SessionRow({
    required this.record,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final date = attendanceRecordDate(record.date);
    final rate = attendanceRecordRate(record);
    final breakdown = attendanceStatusBreakdown(record);
    int count(AttendanceStatus s) => breakdown[s] ?? 0;
    final presentes = count(AttendanceStatus.presente);
    final tarde = count(AttendanceStatus.tarde);
    final ausentes =
        count(AttendanceStatus.ausenteAvisado) +
        count(AttendanceStatus.ausenteSinAviso);
    final excused =
        count(AttendanceStatus.lesionado) + count(AttendanceStatus.permiso);
    final total = presentes + tarde + ausentes + excused;
    final expected = total - excused;
    final note = record.note.trim();
    Widget seg(int value, Color color) => value <= 0
        ? const SizedBox.shrink()
        : Expanded(
            flex: value,
            child: Padding(
              padding: const EdgeInsets.only(right: 1),
              child: ColoredBox(color: color),
            ),
          );
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? CX.greenDark.withValues(alpha: .5) : null,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 42,
              child: Column(
                children: [
                  Text(
                    '${date.day}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    _weekdayShort[date.weekday - 1].toUpperCase(),
                    style: const TextStyle(
                      color: CX.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    note.isEmpty ? 'Práctica' : note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: SizedBox(
                      height: 6,
                      child: Row(
                        children: [
                          seg(presentes, CX.green),
                          seg(tarde, _blueFill),
                          seg(ausentes, _redFill),
                          seg(excused, _grayFill),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 62,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    rate == null ? '—' : '${(rate * 100).round()}%',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    '${presentes + tarde} de $expected',
                    style: const TextStyle(color: CX.muted, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  final List<double> rates; // 0..1, cronológico
  final List<String> labels;
  const _TrendPainter({required this.rates, required this.labels});

  @override
  void paint(Canvas canvas, Size size) {
    const left = 34.0;
    const bottom = 22.0;
    const top = 8.0;
    final chartW = size.width - left - 8;
    final chartH = size.height - bottom - top;
    var lo = 60;
    for (final rate in rates) {
      final pct = (rate * 100).floor();
      if (pct < lo) lo = (pct ~/ 10) * 10;
    }
    const hi = 100;
    double yFor(double rate) =>
        top + chartH - ((rate * 100 - lo) / (hi - lo)).clamp(0, 1) * chartH;
    final grid = Paint()
      ..color = const Color(0x1A0D1A14)
      ..strokeWidth = 1;
    void label(String text, Offset at, {TextAlign align = TextAlign.left}) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(color: CX.muted, fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final dx = align == TextAlign.center ? at.dx - painter.width / 2 : at.dx;
      painter.paint(canvas, Offset(dx, at.dy - painter.height / 2));
    }

    for (final level in [hi, (hi + lo) ~/ 2, lo]) {
      final y = top + chartH - (level - lo) / (hi - lo) * chartH;
      canvas.drawLine(Offset(left, y), Offset(size.width - 8, y), grid);
      label('$level%', Offset(0, y));
    }
    final points = <Offset>[];
    for (var i = 0; i < rates.length; i++) {
      final x = rates.length == 1
          ? left + chartW / 2
          : left + chartW * i / (rates.length - 1);
      points.add(Offset(x, yFor(rates[i])));
    }
    final area = Path()..moveTo(points.first.dx, top + chartH);
    for (final p in points) {
      area.lineTo(p.dx, p.dy);
    }
    area
      ..lineTo(points.last.dx, top + chartH)
      ..close();
    canvas.drawPath(area, Paint()..color = CX.greenDark);
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      line.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = CX.green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    for (var i = 0; i < points.length; i++) {
      final last = i == points.length - 1;
      canvas.drawCircle(
        points[i],
        last ? 5 : 4,
        Paint()..color = last ? CX.green : Colors.white,
      );
      if (!last) {
        canvas.drawCircle(
          points[i],
          4,
          Paint()
            ..color = CX.green
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
      label(
        labels[i],
        Offset(points[i].dx, size.height - 6),
        align: TextAlign.center,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) =>
      old.rates != rates || old.labels != labels;
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
