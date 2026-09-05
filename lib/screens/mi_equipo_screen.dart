// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;

import 'package:flutter/material.dart';

import '../data/cantera_data.dart';
import '../main.dart';
import '../services/export_download_service.dart';
import '../services/export_text_service.dart';
import '../services/player_profile_service.dart';
import '../services/squad_report_service.dart';
import '../ui/export_preview_dialog.dart';
import '../ui/ui_kit.dart';
import 'add_player_dialog.dart';
import 'player_availability_dialog.dart';
import 'player_profile_screen.dart';

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

  Future<void> _editAvailability(Player player) async {
    final updated = await showPlayerAvailabilityDialog(context, player: player);
    if (updated == null || !mounted) return;
    final scope = AppScope.of(context);
    scope.updateClub(
      scope.fullClub.copyWith(
        players: [
          for (final item in scope.fullClub.players)
            if (item.id == updated.id) updated else item,
        ],
      ),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Disponibilidad actualizada: ${updated.availability.label}')),
    );
  }

  void _generateSquadReport(CanteraClub club, List<Player> players) {
    final scope = AppScope.of(context);
    final categoryId = scope.selectedCategoryId ??
        (club.categories.isEmpty ? '' : club.categories.first.id);
    var categoryName = '';
    for (final item in club.categories) {
      if (item.id == categoryId) {
        categoryName = item.name;
        break;
      }
    }
    final content = buildSquadReportContent(
      club: club,
      players: players,
      categoryId: categoryId,
      categoryName: categoryName,
    );
    final fileName = buildExportFileName(
      club: club.name,
      category: categoryName,
      type: 'reporte-plantel',
      extension: 'txt',
    );
    showExportPreviewDialog(
      context,
      title: 'Reporte del plantel',
      content: content,
      fileName: fileName,
      onDownload: (name, text) {
        ExportDownloadService.downloadText(name, text);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reporte descargado: $name')),
        );
      },
    );
  }

  Future<void> _addPlayer() async {
    final scope = AppScope.of(context);
    final cats = scope.fullClub.categories;
    final categoryId = scope.selectedCategoryId ??
        (cats.isNotEmpty ? cats.first.id : 'plantel');
    final player = await showAddPlayerDialog(context, categoryId: categoryId);
    if (player == null || !mounted) return;
    final nextPlayers = [...scope.fullClub.players, player];
    final categories = scope.fullClub.categories
        .map((category) => category.id == categoryId
            ? category.copyWith(
                playerCount: nextPlayers
                    .where((candidate) => candidate.categoryId == categoryId)
                    .length,
              )
            : category)
        .toList();
    scope.updateClub(
      scope.fullClub.copyWith(categories: categories, players: nextPlayers),
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
                  fallback: 'Escudo',
                  placeholder: Icons.shield_outlined,
                  onTap: _pickLogo,
                  round: true,
                );
                final photo = _EditableImage(
                  size: compact ? constraints.maxWidth : 190,
                  height: compact ? 110 : 96,
                  imageUrl: _teamPhoto ?? '',
                  fallback: 'Foto del equipo',
                  placeholder: Icons.photo_library_outlined,
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
          if (players.isNotEmpty) ...[
            _SquadProgress(players: players),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _generateSquadReport(club, players),
                icon: const Icon(Icons.summarize_outlined, size: 17),
                label: const Text('Generar reporte del plantel'),
              ),
            ),
            const SizedBox(height: 18),
          ],
          if (squadGoalTracker(players).isNotEmpty) ...[
            const PremiumSectionHeader(
              eyebrow: 'Seguimiento',
              title: 'Objetivos del plantel',
            ),
            const SizedBox(height: 10),
            _SquadGoalsPanel(entries: squadGoalTracker(players)),
            const SizedBox(height: 18),
          ],
          const PremiumSectionHeader(
            eyebrow: 'Plantel',
            title: 'Jugadores',
          ),
          if (players.isEmpty)
            EmptyStatePanel(
              icon: Icons.groups_2_outlined,
              title: 'Todavía no cargaste jugadores',
              message: 'Sumá el plantel una vez y después Estadísticas, '
                  'Planificar y Alineación trabajan con datos reales.',
              primaryLabel: 'Cargar primer jugador',
              onPrimary: _addPlayer,
            )
          else ...[
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final player in players)
                  _PlayerCard(
                    player: player,
                    onEditAvailability: () => _editAvailability(player),
                  ),
                _AddPlayerTile(onTap: _addPlayer),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SquadProgress extends StatelessWidget {
  final List<Player> players;
  const _SquadProgress({required this.players});

  @override
  Widget build(BuildContext context) {
    final total = players.length;
    final withPosition = players.where((p) => p.position.trim().isNotEmpty).length;
    final complete = players
        .where((p) =>
            p.position.trim().isNotEmpty &&
            p.dominantFoot.trim().isNotEmpty &&
            p.status.trim().isNotEmpty)
        .length;
    final available = players.where((p) => p.isAvailable).length;
    return MetricGrid(
      tiles: [
        MetricTile(
          icon: Icons.badge_outlined,
          value: '$total',
          label: 'Jugadores',
          context: 'en el plantel',
          accent: CX.blue,
        ),
        MetricTile(
          icon: Icons.verified_outlined,
          value: '$complete/$total',
          label: 'Perfiles completos',
          context: complete == total ? 'todo cargado' : 'posición, pie y estado',
          accent: complete == total ? CX.green : CX.amber,
        ),
        MetricTile(
          icon: Icons.place_outlined,
          value: '$withPosition/$total',
          label: 'Con posición',
          context: 'para armar alineación',
          accent: withPosition == total ? CX.green : CX.amber,
        ),
        MetricTile(
          icon: Icons.check_circle_outline,
          value: '$available',
          label: 'Disponibles',
          context: 'sin lesión ni sanción',
          accent: CX.green,
        ),
      ],
    );
  }
}

class _SquadGoalsPanel extends StatelessWidget {
  final List<PlayerGoalEntry> entries;
  const _SquadGoalsPanel({required this.entries});

  @override
  Widget build(BuildContext context) {
    final visible = entries.take(6).toList();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: CX.panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in visible) ...[
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => openPlayerProfile(context, entry.player),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: switch (entry.goal.priority) {
                          PlayerGoalPriority.alta => CX.red,
                          PlayerGoalPriority.media => CX.amber,
                          PlayerGoalPriority.baja => CX.muted,
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${entry.player.firstName} ${entry.player.lastName}',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                          ),
                          Text(
                            formatPlayerGoalLine(entry.goal),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: CX.muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: CX.muted, size: 18),
                  ],
                ),
              ),
            ),
            if (entry != visible.last)
              const Divider(height: 1, color: Color(0x14FFFFFF)),
          ],
          if (entries.length > visible.length) ...[
            const SizedBox(height: 4),
            Text(
              '+ ${entries.length - visible.length} objetivos más en curso',
              style: const TextStyle(color: CX.muted, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ],
        ],
      ),
    );
  }
}

class _AddPlayerTile extends StatelessWidget {
  final VoidCallback onTap;
  const _AddPlayerTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 180,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: CX.greenDark,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: CX.green.withValues(alpha: .35)),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(height: 4),
            CircleAvatar(
              radius: 20,
              backgroundColor: CX.green,
              child: Icon(Icons.add, color: Colors.white),
            ),
            SizedBox(height: 10),
            Text(
              'Agregar jugador',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w900, color: CX.green),
            ),
            SizedBox(height: 2),
            Text(
              'Sumá al plantel',
              style: TextStyle(color: CX.green, fontSize: 11),
            ),
            SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

class _EditableImage extends StatelessWidget {
  final double size;
  final double? height;
  final String imageUrl;
  final String fallback;
  final IconData placeholder;
  final VoidCallback onTap;
  final bool round;

  const _EditableImage({
    required this.size,
    this.height,
    required this.imageUrl,
    required this.fallback,
    required this.placeholder,
    required this.onTap,
    required this.round,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl.trim().isNotEmpty;
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
            child: hasImage
                ? Image.network(imageUrl,
                    width: size, height: height ?? size, fit: BoxFit.cover)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(placeholder, color: CX.faint, size: round ? 30 : 26),
                      if (!round) ...[
                        const SizedBox(height: 5),
                        Text(
                          fallback,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: CX.faint,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
          Positioned(
            right: 4,
            bottom: 4,
            child: CircleAvatar(
              radius: 13,
              backgroundColor: CX.white,
              child: Icon(
                hasImage ? Icons.edit_outlined : Icons.photo_camera_outlined,
                color: CX.panel,
                size: 14,
              ),
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
  final VoidCallback onEditAvailability;

  const _PlayerCard({required this.player, required this.onEditAvailability});

  @override
  Widget build(BuildContext context) {
    final availability = player.availability;
    final secondary = player.secondaryPositionList.take(3).join(' · ');
    return InkWell(
      onTap: () => openPlayerProfile(context, player),
      borderRadius: BorderRadius.circular(8),
      child: Container(
      width: 180,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CX.canvas,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CX.line),
      ),
      child: Column(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: CX.greenDark,
                child: Text(
                  _initials(player),
                  style: const TextStyle(
                    color: CX.green,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: availability.color,
                    shape: BoxShape.circle,
                    border: Border.all(color: CX.canvas, width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            player.fullName,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, height: 1.2),
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: onEditAvailability,
            borderRadius: BorderRadius.circular(999),
            child: AvailabilityChip(availability, compact: true),
          ),
          const SizedBox(height: 6),
          if (player.position.trim().isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: CX.greenDark,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                player.position,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: CX.green,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            )
          else
            const Text(
              'Sin posición',
              style: TextStyle(color: CX.faint, fontSize: 11),
            ),
          if (secondary.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              secondary,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: CX.faint, fontSize: 10),
            ),
          ],
        ],
      ),
      ),
    );
  }

  String _initials(Player player) {
    final a = player.firstName.isNotEmpty ? player.firstName[0] : '';
    final b = player.lastName.isNotEmpty ? player.lastName[0] : '';
    return (a + b).toUpperCase();
  }
}

