import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/user_profile.dart';
import '../device/device_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_settings.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'home_shell.dart';
import 'setup_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  void _go(BuildContext context, {required bool connect}) {
    if (connect) context.read<DeviceService>().connect();
    final nav = Navigator.of(context);
    Route<void> fade(Widget page) => PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 450),
          pageBuilder: (_, __, ___) => page,
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
        );
    // Ask who's being measured the first time only (and not for people
    // who filled in a profile before setup existed).
    final settings = context.read<AppSettings>();
    final needsSetup =
        !settings.setupDone && context.read<ProfileStore>().profile.isEmpty;
    if (!needsSetup) settings.markSetupDone();
    nav.pushReplacement(fade(needsSetup
        ? SetupScreen(
            onDone: () => nav.pushReplacement(fade(const HomeShell())))
        : const HomeShell()));
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
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(26),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Image.asset(
                        'assets/branding/omhs_logo_icon.png',
                        width: 112,
                        height: 112,
                        semanticLabel: 'OMHS',
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
