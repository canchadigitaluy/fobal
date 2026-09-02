// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:convert';
import 'dart:html' as html;
import 'dart:async';

import 'package:flutter/material.dart';

import '../data/cantera_data.dart';
import '../main.dart';
import '../services/offline_mutation_service.dart';

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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Asistencia guardada.')),
    );
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
            child: Container(
              constraints: const BoxConstraints(maxWidth: 380),
              padding: const EdgeInsets.all(20),
              decoration: CX.panelDecoration(),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.fact_check_outlined, color: CX.green, size: 32),
                  SizedBox(height: 12),
                  Text(
                    'Todavía no hay un plantel para pasar lista',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Cargá el equipo en "Mi equipo" y volvé acá para registrar la asistencia.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: CX.muted, fontSize: 12, height: 1.4),
                  ),
                ],
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: CX.panelDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Días y horarios de práctica',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
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
                ElevatedButton.icon(
                  onPressed: () => _saveSchedule(club, category),
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Guardar horarios'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: CX.panelDecoration(),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Asistencia de hoy: $present/${players.length}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _addPlayer(club, category),
                      icon: const Icon(Icons.person_add_alt_outlined),
                      label: const Text('Jugador'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (players.isEmpty)
                  const Text(
                    'Carga jugadores para poder marcar asistencia.',
                    style: TextStyle(color: CX.muted),
                  )
                else
                  ...players.map(
                    (player) => CheckboxListTile(
                      value: _presentIds.contains(player.id),
                      onChanged: (value) {
                        setState(() {
                          if (value == true) {
                            _presentIds.add(player.id);
                          } else {
                            _presentIds.remove(player.id);
                          }
                        });
                      },
                      title: Text(player.fullName.trim()),
                      subtitle: Text(
                        [player.position, player.status]
                            .where((item) => item.trim().isNotEmpty)
                            .join(' / '),
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () => _saveAttendance(club, category),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Guardar asistencia'),
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
