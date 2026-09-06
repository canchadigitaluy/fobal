import 'package:flutter/material.dart';

import '../data/cantera_data.dart';
import '../main.dart';

/// Small, shared visual primitives for the flagship screens (Inicio and
/// Estadísticas). Kept deliberately minimal — no layout framework, no charts.

// --- dark surface palette (the "read" cards) -------------------------------
const _ink = Color(0xFF102019);
const _mint = Color(0xFF6EF2C7);
const _onInk = Color(0xFFE8F1ED);
const _onInkMuted = Color(0xFFB8C5BF);
const _onInkFaint = Color(0xFF8CA39B);
const _hair = Color(0x22FFFFFF);

/// High-contrast dark card for the headline read. One consistent frame for the
/// weekly reading and the home command board.
class InsightCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? badge;
  final Widget child;

  /// Rendered under a hairline divider, integrated — not tacked to the bottom.
  final Widget? actions;

  /// Faint caveats (short sample, missing data). Never hidden.
  final List<String> notes;
  final Color? edge;

  const InsightCard({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.subtitle,
    this.badge,
    this.actions,
    this.notes = const [],
    this.edge,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _ink,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: edge == null ? _hair : edge!.withValues(alpha: .32),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _mint.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: _mint, size: 17),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .2,
                  ),
                ),
              ),
              ?badge,
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(
              subtitle!,
              style: const TextStyle(
                color: _onInkMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 14),
          child,
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...notes.map(
              (note) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, size: 12, color: _onInkFaint),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        note,
                        style: const TextStyle(
                          color: _onInkFaint,
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (actions != null) ...[
            const SizedBox(height: 14),
            const Divider(height: 1, color: _hair),
            const SizedBox(height: 12),
            actions!,
          ],
        ],
      ),
    );
  }
}

/// A single bullet line inside an [InsightCard].
class InsightLine extends StatelessWidget {
  final String text;
  final Color dot;
  const InsightLine(this.text, {super.key, this.dot = _mint});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6, right: 9),
            width: 4,
            height: 4,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: _onInk,
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A labelled row on the dark surface: LABEL over a value, optional trailing.
class InsightRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;
  const InsightRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: _mint),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    color: _onInkFaint,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    color: _onInk,
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ],
      ),
    );
  }
}

/// The one tinted status pill used across the app — a hue-tinted fill with a
/// faint same-hue hairline so it reads as a solid token, not floating text.
/// Both [ConfidenceBadge] and [AvailabilityChip] render through this.
class StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final bool compact;
  const StatusPill(this.label, this.color, {super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .30)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: compact ? 9 : 10,
          fontWeight: FontWeight.w900,
          letterSpacing: .2,
        ),
      ),
    );
  }
}

enum Confidence { alta, media, baja }

class ConfidenceBadge extends StatelessWidget {
  final Confidence level;
  const ConfidenceBadge(this.level, {super.key});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (level) {
      Confidence.alta => ('Confianza alta', _mint),
      Confidence.media => ('Confianza media', CX.amber),
      Confidence.baja => ('Confianza baja', const Color(0xFFFF9B9B)),
    };
    return StatusPill(label, color, compact: true);
  }
}

/// Sober status pill for a player's availability — same 5-state palette
/// (green/amber/red/red/gray) everywhere it appears. Never implies a block:
/// it's a heads-up, not a lock.
class AvailabilityChip extends StatelessWidget {
  final PlayerAvailability availability;
  final bool compact;
  const AvailabilityChip(this.availability, {super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return StatusPill(availability.label, availability.color, compact: compact);
  }
}

/// Eyebrow + title, with an optional trailing action. Groups a light-surface
/// section without another card. [eyebrow] is optional — omit it for a plain
/// titled section that still carries the accent marker.
class PremiumSectionHeader extends StatelessWidget {
  final String? eyebrow;
  final String title;
  final Widget? trailing;
  const PremiumSectionHeader({
    super.key,
    this.eyebrow,
    required this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14, top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 3,
            height: 30,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              color: CX.green,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null && eyebrow!.trim().isNotEmpty) ...[
                  Text(
                    eyebrow!.toUpperCase(),
                    style: const TextStyle(
                      color: CX.green,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .8,
                    ),
                  ),
                  const SizedBox(height: 3),
                ],
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    height: 1.15,
                    letterSpacing: -.2,
                  ),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Thin bar comparing [value] to a [reference] on a [max] scale. Drawn, not
/// charted. Green when [value] is on the good side of the reference.
class CompareMeter extends StatelessWidget {
  final double value;
  final double reference;
  final double max;
  final bool higherIsBetter;
  const CompareMeter({
    super.key,
    required this.value,
    required this.reference,
    required this.max,
    this.higherIsBetter = true,
  });

  @override
  Widget build(BuildContext context) {
    final good = higherIsBetter ? value >= reference : value <= reference;
    return SizedBox(
      height: 6,
      child: CustomPaint(
        painter: _MeterPainter(
          value: (value / max).clamp(0, 1).toDouble(),
          reference: (reference / max).clamp(0, 1).toDouble(),
          fill: good ? CX.green : CX.amber,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _MeterPainter extends CustomPainter {
  final double value;
  final double reference;
  final Color fill;
  _MeterPainter({
    required this.value,
    required this.reference,
    required this.fill,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, r),
      Paint()..color = CX.line,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width * value, size.height),
        r,
      ),
      Paint()..color = fill,
    );
    final refX = size.width * reference;
    canvas.drawRect(
      Rect.fromLTWH(refX - 1, -1, 2, size.height + 2),
      Paint()..color = CX.white.withValues(alpha: .55),
    );
  }

  @override
  bool shouldRepaint(covariant _MeterPainter old) =>
      old.value != value || old.reference != reference || old.fill != fill;
}

/// A metric: icon, big value, label, one context line, optional meter.
class MetricTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final String context;
  final Color accent;
  final Widget? meter;

  const MetricTile({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.context,
    required this.accent,
    this.meter,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CX.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CX.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: accent, size: 17),
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: -.4,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: CX.white,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: .1,
            ),
          ),
          if (meter != null) ...[const SizedBox(height: 4), meter!],
          Text(
            this.context,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: CX.faint, fontSize: 9.5, height: 1.25),
          ),
        ],
      ),
    );
  }
}

/// Responsive grid of [MetricTile]s.
class MetricGrid extends StatelessWidget {
  final List<Widget> tiles;
  const MetricGrid({super.key, required this.tiles});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth < 620
            ? 2
            : c.maxWidth < 940
            ? 3
            : tiles.length.clamp(1, 6);
        return GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: c.maxWidth < 620 ? 1.24 : 1.36,
          children: tiles,
        );
      },
    );
  }
}

/// One result in a recent-form strip. Big, legible, with the score and rival.
class FormPill extends StatelessWidget {
  final String outcome; // 'G' | 'E' | 'P'
  final String? score;
  final String? rival;
  final bool home;
  final bool onDark;

  const FormPill({
    super.key,
    required this.outcome,
    this.score,
    this.rival,
    this.home = true,
    this.onDark = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = outcome == 'E'
        ? CX.amber
        : outcome == 'G'
        ? CX.green
        : CX.red;
    final subColor = onDark ? const Color(0xFF9DB2AB) : CX.faint;
    return Column(
      children: [
        Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: onDark ? .9 : .85),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            outcome,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
        ),
        if (score != null) ...[
          const SizedBox(height: 5),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                home ? Icons.home_rounded : Icons.flight_takeoff_rounded,
                size: 9,
                color: subColor,
              ),
              const SizedBox(width: 3),
              Text(
                score!,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  color: onDark ? _onInk : CX.white,
                ),
              ),
            ],
          ),
        ],
        if (rival != null) ...[
          const SizedBox(height: 1),
          Text(
            rival!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(color: subColor, fontSize: 8.5),
          ),
        ],
      ],
    );
  }
}

class ActionSpec {
  final String label;
  final IconData icon;
  final bool primary;
  final void Function(BuildContext) onTap;
  const ActionSpec({
    required this.label,
    required this.icon,
    required this.onTap,
    this.primary = false,
  });
}

/// Primary + secondary actions in one integrated row.
class ActionStrip extends StatelessWidget {
  final List<ActionSpec> actions;
  final bool onDark;
  const ActionStrip({super.key, required this.actions, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: actions.map((a) {
        if (a.primary) {
          return ElevatedButton.icon(
            onPressed: () => a.onTap(context),
            icon: Icon(a.icon, size: 17),
            label: Text(a.label),
          );
        }
        return OutlinedButton.icon(
          onPressed: () => a.onTap(context),
          style: onDark
              ? OutlinedButton.styleFrom(
                  foregroundColor: _mint,
                  side: const BorderSide(color: Color(0x556EF2C7)),
                )
              : null,
          icon: Icon(a.icon, size: 16),
          label: Text(a.label),
        );
      }).toList(),
    );
  }
}

/// A quiet pill that jumps somewhere. For the row of shortcuts under a board.
class QuickChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool onDark;
  const QuickChip({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.onDark = false,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: onDark ? _onInkMuted : CX.muted,
        side: BorderSide(color: onDark ? _hair : CX.line),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        visualDensity: VisualDensity.compact,
      ),
      icon: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 11)),
    );
  }
}

/// A premium, useful empty state: icon, title, message, one primary CTA and
/// optional secondaries.
class EmptyStatePanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final List<QuickChip> secondary;

  const EmptyStatePanel({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.primaryLabel,
    this.onPrimary,
    this.secondary = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: BoxDecoration(
        color: CX.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CX.line),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: CX.greenDark,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: CX.green.withValues(alpha: .22)),
            ),
            child: Icon(icon, color: CX.green, size: 26),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: .1,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 7),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: CX.muted,
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
          ),
          if (primaryLabel != null && onPrimary != null) ...[
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: onPrimary,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 42),
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              child: Text(primaryLabel!),
            ),
          ],
          if (secondary.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: secondary,
            ),
          ],
        ],
      ),
    );
  }
}

/// A row of quick-pick chips next to a free-text field — nudges a value
/// toward the canonical vocabulary (so it stays filterable/consistent)
/// without blocking a legacy or one-off free-text entry.
class QuickValueRow extends StatelessWidget {
  final List<String> values;
  final ValueChanged<String> onSelected;

  const QuickValueRow({super.key, required this.values, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: values
          .map(
            (value) => ActionChip(
              label: Text(value),
              onPressed: () => onSelected(value),
              visualDensity: VisualDensity.compact,
            ),
          )
          .toList(),
    );
  }
}
