import 'package:flutter/material.dart';

/// Dual-tone palette: royal blue + soft lavender/pink, with a cyan accent.
/// Light and dark variants share the same roles so every widget reads
/// its colours from here (via `context.omhs`) and switches automatically.
@immutable
class OmhsColors extends ThemeExtension<OmhsColors> {
  const OmhsColors({
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.hero,
    required this.primary,
    required this.onPrimary,
    required this.pink,
    required this.onPink,
    required this.cyan,
    required this.text,
    required this.muted,
    required this.divider,
    required this.ringTrack,
    required this.ringSegA,
    required this.ringSegB,
    required this.ringStart,
    required this.ringEnd,
    required this.badge,
    required this.onBadge,
    required this.ok,
    required this.danger,
  });

  /// Page background.
  final Color bg;

  /// Raised surfaces: sheets, dialogs.
  final Color surface;

  /// Tinted cards and tiles.
  final Color surfaceAlt;

  /// Full-bleed blue used on the welcome screen and the live measurement card.
  final Color hero;

  final Color primary;
  final Color onPrimary;
  final Color pink;
  final Color onPink;
  final Color cyan;
  final Color text;
  final Color muted;
  final Color divider;

  // Ring gauge
  final Color ringTrack;
  final Color ringSegA;
  final Color ringSegB;
  final Color ringStart;
  final Color ringEnd;

  // Neutral pill badge
  final Color badge;
  final Color onBadge;

  final Color ok;
  final Color danger;

  static const light = OmhsColors(
    bg: Color(0xFFFBFBFF),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF1F2FB),
    hero: Color(0xFF1F32C4),
    primary: Color(0xFF1F32C4),
    onPrimary: Color(0xFFFFFFFF),
    pink: Color(0xFFFFD3E3),
    onPink: Color(0xFF1F32C4),
    cyan: Color(0xFF1FE3F0),
    text: Color(0xFF101A73),
    muted: Color(0xFF7A7FA6),
    divider: Color(0xFFDDE0F3),
    ringTrack: Color(0xFFEDEEFA),
    ringSegA: Color(0xFFFFD9E7),
    ringSegB: Color(0xFFFFE9F1),
    ringStart: Color(0xFFA597E6),
    ringEnd: Color(0xFF2F43D4),
    badge: Color(0xFFE4E6F3),
    onBadge: Color(0xFF101A73),
    ok: Color(0xFF16A34A),
    danger: Color(0xFFE5484D),
  );

  static const dark = OmhsColors(
    bg: Color(0xFF0A0E2E),
    surface: Color(0xFF1A2157),
    surfaceAlt: Color(0xFF151B4E),
    hero: Color(0xFF1A2690),
    primary: Color(0xFF5566FF),
    onPrimary: Color(0xFFFFFFFF),
    pink: Color(0xFFFFB8D1),
    onPink: Color(0xFF141B6E),
    cyan: Color(0xFF3BEAF4),
    text: Color(0xFFEEF0FF),
    muted: Color(0xFF98A0D8),
    divider: Color(0xFF28307A),
    ringTrack: Color(0xFF1D2462),
    ringSegA: Color(0xFF3A2C6E),
    ringSegB: Color(0xFF2E2766),
    ringStart: Color(0xFFC2B5FF),
    ringEnd: Color(0xFF6475FF),
    badge: Color(0xFF252C6B),
    onBadge: Color(0xFFE6E8FF),
    ok: Color(0xFF4ADE80),
    danger: Color(0xFFFF6B7A),
  );

  @override
  OmhsColors copyWith() => this;

  @override
  OmhsColors lerp(ThemeExtension<OmhsColors>? other, double t) {
    if (other is! OmhsColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return OmhsColors(
      bg: l(bg, other.bg),
      surface: l(surface, other.surface),
      surfaceAlt: l(surfaceAlt, other.surfaceAlt),
      hero: l(hero, other.hero),
      primary: l(primary, other.primary),
      onPrimary: l(onPrimary, other.onPrimary),
      pink: l(pink, other.pink),
      onPink: l(onPink, other.onPink),
      cyan: l(cyan, other.cyan),
      text: l(text, other.text),
      muted: l(muted, other.muted),
      divider: l(divider, other.divider),
      ringTrack: l(ringTrack, other.ringTrack),
      ringSegA: l(ringSegA, other.ringSegA),
      ringSegB: l(ringSegB, other.ringSegB),
      ringStart: l(ringStart, other.ringStart),
      ringEnd: l(ringEnd, other.ringEnd),
      badge: l(badge, other.badge),
      onBadge: l(onBadge, other.onBadge),
      ok: l(ok, other.ok),
      danger: l(danger, other.danger),
    );
  }
}

extension OmhsThemeX on BuildContext {
  OmhsColors get omhs => Theme.of(this).extension<OmhsColors>()!;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}
