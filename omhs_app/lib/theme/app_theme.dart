import 'package:flutter/material.dart';

import 'app_colors.dart';

const kBodyFont = 'Poppins';
const kMonoFont = 'SpaceMono';

/// Monospaced display style used for headlines and numbers.
TextStyle mono(
  double size, {
  FontWeight weight = FontWeight.w700,
  Color? color,
  double? height,
}) =>
    TextStyle(
      fontFamily: kMonoFont,
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
    );

class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(OmhsColors.light, Brightness.light);
  static ThemeData dark() => _build(OmhsColors.dark, Brightness.dark);

  static ThemeData _build(OmhsColors c, Brightness b) {
    final scheme = ColorScheme(
      brightness: b,
      primary: c.primary,
      onPrimary: c.onPrimary,
      secondary: c.pink,
      onSecondary: c.onPink,
      tertiary: c.cyan,
      onTertiary: c.hero,
      error: c.danger,
      onError: Colors.white,
      surface: c.bg,
      onSurface: c.text,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      fontFamily: kBodyFont,
    );

    return base.copyWith(
      scaffoldBackgroundColor: c.bg,
      dividerColor: c.divider,
      textTheme: base.textTheme.apply(
        bodyColor: c.text,
        displayColor: c.text,
        fontFamily: kBodyFont,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.primary,
        selectionColor: c.primary.withValues(alpha: 0.25),
        selectionHandleColor: c.primary,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: c.divider,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.text,
        contentTextStyle: TextStyle(fontFamily: kBodyFont, color: c.bg),
      ),
      extensions: <ThemeExtension<dynamic>>[c],
    );
  }
}
