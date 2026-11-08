import 'package:flutter/material.dart';

/// MapLibre wants `#rrggbb`. Flutter's [Color] is ARGB and its alpha would
/// come out as the first pair, which silently produces a nonsense colour
/// rather than an error.
String mapHex(Color color) {
  final r = (color.r * 255).round();
  final g = (color.g * 255).round();
  final b = (color.b * 255).round();
  return '#'
      '${r.toRadixString(16).padLeft(2, '0')}'
      '${g.toRadixString(16).padLeft(2, '0')}'
      '${b.toRadixString(16).padLeft(2, '0')}';
}
