import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The big segmented ring from the dashboard: pink wedges, a lavender->blue
/// progress arc on the outside and a dashed marker at 12 o'clock.
class RingGauge extends StatelessWidget {
  const RingGauge({
    super.key,
    required this.progress,
    required this.child,
    this.size = 250,
  });

  final double progress;
  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.omhs;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0).toDouble()),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      child: Center(child: child),
      builder: (context, v, child) => SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _RingPainter(v, c), child: child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress, this.c);

  final double progress;
  final OmhsColors c;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2;

    // Outer track
    canvas.drawCircle(center, r, Paint()..color = c.ringTrack);

    // Pink wedges
    const n = 28;
    final r1 = r * 0.60, r2 = r * 0.84;
    final segRect = Rect.fromCircle(center: center, radius: (r1 + r2) / 2);
    final seg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r2 - r1;
    for (var i = 0; i < n; i++) {
      seg.color = i.isEven ? c.ringSegA : c.ringSegB;
      canvas.drawArc(segRect, -pi / 2 + i * 2 * pi / n, 2 * pi / n + 0.004,
          false, seg);
    }

    // Progress arc
    if (progress > 0.001) {
      final arcRect = Rect.fromCircle(center: center, radius: r * 0.90);
      final sweep = 2 * pi * progress;
      final shader = SweepGradient(
        endAngle: max(sweep, 0.01),
        colors: [c.ringStart, c.ringEnd],
        transform: const GradientRotation(-pi / 2),
      ).createShader(arcRect);
      canvas.drawArc(
        arcRect,
        -pi / 2,
        sweep,
        false,
        Paint()
          ..shader = shader
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.11
          ..strokeCap = StrokeCap.round,
      );
    }

    // Inner disc
    canvas.drawCircle(center, r1, Paint()..color = c.bg);

    // Dashed marker at the top
    final tick = Paint()
      ..color = c.text
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final bottom = center.dy - r1 + 6;
    for (var y = center.dy - r + 2; y < bottom; y += 9) {
      canvas.drawLine(
          Offset(center.dx, y), Offset(center.dx, min(y + 5, bottom)), tick);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.c != c;
}

/// Simpler ring for the blue live-measurement card.
class HeroRing extends StatelessWidget {
  const HeroRing({
    super.key,
    required this.progress,
    required this.child,
    this.size = 200,
  });

  final double progress;
  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.omhs;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0).toDouble()),
      duration: const Duration(milliseconds: 250),
      child: Center(child: child),
      builder: (context, v, child) => SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _HeroRingPainter(v, c.cyan), child: child),
      ),
    );
  }
}

class _HeroRingPainter extends CustomPainter {
  _HeroRingPainter(this.progress, this.accent);

  final double progress;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 14.0;
    final center = size.center(Offset.zero);
    final rect = Rect.fromCircle(
        center: center, radius: size.shortestSide / 2 - stroke / 2);
    canvas.drawArc(
      rect,
      0,
      2 * pi,
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.14)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    if (progress > 0.001) {
      canvas.drawArc(
        rect,
        -pi / 2,
        2 * pi * progress,
        false,
        Paint()
          ..color = accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_HeroRingPainter old) =>
      old.progress != progress || old.accent != accent;
}
