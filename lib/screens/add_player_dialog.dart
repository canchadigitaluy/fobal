import 'package:flutter/material.dart';

import '../data/cantera_data.dart';

/// Shared "agregar jugador" form — used by Mi equipo and Asistencia, which
/// used to each carry their own slightly different dialog (one skipped edad
/// y pie hábil entirely, the other split a single "nombre completo" field on
/// whitespace). One form now, with the fuller field set, so a player's
/// completeness no longer depends on which screen the DT happened to use.
/// Availability/status stays out of this — that's player_availability_dialog's
/// job, kept separate on purpose.
/// Normalized "nombre apellido" of every player already in the category —
/// used only to warn (never block) on an apparent duplicate.
Set<String> normalizedPlayerNames(Iterable<Player> players) => {
      for (final p in players)
        '${p.firstName.trim().toLowerCase()} ${p.lastName.trim().toLowerCase()}'
            .trim(),
    };

Future<Player?> showAddPlayerDialog(
  BuildContext context, {
  required String categoryId,
  Set<String> existingNames = const {},
}) {
  return showDialog<Player>(
    context: context,
    builder: (context) =>
        _AddPlayerDialog(categoryId: categoryId, existingNames: existingNames),
  );
}

class _AddPlayerDialog extends StatefulWidget {
  final String categoryId;
  final Set<String> existingNames;
  const _AddPlayerDialog({
    required this.categoryId,
    this.existingNames = const {},
  });

  @override
  State<_AddPlayerDialog> createState() => _AddPlayerDialogState();
}

class _AddPlayerDialogState extends State<_AddPlayerDialog> {
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _age = TextEditingController();
  final _position = TextEditingController();
  final _secondary = TextEditingController();
  final _foot = TextEditingController();
  bool _showError = false;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _age.dispose();
    _position.dispose();
    _secondary.dispose();
    _foot.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final firstName = _firstName.text.trim();
    final lastName = _lastName.text.trim();
    if (firstName.length < 2 || lastName.length < 2) {
      setState(() => _showError = true);
      return;
    }
    final key = '${firstName.toLowerCase()} ${lastName.toLowerCase()}'.trim();
    if (widget.existingNames.contains(key)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Nombre repetido'),
          content: Text(
            'Ya hay un jugador llamado "$firstName $lastName" en esta '
            'categoría. ¿Agregarlo igual?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Agregar igual'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    if (!mounted) return;
    Navigator.pop(
      context,
      Player(
        id: 'player-${DateTime.now().microsecondsSinceEpoch}',
        categoryId: widget.categoryId,
        firstName: firstName,
        lastName: lastName,
        age: int.tryParse(_age.text.trim()) ?? 0,
        position: _position.text.trim(),
        secondaryPositions: _secondary.text.trim(),
        dominantFoot: _foot.text.trim(),
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
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _firstName,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Nombre',
                      errorText: _showError && _firstName.text.trim().length < 2
                          ? 'Requerido'
                          : null,
                    ),
                    onChanged: (_) {
                      if (_showError) setState(() => _showError = false);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _lastName,
                    decoration: InputDecoration(
                      labelText: 'Apellido',
                      errorText: _showError && _lastName.text.trim().length < 2
                          ? 'Requerido'
                          : null,
                    ),
                    onChanged: (_) {
                      if (_showError) setState(() => _showError = false);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _age,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Edad (opcional)'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _foot,
                    decoration: const InputDecoration(
                      labelText: 'Pie hábil (opcional)',
                      hintText: 'Derecho / Izquierdo',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _position,
              decoration: const InputDecoration(labelText: 'Posición principal'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _secondary,
              decoration: const InputDecoration(labelText: 'Posiciones secundarias'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.add),
          label: const Text('Añadir jugador'),
        ),
      ],
    );
  }
}
