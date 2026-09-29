import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/format.dart';
import '../theme/app_colors.dart';
import '../theme/app_settings.dart';
import '../theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Buttons

enum PillVariant { pink, primary, outline }

class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = PillVariant.pink,
    this.icon,
    this.expand = false,
    this.outlineColor,
  });

  final String label;
  final VoidCallback? onPressed;
  final PillVariant variant;
  final IconData? icon;
  final bool expand;

  /// Border/text colour for [PillVariant.outline]; defaults to primary.
  final Color? outlineColor;

  @override
  Widget build(BuildContext context) {
    final c = context.omhs;
    final (Color bg, Color fg, BorderSide side) = switch (variant) {
      PillVariant.pink => (c.pink, c.onPink, BorderSide.none),
      PillVariant.primary => (c.primary, c.onPrimary, BorderSide.none),
      PillVariant.outline => (
          Colors.transparent,
          outlineColor ?? c.primary,
          BorderSide(color: outlineColor ?? c.primary, width: 1.4),
        ),
    };
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: onPressed == null ? 0.45 : 1,
      child: Material(
        color: bg,
        shape: StadiumBorder(side: side),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20, color: fg),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: kBodyFont,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Round sun/moon button that flips light <-> dark.
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key, this.onHero = false});

  /// True when placed on the blue hero background.
  final bool onHero;

  @override
  Widget build(BuildContext context) {
    final c = context.omhs;
    final dark = context.isDark;
    final fg = onHero ? Colors.white : c.primary;
    final bg = onHero ? Colors.white.withValues(alpha: 0.12) : c.surfaceAlt;
    return Tooltip(
      message: dark ? 'Switch to light mode' : 'Switch to dark mode',
      child: Material(
        color: bg,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context
              .read<AppSettings>()
              .toggleDark(Theme.of(context).brightness),
          child: SizedBox.square(
            dimension: 40,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, anim) => RotationTransition(
                turns: Tween(begin: 0.6, end: 1.0).animate(anim),
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: Icon(
                dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                key: ValueKey(dark),
                size: 20,
                color: fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar(this.initials, {super.key});

  final String initials;

  @override
  Widget build(BuildContext context) {
    final c = context.omhs;
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle),
      child: Text(
        initials,
        style: TextStyle(
          color: c.onPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tiles and badges

/// Circle that fills up with [fraction]; a check when complete.
class ProgressDot extends StatelessWidget {
  const ProgressDot({super.key, required this.fraction, this.size = 26});

  final double fraction;
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _DotPainter(
            fraction.clamp(0.0, 1.0).toDouble(), context.omhs.ringStart),
      );
}

class _DotPainter extends CustomPainter {
  _DotPainter(this.f, this.color);

  final double f;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 1;
    if (f >= 0.999) {
      canvas.drawCircle(center, r, Paint()..color = color);
      final s = size.shortestSide;
      final path = Path()
        ..moveTo(s * 0.30, s * 0.52)
        ..lineTo(s * 0.45, s * 0.66)
        ..lineTo(s * 0.72, s * 0.38);
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      return;
    }
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );
    if (f > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r - 3),
        -pi / 2,
        2 * pi * f,
        true,
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_DotPainter old) => old.f != f || old.color != color;
}

/// Label above a tinted tile: dot on the left, "value / max" on the right.
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.fraction,
    this.suffix,
  });

  final String label;
  final String value;
  final String? suffix;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final c = context.omhs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
              color: c.muted, fontSize: 13, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: c.surfaceAlt,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              ProgressDot(fraction: fraction),
              const SizedBox(width: 12),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: value, style: mono(20, color: c.text)),
                        if (suffix != null)
                          TextSpan(
                            text: '  $suffix',
                            style: mono(13,
                                weight: FontWeight.w400, color: c.muted),
                          ),
                      ]),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class PillBadge extends StatelessWidget {
  const PillBadge(this.text, {super.key, required this.bg, required this.fg});

  final String text;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          style: mono(12, color: fg),
        ),
      );
}

class CategoryBadge extends StatelessWidget {
  const CategoryBadge(this.category, {super.key});

  final CholCategory category;

  @override
  Widget build(BuildContext context) {
    final c = context.omhs;
    final (Color bg, Color fg) = switch (category) {
      CholCategory.desirable => (c.primary, c.onPrimary),
      CholCategory.borderline => (c.pink, c.onPink),
      CholCategory.high => (c.danger, Colors.white),
    };
    return PillBadge(categoryLabel(category), bg: bg, fg: fg);
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            color: context.omhs.muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.1,
          ),
        ),
      );
}

/// Label on the left, widget on the right (used inside cards).
class KeyValueRow extends StatelessWidget {
  const KeyValueRow(this.label, this.trailing, {super.key});

  final String label;
  final Widget trailing;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: context.omhs.text),
            ),
          ),
          trailing,
        ],
      );
}

/// Tinted rounded card.
class SoftCard extends StatelessWidget {
  const SoftCard({super.key, required this.child, this.padding = 18});

  final Widget child;
  final double padding;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.all(padding),
        decoration: BoxDecoration(
          color: context.omhs.surfaceAlt,
          borderRadius: BorderRadius.circular(22),
        ),
        child: child,
      );
}

// ---------------------------------------------------------------------------
// Segmented pill selector

class SegmentedPill<T> extends StatelessWidget {
  const SegmentedPill({
    super.key,
    required this.values,
    required this.labels,
    required this.selected,
    required this.onChanged,
    this.icons,
  });

  final List<T> values;
  final List<String> labels;
  final List<IconData>? icons;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.omhs;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: values[i] == selected,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(values[i]),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    height: 44,
                    decoration: BoxDecoration(
                      color:
                          values[i] == selected ? c.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (icons != null) ...[
                          Icon(icons![i],
                              size: 16,
                              color: values[i] == selected
                                  ? c.onPrimary
                                  : c.muted),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          labels[i],
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color:
                                values[i] == selected ? c.onPrimary : c.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
