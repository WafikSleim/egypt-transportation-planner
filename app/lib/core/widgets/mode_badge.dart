import 'package:flutter/material.dart';

import '../presentation/view_models.dart';
import '../theme/mode_theme.dart';
import '../theme/tokens.dart';

/// Draws a mode.
///
/// Two forms, and the difference is load-bearing: **metro lines are circles,
/// everything else is a pill.** M1's blue and the tomnaya's plate blue are
/// close enough to confuse, and the shape is what keeps them apart. The shape
/// is decided in `TripPresenter`, not here — this widget only draws what it
/// is handed.
class ModeBadge extends StatelessWidget {
  const ModeBadge(this.badge, {super.key, this.compact = false});

  final ModeBadgeVm badge;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return badge.shape == ModeBadgeShape.metroCircle
        ? _MetroCircle(badge: badge, compact: compact)
        : _ModePill(badge: badge, compact: compact);
  }
}

class _ModePill extends StatelessWidget {
  const _ModePill({required this.badge, required this.compact});

  final ModeBadgeVm badge;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = context.modeColors.forModeId(badge.modeId);
    return Container(
      padding: EdgeInsetsDirectional.symmetric(
        horizontal: compact ? Insets.sm : Insets.md,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        // A 13% tint of the mode colour, so the hue reads without the chip
        // shouting. The base palette is quiet precisely so these can work.
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(Radii.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
          SizedBox(width: Insets.sm),
          Text(
            badge.label,
            style: TextStyle(
              fontFamily: Faces.ui,
              fontSize: compact ? 12 : 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetroCircle extends StatelessWidget {
  const _MetroCircle({required this.badge, required this.compact});

  final ModeBadgeVm badge;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = context.modeColors.forMetroLine(badge.metroLine);
    final size = compact ? 22.0 : 25.0;
    return Semantics(
      label: '${badge.label} ${badge.metroLine ?? ''}'.trim(),
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Text(
          badge.metroLine ?? 'M',
          textDirection: TextDirection.ltr,
          style: TextStyle(
            fontFamily: Faces.mono,
            fontSize: compact ? 10 : 11,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
