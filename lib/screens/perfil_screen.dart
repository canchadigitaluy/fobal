import 'package:flutter/material.dart';

import '../data/cantera_data.dart';
import '../main.dart';
import '../services/club_access_service.dart';
import '../ui/ui_kit.dart';

class PerfilScreen extends StatelessWidget {
  const PerfilScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final club = AppScope.of(context).club;

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Táctica'),
            Text(
              'Forma de jugar del equipo',
              style: TextStyle(
                color: CX.faint,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 700;
                return ListView(
                  padding: EdgeInsets.fromLTRB(
                    narrow ? 12 : 18,
                    narrow ? 6 : 8,
                    narrow ? 12 : 18,
                    narrow ? 20 : 30,
                  ),
                  children: CanteraMotion.stagger([
                _SignalTile(
                  metric: _SignalMetric(
                    'Plantel',
                    '${club.players.length} '
                        '${club.players.length == 1 ? 'jugador' : 'jugadores'}',
                    Icons.groups_2_outlined,
                    CX.green,
                  ),
                ),
                SizedBox(height: narrow ? 16 : 24),
                PremiumSectionHeader(
                  compact: narrow,
                  eyebrow: 'Identidad',
                  title: 'Impronta futbolística',
                ),
                _MethodologyBoard(methodology: club.methodology),
                SizedBox(height: narrow ? 16 : 24),
                PremiumSectionHeader(
                  compact: narrow,
                  eyebrow: 'Jugadores',
                  title: 'Seguimiento individual',
                ),
                if (club.players.isEmpty)
                  const _IntelligenceEmpty(
                    icon: Icons.person_search_outlined,
                    title: 'Sin jugadores para comparar',
                    description:
                        'Carga el plantel para comenzar el seguimiento de asistencia, estado y evolucion.',
                  )
                else
                  _PlayerRadar(players: club.players),
                  ]),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

}

class _SignalTile extends StatelessWidget {
  final _SignalMetric metric;
  const _SignalTile({required this.metric});
  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 700;
    return Container(
    padding: EdgeInsets.all(narrow ? 10 : 14),
    decoration: CX.panelDecoration(),
    child: Row(
      children: [
        Container(
          width: narrow ? 32 : 36,
          height: narrow ? 32 : 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: metric.color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(metric.icon, color: metric.color, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                metric.value,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.3,
                ),
              ),
              Text(
                metric.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: CX.faint, fontSize: 9),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  }
}

class _MethodologyBoard extends StatelessWidget {
  final Methodology methodology;
  const _MethodologyBoard({required this.methodology});

  @override
  Widget build(BuildContext context) {
    if (methodology.playingStyle.trim().isEmpty) {
      return _EditableMethodologyBox(methodology: methodology, empty: true);
    }
    return _EditableMethodologyBox(methodology: methodology);
  }
}

class _EditableMethodologyBox extends StatelessWidget {
  final Methodology methodology;
  final bool empty;

  const _EditableMethodologyBox({
    required this.methodology,
    this.empty = false,
  });

  @override
  Widget build(BuildContext context) {
    final text = methodology.playingStyle.trim();
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _edit(context),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: CX.panelDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.edit_note_outlined, color: CX.green, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Nuestra forma de jugar',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                  ),
                ),
                Icon(Icons.edit_outlined, color: CX.faint, size: 16),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              text.isEmpty
                  ? 'Defini una idea clara para que todo el cuerpo tecnico trabaje con los mismos criterios: salida, presion, ataque, defensa y pelota quieta.'
                  : text,
              style: TextStyle(
                color: text.isEmpty ? CX.faint : CX.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
            if (!empty) ...[
              const SizedBox(height: 17),
              LayoutBuilder(
                builder: (context, constraints) {
                  final attack = _PrincipleColumn(
                    title: 'Con pelota',
                    color: CX.green,
                    items: methodology.offensivePrinciples,
                    onEdit: () => _editPrinciples(context, offensive: true),
                  );
                  final defense = _PrincipleColumn(
                    title: 'Sin pelota',
                    color: CX.blue,
                    items: methodology.defensivePrinciples,
                    onEdit: () => _editPrinciples(context, offensive: false),
                  );
                  if (constraints.maxWidth < 620) {
                    return Column(
                      children: [attack, const SizedBox(height: 16), defense],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: attack),
                      const SizedBox(width: 18),
                      Expanded(child: defense),
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _editPrinciples(
    BuildContext context, {
    required bool offensive,
  }) async {
    final current = offensive
        ? methodology.offensivePrinciples
        : methodology.defensivePrinciples;
    final value = await promptForText(
      context,
      title: offensive ? 'Principios con pelota' : 'Principios sin pelota',
      initialValue: current.join('\n'),
      hintText: 'Un principio por línea',
      minLines: 4,
      maxLines: 10,
    );
    if (value == null) return;
    final list = value
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (!context.mounted) return;
    final scope = AppScope.of(context);
    final next = offensive
        ? scope.club.methodology.copyWith(offensivePrinciples: list)
        : scope.club.methodology.copyWith(defensivePrinciples: list);
    scope.updateClub(scope.club.copyWith(methodology: next));
    try {
      await ClubAccessService.saveTacticalData(
        type: 'methodology',
        title: 'Forma de jugar',
        categoryId: scope.selectedCategoryId,
        content: {'methodology': next.toJson()},
      );
    } catch (_) {
      // Copia local guardada; la nube reintenta en otro acceso.
    }
  }

  Future<void> _edit(BuildContext context) async {
    final value = await promptForText(
      context,
      title: 'Impronta futbolística',
      initialValue: methodology.playingStyle,
      hintText:
          'Ej: presionar alto tras perdida, salir corto cuando haya apoyo, atacar por bandas...',
      minLines: 6,
      maxLines: 10,
    );
    if (value == null) return;
    final scope = AppScope.of(context);
    scope.updateClub(
      scope.club.copyWith(
        methodology: scope.club.methodology.copyWith(playingStyle: value),
      ),
    );
    try {
      await ClubAccessService.saveTacticalData(
        type: 'methodology',
        title: 'Forma de jugar',
        categoryId: scope.selectedCategoryId,
        content: {
          'methodology': scope.club.methodology
              .copyWith(playingStyle: value)
              .toJson(),
        },
      );
    } catch (_) {
      // La copia local ya quedo guardada; la nube se reintentara en otro acceso.
    }
  }
}

class _PrincipleColumn extends StatelessWidget {
  final String title;
  final Color color;
  final List<String> items;
  final VoidCallback? onEdit;
  const _PrincipleColumn({
    required this.title,
    required this.color,
    required this.items,
    this.onEdit,
  });
  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: onEdit,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
              ),
              if (onEdit != null) ...[
                const SizedBox(width: 6),
                const Icon(Icons.edit_outlined, size: 13, color: CX.faint),
              ],
            ],
          ),
          const SizedBox(height: 9),
          if (items.isEmpty)
            const Text(
              'Sin principios cargados — tocá para definirlos',
              style: TextStyle(color: CX.faint, fontSize: 11),
            )
          else
            ...items
                .take(5)
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Text(
                      '-  $item',
                      style: const TextStyle(
                        color: CX.muted,
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
        ],
      ),
    ),
  );
}

class _PlayerRadar extends StatelessWidget {
  final List<Player> players;
  const _PlayerRadar({required this.players});
  @override
  Widget build(BuildContext context) => Container(
    decoration: CX.panelDecoration(),
    child: Column(
      children: players.take(8).map((player) {
        final position = player.position.trim();
        final hasPosition = position.isNotEmpty;
        final secondary = player.secondaryPositions
            .split(RegExp(r'[,/;]'))
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .take(2)
            .join(' / ');
        final foot = player.dominantFoot.trim();
        final status = player.status.trim();
        final aiReady = _aiReady(player);
        final partiallyReady =
            hasPosition || secondary.isNotEmpty || foot.isNotEmpty;
        final profileParts = [
          if (secondary.isNotEmpty) secondary,
          if (foot.isNotEmpty) foot,
          if (status.isNotEmpty && status.toLowerCase() != 'activo') status,
        ];
        final color = player.hasAvailabilityWarning
            ? player.availability.color
            : player.attendanceRate > 0 && player.attendanceRate < .7
            ? CX.amber
            : CX.green;
        return AnimatedContainer(
          duration: CX.motion,
          curve: CX.curve,
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
          decoration: BoxDecoration(
            border: const Border(bottom: BorderSide(color: CX.line)),
            color: hasPosition
                ? Colors.transparent
                : CX.amber.withValues(alpha: .035),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 520;
              final identity = Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      player.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    if (profileParts.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        profileParts.join(' / '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: CX.faint, fontSize: 9),
                      ),
                    ],
                  ],
                ),
              );
              final roleChip = Container(
                constraints: BoxConstraints(maxWidth: compact ? 130 : 180),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: aiReady
                      ? CX.green.withValues(alpha: .1)
                      : partiallyReady
                      ? CX.amber.withValues(alpha: .1)
                      : CX.red.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: aiReady
                        ? CX.green.withValues(alpha: .22)
                        : partiallyReady
                        ? CX.amber.withValues(alpha: .28)
                        : CX.red.withValues(alpha: .2),
                  ),
                ),
                child: Text(
                  aiReady
                      ? 'Completo'
                      : hasPosition
                      ? 'A completar'
                      : 'Perfil pendiente',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: CX.muted,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
              final attendance = SizedBox(
                width: 38,
                child: Text(
                  player.attendanceRate <= 0
                      ? '--'
                      : '${(player.attendanceRate * 100).round()}%',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              );
              return Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  identity,
                  const SizedBox(width: 10),
                  roleChip,
                  const SizedBox(width: 12),
                  attendance,
                ],
              );
            },
          ),
        );
      }).toList(),
    ),
  );

  bool _aiReady(Player player) =>
      player.position.trim().isNotEmpty &&
      player.secondaryPositions.trim().isNotEmpty &&
      player.dominantFoot.trim().isNotEmpty &&
      player.status.trim().isNotEmpty &&
      player.note.trim().length >= 12;
}

class _IntelligenceEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  const _IntelligenceEmpty({
    required this.icon,
    required this.title,
    required this.description,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: CX.panelDecoration(),
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: CX.panel2,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: CX.faint, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: const TextStyle(
                  color: CX.faint,
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SignalMetric {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _SignalMetric(this.label, this.value, this.icon, this.color);
}
