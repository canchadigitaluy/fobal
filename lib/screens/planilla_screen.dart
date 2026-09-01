// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:convert';
import 'dart:html' as html;

import 'package:flutter/material.dart';

import '../data/cantera_data.dart';
import '../main.dart';

class PlanillaScreen extends StatefulWidget {
  const PlanillaScreen({super.key});

  @override
  State<PlanillaScreen> createState() => _PlanillaScreenState();
}

class _PlanillaScreenState extends State<PlanillaScreen> {
  final _titleController = TextEditingController();
  final _rivalController = TextEditingController();
  final _dateController = TextEditingController();
  final List<String?> _xi = List<String?>.filled(11, null);
  final List<String?> _subs = List<String?>.filled(7, null);
  String? _categoryId;

  @override
  void dispose() {
    _titleController.dispose();
    _rivalController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  String _storageKey(CanteraClub club, CategorySquad category) =>
      'cantera_lineup_${club.id}_${category.id}';

  void _load(CanteraClub club, CategorySquad category) {
    final raw = html.window.localStorage[_storageKey(club, category)];
    if (raw == null || raw.isEmpty) return;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      _titleController.text = json['title'] as String? ?? '';
      _rivalController.text = json['rival'] as String? ?? '';
      _dateController.text = json['date'] as String? ?? '';
      final xi = List<String?>.from(json['xi'] as List<dynamic>? ?? []);
      final subs = List<String?>.from(json['subs'] as List<dynamic>? ?? []);
      for (var i = 0; i < _xi.length; i++) {
        _xi[i] = i < xi.length ? xi[i] : null;
      }
      for (var i = 0; i < _subs.length; i++) {
        _subs[i] = i < subs.length ? subs[i] : null;
      }
    } catch (_) {
      html.window.localStorage.remove(_storageKey(club, category));
    }
  }

  void _save(CanteraClub club, CategorySquad category) {
    final title = _titleController.text.trim().isEmpty
        ? '${category.name} XI vs ${_rivalController.text.trim()}'
        : _titleController.text.trim();
    final payload = {
      'title': title,
      'rival': _rivalController.text.trim(),
      'date': _dateController.text.trim(),
      'xi': _xi,
      'subs': _subs,
      'savedAt': DateTime.now().toIso8601String(),
    };
    html.window.localStorage[_storageKey(club, category)] = jsonEncode(payload);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Planilla guardada: $title')),
    );
  }

  void _export(CategorySquad category, List<Player> players) {
    final byId = {for (final player in players) player.id: player.fullName};
    final lines = [
      _titleController.text.trim().isEmpty
          ? '${category.name} XI'
          : _titleController.text.trim(),
      if (_dateController.text.trim().isNotEmpty)
        'Fecha: ${_dateController.text.trim()}',
      if (_rivalController.text.trim().isNotEmpty)
        'Rival: ${_rivalController.text.trim()}',
      '',
      'Titulares',
      ...List.generate(11, (i) => '${i + 1}. ${byId[_xi[i]] ?? '-'}'),
      '',
      'Suplentes',
      ...List.generate(_subs.length, (i) => '${i + 12}. ${byId[_subs[i]] ?? '-'}'),
    ].join('\n');
    final blob = html.Blob([lines], 'text/plain;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..download = 'planilla_${category.name.replaceAll(' ', '_')}.txt'
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final club = scope.club;
    final categoryId = club.categories.any((item) => item.id == _categoryId)
        ? _categoryId
        : club.categories.isEmpty
            ? null
            : club.categories.first.id;
    if (_categoryId != categoryId) {
      _categoryId = categoryId;
      if (categoryId != null) {
        _load(club, club.categories.firstWhere((item) => item.id == categoryId));
      }
    }
    final category = categoryId == null
        ? null
        : club.categories.firstWhere((item) => item.id == categoryId);
    final players = category == null
        ? <Player>[]
        : club.players.where((item) => item.categoryId == category.id).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Planilla'),
            Text(
              'XI, suplentes y exportacion',
              style: TextStyle(color: CX.faint, fontSize: 10),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 30),
          children: [
            if (category == null)
              const _EmptyLineup()
            else ...[
              _LineupMeta(
                categories: club.categories,
                selectedCategoryId: category.id,
                titleController: _titleController,
                rivalController: _rivalController,
                dateController: _dateController,
                onCategory: (value) => setState(() => _categoryId = value),
              ),
              const SizedBox(height: 14),
              _PitchBoard(
                xi: _xi,
                players: players,
                onChanged: (index, value) => setState(() => _xi[index] = value),
              ),
              const SizedBox(height: 14),
              _SubsBoard(
                subs: _subs,
                players: players,
                usedIds: _xi.whereType<String>().toSet(),
                onChanged: (index, value) =>
                    setState(() => _subs[index] = value),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _save(club, category),
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Guardar planilla'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _export(category, players),
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Exportar'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LineupMeta extends StatelessWidget {
  final List<CategorySquad> categories;
  final String selectedCategoryId;
  final TextEditingController titleController;
  final TextEditingController rivalController;
  final TextEditingController dateController;
  final ValueChanged<String?> onCategory;

  const _LineupMeta({
    required this.categories,
    required this.selectedCategoryId,
    required this.titleController,
    required this.rivalController,
    required this.dateController,
    required this.onCategory,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: CX.panelDecoration(),
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            value: selectedCategoryId,
            decoration: const InputDecoration(labelText: 'Categoria'),
            items: categories
                .map((item) => DropdownMenuItem(value: item.id, child: Text(item.name)))
                .toList(),
            onChanged: onCategory,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: titleController,
            decoration: const InputDecoration(labelText: 'Titulo'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: rivalController,
                  decoration: const InputDecoration(labelText: 'Rival'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: dateController,
                  decoration: const InputDecoration(labelText: 'Fecha'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PitchBoard extends StatelessWidget {
  final List<String?> xi;
  final List<Player> players;
  final void Function(int index, String? value) onChanged;

  const _PitchBoard({
    required this.xi,
    required this.players,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0E251A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CX.green.withValues(alpha: .24)),
      ),
      child: Column(
        children: [
          const Text('Titulares', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 2.4,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: 11,
            itemBuilder: (context, index) => _PlayerChipSelect(
              label: index == 0 ? 'Golero' : 'Puesto ${index + 1}',
              color: index == 0 ? CX.amber : CX.green,
              value: xi[index],
              players: players,
              onChanged: (value) => onChanged(index, value),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubsBoard extends StatelessWidget {
  final List<String?> subs;
  final List<Player> players;
  final Set<String> usedIds;
  final void Function(int index, String? value) onChanged;

  const _SubsBoard({
    required this.subs,
    required this.players,
    required this.usedIds,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: CX.panelDecoration(),
      child: Column(
        children: [
          const Text('Suplentes', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          ...List.generate(
            subs.length,
            (index) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _PlayerChipSelect(
                label: 'Suplente ${index + 1}',
                color: CX.blue,
                value: subs[index],
                players: players
                    .where((player) => !usedIds.contains(player.id) || player.id == subs[index])
                    .toList(),
                onChanged: (value) => onChanged(index, value),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerChipSelect extends StatelessWidget {
  final String label;
  final Color color;
  final String? value;
  final List<Player> players;
  final ValueChanged<String?> onChanged;

  const _PlayerChipSelect({
    required this.label,
    required this.color,
    required this.value,
    required this.players,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: players.any((player) => player.id == value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: color.withValues(alpha: .12),
      ),
      items: [
        const DropdownMenuItem<String>(value: null, child: Text('-')),
        ...players.map(
          (player) => DropdownMenuItem(
            value: player.id,
            child: Text(player.fullName, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: onChanged,
    );
  }
}

class _EmptyLineup extends StatelessWidget {
  const _EmptyLineup();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: CX.panelDecoration(),
      child: const Text('Primero selecciona o carga una categoria con jugadores.'),
    );
  }
}
