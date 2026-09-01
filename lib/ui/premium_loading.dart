import 'package:flutter/material.dart';

import '../main.dart';

class PremiumShimmer extends StatefulWidget {
  final double height;
  final double? width;
  final BorderRadius borderRadius;

  const PremiumShimmer({
    super.key,
    required this.height,
    this.width,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
  });

  @override
  State<PremiumShimmer> createState() => _PremiumShimmerState();
}

class _PremiumShimmerState extends State<PremiumShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1150),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final slide = _controller.value * 2 - 1;
        return ClipRRect(
          borderRadius: widget.borderRadius,
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(-1 + slide, 0),
                end: Alignment(1 + slide, 0),
                colors: const [
                  CX.panel2,
                  Color(0xFFFFFFFF),
                  CX.panel2,
                ],
                stops: const [0.25, 0.5, 0.75],
              ),
            ),
          ),
        );
      },
    );
  }
}

class PremiumPanelSkeleton extends StatelessWidget {
  final int rows;

  const PremiumPanelSkeleton({super.key, this.rows = 4});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: CX.panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PremiumShimmer(width: 180, height: 18),
          const SizedBox(height: 14),
          ...List.generate(
            rows,
            (index) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: PremiumShimmer(
                height: 12,
                width: index.isEven ? double.infinity : 260,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
