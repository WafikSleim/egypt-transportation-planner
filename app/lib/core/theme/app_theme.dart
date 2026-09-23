import 'dart:math' as math;

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
          // 52 in the design frame, but never below the 48dp floor. `.h`
          // scales against an 844-tall design: on a 640-tall phone it returns
          // 39, which is under the minimum and looks entirely normal.
          minimumSize: Size.fromHeight(math.max(52.h, A11y.minTapTarget)),
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
        // ink2, not ink3: a placeholder is text someone reads, and ink3 on
        // any of the three grounds measures under 3.2:1. See
        // `test/accessibility_test.dart`.
        hintStyle: text.bodyMedium?.copyWith(color: p.ink2),
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
      // The quietest text in the product — attribution, hints, "kept on this
      // phone", the line under a card. It carried `ink3`, which measures
      // 3.00:1 on `bg` in light and 4.21:1 in dark: under WCAG AA's 4.5 for
      // normal text in both themes. `ink2` clears it at 5.73 and 7.29.
      //
      // This is a change to the **text** theme, not to the palette. `ink3`
      // stays exactly as designed for the things it is actually good at —
      // rules, the leg spine, decorative dots, icons — none of which anybody
      // has to read. It does flatten the small-text hierarchy slightly, which
      // is the part a person has to look at.
      bodySmall: TextStyle(
        fontFamily: Faces.ui,
        fontSize: 13.sp,
        height: 1.55,
        color: p.ink2,
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
