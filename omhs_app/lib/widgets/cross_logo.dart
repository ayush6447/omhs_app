import 'dart:math';

import 'package:flutter/material.dart';

/// Cyan plus inside a burst of rays, from the welcome screen reference.
class CrossLogo extends StatelessWidget {
  const CrossLogo({
    super.key,
    this.size = 150,
    required this.rayColor,
    required this.accent,
  });

  final double size;
  final Color rayColor;
  final Color accent;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        // SizedBox gives the logo a real intrinsic size (welcome screen
        // uses IntrinsicHeight to scroll on short phones).
        dimension: size,
        child: CustomPaint(painter: _CrossLogoPainter(rayColor, accent)),
      );
}

class _CrossLogoPainter extends CustomPainter {
  _CrossLogoPainter(this.rayColor, this.accent);

  final Color rayColor;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final center = size.center(Offset.zero);

    // Rays
    const n = 16;
    const lengths = [0.30, 0.22, 0.26, 0.20];
    final w = r * 0.13;
    for (var i = 0; i < n; i++) {
      final len = r * lengths[i % lengths.length];
      const start = 0.66;
      final paint = Paint()..color = i == 2 ? accent : rayColor;
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(i * 2 * pi / n);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(-w / 2, -(r * start + len), w, len),
          Radius.circular(w * 0.25),
        ),
        paint,
      );
      canvas.restore();
    }

    // Plus
    final arm = r * 1.02;
    final t = r * 0.36;
    final plus = Paint()..color = accent;
    final radius = Radius.circular(t * 0.42);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromCenter(center: center, width: arm, height: t), radius),
      plus,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromCenter(center: center, width: t, height: arm), radius),
      plus,
    );
  }

  @override
  bool shouldRepaint(_CrossLogoPainter old) =>
      old.rayColor != rayColor || old.accent != accent;
}
