import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../device/device_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/cross_logo.dart';
import 'home_shell.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  void _go(BuildContext context, {required bool connect}) {
    if (connect) context.read<DeviceService>().connect();
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (_, __, ___) => const HomeShell(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omhs;
    final white = Colors.white;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light
          .copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: c.hero,
        body: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _ArcsPainter(white.withValues(alpha: 0.07)),
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, box) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: box.maxHeight),
                    child: IntrinsicHeight(
                      child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Align(
                      alignment: Alignment.centerRight,
                      child: ThemeToggleButton(onHero: true),
                    ),
                    Transform.translate(
                      offset: const Offset(-14, -8),
                      child: CrossLogo(
                        size: 150,
                        rayColor: Color.lerp(c.hero, white, 0.16)!,
                        accent: c.cyan,
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(height: 24),
                    Text(
                      'Cholesterol\ncheck,\nno needles.',
                      style: mono(40, color: white, height: 1.15),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Non-invasive NIR measurement with your OMHS device. '
                      'Results in about a minute.',
                      style: TextStyle(
                        color: white.withValues(alpha: 0.85),
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 36),
                    PillButton(
                      label: 'Connect device',
                      onPressed: () => _go(context, connect: true),
                    ),
                    const SizedBox(height: 14),
                    PillButton(
                      label: 'Explore first',
                      variant: PillVariant.outline,
                      outlineColor: white,
                      onPressed: () => _go(context, connect: false),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'Research prototype · not a medical device',
                      style: TextStyle(
                        color: white.withValues(alpha: 0.55),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Faint concentric arcs in the background, like the reference.
class _ArcsPainter extends CustomPainter {
  _ArcsPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final center = Offset(size.width * 1.05, size.height * 0.52);
    for (final k in [0.75, 1.0, 1.25]) {
      canvas.drawCircle(center, size.width * k, p);
    }
  }

  @override
  bool shouldRepaint(_ArcsPainter old) => old.color != color;
}
