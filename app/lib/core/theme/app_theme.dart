import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../map/map_palette.dart';
import 'mode_theme.dart';
import 'tokens.dart';

/// Builds both themes from one token set.
///
/// Dark is built from [Palette.dark], not from `Brightness.dark` applied to
/// the light palette. The difference is not cosmetic: the mode colours are
/// licence-plate hues, and an inverted light palette leaves them vibrating
/// against the dark ground.
class AppTheme {
  static ThemeData light() =>
      _build(Palette.light, ModeColors.light, Brightness.light);
  static ThemeData dark() =>
      _build(Palette.dark, ModeColors.dark, Brightness.dark);

  static ThemeData _build(Palette p, ModeColors modes, Brightness brightness) {
    final text = _textTheme(p);
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: p.bg,
      canvasColor: p.bg,
      fontFamily: Faces.ui,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: p.accent,
        onPrimary: p.accentInk,
        primaryContainer: p.accentSoft,
        onPrimaryContainer: p.accent,
        secondary: p.accent,
        onSecondary: p.accentInk,
        error: p.critical,
        onError: p.accentInk,
        surface: p.surface,
        onSurface: p.ink,
        surfaceContainerHighest: p.raise,
        outline: p.line,
      ),
      textTheme: text,
      dividerColor: p.line,
      dividerTheme: DividerThemeData(color: p.line, space: 1, thickness: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: p.bg,
        foregroundColor: p.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.card),
          side: BorderSide(color: p.line),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.accent,
          foregroundColor: p.accentInk,
          minimumSize: Size.fromHeight(52.h),
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.field),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.accent,
          textStyle: text.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        hintStyle: text.bodyMedium?.copyWith(color: p.ink3),
        contentPadding: EdgeInsetsDirectional.symmetric(
          horizontal: Insets.lg,
          vertical: Insets.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.field),
          borderSide: BorderSide(color: p.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.field),
          borderSide: BorderSide(color: p.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.field),
          borderSide: BorderSide(color: p.accent, width: 1.6),
        ),
      ),
      listTileTheme: ListTileThemeData(iconColor: p.ink2, textColor: p.ink),
      // The basemap carries its own set, built from the neutral ramp only —
      // a road drawn in a licence-plate colour would overload the one colour
      // system the product depends on. See core/map/map_palette.dart.
      extensions: <ThemeExtension<dynamic>>[
        AppColors(p),
        modes,
        MapPalette.forBrightness(brightness),
      ],
    );
  }

  static TextTheme _textTheme(Palette p) {
    return TextTheme(
      // Display face, used with restraint: screen titles and the one number
      // that matters on a card.
      displaySmall: TextStyle(
        fontFamily: Faces.display,
        fontSize: 30.sp,
        height: 1.25,
        fontWeight: FontWeight.w600,
        color: p.ink,
      ),
      headlineSmall: TextStyle(
        fontFamily: Faces.display,
        fontSize: 22.sp,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: p.ink,
      ),
      titleLarge: TextStyle(
        fontFamily: Faces.display,
        fontSize: 19.sp,
        height: 1.35,
        fontWeight: FontWeight.w600,
        color: p.ink,
      ),
      titleMedium: TextStyle(
        fontFamily: Faces.ui,
        fontSize: 16.sp,
        height: 1.4,
        fontWeight: FontWeight.w600,
        color: p.ink,
      ),
      bodyLarge: TextStyle(
        fontFamily: Faces.ui,
        fontSize: 16.sp,
        height: 1.6,
        color: p.ink,
      ),
      bodyMedium: TextStyle(
        fontFamily: Faces.ui,
        fontSize: 14.5.sp,
        height: 1.6,
        color: p.ink2,
      ),
      bodySmall: TextStyle(
        fontFamily: Faces.ui,
        fontSize: 13.sp,
        height: 1.55,
        color: p.ink3,
      ),
      labelLarge: TextStyle(
        fontFamily: Faces.ui,
        fontSize: 15.sp,
        fontWeight: FontWeight.w600,
        color: p.ink,
      ),
      labelMedium: TextStyle(
        fontFamily: Faces.ui,
        fontSize: 13.sp,
        fontWeight: FontWeight.w600,
        color: p.ink2,
      ),
      // Data face. Times and counts, always with tabular figures so a column
      // of departures lines up.
      labelSmall: TextStyle(
        fontFamily: Faces.mono,
        fontSize: 12.sp,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.12 * 12.sp,
        color: p.ink3,
      ),
    );
  }
}

/// Times, durations and counts. Kept as one style so it cannot drift.
TextStyle dataStyle(
  BuildContext context, {
  double? size,
  FontWeight weight = FontWeight.w600,
  Color? color,
}) {
  return TextStyle(
    fontFamily: Faces.mono,
    fontSize: size ?? 15.sp,
    fontWeight: weight,
    color: color ?? Theme.of(context).extension<AppColors>()!.palette.ink,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}
