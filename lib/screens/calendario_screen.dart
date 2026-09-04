// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:convert';
import 'dart:html' as html;
import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart';
import '../services/offline_mutation_service.dart';
import 'match_result_dialog.dart';

/// Stable-enough link between a calendar Match event and a logged result.
/// Rebuilt from the same day + title on both sides.
String calendarMatchKey(DateTime day, String title) =>
    '${day.year}-${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}|${title.trim().toLowerCase()}';

bool isMatchEventType(String type) => type == 'Partido' || type == 'Torneo';

class CalendarioScreen extends StatefulWidget {
  const CalendarioScreen({super.key});

  @override
  State<CalendarioScreen> createState() => _CalendarioScreenState();
}

class _CalendarioScreenState extends State<CalendarioScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  final Map<String, List<_CalendarEvent>> _events = {};
  DateTime? _selectedDay;

  String get _storageKey {
    final scope = AppScope.of(context);
    final categoryId = _activeCategoryId(scope);
    return 'cantera_calendar_${scope.fullClub.id}_$categoryId';
  }

  String _activeCategoryId(AppScope scope) {
    final cats = scope.fullClub.categories;
    return scope.selectedCategoryId ??
        (cats.isNotEmpty ? cats.first.id : 'plantel');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  void _load() {
    final raw = html.window.localStorage[_storageKey];
    if (raw == null || raw.isEmpty || _events.isNotEmpty) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _events
        ..clear()
        ..addAll(
          data.map(
            (key, value) => MapEntry(
              key,
              (value as List<dynamic>)
                  .map((item) => _CalendarEvent.fromJson(item as Map<String, dynamic>))
                  .toList(),
            ),
          ),
        );
    } catch (_) {
      html.window.localStorage.remove(_storageKey);
    }
  }

  void _save() {
    final payload = _events.map(
      (key, value) => MapEntry(key, value.map((item) => item.toJson()).toList()),
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
    unawaited(OfflineMutationService.instance.saveTacticalDataOfflineFirst(
      type: 'calendar',
      title: 'Calendario $categoryName',
      content: {
        'categoryId': categoryId,
        'events': payload,
      },
      categoryId: categoryId,
    ));
  }

  void _openDay(DateTime day) {
    setState(() => _selectedDay = day);
  }

  void _addEvent(DateTime day, _CalendarEvent event) {
    setState(() {
      _events.update(_key(day), (items) => [...items, event], ifAbsent: () => [event]);
      _save();
    });
  }

  /// Log a result for a past Match event and link it back to the calendar.
  /// The result lives in the club document (not the calendar store), so it
  /// rides the existing sync with no extra plumbing.
  Future<void> _logResult(DateTime day, _CalendarEvent event) async {
    final scope = AppScope.of(context);
    final result = await showMatchResultDialog(
      context,
      categoryId: _activeCategoryId(scope),
      initialDate: day,
      initialOpponent: event.title,
      calendarKey: calendarMatchKey(day, event.title),
    );
    if (result == null || !mounted) return;
    scope.updateClub(
      scope.fullClub.copyWith(
        matchResults: [...scope.fullClub.matchResults, result],
      ),
    );
    setState(() {});
  }

  String _key(DateTime day) =>
      '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final first = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final offset = (first.weekday + 6) % 7;
    final cells = List<DateTime?>.filled(offset, null, growable: true)
      ..addAll(List.generate(daysInMonth, (i) => DateTime(_month.year, _month.month, i + 1)));
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    return ColoredBox(
      color: CX.canvas,
      child: SingleChildScrollView(
        key: const PageStorageKey('calendario-screen'),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
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
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Container(
                  padding: const EdgeInsets.all(16),
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
                      const SizedBox(height: 8),
                      Row(
                        children: const [
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
                      const SizedBox(height: 8),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: cells.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 7,
                              childAspectRatio: 1.55,
                            ),
                        itemBuilder: (context, index) {
                          final day = cells[index];
                          if (day == null) return const SizedBox.shrink();
                          final today = _key(day) == _key(DateTime.now());
                          final hasEvents =
                              (_events[_key(day)] ?? const []).isNotEmpty;
                          return InkWell(
                            onTap: () => _openDay(day),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              margin: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: today
                                    ? CX.greenDark
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: today ? CX.green : CX.line,
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
                                  if (hasEvents) ...[
                                    const SizedBox(height: 4),
                                    const CircleAvatar(
                                      radius: 3,
                                      backgroundColor: CX.green,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      const Divider(height: 22),
                      const _Legend(),
                      if (_selectedDay != null) ...[
                        const SizedBox(height: 14),
                        _DayEditorPanel(
                          key: ValueKey(_key(_selectedDay!)),
                          day: _selectedDay!,
                          events: _events[_key(_selectedDay!)] ?? const [],
                          loggedKeys: {
                            for (final r in AppScope.of(context)
                                .fullClub
                                .matchResults)
                              if (r.calendarKey.isNotEmpty) r.calendarKey,
                          },
                          onAdd: (event) => _addEvent(_selectedDay!, event),
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

class _DayEditorPanel extends StatefulWidget {
  final DateTime day;
  final List<_CalendarEvent> events;
  final Set<String> loggedKeys;
  final ValueChanged<_CalendarEvent> onAdd;
  final ValueChanged<_CalendarEvent> onLogResult;
  final VoidCallback onClose;

  const _DayEditorPanel({
    super.key,
    required this.day,
    required this.events,
    required this.loggedKeys,
    required this.onAdd,
    required this.onLogResult,
    required this.onClose,
  });

  @override
  State<_DayEditorPanel> createState() => _DayEditorPanelState();
}

class _DayEditorPanelState extends State<_DayEditorPanel> {
  final _title = TextEditingController();
  final _time = TextEditingController();
  String _type = 'Entrenamiento';

  @override
  void dispose() {
    _title.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
              ),
              IconButton(onPressed: widget.onClose, icon: const Icon(Icons.close)),
            ],
          ),
          const SizedBox(height: 8),
            if (widget.events.isEmpty)
              const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
                child: Column(
                  children: [
                  CircleAvatar(
                    radius: 34,
                    backgroundColor: CX.greenDark,
                    child: Icon(Icons.calendar_month, color: CX.green, size: 32),
                  ),
                    SizedBox(height: 14),
                    Text('No hay eventos este día', style: TextStyle(color: CX.muted)),
                  ],
                ),
              )
            else
              ...widget.events.map((event) {
                final past = DateTime(
                  widget.day.year,
                  widget.day.month,
                  widget.day.day,
                ).isBefore(
                  DateTime(
                    DateTime.now().year,
                    DateTime.now().month,
                    DateTime.now().day,
                  ),
                );
                final isMatch = isMatchEventType(event.type);
                final key = calendarMatchKey(widget.day, event.title);
                final logged = widget.loggedKeys.contains(key);
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_icon(event.type), color: _color(event.type)),
                  title: Text(event.title),
                  subtitle: Text(
                    event.time.trim().isEmpty
                        ? event.type
                        : '${event.type} · ${event.time}',
                  ),
                  trailing: (isMatch && past)
                      ? (logged
                          ? const Chip(
                              label: Text('Resultado cargado'),
                              visualDensity: VisualDensity.compact,
                            )
                          : TextButton.icon(
                              onPressed: () => widget.onLogResult(event),
                              icon: const Icon(Icons.scoreboard_outlined, size: 16),
                              label: const Text('Cargar resultado'),
                            ))
                      : null,
                );
              }),
            const Divider(height: 28),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('CREAR UN EVENTO NUEVO', style: TextStyle(color: CX.faint, fontSize: 11, fontWeight: FontWeight.w900)),
            ),
            DropdownButtonFormField<String>(
              value: _type,
              items: const ['Entrenamiento', 'Partido', 'Torneo', 'Evento', 'Cumpleaños', 'Tarea']
                  .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                  .toList(),
              onChanged: (value) => setState(() => _type = value ?? _type),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Título'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _time,
              keyboardType: TextInputType.datetime,
              decoration: const InputDecoration(
                labelText: 'Hora',
                hintText: 'Ej: 19:30',
                prefixIcon: Icon(Icons.schedule_outlined),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () {
                final title = _title.text.trim();
                if (title.isEmpty) return;
                widget.onAdd(_CalendarEvent(type: _type, title: title, time: _time.text.trim()));
                _title.clear();
                _time.clear();
              },
              icon: const Icon(Icons.add),
              label: const Text('Agregar evento'),
            ),
          ],
        ),
      ),
    );
  }

  static String _weekday(int day) => const ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'][day - 1];
  static String _month(int month) => const ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'setiembre', 'octubre', 'noviembre', 'diciembre'][month - 1];
  static IconData _icon(String type) => switch (type) {
        'Partido' => Icons.sports_soccer_outlined,
        'Torneo' => Icons.emoji_events_outlined,
        'Evento' => Icons.event_outlined,
        'Cumpleaños' => Icons.cake_outlined,
        'Tarea' => Icons.task_alt,
        _ => Icons.flag_outlined,
      };
  static Color _color(String type) => switch (type) {
        'Partido' => CX.blue,
        'Torneo' => Colors.purple,
        'Evento' => Colors.indigo,
        'Cumpleaños' => Colors.pink,
        'Tarea' => Colors.orange,
        _ => CX.green,
      };
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
                Text(entry.key, style: const TextStyle(color: CX.muted, fontSize: 11)),
              ],
            ),
          )
          .toList(),
    );
  }
}

class _CalendarEvent {
  final String type;
  final String title;
  final String time;

  const _CalendarEvent({required this.type, required this.title, this.time = ''});

  Map<String, dynamic> toJson() => {'type': type, 'title': title, 'time': time};

  factory _CalendarEvent.fromJson(Map<String, dynamic> json) => _CalendarEvent(
        type: json['type'] as String? ?? 'Entrenamiento',
        title: json['title'] as String? ?? '',
        time: json['time'] as String? ?? '',
      );
}
