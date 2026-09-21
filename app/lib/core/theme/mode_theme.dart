import 'package:flutter/material.dart';

import 'tokens.dart';

/// Mode and metro-line colours, as a theme extension so light/dark is one
/// lookup rather than a conditional at every call site.
///
/// **Every colour here is a real Egyptian licence-plate colour** — orange for
/// the 14-seater microbus, blue for the 8-seater tomnaya, grey for the
/// cooperative 29-seater. The road feed names its own operators that way
/// (`Paratransit 14 Seater Microbus (Orange Licenseplates)`) because that is
/// how people identify a vehicle at the kerb, before reading anything written
/// on it. It is a colour system users already know, which is the whole reason
/// the rest of the interface stays quiet.
///
/// Changing one of these to something prettier breaks the mapping to the
/// street. Don't.
@immutable
class ModeColors extends ThemeExtension<ModeColors> {
  const ModeColors({
    required this.microbus,
    required this.tomnaya,
    required this.cooperative,
    required this.formalBus,
    required this.walk,
    required this.unknown,
    required this.metroLines,
  });

  /// Orange plates. Shared by `box` and `peugeot`, which carry orange plates
  /// too — they are told apart by their label, not by hue, because inventing
  /// a colour for them would break the plate mapping for all three.
  final Color microbus;

  /// Blue plates.
  final Color tomnaya;

  /// Grey plates.
  final Color cooperative;

  /// CTA bus and minibus, and the other formal operators (LTRA, Mwasalat
  /// Misr, Green Bus). Deliberately distinct from every plate colour.
  final Color formalBus;

  final Color walk;
  final Color unknown;

  /// Keyed by the metro line's `short_name` — `M1`, `M2`, `M3`.
  ///
  /// Provisional: these hues are placeholders until they are confirmed
  /// against the operator's own wayfinding. M3 is not in the feed at all yet.
  final Map<String, Color> metroLines;

  static const light = ModeColors(
    microbus: Color(0xFFD2620B),
    tomnaya: Color(0xFF1C6FB8),
    cooperative: Color(0xFF6E6A61),
    formalBus: Color(0xFF146A60),
    walk: Color(0xFF96918A),
    unknown: Color(0xFF67635A),
    metroLines: {
      'M1': Color(0xFF1F6FB2),
      'M2': Color(0xFFC1272D),
      'M3': Color(0xFF0E8A4F),
    },
  );

  static const dark = ModeColors(
    microbus: Color(0xFFFF9F51),
    tomnaya: Color(0xFF5FAAE8),
    cooperative: Color(0xFFA8A399),
    formalBus: Color(0xFF3FB5A5),
    walk: Color(0xFF7C776D),
    unknown: Color(0xFFA6A197),
    metroLines: {
      'M1': Color(0xFF5BA3DE),
      'M2': Color(0xFFF0605F),
      'M3': Color(0xFF3FBE7C),
    },
  );

  /// Resolve a mode id — the `mode.id` the API returns, which it derives from
  /// `agency_id`.
  ///
  /// **Never** resolve a mode from `route_type`. All 1,011 routes in the road
  /// feed declare `route_type = 3`, microbuses included, because GTFS has no
  /// code for a 14-seater. `api/modes.py` already did this work; the client
  /// only maps its answer to a colour.
  Color forModeId(String id) {
    switch (id) {
      case 'microbus':
      case 'box':
      case 'peugeot':
        return microbus;
      case 'tomnaya':
        return tomnaya;
      case 'coop_minibus':
        return cooperative;
      case 'cta_bus':
      case 'cta_minibus':
      case 'ltra_minibus':
      case 'mwasalat_misr':
      case 'green_bus':
        return formalBus;
      case 'walk':
        return walk;
      case 'metro':
      default:
        // A metro leg gets its line colour from [forMetroLine]; this is only
        // reached when the line is unknown, where a guess would be a lie.
        return unknown;
    }
  }

  Color forMetroLine(String? shortName) =>
      metroLines[shortName?.toUpperCase()] ?? unknown;

  @override
  ModeColors copyWith({
    Color? microbus,
    Color? tomnaya,
    Color? cooperative,
    Color? formalBus,
    Color? walk,
    Color? unknown,
    Map<String, Color>? metroLines,
  }) {
    return ModeColors(
      microbus: microbus ?? this.microbus,
      tomnaya: tomnaya ?? this.tomnaya,
      cooperative: cooperative ?? this.cooperative,
      formalBus: formalBus ?? this.formalBus,
      walk: walk ?? this.walk,
      unknown: unknown ?? this.unknown,
      metroLines: metroLines ?? this.metroLines,
    );
  }

  @override
  ModeColors lerp(ThemeExtension<ModeColors>? other, double t) {
    if (other is! ModeColors) return this;
    return ModeColors(
      microbus: Color.lerp(microbus, other.microbus, t)!,
      tomnaya: Color.lerp(tomnaya, other.tomnaya, t)!,
      cooperative: Color.lerp(cooperative, other.cooperative, t)!,
      formalBus: Color.lerp(formalBus, other.formalBus, t)!,
      walk: Color.lerp(walk, other.walk, t)!,
      unknown: Color.lerp(unknown, other.unknown, t)!,
      metroLines: t < 0.5 ? metroLines : other.metroLines,
    );
  }
}

/// The neutral/accent palette, carried the same way so widgets read one
/// theme extension rather than reaching for [Palette] directly and picking
/// the wrong brightness.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors(this.palette);

  final Palette palette;

  @override
  AppColors copyWith({Palette? palette}) => AppColors(palette ?? this.palette);

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) =>
      t < 0.5 ? this : (other is AppColors ? other : this);
}

extension ThemeColorAccess on BuildContext {
  Palette get colors => Theme.of(this).extension<AppColors>()!.palette;
  ModeColors get modeColors => Theme.of(this).extension<ModeColors>()!;
}
