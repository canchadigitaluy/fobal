import 'package:flutter/material.dart';

import '../main.dart';

/// Full-bleed branded loading state — dark green gradient, pitch-lines
/// watermark, fobal lockup, and a 3-step checklist that animates in
/// sequence. Used anywhere the app needs to cover the whole viewport while
/// auth/club data loads (the access gate on cold boot, and hydrating a club
/// after picking a category) so the loading experience is consistent.
class BrandedLoadingScreen extends StatefulWidget {
  const BrandedLoadingScreen({super.key});

  @override
  State<BrandedLoadingScreen> createState() => _BrandedLoadingScreenState();
}

class _BrandedLoadingScreenState extends State<BrandedLoadingScreen>
    with TickerProviderStateMixin {
  late final AnimationController _steps = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..forward();
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _steps.dispose();
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF16332A), Color(0xFF0C201A)],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: .09,
                child: CustomPaint(painter: PitchLinesPainter()),
              ),
            ),
            Positioned(
              right: -140,
              bottom: -180,
              child: Container(
                width: 480,
                height: 480,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [CX.green.withValues(alpha: .28), Colors.transparent],
                  ),
                ),
              ),
            ),
            Positioned(
              left: -120,
              top: -140,
              child: Container(
                width: 380,
                height: 380,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [CX.green.withValues(alpha: .16), Colors.transparent],
                  ),
                ),
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      color: CX.green,
                      borderRadius: BorderRadius.circular(19),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x59000000),
                          blurRadius: 28,
                          offset: Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'fobal',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Preparando tu plataforma',
                    style: TextStyle(color: Color(0xDDE0F3EB), fontSize: 14.5),
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: 340,
                    child: Column(
                      children: [
                        _ShimmerTrack(animation: _shimmer),
                        const SizedBox(height: 18),
                        _LoadingStep(
                          animation: _steps,
                          start: 0.05,
                          label: 'Verificando tu sesión',
                        ),
                        const SizedBox(height: 13),
                        _LoadingStep(
                          animation: _steps,
                          start: 0.4,
                          label: 'Cargando datos de tu club',
                        ),
                        const SizedBox(height: 13),
                        _LoadingStep(
                          animation: _steps,
                          start: 0.75,
                          label: 'Sincronizando categorías',
                          isLast: true,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Positioned(
              bottom: 28,
              left: 0,
              right: 0,
              child: Text(
                'Plataforma para cuerpos técnicos de fútbol',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0x88E0F3EB), fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShimmerTrack extends StatelessWidget {
  final Animation<double> animation;
  const _ShimmerTrack({required this.animation});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Container(
        height: 4,
        color: Colors.white.withValues(alpha: .12),
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, _) {
            final slide = animation.value * 2.2 - 0.7;
            return Align(
              alignment: Alignment(slide * 2 - 1, 0),
              child: FractionallySizedBox(
                widthFactor: 0.45,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Color(0xFF6EF2C7),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LoadingStep extends StatelessWidget {
  final Animation<double> animation;
  final double start;
  final String label;
  final bool isLast;
  const _LoadingStep({
    required this.animation,
    required this.start,
    required this.label,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final active = animation.value >= start;
        final popT = ((animation.value - start) / 0.12).clamp(0.0, 1.0);
        final scale = Curves.easeOutBack.transform(popT);
        return Row(
          children: [
            if (isLast)
              Opacity(
                opacity: active ? 1 : 0,
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: const Color(0xFF6EF2C7),
                    backgroundColor: Colors.white.withValues(alpha: .25),
                  ),
                ),
              )
            else
              Transform.scale(
                scale: scale,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(
                    color: CX.green,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, size: 12, color: Colors.white),
                ),
              ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: active
                    ? (isLast ? Colors.white : const Color(0xDDE0F3EB))
                    : const Color(0x66E0F3EB),
                fontSize: 13.5,
                fontWeight: isLast && active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Faint pitch-outline watermark (touchline rect, halfway line, center
/// circle, penalty boxes and arcs) drawn in a single translucent stroke.
/// Purely decorative — shared by every branded dark panel in the app.
class PitchLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final fill = Paint()..color = Colors.white;
    const inset = 8.0;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - inset * 2,
      size.height - inset * 2,
    );
    canvas.drawRect(rect, stroke);
    canvas.drawLine(
      Offset(inset, size.height / 2),
      Offset(size.width - inset, size.height / 2),
      stroke,
    );
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide * .16;
    canvas.drawCircle(center, radius, stroke);
    canvas.drawCircle(center, 2.2, fill);
    final boxWidth = size.width * .57;
    final boxHeight = size.height * .14;
    final boxLeft = (size.width - boxWidth) / 2;
    canvas.drawRect(Rect.fromLTWH(boxLeft, inset, boxWidth, boxHeight), stroke);
    canvas.drawRect(
      Rect.fromLTWH(
        boxLeft,
        size.height - inset - boxHeight,
        boxWidth,
        boxHeight,
      ),
      stroke,
    );
    final arcRadius = size.shortestSide * .2;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(size.width / 2, inset), radius: arcRadius),
      0.4,
      3.14 - 0.8,
      false,
      stroke,
    );
    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(size.width / 2, size.height - inset),
        radius: arcRadius,
      ),
      3.14 + 0.4,
      3.14 - 0.8,
      false,
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant PitchLinesPainter oldDelegate) => false;
}
