import 'dart:math' as math;
import 'dart:ui';

/// WCAG 2.1 contrast arithmetic.
///
/// One implementation, used by the widgets that pick a foreground **and** by
/// `test/accessibility_test.dart`, which records the measured ratio of every
/// pair in the product. Two copies would drift, and the drift would be
/// invisible: the test would keep passing against numbers the app no longer
/// draws.
///
/// The formulae are from WCAG 2.1 — relative luminance §Relative luminance,
/// contrast ratio §Contrast ratio. Colours must be opaque; composite first
/// with [compositeOver] if they are not, because a tint over an unknown ground
/// has no contrast ratio.
double relativeLuminance(Color colour) {
  double channel(double c) =>
      c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(colour.r) +
      0.7152 * channel(colour.g) +
      0.0722 * channel(colour.b);
}

/// 1.0 (identical) to 21.0 (black on white).
double contrastRatio(Color a, Color b) {
  final la = relativeLuminance(a);
  final lb = relativeLuminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Flatten a translucent colour onto an opaque one.
///
/// The mode chips are a 13% tint of the plate colour, so the colour a reader
/// actually sees behind the label is this, never the token.
Color compositeOver(Color foreground, Color background) {
  final a = foreground.a;
  return Color.from(
    alpha: 1,
    red: foreground.r * a + background.r * (1 - a),
    green: foreground.g * a + background.g * (1 - a),
    blue: foreground.b * a + background.b * (1 - a),
  );
}

/// Whichever of [dark] and [light] is more legible on [background].
///
/// Used for the metro line badge, and deliberately **not** for the mode chips.
/// A line badge is a solid disc of the operator's own colour with a label on
/// top: the colour is the datum and the label is only a label, so choosing the
/// label for legibility costs nothing. A mode chip's label *is* the plate
/// colour, and adjusting it would repaint the one colour system this product
/// has — see `docs/design-system.md`.
Color legibleOn(Color background, {required Color dark, required Color light}) {
  return contrastRatio(dark, background) >= contrastRatio(light, background)
      ? dark
      : light;
}
