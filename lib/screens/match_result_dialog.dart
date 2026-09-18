import 'package:flutter/material.dart';

import '../data/cantera_data.dart';
import '../main.dart';
import '../ui/ui_kit.dart';

/// Fast, single-screen form to log or edit a match result by hand.
/// Returns the [MatchResult] on save, or null on cancel.
Future<MatchResult?> showMatchResultDialog(
  BuildContext context, {
  required String categoryId,
  MatchResult? existing,
  DateTime? initialDate,
  String? initialOpponent,
  String? calendarKey,

  /// Category's own players, for the optional "quién jugó / quién anotó"
  /// picker — only meaningful (and only shown) for manual/No-LUD categories,
  /// which have no league sync to source matchesPlayed/goals from.
  List<Player> players = const [],

  /// Best-effort lineup suggestion (from Alineación's saved history for this
  /// rival) to pre-check when creating a brand-new result. Ignored when
  /// editing an existing one — that already has its own real lineup.
  List<String> suggestedLineupIds = const [],
}) {
  return showDialog<MatchResult>(
    context: context,
    builder: (context) => _MatchResultDialog(
      categoryId: categoryId,
      existing: existing,
      initialDate: initialDate,
      initialOpponent: initialOpponent,
      calendarKey: calendarKey,
      players: players,
      suggestedLineupIds: suggestedLineupIds,
    ),
  );
}

class _MatchResultDialog extends StatefulWidget {
  final String categoryId;
  final MatchResult? existing;
  final DateTime? initialDate;
  final String? initialOpponent;
  final String? calendarKey;
  final List<Player> players;
  final List<String> suggestedLineupIds;

  const _MatchResultDialog({
    required this.categoryId,
    this.existing,
    this.initialDate,
    this.initialOpponent,
    this.suggestedLineupIds = const [],
    this.calendarKey,
    this.players = const [],
  });

  @override
  State<_MatchResultDialog> createState() => _MatchResultDialogState();
}

class _MatchResultDialogState extends State<_MatchResultDialog> {
  late DateTime _date;
  late final TextEditingController _opponent;
  late final TextEditingController _note;
  late String _venue;
  late String _kind;
  late int _goalsFor;
  late int _goalsAgainst;
  bool _showOpponentError = false;
  final Set<String> _lineup = {};
  final Map<String, int> _scorers = {};
  final Map<String, int> _minutes = {};
  bool _lineupSuggested = false;
  String _playerSearch = '';

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _date = e != null
        ? (DateTime.tryParse(e.date) ?? DateTime.now())
        : (widget.initialDate ?? DateTime.now());
    _opponent = TextEditingController(
      text: e?.opponent ?? widget.initialOpponent ?? '',
    );
    _note = TextEditingController(text: e?.note ?? '');
    _venue = e?.venue ?? 'home';
    _kind = e?.kind ?? 'oficial';
    _goalsFor = e?.goalsFor ?? 0;
    _goalsAgainst = e?.goalsAgainst ?? 0;
    if (e != null) {
      _lineup.addAll(e.lineupIds);
      for (final id in e.scorerIds) {
        _scorers[id] = (_scorers[id] ?? 0) + 1;
      }
      _minutes.addAll(e.minutesByPlayer);
    } else if (widget.suggestedLineupIds.isNotEmpty) {
      final validIds = widget.players.map((p) => p.id).toSet();
      _lineup.addAll(widget.suggestedLineupIds.where(validIds.contains));
      _lineupSuggested = _lineup.isNotEmpty;
    }
  }

  @override
  void dispose() {
    _opponent.dispose();
    _note.dispose();
    super.dispose();
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  void _save() {
    final opponent = _opponent.text.trim();
    if (opponent.isEmpty) {
      setState(() => _showOpponentError = true);
      return;
    }
    final e = widget.existing;
    final result = MatchResult(
      id: e?.id ?? 'result-${DateTime.now().microsecondsSinceEpoch}',
      categoryId: widget.categoryId,
      date: _date.toIso8601String().split('T').first,
      opponent: opponent,
      venue: _venue,
      goalsFor: _goalsFor,
      goalsAgainst: _goalsAgainst,
      kind: _kind,
      note: _note.text.trim(),
      calendarKey: widget.calendarKey ?? e?.calendarKey ?? '',
      lineupIds: _lineup.toList(),
      scorerIds: [
        for (final entry in _scorers.entries)
          for (var i = 0; i < entry.value; i++) entry.key,
      ],
      minutesByPlayer: {
        for (final id in _lineup) id: (_minutes[id] ?? 0).clamp(0, 240),
      },
    );
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final isLud = isLudCategoryId(widget.categoryId);
    return AlertDialog(
      title: Text(
        widget.existing == null ? 'Cargar resultado' : 'Editar resultado',
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isLud) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: CX.amber.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: CX.amber.withValues(alpha: .25)),
                  ),
                  child: const Text(
                    'Este es un registro personal — no reemplaza ni modifica '
                    'la tabla oficial de la liga.',
                    style: TextStyle(
                      color: CX.amber,
                      fontSize: 11.5,
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime.now().subtract(
                      const Duration(days: 730),
                    ),
                    lastDate: DateTime.now().add(const Duration(days: 7)),
                  );
                  if (picked != null) setState(() => _date = picked);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Fecha',
                    prefixIcon: Icon(Icons.calendar_month_outlined),
                  ),
                  child: Text(
                    _fmt(_date),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _opponent,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Rival',
                  errorText: _showOpponentError
                      ? 'Escribí el nombre del rival'
                      : null,
                ),
                onChanged: (_) {
                  if (_showOpponentError) {
                    setState(() => _showOpponentError = false);
                  }
                },
              ),
              const SizedBox(height: 14),
              _Segments(
                label: 'Condición',
                value: _venue,
                options: const {
                  'home': 'Local',
                  'away': 'Visitante',
                  'neutral': 'Neutral',
                },
                onChanged: (v) => setState(() => _venue = v),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _GoalStepper(
                      label: 'A favor',
                      value: _goalsFor,
                      onChanged: (v) => setState(() => _goalsFor = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _GoalStepper(
                      label: 'En contra',
                      value: _goalsAgainst,
                      onChanged: (v) => setState(() => _goalsAgainst = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _Segments(
                label: 'Tipo',
                value: _kind,
                options: const {
                  'oficial': 'Oficial',
                  'torneo': 'Torneo',
                  'amistoso': 'Amistoso',
                  'practica': 'Práctica',
                },
                onChanged: (v) => setState(() => _kind = v),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _note,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Nota (opcional)',
                  hintText: 'Una línea sobre el partido',
                ),
              ),
              if (widget.players.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  'QUIÉN JUGÓ Y QUIÉN ANOTÓ (OPCIONAL)',
                  style: const TextStyle(
                    color: CX.faint,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Alimenta partidos jugados y goles en el perfil de cada jugador.',
                  style: const TextStyle(color: CX.faint, fontSize: 10.5),
                ),
                if (_lineupSuggested) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Precargado desde la última alineación citada contra este rival — revisá y ajustá.',
                    style: const TextStyle(
                      color: CX.blue,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                if (widget.players.length > 8) ...[
                  TextField(
                    onChanged: (value) => setState(() => _playerSearch = value),
                    decoration: const InputDecoration(
                      hintText: 'Buscar jugador',
                      prefixIcon: Icon(Icons.search, size: 18),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (final player in widget.players.where(
                          (p) => p.fullName.toLowerCase().contains(
                            _playerSearch.trim().toLowerCase(),
                          ),
                        ))
                          _PlayerStatRow(
                            player: player,
                            played: _lineup.contains(player.id),
                            goals: _scorers[player.id] ?? 0,
                            minutes: _minutes[player.id] ?? 0,
                            onPlayedChanged: (played) => setState(() {
                              if (played) {
                                _lineup.add(player.id);
                                if ((_minutes[player.id] ?? 0) == 0) {
                                  _minutes[player.id] = 90;
                                }
                              } else {
                                _lineup.remove(player.id);
                                _scorers.remove(player.id);
                                _minutes.remove(player.id);
                              }
                            }),
                            onMinutesChanged: (minutes) => setState(() {
                              _minutes[player.id] = minutes.clamp(0, 240);
                              if (minutes > 0) _lineup.add(player.id);
                            }),
                            onGoalsChanged: (goals) => setState(() {
                              if (goals <= 0) {
                                _scorers.remove(player.id);
                              } else {
                                _scorers[player.id] = goals;
                                _lineup.add(player.id);
                                if ((_minutes[player.id] ?? 0) == 0) {
                                  _minutes[player.id] = 90;
                                }
                              }
                            }),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(onPressed: _save, child: const Text('Guardar')),
      ],
    );
  }
}

class _PlayerStatRow extends StatelessWidget {
  final Player player;
  final bool played;
  final int goals;
  final int minutes;
  final ValueChanged<bool> onPlayedChanged;
  final ValueChanged<int> onGoalsChanged;
  final ValueChanged<int> onMinutesChanged;

  const _PlayerStatRow({
    required this.player,
    required this.played,
    required this.goals,
    required this.minutes,
    required this.onPlayedChanged,
    required this.onGoalsChanged,
    required this.onMinutesChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Checkbox(
            value: played,
            onChanged: (value) => onPlayedChanged(value ?? false),
          ),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    player.fullName.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (player.hasAvailabilityWarning) ...[
                  const SizedBox(width: 6),
                  AvailabilityChip(player.availability, compact: true),
                ],
              ],
            ),
          ),
          SizedBox(
            width: 58,
            child: TextFormField(
              key: ValueKey('${player.id}-$played'),
              initialValue: played && minutes > 0 ? '$minutes' : '',
              enabled: played,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(hintText: 'min', isDense: true),
              onChanged: (value) => onMinutesChanged(int.tryParse(value) ?? 0),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: goals > 0 ? () => onGoalsChanged(goals - 1) : null,
            icon: const Icon(Icons.remove, size: 16),
          ),
          SizedBox(
            width: 18,
            child: Text(
              '$goals',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => onGoalsChanged(goals + 1),
            icon: const Icon(Icons.add, size: 16),
          ),
        ],
      ),
    );
  }
}

class _Segments extends StatelessWidget {
  final String label;
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;

  const _Segments({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: CX.faint,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: options.entries.map((entry) {
            final selected = entry.key == value;
            return ChoiceChip(
              label: Text(entry.value),
              selected: selected,
              showCheckmark: false,
              onSelected: (_) => onChanged(entry.key),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _GoalStepper extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  const _GoalStepper({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: CX.panel2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CX.line),
      ),
      child: Column(
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: value > 0 ? () => onChanged(value - 1) : null,
                icon: const Icon(Icons.remove, size: 18),
              ),
              Text(
                '$value',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: value < 30 ? () => onChanged(value + 1) : null,
                icon: const Icon(Icons.add, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
