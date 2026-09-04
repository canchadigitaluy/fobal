import 'package:flutter/material.dart';

import '../data/cantera_data.dart';
import '../main.dart';

/// Fast, single-screen form to log or edit a match result by hand.
/// Returns the [MatchResult] on save, or null on cancel.
Future<MatchResult?> showMatchResultDialog(
  BuildContext context, {
  required String categoryId,
  MatchResult? existing,
  DateTime? initialDate,
  String? initialOpponent,
  String? calendarKey,
}) {
  return showDialog<MatchResult>(
    context: context,
    builder: (context) => _MatchResultDialog(
      categoryId: categoryId,
      existing: existing,
      initialDate: initialDate,
      initialOpponent: initialOpponent,
      calendarKey: calendarKey,
    ),
  );
}

class _MatchResultDialog extends StatefulWidget {
  final String categoryId;
  final MatchResult? existing;
  final DateTime? initialDate;
  final String? initialOpponent;
  final String? calendarKey;

  const _MatchResultDialog({
    required this.categoryId,
    this.existing,
    this.initialDate,
    this.initialOpponent,
    this.calendarKey,
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
    );
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Cargar resultado' : 'Editar resultado'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime.now().subtract(const Duration(days: 730)),
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
                  errorText: _showOpponentError ? 'Escribí el nombre del rival' : null,
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
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _save,
          child: const Text('Guardar'),
        ),
      ],
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
            fontSize: 10,
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
              fontSize: 9,
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
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
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
