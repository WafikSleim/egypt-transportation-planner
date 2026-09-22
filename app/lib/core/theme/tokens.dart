import 'package:flutter/widgets.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Design tokens, transcribed from `docs/design-system.md`.
///
/// That document is the source, not this file and not the HTML prototypes.
/// If a value here disagrees with it, the document wins.
///
/// Both themes are declared as complete sets. Dark is **not** an inverted
/// light theme: the mode colours below are desaturated separately, because
/// the plate hues vibrate against a dark ground otherwise.
class Palette {
  const Palette({
    required this.bg,
    required this.surface,
    required this.raise,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.line,
    required this.accent,
    required this.accentSoft,
    required this.accentInk,
    required this.ok,
    required this.warn,
    required this.critical,
  });

  final Color bg;
  final Color surface;
  final Color raise;
  final Color ink;
  final Color ink2;
  final Color ink3;
  final Color line;

  /// Deep indigo, chosen because it is neither a licence-plate colour nor a
  /// metro line colour. It can therefore never be mistaken for a mode, and
  /// must never be used to mean one.
  final Color accent;
  final Color accentSoft;
  final Color accentInk;

  /// Semantic, and deliberately separate from the accent. Never carried by
  /// colour alone — always paired with a stripe, a pill or a label.
  final Color ok;
  final Color warn;
  final Color critical;

  static const light = Palette(
    bg: Color(0xFFFBFAF7),
    surface: Color(0xFFFFFFFF),
    raise: Color(0xFFF4F2EC),
    ink: Color(0xFF14130F),
    ink2: Color(0xFF67635A),
    ink3: Color(0xFF96918A),
    line: Color(0xFFE6E2D9),
    accent: Color(0xFF4A3FA0),
    accentSoft: Color(0xFFEFEDFB),
    accentInk: Color(0xFFFFFFFF),
    ok: Color(0xFF1E7A4C),
    warn: Color(0xFF9A6E06),
    critical: Color(0xFFB3261E),
  );

  static const dark = Palette(
    bg: Color(0xFF121210),
    surface: Color(0xFF1C1B18),
    raise: Color(0xFF24231F),
    ink: Color(0xFFF3F1EA),
    ink2: Color(0xFFA6A197),
    ink3: Color(0xFF7C776D),
    line: Color(0xFF2E2D28),
    accent: Color(0xFF9A90F0),
    accentSoft: Color(0xFF232041),
    accentInk: Color(0xFF15122B),
    ok: Color(0xFF4FC98A),
    warn: Color(0xFFE0B341),
    critical: Color(0xFFF27168),
  );
}

/// Spacing, on a 4px base, **already scaled**.
///
/// These are getters rather than constants because each one runs the design
/// figure through screenutil (`.r`). Scaling here rather than at every call
/// site means there is one place to get it right, and no screen can quietly
/// opt out — but it does mean these are not compile-time constants, so the
/// widgets using them are not `const`.
///
/// Design figures are in the 390x844 frame declared in `app.dart`.
class Insets {
  static double get xs => 4.0.r;
  static double get sm => 8.0.r;
  static double get md => 12.0.r;
  static double get lg => 16.0.r;
  static double get xl => 24.0.r;
  static double get xxl => 32.0.r;
}

/// Accessibility floors.
///
/// **Raw values, deliberately not scaled.** Everything else in this file runs
/// its design figure through screenutil, which is right for spacing: the
/// design is drawn at 390x844 and a small phone should get a proportionally
/// smaller gap. A minimum touch target is the opposite kind of number. It is a
/// floor set by the human finger, not by the frame, and scaling 48 against a
/// 640-tall phone yields 36 — on exactly the cheap, small Androids this app is
/// for, and without anything looking wrong.
class A11y {
  /// Android's minimum touch target, and what
  /// `meetsGuideline(androidTapTargetGuideline)` checks in `test/`.
  static const double minTapTarget = 48.0;
}

class Radii {
  /// Cards. Reserve borders and shadow for genuinely separate objects — not
  /// every block is a card.
  static double get card => 17.0.r;
  static double get chip => 999.0.r;
  static double get field => 14.0.r;
}

class Faces {
  /// Readex Pro — drawn for Arabic/Latin harmony and low-literacy
  /// legibility, which is the right reasoning for a civic tool.
  static const display = 'ReadexPro';

  static const ui = 'IBMPlexSansArabic';

  /// Times, counts, ids. Anything in a column also gets tabular figures.
  static const mono = 'IBMPlexMono';

  static const fallback = <String>['IBMPlexSansArabic'];
}
