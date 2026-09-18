// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import 'package:flutter/material.dart';

import '../data/cantera_data.dart';
import '../main.dart';
import '../services/attendance_stats_service.dart';
import '../services/club_access_service.dart';
import '../services/plantel_service.dart';
import '../state/calendar_events.dart';
import '../services/week_view_service.dart';
import '../state/section_handoff.dart';
import '../ui/ui_kit.dart';

class WeekScreen extends StatefulWidget {
  const WeekScreen({super.key});

  @override
  State<WeekScreen> createState() => _WeekScreenState();
}

class _WeekScreenState extends State<WeekScreen> {
  DateTime _week = weekStart(DateTime.now());
  bool _byPlayer = false;
  String _plantelId = '';
  // Semana used to read the calendar straight from this browser's
  // localStorage — a different device or a cleared cache showed an empty
  // or stale week even though the real calendar was synced. This mirrors
  // the same "latest shared snapshot wins" read Calendario itself uses.
  Map<String, dynamic>? _remoteCalendarData;
  String? _remoteFetchKey;

  String _day(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';

  void _maybeLoadRemoteCalendar(String clubId, String categoryId) {
    final key = '$clubId|$categoryId';
    if (_remoteFetchKey == key) return;
    _remoteFetchKey = key;
    _remoteCalendarData = null;
    unawaited(_loadRemoteCalendar(key, categoryId));
  }

  Future<void> _loadRemoteCalendar(String key, String categoryId) async {
    try {
      final records = await ClubAccessService.loadTacticalData(
        limit: 100,
        type: 'calendar',
      );
      if (!mounted || _remoteFetchKey != key) return;
      for (final record in records) {
        if (record.type != 'calendar') continue;
        if ((record.content['categoryId']?.toString() ?? '') != categoryId) {
          continue;
        }
        final rawEvents = record.content['events'];
        if (rawEvents is! Map) return;
        setState(() {
          _remoteCalendarData = Map<String, dynamic>.from(rawEvents);
        });
        return;
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final club = AppScope.of(context).club;
    final selectedId = AppScope.of(context).selectedCategoryId;
    CategorySquad? category;
    for (final item in club.categories) {
      if (item.id == selectedId) {
        category = item;
        break;
      }
    }
    if (category == null) {
      return const Scaffold(
        body: Center(
          child: EmptyStatePanel(
            icon: Icons.date_range_outlined,
            title: 'Primero elegí una categoría',
            message: 'La semana se organiza dentro de la categoría activa.',
          ),
        ),
      );
    }
    final activeCategory = category;
    _maybeLoadRemoteCalendar(club.id, activeCategory.id);
    final planteles = club.isManualClub
        ? plantelesForCategory(club, activeCategory.id)
        : const <Plantel>[];
    final players = club.players
        .where(
          (p) =>
              p.categoryId == activeCategory.id &&
              (_plantelId.isEmpty || p.plantelId == _plantelId),
        )
        .toList();
    final playerIds = players.map((p) => p.id).toSet();
    final attendance =
        attendanceForWeek(
          club.attendanceRecords,
          _week,
          categoryId: activeCategory.id,
        ).where((record) {
          if (_plantelId.isEmpty) return true;
          return record.rosterIds.any(playerIds.contains);
        }).toList();
    final matches = matchesForWeek(
      club.matchResults,
      _week,
      categoryId: activeCategory.id,
    );
    final sessions = club.sessions.where((session) {
      if (session.categoryId != activeCategory.id) return false;
      final date = DateTime.tryParse(session.scheduledDate);
      if (date == null) return false;
      final day = DateTime(date.year, date.month, date.day);
      return !day.isBefore(_week) &&
          day.isBefore(_week.add(const Duration(days: 7)));
    }).toList();
    final calendarEvents = _calendarEventsForWeek(club, activeCategory.id);
    final rates = attendance.map(attendanceRecordRate).whereType<double>();
    final average = rates.isEmpty
        ? null
        : rates.reduce((a, b) => a + b) / rates.length;
    final minutes = minutesForWeek(matches);
    final days = daysOfWeek(_week);

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Semana'),
            Text(
              'Carga, asistencia y competencia',
              style: TextStyle(fontSize: 10, color: CX.faint),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 30),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Semana anterior',
                onPressed: () => setState(
                  () => _week = _week.subtract(const Duration(days: 7)),
                ),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  '${_day(days.first)} al ${_day(days.last)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              TextButton(
                onPressed: () =>
                    setState(() => _week = weekStart(DateTime.now())),
                child: const Text('Hoy'),
              ),
              IconButton(
                tooltip: 'Semana siguiente',
                onPressed: () =>
                    setState(() => _week = _week.add(const Duration(days: 7))),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Semana is a hub, not one more parallel screen — jump straight
          // into the workflows that actually write the data shown here.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              QuickChip(
                label: 'Pasar lista',
                icon: Icons.fact_check_outlined,
                onTap: () => ShellActions.maybeOf(
                  context,
                )?.openSection(ShellSection.attendance),
              ),
              QuickChip(
                label: 'Alineación y citación',
                icon: Icons.view_module_outlined,
                onTap: () => ShellActions.maybeOf(
                  context,
                )?.openSection(ShellSection.lineup),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                icon: Icon(Icons.view_agenda_outlined),
                label: Text('Agenda'),
              ),
              ButtonSegment(
                value: true,
                icon: Icon(Icons.people_outline),
                label: Text('Por jugador'),
              ),
            ],
            selected: {_byPlayer},
            onSelectionChanged: (value) =>
                setState(() => _byPlayer = value.first),
          ),
          if (planteles.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Todos'),
                  selected: _plantelId.isEmpty,
                  onSelected: (_) => setState(() => _plantelId = ''),
                ),
                for (final plantel in planteles)
                  ChoiceChip(
                    label: Text(plantel.name),
                    selected: _plantelId == plantel.id,
                    onSelected: (_) => setState(() => _plantelId = plantel.id),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          MetricGrid(
            tiles: [
              MetricTile(
                icon: Icons.fitness_center,
                value: '${attendance.length}',
                label: 'Prácticas',
                context: 'registradas esta semana',
                accent: CX.green,
              ),
              MetricTile(
                icon: Icons.how_to_reg,
                value: average == null ? '—' : '${(average * 100).round()}%',
                label: 'Asistencia',
                context: average == null ? 'sin registros' : 'promedio semanal',
                accent: CX.blue,
              ),
              MetricTile(
                icon: Icons.sports_soccer,
                value: '${matches.length}',
                label: 'Partidos',
                context: 'registrados esta semana',
                accent: CX.amber,
              ),
              MetricTile(
                icon: Icons.timer_outlined,
                value: minutes == null ? '—' : '$minutes',
                label: 'Minutos',
                context: minutes == null ? 'sin carga' : 'acumulados',
                accent: CX.red,
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (attendance.isEmpty &&
              matches.isEmpty &&
              sessions.isEmpty &&
              calendarEvents.isEmpty)
            const EmptyStatePanel(
              icon: Icons.event_available_outlined,
              title: 'Semana sin actividad registrada',
              message:
                  'Las prácticas y los partidos aparecerán acá cuando los registres.',
            )
          else if (_byPlayer)
            _PlayerMatrix(
              players: players,
              days: days,
              attendance: attendance,
              matches: matches,
            )
          else
            _Agenda(
              attendance: attendance,
              matches: matches,
              sessions: sessions,
              calendarEvents: calendarEvents,
            ),
        ],
      ),
    );
  }

  List<_WeekCalendarEvent> _calendarEventsForWeek(
    CanteraClub club,
    String categoryId,
  ) {
    Map<String, dynamic>? data = _remoteCalendarData;
    if (data == null) {
      final raw =
          html.window.localStorage['cantera_calendar_${club.id}_$categoryId'];
      if (raw == null || raw.isEmpty) return const [];
      try {
        data = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        return const [];
      }
    }
    final out = <_WeekCalendarEvent>[];
    try {
      for (final entry in data.entries) {
        final day = DateTime.tryParse(entry.key);
        if (day == null ||
            day.isBefore(_week) ||
            !day.isBefore(_week.add(const Duration(days: 7)))) {
          continue;
        }
        for (final rawEvent in entry.value as List<dynamic>? ?? const []) {
          if (rawEvent is! Map) continue;
          final event = normalizeEventJson(
            Map<String, dynamic>.from(rawEvent),
            entry.key,
          );
          final title = event['title']?.toString().trim() ?? '';
          if (title.isEmpty) continue;
          out.add(
            _WeekCalendarEvent(
              date: entry.key,
              title: title,
              type: event['type']?.toString().trim() ?? 'Evento',
              time: event['time']?.toString().trim() ?? '',
            ),
          );
        }
      }
    } catch (_) {
      return const [];
    }
    return out;
  }
}

class _WeekCalendarEvent {
  final String date;
  final String title;
  final String type;
  final String time;

  const _WeekCalendarEvent({
    required this.date,
    required this.title,
    required this.type,
    required this.time,
  });
}

const _weekdayNames = [
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo',
];

class _Agenda extends StatelessWidget {
  final List<AttendanceRecord> attendance;
  final List<MatchResult> matches;
  final List<TrainingSession> sessions;
  final List<_WeekCalendarEvent> calendarEvents;
  const _Agenda({
    required this.attendance,
    required this.matches,
    required this.sessions,
    required this.calendarEvents,
  });

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.of(context).size.width < 700;
    final items = <({String date, Widget child})>[
      for (final record in attendance)
        (
          date: record.date,
          child: _AgendaRow(
            icon: Icons.fitness_center,
            accent: CX.green,
            title: 'Práctica',
            subtitle:
                '${record.rosterIds.where((id) => record.effectiveStatus(id).attended).length}/${record.rosterIds.where((id) => record.effectiveStatus(id).expected).length} asistieron',
            trailing: null,
            onTap: () => ShellActions.maybeOf(
              context,
            )?.openSection(ShellSection.attendance),
            compact: narrow,
          ),
        ),
      for (final match in matches)
        (
          date: match.date,
          child: _AgendaRow(
            icon: Icons.sports_soccer,
            accent: CX.blue,
            title: 'vs ${match.opponent}',
            subtitle: '${match.goalsFor}-${match.goalsAgainst} · ${match.venueLabel}',
            trailing: match.minutesByPlayer.isEmpty
                ? null
                : '${match.minutesByPlayer.values.fold(0, (a, b) => a + b)} min',
            onTap: () =>
                ShellActions.maybeOf(context)?.openSection(ShellSection.lineup),
            compact: narrow,
          ),
        ),
      for (final session in sessions)
        (
          date: session.scheduledDate,
          child: _AgendaRow(
            icon: Icons.view_agenda_outlined,
            accent: CX.amber,
            title: session.title.trim().isEmpty
                ? 'Sesion planificada'
                : session.title.trim(),
            subtitle: [
              if (session.objective.trim().isNotEmpty) session.objective.trim(),
              if (session.duration > 0) '${session.duration} min',
              if (session.space.trim().isNotEmpty) session.space.trim(),
            ].join(' - '),
            trailing: session.playerCount > 0 ? '${session.playerCount} jug' : null,
            onTap: () =>
                ShellActions.maybeOf(context)?.openSection(ShellSection.planner),
            compact: narrow,
          ),
        ),
      for (final event in calendarEvents)
        (
          date: event.date,
          child: _AgendaRow(
            icon: event.type == 'Partido' || event.type == 'Torneo'
                ? Icons.sports_soccer
                : Icons.event_outlined,
            accent: event.type == 'Partido' || event.type == 'Torneo'
                ? CX.blue
                : CX.faint,
            title: event.title,
            subtitle: [
              event.type,
              if (event.time.isNotEmpty) event.time,
            ].join(' - '),
            trailing: null,
            onTap: null,
            compact: narrow,
          ),
        ),
    ]..sort((a, b) => a.date.compareTo(b.date));

    final grouped = <String, List<Widget>>{};
    for (final item in items) {
      grouped.putIfAbsent(item.date, () => []).add(item.child);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in grouped.entries) ...[
          Padding(
            padding: EdgeInsets.only(bottom: narrow ? 6 : 8, left: 2),
            child: Text(
              _dayLabel(entry.key),
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: CX.faint,
              ),
            ),
          ),
          Container(
            margin: EdgeInsets.only(bottom: narrow ? 11 : 16),
            decoration: CX.panelDecoration(),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < entry.value.length; i++) ...[
                  entry.value[i],
                  if (i < entry.value.length - 1)
                    const Divider(height: 1, color: CX.line),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _dayLabel(String isoDate) {
    final date = DateTime.tryParse(isoDate);
    if (date == null) return isoDate;
    final weekday = _weekdayNames[date.weekday - 1];
    return '$weekday ${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
  }
}

class _AgendaRow extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final String? trailing;
  final VoidCallback? onTap;
  final bool compact;
  const _AgendaRow({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final badgeSize = compact ? 32.0 : 38.0;
    return TappableScale(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 16,
          vertical: compact ? 10 : 13,
        ),
        child: Row(
          children: [
            Container(
              width: badgeSize,
              height: badgeSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(compact ? 9 : 11),
              ),
              child: Icon(icon, size: compact ? 16 : 19, color: accent),
            ),
            SizedBox(width: compact ? 10 : 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12.5, color: CX.muted),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              Text(
                trailing!,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: CX.faint,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PlayerMatrix extends StatelessWidget {
  final List<Player> players;
  final List<DateTime> days;
  final List<AttendanceRecord> attendance;
  final List<MatchResult> matches;
  const _PlayerMatrix({
    required this.players,
    required this.days,
    required this.attendance,
    required this.matches,
  });

  String _key(DateTime date) => date.toIso8601String().split('T').first;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: [
          const DataColumn(label: Text('Jugador')),
          for (final day in days)
            DataColumn(label: Text('${day.day}/${day.month}')),
        ],
        rows: [
          for (final player in players)
            DataRow(
              cells: [
                DataCell(
                  Text(
                    player.fullName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                for (final day in days)
                  DataCell(
                    _DayCell(
                      playerId: player.id,
                      date: _key(day),
                      attendance: attendance,
                      matches: matches,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  final String playerId;
  final String date;
  final List<AttendanceRecord> attendance;
  final List<MatchResult> matches;
  const _DayCell({
    required this.playerId,
    required this.date,
    required this.attendance,
    required this.matches,
  });

  @override
  Widget build(BuildContext context) {
    for (final record in attendance) {
      if (record.date == date && record.rosterIds.contains(playerId)) {
        final status = record.effectiveStatus(playerId);
        return Tooltip(
          message: status.label,
          child: Icon(
            attendanceStatusIcon(status),
            color: attendanceStatusColor(status),
            size: 18,
          ),
        );
      }
    }
    for (final match in matches) {
      if (match.date == date && match.lineupIds.contains(playerId)) {
        final minutes = match.minutesByPlayer[playerId];
        return Text(
          minutes == null ? 'J' : '$minutes′',
          style: const TextStyle(fontWeight: FontWeight.w900),
        );
      }
    }
    return const Text('—', style: TextStyle(color: CX.faint));
  }
}
