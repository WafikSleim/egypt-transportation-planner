import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../domain/entities/trip_endpoint.dart';
import '../theme/mode_theme.dart';

/// The 32px mark in front of a stop, a place or a plain point.
///
/// Different on purpose, because they behave differently: **a stop is where a
/// vehicle calls, a place is where you are going.** A stop is drawn in the
/// microbus plate orange and a place in the accent — `.pmark.stop` and
/// `.pmark.place` in `docs/design-system.md`. The accent is the one colour
/// that is neither a plate nor a metro line, so a place can never be mistaken
/// for a mode; and the orange is borrowed for a stop only because that is the
/// register a passenger already reads as "the kerb".
///
/// The shape differs as well as the colour (a signpost against a pin), so the
/// distinction survives greyscale.
class EndpointMark extends StatelessWidget {
  const EndpointMark(this.kind, {super.key});

  final EndpointKind kind;

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    final (Color ground, Color glyph, IconData icon) = switch (kind) {
      EndpointKind.stop => (
        context.modeColors.microbus.withValues(alpha: 0.13),
        context.modeColors.microbus,
        Icons.signpost_outlined,
      ),
      EndpointKind.place => (p.accentSoft, p.accent, Icons.place_outlined),
      EndpointKind.point => (p.raise, p.ink2, Icons.pin_drop_outlined),
    };

    // ExcludeSemantics: the row it sits in already says what kind of thing it
    // is, in words, and a screen reader should not announce a glyph as well.
    return ExcludeSemantics(
      child: Container(
        width: 32.r,
        height: 32.r,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: ground,
          borderRadius: BorderRadius.circular(10.r),
        ),
        child: Icon(icon, size: 17.r, color: glyph),
      ),
    );
  }
}
