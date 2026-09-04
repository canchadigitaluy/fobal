// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:convert';
import 'dart:html' as html;
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../data/cantera_data.dart';
import '../main.dart';
import '../services/offline_mutation_service.dart';
import '../state/section_handoff.dart';
import '../ui/ui_kit.dart';

class AlineacionScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const AlineacionScreen({super.key, this.onBack});

  @override
  State<AlineacionScreen> createState() => _AlineacionScreenState();
}

class _AlineacionScreenState extends State<AlineacionScreen> {
  final _rivalController = TextEditingController();
  final _dateController = TextEditingController();
  final _titleController = TextEditingController();
  final _captureKey = GlobalKey();
  final List<String?> _xi = List<String?>.filled(11, null);
  final List<String?> _subs = List<String?>.filled(7, null);
  final Map<int, Offset> _customSpots = {};
  List<_SavedAlignment> _savedAlignments = const [];
  String? _categoryId;
  String _formation = '4-4-2';
  bool _editing = false;

  static const _formations = <String, List<_Spot>>{
    '4-4-2': [
      _Spot('POR', .50, .91, true),
      _Spot('LI', .18, .72, false),
      _Spot('Z1', .39, .75, false),
      _Spot('Z2', .61, .75, false),
      _Spot('LD', .82, .72, false),
      _Spot('MI', .20, .48, false),
      _Spot('MC', .41, .51, false),
      _Spot('MC', .59, .51, false),
      _Spot('MD', .80, .48, false),
      _Spot('DC', .39, .22, false),
      _Spot('DC', .61, .22, false),
    ],
    '4-3-3': [
      _Spot('POR', .50, .91, true),
      _Spot('LI', .18, .72, false),
      _Spot('Z1', .39, .75, false),
      _Spot('Z2', .61, .75, false),
      _Spot('LD', .82, .72, false),
      _Spot('M5', .50, .56, false),
      _Spot('INT', .32, .45, false),
      _Spot('INT', .68, .45, false),
      _Spot('EI', .20, .22, false),
      _Spot('DC', .50, .17, false),
      _Spot('ED', .80, .22, false),
    ],
    '4-2-3-1': [
      _Spot('POR', .50, .91, true),
      _Spot('LI', .18, .72, false),
      _Spot('Z1', .39, .75, false),
      _Spot('Z2', .61, .75, false),
      _Spot('LD', .82, .72, false),
      _Spot('MC', .39, .56, false),
      _Spot('MC', .61, .56, false),
      _Spot('EI', .22, .36, false),
      _Spot('MP', .50, .34, false),
      _Spot('ED', .78, .36, false),
      _Spot('DC', .50, .16, false),
    ],
    '3-5-2': [
      _Spot('POR', .50, .91, true),
      _Spot('Z1', .31, .75, false),
      _Spot('Z2', .50, .78, false),
      _Spot('Z3', .69, .75, false),
      _Spot('CAI', .16, .50, false),
      _Spot('MC', .38, .53, false),
      _Spot('M5', .50, .45, false),
      _Spot('MC', .62, .53, false),
      _Spot('CAD', .84, .50, false),
      _Spot('DC', .39, .20, false),
      _Spot('DC', .61, .20, false),
    ],
  };

  List<_Spot> get _spots => _formations[_formation] ?? _formations.values.first;

  @override
  void initState() {
    super.initState();
    _titleController.addListener(_refreshPitchHeader);
    _rivalController.addListener(_refreshPitchHeader);
    _dateController.addListener(_refreshPitchHeader);
  }

  LineupHint? _hint;
  bool _hintConsumed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncCategory();
    if (!_hintConsumed) {
      final actions = ShellActions.maybeOf(context);
      final hint = actions?.takeLineupHint();
      if (hint != null) {
        _hintConsumed = true;
        _hint = hint;
      }
    }
  }

  /// Reacts to a club/category change. Runs here (not in build) because
  /// [_load] writes to text controllers whose listeners call setState, which
  /// is illegal during build and was leaving the screen blank.
  void _syncCategory() {
    final club = AppScope.of(context).club;
    final next = club.categories.any((c) => c.id == _categoryId)
        ? _categoryId
        : club.categories.isEmpty
            ? null
            : club.categories.first.id;
    if (_categoryId == next) return;
    _categoryId = next;
    _editing = false;
    if (next != null) {
      _load(club, club.categories.firstWhere((c) => c.id == next));
    }
  }

  void _refreshPitchHeader() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _titleController.removeListener(_refreshPitchHeader);
    _rivalController.removeListener(_refreshPitchHeader);
    _dateController.removeListener(_refreshPitchHeader);
    _rivalController.dispose();
    _dateController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  String _storageKey(CanteraClub club, CategorySquad category) =>
      'cantera_alignment_${club.id}_${category.id}';

  String _historyKey(CanteraClub club, CategorySquad category) =>
      'cantera_alignment_history_${club.id}_${category.id}';

  void _load(CanteraClub club, CategorySquad category) {
    _loadHistory(club, category);
    final raw = html.window.localStorage[_storageKey(club, category)];
    if (raw == null || raw.isEmpty) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _titleController.text = data['title'] as String? ?? '';
      _rivalController.text = data['rival'] as String? ?? '';
      _dateController.text = data['date'] as String? ?? '';
      _formation = data['formation'] as String? ?? _formation;
      final xi = List<String?>.from(data['xi'] as List<dynamic>? ?? []);
      final subs = List<String?>.from(data['subs'] as List<dynamic>? ?? []);
      final custom = data['customSpots'] as Map<String, dynamic>? ?? {};
      _customSpots
        ..clear()
        ..addEntries(
          custom.entries.map((entry) {
            final values = List<num>.from(entry.value as List<dynamic>? ?? []);
            return MapEntry(
              int.tryParse(entry.key) ?? 0,
              Offset(
                values.isNotEmpty ? values[0].toDouble() : .5,
                values.length > 1 ? values[1].toDouble() : .5,
              ),
            );
          }),
        );
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

  void _loadHistory(CanteraClub club, CategorySquad category) {
    final raw = html.window.localStorage[_historyKey(club, category)];
    if (raw == null || raw.isEmpty) {
      _savedAlignments = const [];
      return;
    }
    try {
      _savedAlignments = (jsonDecode(raw) as List<dynamic>)
          .map((item) => _SavedAlignment.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      _savedAlignments = const [];
      html.window.localStorage.remove(_historyKey(club, category));
    }
  }

  Map<String, dynamic> _alignmentPayload(CategorySquad category, String title) {
    return {
      'title': title,
      'categoryName': category.name,
      'rival': _rivalController.text.trim(),
      'date': _dateController.text.trim(),
      'formation': _formation,
      'xi': _xi,
      'subs': _subs,
      'customSpots': _customSpots.map(
        (key, value) => MapEntry('$key', [value.dx, value.dy]),
      ),
      'savedAt': DateTime.now().toIso8601String(),
    };
  }

  void _save(CanteraClub club, CategorySquad category) {
    final title = _titleController.text.trim().isEmpty
        ? '${category.name} vs ${_rivalController.text.trim()}'
        : _titleController.text.trim();
    final payload = _alignmentPayload(category, title);
    html.window.localStorage[_storageKey(club, category)] = jsonEncode(payload);
    final nextHistory = [
      _SavedAlignment.fromJson(payload),
      ..._savedAlignments.where((item) => item.title != title),
    ].take(12).toList();
    html.window.localStorage[_historyKey(club, category)] = jsonEncode(
      nextHistory.map((item) => item.toJson()).toList(),
    );
    unawaited(OfflineMutationService.instance.saveTacticalDataOfflineFirst(
      type: 'alignment',
      title: title,
      content: payload,
      categoryId: category.id,
    ));
    setState(() => _savedAlignments = nextHistory);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Guardada en Alineación: $title')));
  }

  Future<void> _exportImage(CategorySquad category) async {
    final boundary =
        _captureKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return;
    final blob = html.Blob([bytes.buffer.asUint8List()], 'image/png');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..download = 'alineacion_${category.name.replaceAll(' ', '_')}.png'
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  void _exportCitation(CategorySquad category, List<Player> players) {
    final names = {for (final player in players) player.id: player.fullName};
    final title = _titleController.text.trim().isEmpty
        ? 'Citación ${category.name}'
        : _titleController.text.trim();
    final selected = [
      ..._xi.whereType<String>(),
      ..._subs.whereType<String>(),
    ];
    final content = [
      title,
      if (_rivalController.text.trim().isNotEmpty)
        'Rival: ${_rivalController.text.trim()}',
      if (_dateController.text.trim().isNotEmpty)
        'Fecha: ${_dateController.text.trim()}',
      'Categoría: ${category.name}',
      '',
      'Convocados',
      ...selected.asMap().entries.map(
            (entry) => '${entry.key + 1}. ${names[entry.value] ?? '-'}',
          ),
      '',
      'Mensaje',
      'Quedan citados para el próximo compromiso. Confirmar disponibilidad.',
    ].join('\n');
    final blob = html.Blob([content], 'text/plain;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..download = 'citacion_${category.name.replaceAll(' ', '_')}.txt'
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  void _openSaved(_SavedAlignment saved) {
    _titleController.text = saved.title;
    _rivalController.text = saved.rival;
    _dateController.text = saved.date;
    setState(() {
      _formation = saved.formation;
      for (var i = 0; i < _xi.length; i++) {
        _xi[i] = i < saved.xi.length ? saved.xi[i] : null;
      }
      for (var i = 0; i < _subs.length; i++) {
        _subs[i] = i < saved.subs.length ? saved.subs[i] : null;
      }
      _customSpots
        ..clear()
        ..addAll(saved.customSpots);
      _editing = true;
    });
  }

  void _createNew() {
    _titleController.clear();
    _rivalController.clear();
    _dateController.clear();
    setState(() {
      _formation = '4-4-2';
      for (var i = 0; i < _xi.length; i++) {
        _xi[i] = null;
      }
      for (var i = 0; i < _subs.length; i++) {
        _subs[i] = null;
      }
      _customSpots.clear();
      _editing = true;
    });
  }

  void _addFirstAvailable(Player player) {
    if (_xi.contains(player.id) || _subs.contains(player.id)) return;
    final xiIndex = _xi.indexWhere((id) => id == null);
    if (xiIndex != -1) {
      setState(() => _xi[xiIndex] = player.id);
      return;
    }
    final subIndex = _subs.indexWhere((id) => id == null);
    if (subIndex != -1) setState(() => _subs[subIndex] = player.id);
  }

  Future<void> _pickPlayer({
    required List<Player> players,
    required Set<String> usedIds,
    String? currentValue,
    required String title,
    required ValueChanged<String?> onPick,
  }) async {
    final picked = await showModalBottomSheet<String?>(
      context: context,
      backgroundColor: CX.panel,
      isScrollControlled: true,
      builder: (context) => _PlayerPickerSheet(
        title: title,
        players: players
            .where(
              (player) =>
                  !usedIds.contains(player.id) || player.id == currentValue,
            )
            .toList(),
      ),
    );
    onPick(picked);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final club = scope.club;
    final selectedCategoryId = club.categories.any((c) => c.id == _categoryId)
        ? _categoryId
        : club.categories.isEmpty
        ? null
        : club.categories.first.id;
    final category = selectedCategoryId == null
        ? null
        : club.categories.firstWhere((c) => c.id == selectedCategoryId);
    final players = category == null
        ? <Player>[]
        : club.players.where((p) => p.categoryId == category.id).toList();
    final playerById = {for (final player in players) player.id: player};

    return Scaffold(
      appBar: AppBar(
        leading: _editing
            ? IconButton(
                tooltip: 'Volver a alineaciones',
                onPressed: () => setState(() => _editing = false),
                icon: const Icon(Icons.arrow_back),
              )
            : null,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Alineación & citaciones'),
            Text(
              'XI inicial, banco y citación',
              style: TextStyle(color: CX.faint, fontSize: 10),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
          children: [
            if (_hint != null) ...[
              _LineupHintBanner(
                hint: _hint!,
                onDismiss: () => setState(() => _hint = null),
              ),
              const SizedBox(height: 12),
            ],
            if (category == null)
              const EmptyStatePanel(
                icon: Icons.account_tree_outlined,
                title: 'Primero cargá una categoría',
                message: 'Creá una categoría con jugadores para poder armar '
                    'la alineación y la citación.',
              )
            else if (!_editing) ...[
              _AlignmentStart(
                categories: club.categories,
                categoryId: category.id,
                players: players,
                saved: _savedAlignments,
                onCategory: (value) => setState(() => _categoryId = value),
                onCreate: _createNew,
                onOpen: _openSaved,
              ),
            ] else ...[
              _AlignmentHeader(
                categories: club.categories,
                categoryId: category.id,
                titleController: _titleController,
                rivalController: _rivalController,
                dateController: _dateController,
                formation: _formation,
                formations: _formations.keys.toList(),
                onCategory: (value) => setState(() => _categoryId = value),
                onFormation: (value) {
                  if (value == null) return;
                  setState(() {
                    _formation = value;
                    _customSpots.clear();
                  });
                },
              ),
              const SizedBox(height: 12),
              _LineupProgressStrip(
                xiFilled: _xi.where((id) => id != null).length,
                xiTotal: _xi.length,
                subsFilled: _subs.where((id) => id != null).length,
                subsTotal: _subs.length,
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 900;
                  final pitch = _Pitch(
                    repaintKey: _captureKey,
                    categoryName: category.name,
                    title: _titleController.text.trim(),
                    rival: _rivalController.text.trim(),
                    date: _dateController.text.trim(),
                    spots: _spots,
                    customSpots: _customSpots,
                    xi: _xi,
                    players: playerById,
                    onMove: (index, spot) {
                      setState(() => _customSpots[index] = spot);
                    },
                    onTap: (index) => _pickPlayer(
                      players: players,
                      usedIds: {
                        ..._xi.whereType<String>(),
                        ..._subs.whereType<String>(),
                      },
                      currentValue: _xi[index],
                      title: 'Elegir ${_spots[index].label}',
                      onPick: (value) => setState(() => _xi[index] = value),
                    ),
                  );
                  final panel = _LineupPlayerPanel(
                    players: players,
                    usedIds: {
                      ..._xi.whereType<String>(),
                      ..._subs.whereType<String>(),
                    },
                    onAdd: _addFirstAvailable,
                  );
                  if (!wide) {
                    return Column(
                      children: [pitch, const SizedBox(height: 12), panel],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 6, child: pitch),
                      const SizedBox(width: 14),
                      Expanded(flex: 4, child: panel),
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              _Bench(
                subs: _subs,
                players: playerById,
                onTap: (index) => _pickPlayer(
                  players: players,
                  usedIds: {
                    ..._xi.whereType<String>(),
                    ..._subs.whereType<String>(),
                  },
                  currentValue: _subs[index],
                  title: 'Elegir suplente',
                  onPick: (value) => setState(() => _subs[index] = value),
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: 190,
                    child: ElevatedButton.icon(
                      onPressed: () => _save(club, category),
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Guardar'),
                    ),
                  ),
                  SizedBox(
                    width: 190,
                    child: OutlinedButton.icon(
                      onPressed: () => _exportImage(category),
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Exportar PNG'),
                    ),
                  ),
                  SizedBox(
                    width: 190,
                    child: OutlinedButton.icon(
                      onPressed: () => _exportCitation(category, players),
                      icon: const Icon(Icons.outgoing_mail),
                      label: const Text('Citación'),
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

/// Read-only "qué falta" readout: never picks players on its own, just
/// counts what the DT already placed on the pitch and the bench.
class _LineupProgressStrip extends StatelessWidget {
  final int xiFilled;
  final int xiTotal;
  final int subsFilled;
  final int subsTotal;

  const _LineupProgressStrip({
    required this.xiFilled,
    required this.xiTotal,
    required this.subsFilled,
    required this.subsTotal,
  });

  @override
  Widget build(BuildContext context) {
    final xiDone = xiFilled == xiTotal;
    final subsStarted = subsFilled > 0;
    return Row(
      children: [
        Expanded(
          child: _chip(
            icon: Icons.sports_soccer,
            label: 'XI titular',
            value: '$xiFilled/$xiTotal',
            color: xiDone ? CX.green : CX.amber,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _chip(
            icon: Icons.groups_outlined,
            label: 'Banco',
            value: '$subsFilled/$subsTotal',
            color: subsStarted ? CX.green : CX.faint,
          ),
        ),
      ],
    );
  }

  Widget _chip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: CX.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CX.line),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(color: CX.muted, fontSize: 11.5, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _AlignmentHeader extends StatelessWidget {
  final List<CategorySquad> categories;
  final String categoryId;
  final TextEditingController titleController;
  final TextEditingController rivalController;
  final TextEditingController dateController;
  final String formation;
  final List<String> formations;
  final ValueChanged<String?> onCategory;
  final ValueChanged<String?> onFormation;

  const _AlignmentHeader({
    required this.categories,
    required this.categoryId,
    required this.titleController,
    required this.rivalController,
    required this.dateController,
    required this.formation,
    required this.formations,
    required this.onCategory,
    required this.onFormation,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: CX.panelDecoration(),
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            value: categoryId,
            decoration: const InputDecoration(labelText: 'Categoría'),
            items: categories
                .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                .toList(),
            onChanged: onCategory,
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: formation,
            decoration: const InputDecoration(labelText: 'Formación'),
            items: formations
                .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                .toList(),
            onChanged: onFormation,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: titleController,
            decoration: const InputDecoration(
              labelText: 'Nombre de la alineación',
            ),
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

class _AlignmentStart extends StatelessWidget {
  final List<CategorySquad> categories;
  final String categoryId;
  final List<Player> players;
  final List<_SavedAlignment> saved;
  final ValueChanged<String?> onCategory;
  final VoidCallback onCreate;
  final ValueChanged<_SavedAlignment> onOpen;

  const _AlignmentStart({
    required this.categories,
    required this.categoryId,
    required this.players,
    required this.saved,
    required this.onCategory,
    required this.onCreate,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final available = players
        .where((p) => p.status.toLowerCase() != 'lesionado')
        .length;
    final atRisk = players.length - available;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: CX.panelDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Alineaciones y citaciones',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              const Text(
                'Armá un XI nuevo o abrí una alineación guardada de esta '
                'categoría.',
                style: TextStyle(color: CX.muted, height: 1.35),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: categoryId,
                decoration: const InputDecoration(labelText: 'Categoría'),
                items: categories
                    .map(
                      (category) => DropdownMenuItem(
                        value: category.id,
                        child: Text(category.name),
                      ),
                    )
                    .toList(),
                onChanged: onCategory,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: players.isEmpty ? null : onCreate,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('Crear alineación'),
                ),
              ),
            ],
          ),
        ),
        if (players.isNotEmpty) ...[
          const SizedBox(height: 14),
          MetricGrid(
            tiles: [
              MetricTile(
                icon: Icons.groups_2_outlined,
                value: '${players.length}',
                label: 'Plantel',
                context: 'en esta categoría',
                accent: CX.blue,
              ),
              MetricTile(
                icon: Icons.check_circle_outline,
                value: '$available',
                label: 'Disponibles',
                context: atRisk == 0
                    ? 'sin lesiones cargadas'
                    : '$atRisk marcado(s) lesionado',
                accent: atRisk == 0 ? CX.green : CX.amber,
              ),
              MetricTile(
                icon: Icons.bookmark_added_outlined,
                value: '${saved.length}',
                label: 'Guardadas',
                context: saved.isEmpty ? 'ninguna todavía' : 'alineaciones',
                accent: CX.green,
              ),
            ],
          ),
        ],
        const SizedBox(height: 18),
        const PremiumSectionHeader(
          eyebrow: 'Historial',
          title: 'Alineaciones guardadas',
        ),
        if (players.isEmpty)
          const EmptyStatePanel(
            icon: Icons.groups_2_outlined,
            title: 'Esta categoría todavía no tiene jugadores',
            message: 'Sumá el plantel en Mi equipo para poder armar un XI '
                'y citar jugadores.',
          )
        else if (saved.isEmpty)
          EmptyStatePanel(
            icon: Icons.bookmark_border,
            title: 'Todavía no guardaste ninguna alineación',
            message: 'Armá el XI, el banco y guardala: la vas a tener acá '
                'lista para reabrir y ajustar antes del próximo partido.',
            primaryLabel: 'Crear alineación',
            onPrimary: onCreate,
          )
        else
          _SavedAlignmentsList(saved: saved, onOpen: onOpen),
      ],
    );
  }
}

class _LineupPlayerPanel extends StatelessWidget {
  final List<Player> players;
  final Set<String> usedIds;
  final ValueChanged<Player> onAdd;

  const _LineupPlayerPanel({
    required this.players,
    required this.usedIds,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final available = players
        .where((player) => !usedIds.contains(player.id))
        .toList();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: CX.panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Jugadores disponibles (${available.length})',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 3),
          const Text(
            'Tocá un jugador para sumarlo al primer puesto libre.',
            style: TextStyle(color: CX.faint, fontSize: 11),
          ),
          const SizedBox(height: 10),
          if (available.isEmpty)
            const Text(
              'Ya ubicaste a todo el plantel disponible en la cancha o el '
              'banco.',
              style: TextStyle(color: CX.muted),
            )
          else
            ...available
                .take(14)
                .map(
                  (player) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _LineupPlayerCard(
                      player: player,
                      onAdd: () => onAdd(player),
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

class _LineupPlayerCard extends StatelessWidget {
  final Player player;
  final VoidCallback onAdd;

  const _LineupPlayerCard({required this.player, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final minutes = _extractStat(
      player,
      RegExp(r'(\d+)\s*min', caseSensitive: false),
    );
    final goals = _extractStat(
      player,
      RegExp(r'(\d+)\s*goles?', caseSensitive: false),
    );
    final matches = _extractStat(
      player,
      RegExp(r'(\d+)\s*PJ', caseSensitive: false),
    );
    return InkWell(
      onTap: onAdd,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: CX.panel2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: CX.line),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: CX.green.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.add, color: CX.green, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    player.fullName.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      player.position,
                      if (matches.isNotEmpty) '$matches PJ',
                      if (minutes.isNotEmpty) '$minutes min',
                      if (goals.isNotEmpty) '$goals goles',
                    ].where((v) => v.trim().isNotEmpty).join(' - '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: CX.muted, fontSize: 10),
                  ),
                  if (player.availabilityLabel.trim().isNotEmpty)
                    Text(
                      player.availabilityLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: CX.faint, fontSize: 9),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _extractStat(Player player, RegExp pattern) {
    final source = '${player.trend} ${player.note}';
    final match = pattern.firstMatch(source);
    return match?.group(1) ?? '';
  }
}

class _Pitch extends StatelessWidget {
  final GlobalKey repaintKey;
  final String categoryName;
  final String title;
  final String rival;
  final String date;
  final List<_Spot> spots;
  final Map<int, Offset> customSpots;
  final List<String?> xi;
  final Map<String, Player> players;
  final void Function(int index, Offset spot) onMove;
  final ValueChanged<int> onTap;

  const _Pitch({
    required this.repaintKey,
    required this.categoryName,
    required this.title,
    required this.rival,
    required this.date,
    required this.spots,
    required this.customSpots,
    required this.xi,
    required this.players,
    required this.onMove,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: repaintKey,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: AspectRatio(
            aspectRatio: .74,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF15803D),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.white.withValues(alpha: .42),
                  width: 2,
                ),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(painter: _PitchPainter()),
                      ),
                      Positioned(
                        left: 14,
                        top: 12,
                        right: 14,
                        child: _PitchContextBadge(
                          categoryName: categoryName,
                          title: title,
                          rival: rival,
                          date: date,
                        ),
                      ),
                      ...List.generate(spots.length, (index) {
                        final base = spots[index];
                        final normalized =
                            customSpots[index] ?? Offset(base.x, base.y);
                        final player = players[xi[index]];
                        const discWidth = 108.0;
                        const discHeight = 82.0;
                        return Positioned(
                          left: normalized.dx * size.width - discWidth / 2,
                          top: normalized.dy * size.height - discHeight / 2,
                          width: discWidth,
                          height: discHeight,
                          child: GestureDetector(
                            onPanUpdate: (details) {
                              final next = Offset(
                                ((normalized.dx * size.width +
                                            details.delta.dx) /
                                        size.width)
                                    .clamp(.08, .92),
                                ((normalized.dy * size.height +
                                            details.delta.dy) /
                                        size.height)
                                    .clamp(.08, .94),
                              );
                              onMove(index, next);
                            },
                            child: _PlayerDisc(
                              label: base.label,
                              player: player,
                              goalkeeper: base.goalkeeper,
                              onTap: () => onTap(index),
                            ),
                          ),
                        );
                      }),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PitchContextBadge extends StatelessWidget {
  final String categoryName;
  final String title;
  final String rival;
  final String date;

  const _PitchContextBadge({
    required this.categoryName,
    required this.title,
    required this.rival,
    required this.date,
  });

  @override
  Widget build(BuildContext context) {
    final main = title.isNotEmpty ? title : categoryName;
    final secondary = [
      if (rival.isNotEmpty) 'VS ${rival.toUpperCase()}',
      if (date.isNotEmpty) date,
    ].join('  |  ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xDD07120D),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: .18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            main,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 15,
              letterSpacing: 0,
            ),
          ),
          if (secondary.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              secondary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: .72),
                fontWeight: FontWeight.w800,
                fontSize: 11,
                letterSpacing: 0,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlayerDisc extends StatelessWidget {
  final String label;
  final Player? player;
  final bool goalkeeper;
  final VoidCallback onTap;

  const _PlayerDisc({
    required this.label,
    required this.player,
    required this.goalkeeper,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = goalkeeper ? CX.amber : CX.green;
    final name = player?.fullName ?? label;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(color: Color(0x66000000), blurRadius: 10),
              ],
            ),
            child: Center(
              child: Text(
                player == null || name.isEmpty ? '+' : name[0].toUpperCase(),
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .55),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bench extends StatelessWidget {
  final List<String?> subs;
  final Map<String, Player> players;
  final ValueChanged<int> onTap;

  const _Bench({
    required this.subs,
    required this.players,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: CX.panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Banco', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: List.generate(subs.length, (index) {
              final player = players[subs[index]];
              return SizedBox(
                width: 118,
                child: _PlayerDisc(
                  label: 'SUP ${index + 1}',
                  player: player,
                  goalkeeper: false,
                  onTap: () => onTap(index),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _PlayerPickerSheet extends StatefulWidget {
  final String title;
  final List<Player> players;

  const _PlayerPickerSheet({required this.title, required this.players});

  @override
  State<_PlayerPickerSheet> createState() => _PlayerPickerSheetState();
}

class _PlayerPickerSheetState extends State<_PlayerPickerSheet> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 14,
          right: 14,
          top: 14,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 14,
        ),
        child: AnimatedBuilder(
          animation: _searchController,
          builder: (context, _) {
            final query = _searchController.text.trim().toLowerCase();
            final filtered = widget.players.where((player) {
              final haystack =
                  '${player.fullName} ${player.position} ${player.status}'
                      .toLowerCase();
              return query.isEmpty || haystack.contains(query);
            }).toList();
            return ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _searchController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Buscar jugador',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Flexible(
                    child: Material(
                      type: MaterialType.transparency,
                      child: ListView(
                      shrinkWrap: true,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.remove_circle_outline),
                          title: const Text('Vaciar puesto'),
                          onTap: () => Navigator.pop(context, null),
                        ),
                        if (filtered.isEmpty)
                          const ListTile(
                            title: Text('No quedan jugadores disponibles.'),
                          ),
                        ...filtered.map(
                          (player) => ListTile(
                            leading: CircleAvatar(
                              backgroundColor: CX.greenDark,
                              child: Text(
                                player.fullName.isEmpty
                                    ? '?'
                                    : player.fullName[0].toUpperCase(),
                              ),
                            ),
                            title: Text(player.fullName),
                            subtitle: Text(
                              [player.position, player.status]
                                  .where((item) => item.trim().isNotEmpty)
                                  .join(' / '),
                            ),
                            onTap: () => Navigator.pop(context, player.id),
                          ),
                        ),
                      ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SavedAlignmentsList extends StatelessWidget {
  final List<_SavedAlignment> saved;
  final ValueChanged<_SavedAlignment> onOpen;

  const _SavedAlignmentsList({required this.saved, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: CX.panelDecoration(),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Alineaciones guardadas',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          ...saved.map(
            (item) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.bookmark_added_outlined),
              title: Text(item.title),
              subtitle: Text(
                [
                  item.date,
                  item.rival,
                  item.formation,
                ].where((value) => value.trim().isNotEmpty).join(' / '),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onOpen(item),
            ),
          ),
        ],
        ),
      ),
    );
  }
}

class _SavedAlignment {
  final String title;
  final String rival;
  final String date;
  final String formation;
  final List<String?> xi;
  final List<String?> subs;
  final Map<int, Offset> customSpots;
  final String savedAt;

  const _SavedAlignment({
    required this.title,
    required this.rival,
    required this.date,
    required this.formation,
    required this.xi,
    required this.subs,
    required this.customSpots,
    required this.savedAt,
  });

  factory _SavedAlignment.fromJson(Map<String, dynamic> json) {
    final rawCustom = json['customSpots'] as Map<String, dynamic>? ?? {};
    return _SavedAlignment(
      title: json['title'] as String? ?? 'Alineación',
      rival: json['rival'] as String? ?? '',
      date: json['date'] as String? ?? '',
      formation: json['formation'] as String? ?? '4-4-2',
      xi: List<String?>.from(json['xi'] as List<dynamic>? ?? []),
      subs: List<String?>.from(json['subs'] as List<dynamic>? ?? []),
      customSpots: rawCustom.map((key, value) {
        final values = List<num>.from(value as List<dynamic>? ?? []);
        return MapEntry(
          int.tryParse(key) ?? 0,
          Offset(
            values.isNotEmpty ? values[0].toDouble() : .5,
            values.length > 1 ? values[1].toDouble() : .5,
          ),
        );
      }),
      savedAt: json['savedAt'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'rival': rival,
    'date': date,
    'formation': formation,
    'xi': xi,
    'subs': subs,
    'customSpots': customSpots.map(
      (key, value) => MapEntry('$key', [value.dx, value.dy]),
    ),
    'savedAt': savedAt,
  };
}

class _PitchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      paint,
    );
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), 42, paint);
    canvas.drawRect(
      Rect.fromLTWH(size.width * .18, 0, size.width * .64, 82),
      paint,
    );
    canvas.drawRect(
      Rect.fromLTWH(size.width * .18, size.height - 82, size.width * .64, 82),
      paint,
    );
    canvas.drawCircle(Offset(size.width / 2, size.height * .16), 3, paint);
    canvas.drawCircle(Offset(size.width / 2, size.height * .84), 3, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Spot {
  final String label;
  final double x;
  final double y;
  final bool goalkeeper;

  const _Spot(this.label, this.x, this.y, this.goalkeeper);
}

class _LineupHintBanner extends StatelessWidget {
  final LineupHint hint;
  final VoidCallback onDismiss;

  const _LineupHintBanner({required this.hint, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 10, 6, 10),
      decoration: BoxDecoration(
        color: CX.amber.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: CX.amber, width: 3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.flag_outlined, size: 16, color: CX.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Para revisar en la citación: ${hint.reason}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
                if (hint.players.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    hint.players.join(' · '),
                    style: const TextStyle(
                      color: CX.muted,
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
                ],
                const SizedBox(height: 2),
                const Text(
                  'Es un aviso. La citación la decidís vos.',
                  style: TextStyle(color: CX.faint, fontSize: 10),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Ocultar',
            onPressed: onDismiss,
            icon: const Icon(Icons.close, size: 16),
          ),
        ],
      ),
    );
  }
}
