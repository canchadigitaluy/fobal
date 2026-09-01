// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../data/cantera_data.dart';
import '../main.dart';

/// Renders a training block's [AnimationScene] as a looping pitch animation:
/// the real space, players (own / rival / neutral), ball path, per-player
/// movements and target / forbidden / lane zones — all from the scene data,
/// never a generic template.
class ExerciseAnimationPreview extends StatefulWidget {
  final AnimationScene scene;
  final String title;

  const ExerciseAnimationPreview({
    super.key,
    required this.scene,
    this.title = 'Animación del ejercicio',
  });

  @override
  State<ExerciseAnimationPreview> createState() =>
      _ExerciseAnimationPreviewState();
}

class _ExerciseAnimationPreviewState extends State<ExerciseAnimationPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final GlobalKey _boardKey = GlobalKey();
  bool _playing = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: (widget.scene.durationSeconds * 1000).round(),
      ),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant ExerciseAnimationPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scene.durationSeconds != widget.scene.durationSeconds) {
      _controller.duration = Duration(
        milliseconds: (widget.scene.durationSeconds * 1000).round(),
      );
      if (_playing) _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlay() {
    setState(() {
      _playing = !_playing;
      if (_playing) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    });
  }

  void _restart() {
    _controller
      ..reset()
      ..repeat();
    if (!_playing) setState(() => _playing = true);
  }

  Future<void> _downloadPng() async {
    try {
      final boundary =
          _boardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final blob = html.Blob(<Object>[bytes.buffer.asUint8List()], 'image/png');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..download =
            'animacion_${widget.title.replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_')}.png'
        ..click();
      html.Url.revokeObjectUrl(url);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Imagen de la animación descargada.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No pudimos exportar la imagen en este navegador.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scene = widget.scene;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CX.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: CX.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.animation, color: CX.green, size: 16),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  _pitchLabel(scene.pitchArea),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
              if (scene.isFallback)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: CX.amber.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'aproximada',
                    style: TextStyle(
                      color: CX.amber,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          RepaintBoundary(
            key: _boardKey,
            child: AspectRatio(
              aspectRatio: 3 / 2,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) => CustomPaint(
                    painter: _ScenePainter(
                      scene: scene,
                      progress: _controller.value,
                    ),
                    size: Size.infinite,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                tooltip: _playing ? 'Pausar' : 'Reproducir',
                onPressed: _togglePlay,
                icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                iconSize: 20,
              ),
              IconButton(
                tooltip: 'Reiniciar',
                onPressed: _restart,
                icon: const Icon(Icons.replay),
                iconSize: 18,
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _downloadPng,
                icon: const Icon(Icons.download, size: 16),
                label: const Text('Descargar'),
              ),
            ],
          ),
          if (scene.coachingCues.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                scene.coachingCues.join('  ·  '),
                style: const TextStyle(color: CX.muted, fontSize: 11, height: 1.3),
              ),
            ),
        ],
      ),
    );
  }

  static String _pitchLabel(String area) => switch (area) {
    'half' => 'Media cancha',
    'attacking_third' => 'Tercio ofensivo',
    'middle_third' => 'Tercio medio',
    'defensive_third' => 'Tercio defensivo / salida',
    'small_grid' => 'Espacio reducido',
    'wide_channels' => 'Cancha con carriles / amplitud',
    _ => 'Cancha completa',
  };
}

/// Sub-rectangle of the full pitch that a [pitchArea] emphasises. Everything
/// is drawn inside this so a "small grid" scene really looks small.
Rect _areaRect(String area, Size s) {
  switch (area) {
    case 'half':
      return Rect.fromLTWH(0, s.height * 0.5, s.width, s.height * 0.5);
    case 'attacking_third':
      return Rect.fromLTWH(0, s.height * 0.62, s.width, s.height * 0.38);
    case 'middle_third':
      return Rect.fromLTWH(0, s.height * 0.33, s.width, s.height * 0.34);
    case 'defensive_third':
      return Rect.fromLTWH(0, 0, s.width, s.height * 0.42);
    case 'small_grid':
      final side = math.min(s.width, s.height) * 0.7;
      return Rect.fromCenter(
        center: Offset(s.width / 2, s.height / 2),
        width: side,
        height: side,
      );
    default:
      return Offset.zero & s;
  }
}

class _ScenePainter extends CustomPainter {
  final AnimationScene scene;
  final double progress;

  _ScenePainter({required this.scene, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final grass = Paint()..color = const Color(0xFF12362A);
    canvas.drawRect(Offset.zero & size, grass);

    // Faint full-pitch markings.
    final line = Paint()
      ..color = Colors.white.withValues(alpha: .16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final inset = Rect.fromLTWH(6, 6, size.width - 12, size.height - 12);
    canvas.drawRRect(RRect.fromRectAndRadius(inset, const Radius.circular(8)), line);
    canvas.drawLine(
      Offset(inset.left, size.height / 2),
      Offset(inset.right, size.height / 2),
      line,
    );
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.height * 0.13,
      line,
    );

    final area = _areaRect(scene.pitchArea, size);
    if (scene.pitchArea != 'full') {
      canvas.drawRRect(
        RRect.fromRectAndRadius(area.deflate(2), const Radius.circular(6)),
        Paint()
          ..color = Colors.white.withValues(alpha: .5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    Offset toPx(ScenePoint p) =>
        Offset(area.left + p.x * area.width, area.top + p.y * area.height);

    // Zones.
    for (final z in scene.zones) {
      final rect = Rect.fromLTWH(
        area.left + z.x * area.width,
        area.top + z.y * area.height,
        z.width * area.width,
        z.height * area.height,
      );
      final (fill, stroke) = switch (z.type) {
        'forbidden' => (
            const Color(0xFFDC3D3D).withValues(alpha: .14),
            const Color(0xFFDC3D3D).withValues(alpha: .6),
          ),
        'lane' => (
            Colors.white.withValues(alpha: .04),
            const Color(0xFFE0A11A).withValues(alpha: .55),
          ),
        _ => (
            const Color(0xFF159463).withValues(alpha: .16),
            const Color(0xFF6EF2C7).withValues(alpha: .7),
          ),
      };
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        Paint()..color = fill,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        Paint()
          ..color = stroke
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
      if (z.label.isNotEmpty) {
        _text(canvas, z.label, rect.topLeft + const Offset(4, 3), 8,
            Colors.white.withValues(alpha: .8));
      }
    }

    // Ball path (full trace) + moving ball.
    if (scene.ballPath.length >= 2) {
      final path = Path()..moveTo(toPx(scene.ballPath.first).dx,
          toPx(scene.ballPath.first).dy);
      for (final p in scene.ballPath.skip(1)) {
        path.lineTo(toPx(p).dx, toPx(p).dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFFF6C35B).withValues(alpha: .5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
      final ballPos = _along(scene.ballPath.map(toPx).toList(), progress);
      canvas.drawCircle(ballPos, 6, Paint()..color = const Color(0xFFF6C35B));
      canvas.drawCircle(
        ballPos,
        6,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    // Players.
    final eased = Curves.easeInOut.transform(progress);
    for (final actor in scene.players) {
      SceneMovement? move;
      for (final m in scene.movements) {
        if (m.playerId == actor.id) {
          move = m;
          break;
        }
      }
      Offset pos;
      Offset from;
      if (move != null && scene.durationSeconds > 0) {
        final s = (move.startS / scene.durationSeconds).clamp(0.0, 1.0);
        final e = (move.endS / scene.durationSeconds).clamp(0.0, 1.0);
        final local = e <= s
            ? 1.0
            : ((progress - s) / (e - s)).clamp(0.0, 1.0);
        from = toPx(ScenePoint(move.from.x, move.from.y));
        final to = toPx(ScenePoint(move.to.x, move.to.y));
        pos = Offset.lerp(from, to, Curves.easeInOut.transform(local))!;
      } else {
        from = toPx(actor.start);
        pos = Offset.lerp(from, toPx(actor.end), eased)!;
      }

      // Trail.
      canvas.drawLine(
        from,
        pos,
        Paint()
          ..color = (actor.team == 'rival'
                  ? const Color(0xFFDC3D3D)
                  : const Color(0xFF6EF2C7))
              .withValues(alpha: .35)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );

      final (fill, textColor) = switch (actor.team) {
        'rival' => (const Color(0xFF20262B), Colors.white),
        'neutral' => (const Color(0xFFE0A11A), const Color(0xFF102019)),
        _ => (const Color(0xFF6EF2C7), const Color(0xFF07100B)),
      };
      canvas.drawCircle(pos, 11, Paint()..color = fill);
      canvas.drawCircle(
        pos,
        11,
        Paint()
          ..color = Colors.white.withValues(alpha: .85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
      _text(
        canvas,
        actor.label.isEmpty ? '•' : actor.label,
        pos,
        9,
        textColor,
        center: true,
      );
    }
  }

  void _text(
    Canvas canvas,
    String value,
    Offset at,
    double size,
    Color color, {
    bool center = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      center ? at - Offset(tp.width / 2, tp.height / 2) : at,
    );
  }

  /// Point along a polyline at [t] (0..1), segments weighted equally.
  Offset _along(List<Offset> pts, double t) {
    if (pts.length == 1) return pts.first;
    final segs = pts.length - 1;
    final scaled = (t * segs).clamp(0.0, segs.toDouble());
    final i = math.min(scaled.floor(), segs - 1);
    return Offset.lerp(pts[i], pts[i + 1], scaled - i)!;
  }

  @override
  bool shouldRepaint(covariant _ScenePainter old) =>
      old.progress != progress || old.scene != scene;
}
