import 'package:flutter/material.dart';

import '../theme/mode_theme.dart';
import '../theme/tokens.dart';

/// The pattern that carries the rules about what we do **not** know.
///
/// There is no real-time vehicle data for Cairo paratransit and none to buy
/// or scrape, so every time estimate in this app comes from a recorded
/// schedule. Wherever a user would otherwise assume live data, this panel
/// says so in plain words. It is neutral by default and takes a `warn` tint
/// when it is stating a limitation rather than a caveat.
class HonestyPanel extends StatelessWidget {
  const HonestyPanel({
    super.key,
    required this.text,
    this.severity = HonestySeverity.neutral,
    this.icon,
  });

  final String text;
  final HonestySeverity severity;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    final tint = severity == HonestySeverity.warning ? p.warn : p.ink3;

    return Container(
      padding: EdgeInsetsDirectional.all(Insets.lg),
      decoration: BoxDecoration(
        color: severity == HonestySeverity.warning
            ? tint.withValues(alpha: 0.10)
            : p.raise,
        borderRadius: BorderRadius.circular(Radii.card),
        // A stripe rather than colour alone, so the state survives greyscale
        // and colour-blind viewing.
        border: BorderDirectional(start: BorderSide(color: tint, width: 4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? Icons.info_outline, size: 18, color: tint),
          SizedBox(width: Insets.md),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: severity == HonestySeverity.warning ? p.ink : p.ink2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum HonestySeverity { neutral, warning }
