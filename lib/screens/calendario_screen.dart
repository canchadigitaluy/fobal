// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:convert';
import 'dart:html' as html;
import 'dart:async';

import 'package:flutter/material.dart';

import '../data/cantera_data.dart';
import '../main.dart';
import '../services/club_access_service.dart';
import '../services/offline_mutation_service.dart';
import '../services/player_match_stats_service.dart';
import '../state/calendar_events.dart';
import '../state/calendar_time.dart';
import '../state/section_handoff.dart';
import '../ui/ui_kit.dart';
import 'match_preparation_screen.dart';
import 'match_result_dialog.dart';

bool isMatchEventType(String type) => type == 'Partido' || type == 'Torneo';

Color _eventColor(String type) => switch (type) {
  'Partido' => CX.blue,
  'Torneo' => Colors.purple,
  'Evento' => Colors.indigo,
  'Cumpleaños' => Colors.pink,
  'Tarea' => Colors.orange,
  _ => CX.green,
};

IconData _eventIcon(String type) => switch (type) {
  'Partido' => Icons.sports_soccer_outlined,
  'Torneo' => Icons.emoji_events_outlined,
  'Evento' => Icons.event_outlined,
  'Cumpleaños' => Icons.cake_outlined,
  'Tarea' => Icons.task_alt,
  _ => Icons.fitness_center,
};

class CalendarioScreen extends StatefulWidget {
  const CalendarioScreen({super.key});

  @override
  State<CalendarioScreen> createState() => _CalendarioScreenState();
}

class _CalendarioScreenState extends State<CalendarioScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  final Map<String, List<_CalendarEvent>> _events = {};
  DateTime? _selectedDay;
  String? _pendingEditEventId;
  String? _loadedStorageKey;
  String? _remoteLoadedStorageKey;

  String get _storageKey {
    final scope = AppScope.of(context);
    final categoryId = _activeCategoryId(scope);
    return 'cantera_calendar_${scope.fullClub.id}_$categoryId';
  }

  String _activeCategoryId(AppScope scope) {
    final cats = scope.fullClub.categories;
    return cats.any((category) => category.id == scope.selectedCategoryId)
        ? scope.selectedCategoryId!
        : (cats.isNotEmpty ? cats.first.id : 'plantel');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  void _load() {
    final key = _storageKey;
    if (_loadedStorageKey != key) {
      _loadedStorageKey = key;
      _events.clear();
      _selectedDay = null;
      _pendingEditEventId = null;
      _remoteLoadedStorageKey = null;
    }
    final raw = html.window.localStorage[key];
    if (raw != null && raw.isNotEmpty && _events.isEmpty) {
      try {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        _events
          ..clear()
          ..addAll(_eventsFromJson(data));
      } catch (_) {
        html.window.localStorage.remove(key);
      }
    }
    if (_remoteLoadedStorageKey != key) {
      _remoteLoadedStorageKey = key;
      unawaited(_loadRemoteCalendar(key));
    }
  }

  Map<String, List<_CalendarEvent>> _eventsFromJson(
    Map<String, dynamic> data,
  ) {
    return data.map(
      (key, value) => MapEntry(
        key,
        (value as List<dynamic>)
            .whereType<Map>()
            .map(
              (item) => _CalendarEvent.fromJson(
                normalizeEventJson(Map<String, dynamic>.from(item), key),
              ),
            )
            .toList(),
      ),
    );
  }

  Future<void> _loadRemoteCalendar(String storageKey) async {
    try {
      final scope = AppScope.of(context);
      final categoryId = _activeCategoryId(scope);
      final records = await ClubAccessService.loadTacticalData(
        limit: 100,
        type: 'calendar',
      );
      if (!mounted || storageKey != _storageKey) return;
      // loadTacticalData() returns newest-first. Each 'calendar' record is a
      // full snapshot for the category, not a diff — the old code unioned
      // events from every one of the last 100 snapshots it could find, so a
      // day removed locally and re-saved would still exist in an older
      // snapshot and get merged right back in as if it was never deleted.
      // Only the newest snapshot for this category is authoritative; take
      // the first match and stop.
      ClubTacticalRecord? latest;
      for (final record in records) {
        if (record.type != 'calendar') continue;
        if ((record.content['categoryId']?.toString() ?? '') != categoryId) {
          continue;
        }
        latest = record;
        break;
      }
      if (latest == null) return;
      final rawEvents = latest.content['events'];
      if (rawEvents is! Map) return;
      final remote = _eventsFromJson(Map<String, dynamic>.from(rawEvents));
      final merged = <String, List<_CalendarEvent>>{
        for (final entry in _events.entries) entry.key: [...entry.value],
      };
      var changed = false;
      for (final entry in remote.entries) {
        final existingIds = {
          for (final event in merged[entry.key] ?? const <_CalendarEvent>[])
            event.id,
        };
        for (final event in entry.value) {
          if (existingIds.add(event.id)) {
            merged.update(
              entry.key,
              (items) => [...items, event],
              ifAbsent: () => [event],
            );
            changed = true;
          }
        }
      }
      if (!changed) return;
      setState(() {
        _events
          ..clear()
          ..addAll(merged);
      });
      html.window.localStorage[storageKey] = jsonEncode(
        _events.map(
          (key, value) =>
              MapEntry(key, value.map((item) => item.toJson()).toList()),
        ),
      );
    } catch (_) {}
  }

  void _save() {
    final payload = _events.map(
      (key, value) =>
          MapEntry(key, value.map((item) => item.toJson()).toList()),
    );
    html.window.localStorage[_storageKey] = jsonEncode(payload);
    final scope = AppScope.of(context);
    final categoryId = _activeCategoryId(scope);
    var categoryName = 'Plantel';
    for (final category in scope.fullClub.categories) {
      if (category.id == categoryId) {
        categoryName = category.name;
        break;
      }
    }
    unawaited(
      OfflineMutationService.instance.saveTacticalDataOfflineFirst(
        type: 'calendar',
        title: 'Calendario $categoryName',
        content: {'categoryId': categoryId, 'events': payload},
        categoryId: categoryId,
      ),
    );
  }

  void _openDay(DateTime day) {
    setState(() => _selectedDay = day);
  }

  void _addEvent(DateTime day, _CalendarEvent event) {
    setState(() {
      _events.update(
        _key(day),
        (items) => [...items, event],
        ifAbsent: () => [event],
      );
      _save();
    });
  }

  void _editEvent(DateTime day, int index, _CalendarEvent updated) {
    setState(() {
      final items = _events[_key(day)];
      if (items == null || index < 0 || index >= items.length) return;
      items[index] = updated;
      _save();
    });
  }

  void _deleteEvent(DateTime day, int index) {
    setState(() {
      final items = _events[_key(day)];
      if (items == null || index < 0 || index >= items.length) return;
      items.removeAt(index);
      if (items.isEmpty) _events.remove(_key(day));
      _save();
    });
  }

  /// Log a result for a past Match event and link it back to the calendar
  /// via the event's own id — stable even if the event gets renamed later.
  /// The result lives in the club document (not the calendar store), so it
  /// rides the existing sync with no extra plumbing.
  Future<void> _logResult(DateTime day, _CalendarEvent event) async {
    final scope = AppScope.of(context);
    final categoryId = _activeCategoryId(scope);
    final categoryPlayers = isLudCategoryId(categoryId)
        ? const <Player>[]
        : scope.fullClub.players
              .where((player) => player.categoryId == categoryId)
              .toList();
    final result = await showMatchResultDialog(
      context,
      categoryId: categoryId,
      initialDate: day,
      initialOpponent: event.title,
      calendarKey: event.id,
      players: categoryPlayers,
    );
    if (result == null || !mounted) return;
    final club = scope.fullClub;
    final nextResults = [...club.matchResults, result];
    var players = club.players;
    if (categoryPlayers.isNotEmpty) {
      final categoryResults = nextResults
          .where((r) => r.categoryId == categoryId)
          .toList();
      final stats = computePlayerMatchStats(
        lineups: [for (final r in categoryResults) r.lineupIds],
        scorers: [for (final r in categoryResults) r.scorerIds],
        minutesByMatch: [for (final r in categoryResults) r.minutesByPlayer],
        playerIds: categoryPlayers.map((p) => p.id).toList(),
      );
      players = [
        for (final player in club.players)
          if (stats.containsKey(player.id))
            player.copyWith(
              matchesPlayed: stats[player.id]!.matchesPlayed,
              goals: stats[player.id]!.goals,
              minutesPlayed: stats[player.id]!.minutesPlayed,
            )
          else
            player,
      ];
    }
    scope.updateClub(
      club.copyWith(matchResults: nextResults, players: players),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Resultado cargado para ${event.title}.')),
    );
    setState(() {});
  }

  void _openDayToEdit(DateTime day, String eventId) {
    setState(() {
      _selectedDay = day;
      _pendingEditEventId = eventId;
    });
  }

  String _key(DateTime day) => calendarDayKey(day);

  @override
  Widget build(BuildContext context) {
    final first = DateTime(_month.year, _month.month, 1);
    final narrow = MediaQuery.sizeOf(context).width < 700;
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final offset = (first.weekday + 6) % 7;
    final cells = List<DateTime?>.filled(offset, null, growable: true)
      ..addAll(
        List.generate(
          daysInMonth,
          (i) => DateTime(_month.year, _month.month, i + 1),
        ),
      );
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    // Un mes completo de 7 columnas es dificil de leer apretado en un
    // celular. En mobile mostramos primero la agenda (proximos eventos +
    // partidos sin resultado) y dejamos la grilla del mes mas abajo para
    // quien quiera navegar visualmente; en desktop el orden no cambia.
    final upcomingBlock = <Widget>[
      const SizedBox(height: 14),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        // Nivel 1: la agenda es la razon por la que un DT entra a esta
        // pantalla — que se viene, que falta cargar resultado.
        decoration: CX.heroDecoration(),
        child: _UpcomingEvents(
          events: _events,
          onOpenDay: _openDay,
          onEdit: _openDayToEdit,
          preparedEventIds: {
            for (final p in AppScope.of(context).fullClub.matchPreparations)
              if (p.calendarEventId.isNotEmpty) p.calendarEventId,
          },
          sessions: AppScope.of(context).club.sessions,
        ),
      ),
      Builder(
        builder: (context) {
          final logged = {
            for (final r in AppScope.of(context).fullClub.matchResults)
              if (r.calendarKey.isNotEmpty) r.calendarKey,
          };
          final now = DateTime.now();
          final floor = DateTime(now.year, now.month, now.day);
          final pending = <({DateTime day, _CalendarEvent event})>[];
          for (final entry in _events.entries) {
            final parts = entry.key.split('-');
            if (parts.length != 3) continue;
            final day = DateTime(
              int.tryParse(parts[0]) ?? 0,
              int.tryParse(parts[1]) ?? 1,
              int.tryParse(parts[2]) ?? 1,
            );
            if (day.isAfter(floor)) continue;
            for (final e in entry.value) {
              if (!isMatchEventType(e.type)) continue;
              if (logged.contains(e.id)) continue;
              pending.add((day: day, event: e));
            }
          }
          if (pending.isEmpty) return const SizedBox.shrink();
          pending.sort((a, b) => b.day.compareTo(a.day));
          return Padding(
            padding: const EdgeInsets.only(top: 16),
            child: _PendingResultsPanel(
              pending: pending.take(5).toList(),
              onOpenDay: _openDay,
            ),
          );
        },
      ),
    ];
    return ColoredBox(
      color: CX.canvas,
      child: SingleChildScrollView(
        key: const PageStorageKey('calendario-screen'),
        padding: EdgeInsets.fromLTRB(
          narrow ? 12 : 18,
          narrow ? 12 : 18,
          narrow ? 12 : 18,
          narrow ? 20 : 30,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Calendario',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 2),
            const Text(
              'Entrenamientos, partidos y eventos',
              style: TextStyle(color: CX.faint, fontSize: 11),
            ),
            SizedBox(height: narrow ? 12 : 18),
            if (narrow && _selectedDay == null) ...[
              ...upcomingBlock,
              const SizedBox(height: 18),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Container(
                  padding: EdgeInsets.all(narrow ? 11 : 16),
                  decoration: CX.panelDecoration(),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => setState(
                              () => _month = DateTime(
                                _month.year,
                                _month.month - 1,
                              ),
                            ),
                            icon: const Icon(Icons.chevron_left),
                          ),
                          Expanded(
                            child: Text(
                              '${_monthName(_month.month)} de ${_month.year}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 17,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => setState(
                              () => _month = DateTime(
                                _month.year,
                                _month.month + 1,
                              ),
                            ),
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ],
                      ),
                      SizedBox(height: narrow ? 6 : 8),
                      Row(
                        children:
                            const [
                                  'LUN',
                                  'MAR',
                                  'MIÉ',
                                  'JUE',
                                  'VIE',
                                  'SÁB',
                                  'DOM',
                                ]
                                .map(
                                  (d) => Expanded(
                                    child: Center(
                                      child: Text(
                                        d,
                                        style: TextStyle(
                                          color: CX.faint,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                      ),
                      SizedBox(height: narrow ? 6 : 8),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: cells.length,
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 7,
                              childAspectRatio: narrow ? 1.35 : 1.55,
                            ),
                        itemBuilder: (context, index) {
                          final day = cells[index];
                          if (day == null) return const SizedBox.shrink();
                          final today = _key(day) == _key(DateTime.now());
                          final selected =
                              _selectedDay != null &&
                              _key(day) == _key(_selectedDay!);
                          final dayEvents = _events[_key(day)] ?? const [];
                          final types = <String>{
                            for (final e in dayEvents) e.type,
                          }.take(3).toList();
                          return InkWell(
                            onTap: () => _openDay(day),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              margin: EdgeInsets.all(narrow ? 2 : 3),
                              decoration: BoxDecoration(
                                color: selected
                                    ? CX.green.withValues(alpha: .12)
                                    : today
                                    ? CX.greenDark
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: selected || today ? CX.green : CX.line,
                                  width: selected ? 1.5 : 1,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '${day.day}',
                                    style: TextStyle(
                                      fontWeight: today
                                          ? FontWeight.w900
                                          : FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  SizedBox(
                                    height: 6,
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        for (final t in types)
                                          Container(
                                            margin: const EdgeInsets.symmetric(
                                              horizontal: 1.5,
                                            ),
                                            width: 5,
                                            height: 5,
                                            decoration: BoxDecoration(
                                              color: _eventColor(t),
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      const Divider(height: 22),
                      const _Legend(),
                      // En mobile la agenda ya se muestra arriba de la
                      // grilla del mes (ver upcomingBlock al inicio de
                      // build) — repetirla aca la duplicaria.
                      if (_selectedDay == null && !narrow) ...upcomingBlock,
                      if (_selectedDay != null) ...[
                        const SizedBox(height: 14),
                        _DayEditorPanel(
                          key: ValueKey(_key(_selectedDay!)),
                          day: _selectedDay!,
                          events: _events[_key(_selectedDay!)] ?? const [],
                          loggedKeys: {
                            for (final r in AppScope.of(
                              context,
                            ).fullClub.matchResults)
                              if (r.calendarKey.isNotEmpty) r.calendarKey,
                          },
                          scoreByKey: {
                            for (final r in AppScope.of(
                              context,
                            ).fullClub.matchResults)
                              if (r.calendarKey.isNotEmpty)
                                r.calendarKey:
                                    '${r.goalsFor}-${r.goalsAgainst}',
                          },
                          preparedEventIds: {
                            for (final p in AppScope.of(
                              context,
                            ).fullClub.matchPreparations)
                              if (p.calendarEventId.isNotEmpty)
                                p.calendarEventId,
                          },
                          daySessions: sessionsOnDay(
                            AppScope.of(context).club.sessions,
                            _selectedDay!,
                          ),
                          initialEditEventId: _pendingEditEventId,
                          onEditConsumed: () =>
                              setState(() => _pendingEditEventId = null),
                          onAdd: (event) => _addEvent(_selectedDay!, event),
                          onEdit: (index, event) =>
                              _editEvent(_selectedDay!, index, event),
                          onDelete: (index) =>
                              _deleteEvent(_selectedDay!, index),
                          onLogResult: (event) =>
                              _logResult(_selectedDay!, event),
                          onClose: () => setState(() => _selectedDay = null),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _monthName(int month) => const [
    'Enero',
    'Febrero',
    'Marzo',
    'Abril',
    'Mayo',
    'Junio',
    'Julio',
    'Agosto',
    'Setiembre',
    'Octubre',
    'Noviembre',
    'Diciembre',
  ][month - 1];
}

class _PendingResultsPanel extends StatelessWidget {
  final List<({DateTime day, _CalendarEvent event})> pending;
  final ValueChanged<DateTime> onOpenDay;

  const _PendingResultsPanel({required this.pending, required this.onOpenDay});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CX.amber.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: CX.amber.withValues(alpha: .28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.scoreboard_outlined, color: CX.amber, size: 16),
              SizedBox(width: 6),
              Text(
                'PARTIDOS SIN RESULTADO',
                style: TextStyle(
                  color: CX.amber,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final item in pending)
            InkWell(
              onTap: () => onOpenDay(item.day),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.event.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    Text(
                      '${item.day.day.toString().padLeft(2, '0')}/'
                      '${item.day.month.toString().padLeft(2, '0')}',
                      style: const TextStyle(color: CX.faint, fontSize: 11),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.chevron_right, size: 16, color: CX.muted),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _UpcomingEvents extends StatelessWidget {
  final Map<String, List<_CalendarEvent>> events;
  final ValueChanged<DateTime> onOpenDay;
  final void Function(DateTime day, String eventId) onEdit;
  final Set<String> preparedEventIds;
  final List<TrainingSession> sessions;
  const _UpcomingEvents({
    required this.events,
    required this.onOpenDay,
    required this.onEdit,
    this.preparedEventIds = const {},
    this.sessions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final upcomingSessions = sessions.where((session) {
      if (session.status == 'completed') return false;
      final date = DateTime.tryParse(session.scheduledDate);
      return date != null &&
          !DateTime(date.year, date.month, date.day).isBefore(today);
    }).toList()..sort((a, b) => a.scheduledDate.compareTo(b.scheduledDate));
    final upcoming = <({DateTime day, _CalendarEvent event})>[];
    for (final entry in events.entries) {
      final parts = entry.key.split('-');
      if (parts.length != 3) continue;
      final day = DateTime(
        int.tryParse(parts[0]) ?? 0,
        int.tryParse(parts[1]) ?? 1,
        int.tryParse(parts[2]) ?? 1,
      );
      if (day.isBefore(today)) continue;
      for (final e in entry.value) {
        upcoming.add((day: day, event: e));
      }
    }
    upcoming.sort((a, b) => a.day.compareTo(b.day));

    if (upcoming.isEmpty && upcomingSessions.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: CX.panel2,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Column(
          children: [
            Icon(Icons.event_available_outlined, color: CX.green, size: 24),
            SizedBox(height: 8),
            Text(
              'Sin eventos próximos',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            SizedBox(height: 3),
            Text(
              'Tocá un día del calendario para agregar un entrenamiento, '
              'partido o evento.',
              textAlign: TextAlign.center,
              style: TextStyle(color: CX.muted, fontSize: 11.5, height: 1.35),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PRÓXIMOS EVENTOS',
          style: TextStyle(
            color: CX.faint,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: .4,
          ),
        ),
        const SizedBox(height: 8),
        for (final item in upcoming.take(5))
          InkWell(
            onTap: () => onOpenDay(item.day),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 3,
                    height: 30,
                    margin: const EdgeInsets.only(top: 2),
                    decoration: BoxDecoration(
                      color: _eventColor(item.event.type),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(
                    _eventIcon(item.event.type),
                    size: 16,
                    color: _eventColor(item.event.type),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                item.event.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (isMatchEventType(item.event.type) &&
                                preparedEventIds.contains(item.event.id)) ...[
                              const SizedBox(width: 5),
                              const Icon(
                                Icons.assignment_turned_in_outlined,
                                size: 13,
                                color: CX.green,
                              ),
                            ],
                          ],
                        ),
                        Text(
                          _dayLabel(item.day),
                          style: const TextStyle(color: CX.faint, fontSize: 11),
                        ),
                        if (item.event.notes.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              item.event.notes.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: CX.faint,
                                fontSize: 10.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (item.event.time.trim().isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: CX.panel2,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.schedule, size: 12, color: CX.muted),
                          const SizedBox(width: 4),
                          Text(
                            item.event.time.trim(),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  IconButton(
                    tooltip: 'Editar',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => onEdit(item.day, item.event.id),
                    icon: const Icon(
                      Icons.edit_outlined,
                      size: 17,
                      color: CX.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (upcomingSessions.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text(
            'SESIONES PLANIFICADAS',
            style: TextStyle(
              color: CX.faint,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: .4,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Cargadas desde Planificar — no hace falta repetirlas acá.',
            style: TextStyle(color: CX.faint, fontSize: 10.5),
          ),
          const SizedBox(height: 8),
          for (final session in upcomingSessions.take(5))
            _PlannedSessionTile(
              session: session,
              dayLabel: _dayLabel(DateTime.parse(session.scheduledDate)),
            ),
        ],
      ],
    );
  }

  static String _dayLabel(DateTime day) {
    const wd = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
    const mo = [
      'ene',
      'feb',
      'mar',
      'abr',
      'may',
      'jun',
      'jul',
      'ago',
      'set',
      'oct',
      'nov',
      'dic',
    ];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = day.difference(today).inDays;
    if (diff == 0) return 'Hoy';
    if (diff == 1) return 'Mañana';
    return '${wd[day.weekday - 1]} ${day.day} ${mo[day.month - 1]}';
  }
}

class _PlannedSessionTile extends StatelessWidget {
  final TrainingSession session;
  final String dayLabel;
  const _PlannedSessionTile({required this.session, required this.dayLabel});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () =>
        ShellActions.maybeOf(context)?.openSection(ShellSection.planner),
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 30,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: CX.green,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          const Icon(Icons.fitness_center, size: 16, color: CX.green),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  dayLabel,
                  style: const TextStyle(color: CX.faint, fontSize: 11),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, size: 17, color: CX.muted),
        ],
      ),
    ),
  );
}

class _DayEditorPanel extends StatefulWidget {
  final DateTime day;
  final List<_CalendarEvent> events;
  final Set<String> loggedKeys;
  final Map<String, String> scoreByKey;
  final Set<String> preparedEventIds;
  final List<TrainingSession> daySessions;
  final String? initialEditEventId;
  final VoidCallback onEditConsumed;
  final ValueChanged<_CalendarEvent> onAdd;
  final void Function(int index, _CalendarEvent updated) onEdit;
  final ValueChanged<int> onDelete;
  final ValueChanged<_CalendarEvent> onLogResult;
  final VoidCallback onClose;

  const _DayEditorPanel({
    super.key,
    required this.day,
    required this.events,
    required this.loggedKeys,
    this.scoreByKey = const {},
    this.preparedEventIds = const {},
    this.daySessions = const [],
    this.initialEditEventId,
    required this.onEditConsumed,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onLogResult,
    required this.onClose,
  });

  @override
  State<_DayEditorPanel> createState() => _DayEditorPanelState();
}

class _DayEditorPanelState extends State<_DayEditorPanel> {
  final _title = TextEditingController();
  final _notes = TextEditingController();
  String _type = 'Entrenamiento';
  String _timeValue = '';
  int? _editingIndex;

  @override
  void initState() {
    super.initState();
    final targetId = widget.initialEditEventId;
    if (targetId == null) return;
    final index = widget.events.indexWhere((e) => e.id == targetId);
    if (index != -1) {
      final event = widget.events[index];
      _title.text = event.title;
      _notes.text = event.notes;
      _type = event.type;
      _timeValue = event.time;
      _editingIndex = index;
    }
    // Tell the parent this pending edit was picked up so it doesn't
    // re-trigger it next time this day (or another) opens with a stale
    // value. Deferred so we never setState the parent mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onEditConsumed();
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _resetForm() {
    _title.clear();
    _notes.clear();
    setState(() {
      _type = 'Entrenamiento';
      _timeValue = '';
      _editingIndex = null;
    });
  }

  void _startEdit(int index, _CalendarEvent event) {
    _title.text = event.title;
    _notes.text = event.notes;
    setState(() {
      _type = event.type;
      _timeValue = event.time;
      _editingIndex = index;
    });
  }

  Future<void> _confirmDelete(int index, _CalendarEvent event) async {
    final hasResult = widget.loggedKeys.contains(event.id);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Borrar evento'),
        content: Text(
          hasResult
              ? 'Vas a borrar "${event.title}". Este partido tiene un '
                    'resultado cargado: el evento se borra del calendario, '
                    'pero el resultado se conserva en Estadísticas.'
              : 'Vas a borrar "${event.title}". No se puede deshacer.',
        ),
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
    if (confirmed != true) return;
    if (_editingIndex == index) _resetForm();
    widget.onDelete(index);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Evento borrado: ${event.title}')));
  }

  Future<void> _pickTime() async {
    final preset = parseHm(_timeValue);
    final picked = await showTimePicker(
      context: context,
      initialTime: preset == null
          ? TimeOfDay.now()
          : TimeOfDay(hour: preset.hour, minute: preset.minute),
      helpText: 'Hora del evento',
    );
    if (picked == null) return;
    setState(() => _timeValue = formatHm(picked.hour, picked.minute));
  }

  void _submit() {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final editing = _editingIndex;
    final event = _CalendarEvent(
      // Keep the original id on edit — that's what keeps a "Cargar
      // resultado" link (and the "Resultado cargado" badge) working even
      // if the DT renames the event.
      id: editing != null ? widget.events[editing].id : newEventId(),
      type: _type,
      title: title,
      time: _timeValue.trim(),
      notes: _notes.text.trim(),
    );
    if (editing != null) {
      widget.onEdit(editing, event);
    } else {
      widget.onAdd(event);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          editing != null ? 'Evento actualizado.' : 'Evento agregado.',
        ),
      ),
    );
    _resetForm();
  }

  @override
  Widget build(BuildContext context) {
    final editing = _editingIndex != null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CX.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CX.line),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_weekday(widget.day.weekday)}, ${widget.day.day} de ${_month(widget.day.month)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (widget.events.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: CX.panel2,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${widget.events.length}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ),
                IconButton(
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (widget.events.isEmpty && widget.daySessions.isEmpty)
              const EmptyStatePanel(
                icon: Icons.calendar_month,
                title: 'No hay eventos este día',
                message:
                    'Cargá un entrenamiento, partido u otro evento con '
                    'el formulario de abajo.',
              )
            else ...[
              for (final session in widget.daySessions)
                _PlannedSessionTile(session: session, dayLabel: 'Planificada'),
              for (final (index, event) in widget.events.indexed)
                _EventTile(
                  day: widget.day,
                  event: event,
                  logged: widget.loggedKeys.contains(event.id),
                  resultScore: widget.scoreByKey[event.id],
                  hasPreparation: widget.preparedEventIds.contains(event.id),
                  onEdit: () => _startEdit(index, event),
                  onDelete: () => _confirmDelete(index, event),
                  onLogResult: () => widget.onLogResult(event),
                  onPrepareMatch: () => openMatchPreparation(
                    context,
                    calendarEventId: event.id,
                    rival: event.title,
                    date:
                        '${widget.day.day.toString().padLeft(2, '0')}/'
                        '${widget.day.month.toString().padLeft(2, '0')}/'
                        '${widget.day.year}',
                    time: event.time,
                  ),
                  onTakeAttendance: () => ShellActions.maybeOf(
                    context,
                  )?.openAttendanceForDate(
                    '${widget.day.year.toString().padLeft(4, '0')}-'
                    '${widget.day.month.toString().padLeft(2, '0')}-'
                    '${widget.day.day.toString().padLeft(2, '0')}',
                  ),
                ),
            ],
            const SizedBox(height: 10),
            PremiumSectionHeader(
              eyebrow: editing ? 'Editando' : 'Nuevo',
              title: editing ? 'Editar evento' : 'Crear un evento',
            ),
            DropdownButtonFormField<String>(
              value: _type,
              decoration: const InputDecoration(labelText: 'Tipo de evento'),
              items:
                  const [
                        'Entrenamiento',
                        'Partido',
                        'Torneo',
                        'Evento',
                        'Cumpleaños',
                        'Tarea',
                      ]
                      .map(
                        (item) =>
                            DropdownMenuItem(value: item, child: Text(item)),
                      )
                      .toList(),
              onChanged: (value) => setState(() => _type = value ?? _type),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Título'),
            ),
            const SizedBox(height: 10),
            InkWell(
              onTap: _pickTime,
              borderRadius: BorderRadius.circular(8),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Hora',
                  prefixIcon: const Icon(Icons.schedule_outlined),
                  suffixIcon: _timeValue.trim().isEmpty
                      ? const Icon(Icons.expand_more)
                      : IconButton(
                          tooltip: 'Quitar hora',
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setState(() => _timeValue = ''),
                        ),
                ),
                child: Text(
                  _timeValue.trim().isEmpty
                      ? 'Sin hora definida'
                      : _timeValue.trim(),
                  style: TextStyle(
                    color: _timeValue.trim().isEmpty ? CX.faint : CX.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notes,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notas (opcional)',
                hintText: 'Ej: traer petos, confirmar cancha',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _submit,
                    icon: Icon(editing ? Icons.save_outlined : Icons.add),
                    label: Text(editing ? 'Guardar cambios' : 'Agregar evento'),
                  ),
                ),
                if (editing) ...[
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: _resetForm,
                    child: const Text('Cancelar'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _weekday(int day) =>
      const ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'][day - 1];
  static String _month(int month) => const [
    'enero',
    'febrero',
    'marzo',
    'abril',
    'mayo',
    'junio',
    'julio',
    'agosto',
    'setiembre',
    'octubre',
    'noviembre',
    'diciembre',
  ][month - 1];
}

class _EventTile extends StatelessWidget {
  final DateTime day;
  final _CalendarEvent event;
  final bool logged;
  final String? resultScore;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onLogResult;
  final VoidCallback onPrepareMatch;
  final bool hasPreparation;
  final VoidCallback? onTakeAttendance;

  const _EventTile({
    required this.day,
    required this.event,
    required this.logged,
    this.resultScore,
    required this.onEdit,
    required this.onDelete,
    required this.onLogResult,
    required this.onPrepareMatch,
    this.hasPreparation = false,
    this.onTakeAttendance,
  });

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final past = DateTime(
      day.year,
      day.month,
      day.day,
    ).isBefore(DateTime(today.year, today.month, today.day));
    final isMatch = isMatchEventType(event.type);
    final color = _eventColor(event.type);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: CX.panel2,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: CX.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(_eventIcon(event.type), color: color, size: 17),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          event.type,
                          style: const TextStyle(color: CX.muted, fontSize: 11),
                        ),
                        if (event.time.trim().isNotEmpty) ...[
                          const SizedBox(width: 7),
                          const Icon(Icons.schedule, size: 11, color: CX.faint),
                          const SizedBox(width: 2),
                          Text(
                            event.time.trim(),
                            style: const TextStyle(
                              color: CX.muted,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Editar',
                visualDensity: VisualDensity.compact,
                onPressed: onEdit,
                icon: const Icon(
                  Icons.edit_outlined,
                  size: 18,
                  color: CX.muted,
                ),
              ),
              IconButton(
                tooltip: 'Borrar',
                visualDensity: VisualDensity.compact,
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 18, color: CX.red),
              ),
            ],
          ),
          if (event.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              event.notes.trim(),
              style: const TextStyle(
                color: CX.faint,
                fontSize: 11.5,
                height: 1.35,
              ),
            ),
          ],
          if (isMatch) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onPrepareMatch,
                  icon: Icon(
                    hasPreparation
                        ? Icons.assignment_turned_in_outlined
                        : Icons.assignment_outlined,
                    size: 16,
                  ),
                  label: Text(
                    hasPreparation ? 'Ver plan de partido' : 'Preparar partido',
                  ),
                ),
                if (past)
                  logged
                      ? Chip(
                          label: Text(
                            resultScore == null
                                ? 'Resultado cargado'
                                : 'Resultado $resultScore',
                          ),
                          visualDensity: VisualDensity.compact,
                        )
                      : OutlinedButton.icon(
                          onPressed: onLogResult,
                          icon: const Icon(Icons.scoreboard_outlined, size: 16),
                          label: const Text('Cargar resultado'),
                        ),
              ],
            ),
          ],
          if (!isMatch &&
              event.type == 'Entrenamiento' &&
              onTakeAttendance != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onTakeAttendance,
              icon: const Icon(Icons.fact_check_outlined, size: 16),
              label: const Text('Tomar asistencia'),
            ),
          ],
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final items = {
      'Entrenamiento': CX.green,
      'Partido': CX.blue,
      'Torneo': Colors.purple,
      'Evento': Colors.indigo,
      'Cumpleaños': Colors.pink,
      'Tarea': Colors.orange,
    };
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: items.entries
          .map(
            (entry) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(radius: 3, backgroundColor: entry.value),
                const SizedBox(width: 5),
                Text(
                  entry.key,
                  style: const TextStyle(color: CX.muted, fontSize: 11),
                ),
              ],
            ),
          )
          .toList(),
    );
  }
}

class _CalendarEvent {
  /// Stable identity, independent of title/day — what a logged result's
  /// `MatchResult.calendarKey` points to. Callers loading from storage
  /// should run the JSON through [normalizeEventJson] first so this is
  /// never empty for a legacy record.
  final String id;
  final String type;
  final String title;
  final String time;
  final String notes;

  const _CalendarEvent({
    required this.id,
    required this.type,
    required this.title,
    this.time = '',
    this.notes = '',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'title': title,
    'time': time,
    'notes': notes,
  };

  factory _CalendarEvent.fromJson(Map<String, dynamic> json) => _CalendarEvent(
    id: (json['id'] as String?)?.trim().isNotEmpty == true
        ? json['id'] as String
        : newEventId(),
    type: json['type'] as String? ?? 'Entrenamiento',
    title: json['title'] as String? ?? '',
    time: json['time'] as String? ?? '',
    notes: json['notes'] as String? ?? '',
  );
}
