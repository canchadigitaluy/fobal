import 'package:flutter/material.dart';

import '../data/cantera_data.dart';
import '../main.dart';

/// Focused dialog to set a player's availability — the 5 canonical states
/// plus the optional note/return date/suspension count already on [Player].
/// Returns the updated player, or null if cancelled.
Future<Player?> showPlayerAvailabilityDialog(
  BuildContext context, {
  required Player player,
}) {
  return showDialog<Player>(
    context: context,
    builder: (context) => _PlayerAvailabilityDialog(player: player),
  );
}

class _PlayerAvailabilityDialog extends StatefulWidget {
  final Player player;
  const _PlayerAvailabilityDialog({required this.player});

  @override
  State<_PlayerAvailabilityDialog> createState() =>
      _PlayerAvailabilityDialogState();
}

class _PlayerAvailabilityDialogState
    extends State<_PlayerAvailabilityDialog> {
  late PlayerAvailability _availability;
  late final TextEditingController _detail;
  late final TextEditingController _returnDate;
  late final TextEditingController _suspensionDates;

  @override
  void initState() {
    super.initState();
    _availability = widget.player.availability;
    _detail = TextEditingController(text: widget.player.statusDetail);
    _returnDate = TextEditingController(text: widget.player.expectedReturnDate);
    _suspensionDates = TextEditingController(
      text: widget.player.suspensionDates > 0
          ? '${widget.player.suspensionDates}'
          : '',
    );
  }

  @override
  void dispose() {
    _detail.dispose();
    _returnDate.dispose();
    _suspensionDates.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.pop(
      context,
      widget.player.copyWith(
        status: _availability.label,
        statusDetail: _detail.text.trim(),
        expectedReturnDate: _returnDate.text.trim(),
        suspensionDates: _availability == PlayerAvailability.sancionado
            ? (int.tryParse(_suspensionDates.text.trim()) ?? 0)
            : 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showReturnDate = _availability == PlayerAvailability.lesionado ||
        _availability == PlayerAvailability.tocado;
    final showSuspensionCount = _availability == PlayerAvailability.sancionado;
    return AlertDialog(
      title: Text('Disponibilidad de ${widget.player.fullName.trim()}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in PlayerAvailability.values)
                  ChoiceChip(
                    label: Text(option.label),
                    selected: _availability == option,
                    onSelected: (_) => setState(() => _availability = option),
                    selectedColor: option.color.withValues(alpha: .18),
                    labelStyle: TextStyle(
                      color: _availability == option ? option.color : CX.muted,
                      fontWeight: FontWeight.w800,
                    ),
                    side: BorderSide(
                      color: _availability == option
                          ? option.color.withValues(alpha: .5)
                          : CX.line,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _detail,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Nota breve (opcional)',
                hintText: 'Ej: molestia en el isquio, vuelve a entrenar el lunes',
              ),
            ),
            if (showReturnDate) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _returnDate,
                decoration: const InputDecoration(
                  labelText: 'Regreso estimado (opcional)',
                  hintText: 'Ej: 15/09 o "en 2 semanas"',
                ),
              ),
            ],
            if (showSuspensionCount) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _suspensionDates,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Fechas de sanción (opcional)',
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
