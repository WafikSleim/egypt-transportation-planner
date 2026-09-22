import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The basemap's own colours.
///
/// ### Why these are not the mode colours
///
/// Every mode colour in this product is a real Egyptian licence-plate colour,
/// and that mapping only works while nothing else on screen competes with it.
/// A basemap is thousands of coloured shapes. If a motorway were drawn in
/// microbus orange, the one colour system the product depends on would be
/// carrying two meanings at once, and the weaker one — a road casing — would
/// be winning by area. So **the basemap is built from the neutral ramp
/// only**: the warm greys in [Palette], plus one desaturated blue for water
/// that is deliberately far below the chroma of the tomnaya's plate blue and
/// of M1's navy.
///
/// The accent appears exactly once, on the coverage outline, which is a
/// statement about the app rather than about a mode.
///
/// ### Why dark is a separate set and not an inversion
///
/// Inverting a light basemap gives light roads on a dark ground at the same
/// contrast ratio, which at 3 am on a phone at full brightness is a lit grid.
/// Real dark maps compress the whole range: water goes *darker* than land
/// rather than lighter, roads sit a few steps above the ground rather than at
/// the top of the ramp, and only labels reach full ink. That is what [dark]
/// below does, and it is why it is written out rather than derived.
@immutable
class MapPalette extends ThemeExtension<MapPalette> {
  const MapPalette({
    required this.earth,
    required this.water,
    required this.green,
    required this.builtUp,
    required this.building,
    required this.roadMajor,
    required this.roadMinor,
    required this.roadCasing,
    required this.boundary,
    required this.label,
    required this.labelMinor,
    required this.labelHalo,
    required this.coverage,
  });

  /// Land. Sits at `raise` in light, so the map reads as a recessed panel
  /// under the surface-coloured cards above it.
  final Color earth;

  /// The Nile, which is most of the water Cairo has, and the one place the
  /// basemap is allowed a hue. Held at low chroma on purpose — see the class
  /// comment.
  final Color water;

  final Color green;

  /// `landcover: urban_area`, drawn only far out, where it is the only thing
  /// distinguishing the city from the desert around it.
  final Color builtUp;

  final Color building;

  final Color roadMajor;
  final Color roadMinor;

  /// The line drawn under a road so two roads crossing read as two roads.
  /// In dark this goes *below* the ground colour rather than above it.
  final Color roadCasing;

  final Color boundary;

  /// Place names at the top of the hierarchy — Cairo, Giza, Helwan.
  final Color label;

  /// Neighbourhoods and everything else.
  final Color labelMinor;

  /// Arabic label strokes are fine and long; without a halo they disappear
  /// over a building fill. This is the map background, not white, or the halo
  /// itself becomes the thing you see in dark.
  final Color labelHalo;

  /// The coverage box. The one accent-coloured thing on the map.
  final Color coverage;

  static const light = MapPalette(
    earth: Color(0xFFF4F2EC),
    water: Color(0xFFD3DEE4),
    green: Color(0xFFE5EBDD),
    builtUp: Color(0xFFEDEAE1),
    building: Color(0xFFE7E3D9),
    roadMajor: Color(0xFFFFFFFF),
    roadMinor: Color(0xFFFAF8F3),
    roadCasing: Color(0xFFE0DBD0),
    boundary: Color(0xFFC9C4B8),
    label: Color(0xFF14130F),
    labelMinor: Color(0xFF67635A),
    labelHalo: Color(0xFFF4F2EC),
    coverage: Color(0xFF4A3FA0),
  );

  static const dark = MapPalette(
    // Below the app's own `bg` (#121210) so the map reads as a hole in the
    // page rather than a panel sitting on it.
    earth: Color(0xFF171714),
    // Darker than the land, the way water actually is at night. An inverted
    // light map would put it lighter and the Nile would glow.
    water: Color(0xFF10161A),
    green: Color(0xFF1A2019),
    builtUp: Color(0xFF1E1D1A),
    building: Color(0xFF232220),
    roadMajor: Color(0xFF3B3934),
    roadMinor: Color(0xFF2B2A26),
    roadCasing: Color(0xFF121210),
    boundary: Color(0xFF403E37),
    label: Color(0xFFF3F1EA),
    labelMinor: Color(0xFFA6A197),
    labelHalo: Color(0xFF171714),
    coverage: Color(0xFF9A90F0),
  );

  static MapPalette forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  @override
  MapPalette copyWith({
    Color? earth,
    Color? water,
    Color? green,
    Color? builtUp,
    Color? building,
    Color? roadMajor,
    Color? roadMinor,
    Color? roadCasing,
    Color? boundary,
    Color? label,
    Color? labelMinor,
    Color? labelHalo,
    Color? coverage,
  }) {
    return MapPalette(
      earth: earth ?? this.earth,
      water: water ?? this.water,
      green: green ?? this.green,
      builtUp: builtUp ?? this.builtUp,
      building: building ?? this.building,
      roadMajor: roadMajor ?? this.roadMajor,
      roadMinor: roadMinor ?? this.roadMinor,
      roadCasing: roadCasing ?? this.roadCasing,
      boundary: boundary ?? this.boundary,
      label: label ?? this.label,
      labelMinor: labelMinor ?? this.labelMinor,
      labelHalo: labelHalo ?? this.labelHalo,
      coverage: coverage ?? this.coverage,
    );
  }

  /// Not interpolated. A style is handed to MapLibre as a finished JSON
  /// document and reloaded wholesale on a theme change, so a half-way palette
  /// would only ever produce a style nobody sees — and would make the styles
  /// emitted during a theme animation differ from the one that lands.
  @override
  MapPalette lerp(ThemeExtension<MapPalette>? other, double t) =>
      t < 0.5 ? this : (other is MapPalette ? other : this);
}

extension MapPaletteAccess on BuildContext {
  MapPalette get mapColors => Theme.of(this).extension<MapPalette>()!;
}
