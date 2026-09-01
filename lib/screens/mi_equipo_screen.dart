// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;

import 'package:flutter/material.dart';

import '../data/cantera_data.dart';
import '../main.dart';

class MiEquipoScreen extends StatefulWidget {
  const MiEquipoScreen({super.key});

  @override
  State<MiEquipoScreen> createState() => _MiEquipoScreenState();
}

class _MiEquipoScreenState extends State<MiEquipoScreen> {
  String? _teamPhoto;

  String get _photoKey => 'cantera_team_photo_${AppScope.of(context).fullClub.id}';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _teamPhoto ??= html.window.localStorage[_photoKey];
  }

  Future<void> _pickLogo() async {
    final dataUrl = await _pickImageDataUrl();
    if (dataUrl == null || !mounted) return;
    final scope = AppScope.of(context);
    scope.updateClub(scope.fullClub.copyWith(logoUrl: dataUrl));
    if (mounted) setState(() {});
  }

  Future<void> _pickTeamPhoto() async {
    final dataUrl = await _pickImageDataUrl();
    if (dataUrl == null) return;
    html.window.localStorage[_photoKey] = dataUrl;
    if (mounted) setState(() => _teamPhoto = dataUrl);
  }

  Future<String?> _pickImageDataUrl() async {
    final upload = html.FileUploadInputElement()..accept = 'image/*';
    upload.click();
    await upload.onChange.first;
    final file = upload.files?.isNotEmpty == true ? upload.files!.first : null;
    if (file == null) return null;
    final reader = html.FileReader();
    reader.readAsDataUrl(file);
    await reader.onLoad.first;
    return reader.result as String?;
  }

  Future<void> _addPlayer() async {
    final player = await showDialog<Player>(
      context: context,
      builder: (context) => const _AddPlayerDialog(),
    );
    if (player == null || !mounted) return;
    final scope = AppScope.of(context);
    final cats = scope.fullClub.categories;
    final categoryId = scope.selectedCategoryId ??
        (cats.isNotEmpty ? cats.first.id : 'plantel');
    final updated = player.copyWith(categoryId: categoryId);
    final categories = scope.fullClub.categories
        .map((category) => category.id == categoryId
            ? category.copyWith(playerCount: category.playerCount + 1)
            : category)
        .toList();
    scope.updateClub(
      scope.fullClub.copyWith(
        categories: categories,
        players: [...scope.fullClub.players, updated],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final club = scope.fullClub;
    final players = scope.club.players;
    return Scaffold(
      appBar: AppBar(title: const Text('Mi equipo')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 36),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: CX.panelDecoration(),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 720;
                final logo = _EditableImage(
                  size: 92,
                  imageUrl: club.logoUrl,
                  fallback: 'TEAM\nLOGO',
                  onTap: _pickLogo,
                  round: true,
                );
                final photo = _EditableImage(
                  size: compact ? constraints.maxWidth : 190,
                  height: compact ? 110 : 96,
                  imageUrl: _teamPhoto ?? '',
                  fallback: 'Foto del equipo',
                  onTap: _pickTeamPhoto,
                  round: false,
                );
                final info = Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: CX.green,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'BÁSICO',
                          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        club.name,
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${scope.club.categories.isEmpty ? "Plantel" : scope.club.categories.first.name} | Año ${club.seasonYear.isEmpty ? DateTime.now().year.toString() : club.seasonYear}',
                        style: const TextStyle(color: CX.muted, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          _SoftChip(icon: Icons.calendar_today_outlined, text: club.seasonYear.isEmpty ? DateTime.now().year.toString() : club.seasonYear),
                          const _SoftChip(icon: Icons.edit_outlined, text: 'Datos editables'),
                        ],
                      ),
                    ],
                  ),
                );
                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [logo, const SizedBox(width: 14), info]),
                      const SizedBox(height: 14),
                      photo,
                    ],
                  );
                }
                return Row(
                  children: [
                    logo,
                    const SizedBox(width: 18),
                    info,
                    const SizedBox(width: 18),
                    SizedBox(width: 210, child: photo),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 18),
          Container(
            decoration: CX.panelDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.sports_soccer_outlined, size: 17, color: CX.muted),
                      const SizedBox(width: 8),
                      Text(
                        'PLANTILLA (${players.length})',
                        style: const TextStyle(color: CX.muted, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                if (players.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(18),
                    child: Text('Todavía no cargaste jugadores.', style: TextStyle(color: CX.muted)),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: players.map((player) => _PlayerCard(player: player)).toList(),
                    ),
                  ),
                InkWell(
                  onTap: _addPlayer,
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                    decoration: BoxDecoration(
                      color: CX.panel,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: CX.line),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.add_circle_outline, color: CX.green),
                        SizedBox(width: 12),
                        Expanded(child: Text('Amplía tu plantilla', style: TextStyle(fontWeight: FontWeight.w800))),
                        Icon(Icons.chevron_right, color: CX.muted),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EditableImage extends StatelessWidget {
  final double size;
  final double? height;
  final String imageUrl;
  final String fallback;
  final VoidCallback onTap;
  final bool round;

  const _EditableImage({
    required this.size,
    this.height,
    required this.imageUrl,
    required this.fallback,
    required this.onTap,
    required this.round,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(round ? 999 : 12),
      child: Stack(
        children: [
          Container(
            width: size,
            height: height ?? size,
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: CX.panel2,
              shape: round ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: round ? null : BorderRadius.circular(12),
              border: Border.all(color: CX.line),
            ),
            child: imageUrl.trim().isEmpty
                ? Text(
                    fallback,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: CX.faint, fontWeight: FontWeight.w900),
                  )
                : Image.network(imageUrl, width: size, height: height ?? size, fit: BoxFit.cover),
          ),
          Positioned(
            right: 4,
            bottom: 4,
            child: CircleAvatar(
              radius: 14,
              backgroundColor: CX.white,
              child: Icon(Icons.photo_camera_outlined, color: CX.panel, size: 15),
            ),
          ),
        ],
      ),
    );
  }
}

class _SoftChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _SoftChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: CX.panel2, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: CX.green),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(color: CX.muted, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _PlayerCard extends StatelessWidget {
  final Player player;

  const _PlayerCard({required this.player});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CX.canvas,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CX.line),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: CX.greenDark,
            child: Text(
              _initials(player),
              style: const TextStyle(color: CX.green, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 10),
          Text(player.fullName, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)),
          if (player.position.trim().isNotEmpty)
            Text(player.position, style: const TextStyle(color: CX.faint, fontSize: 12)),
        ],
      ),
    );
  }

  String _initials(Player player) {
    final a = player.firstName.isNotEmpty ? player.firstName[0] : '';
    final b = player.lastName.isNotEmpty ? player.lastName[0] : '';
    return (a + b).toUpperCase();
  }
}

class _AddPlayerDialog extends StatefulWidget {
  const _AddPlayerDialog();

  @override
  State<_AddPlayerDialog> createState() => _AddPlayerDialogState();
}

class _AddPlayerDialogState extends State<_AddPlayerDialog> {
  final _name = TextEditingController();
  final _lastName = TextEditingController();
  final _position = TextEditingController();
  final _secondary = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _lastName.dispose();
    _position.dispose();
    _secondary.dispose();
    super.dispose();
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
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nombre')),
            const SizedBox(height: 10),
            TextField(controller: _lastName, decoration: const InputDecoration(labelText: 'Apellido')),
            const SizedBox(height: 10),
            TextField(controller: _position, decoration: const InputDecoration(labelText: 'Posición principal')),
            const SizedBox(height: 10),
            TextField(controller: _secondary, decoration: const InputDecoration(labelText: 'Posiciones secundarias')),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton.icon(
          onPressed: () {
            final name = _name.text.trim();
            final last = _lastName.text.trim();
            if (name.length < 2 || last.length < 2) return;
            Navigator.pop(
              context,
              Player(
                id: 'manual-${DateTime.now().millisecondsSinceEpoch}',
                categoryId: '',
                firstName: name,
                lastName: last,
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
          },
          icon: const Icon(Icons.add),
          label: const Text('Añadir jugador'),
        ),
      ],
    );
  }
}
