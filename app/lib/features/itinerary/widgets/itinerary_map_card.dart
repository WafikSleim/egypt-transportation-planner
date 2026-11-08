import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/map/map_palette.dart';
import '../../../core/map/map_view.dart';
import '../../../core/map/route_overlay.dart';
import '../../../core/map/tile_source.dart';
import '../../../core/presentation/view_models.dart';
import '../../../core/theme/mode_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/honesty_panel.dart';
import '../../../core/widgets/mode_badge.dart';
import '../../../l10n/generated/app_localizations.dart';

/// The trip, drawn: one line per leg in its mode colour, walking dashed.
///
/// ### When this draws nothing at all
///
/// When no leg has a path. That is every plan cached before the API sent
/// geometry, and any trip OTP returned no shapes for. The card is then absent
/// rather than showing an empty map or a map with straight lines — and absent
/// rather than apologising too, because the screen under it is a complete,
/// correct itinerary that never promised a map. When *some* legs have a path,
/// the map shows those and says the rest are not drawn.
///
/// ### What is on the map, and what cannot be
///
/// Lines (legs) and dots (stops on them). Nothing moves. There is no vehicle
/// feed for Cairo paratransit, so there is nothing to put a vehicle dot on,
/// and the caption says so rather than leaving it to inference.
///
/// ### The metro on the map
///
/// A metro boarding is a disc carrying its line name, drawn by the style, and
/// the legend underneath uses the same [ModeBadge] as everywhere else, which
/// is a circle for the metro and a pill for the rest. The map is mostly shapes
/// and colours, so it is the place where M1's blue sitting next to a tomnaya
/// would be most confusing if the form difference were dropped.
class ItineraryMapCard extends StatelessWidget {
  const ItineraryMapCard({
    super.key,
    required this.route,
    this.source,
    this.surfaceBuilder,
  });

  final RouteMapVm route;

  /// Injected by tests.
  final MapTileSource? source;
  final MapSurfaceBuilder? surfaceBuilder;

  /// Distinct transit badges in trip order — one legend entry per mode or
  /// line, not per leg.
  List<ModeBadgeVm> get _legend {
    final seen = <ModeBadgeVm>[];
    for (final s in route.segments) {
      if (!s.isWalk && !seen.contains(s.badge)) seen.add(s.badge);
    }
    return seen;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final p = context.colors;
    final tiles = source ?? MapTileSource.fromEnvironment();
    final overlay = MapRouteOverlay.from(
      route,
      modes: context.modeColors,
      base: context.mapColors,
    );
    if (overlay == null) return const SizedBox.shrink();

    final hasWalk = route.segments.any((s) => s.isWalk);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The map, as a labelled picture. A platform view has no useful
        // semantics of its own; what a TalkBack user needs is that it exists
        // and what it is, with the real content in the leg list below it.
        Semantics(
          label: l.routeMapLabel,
          image: true,
          excludeSemantics: true,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.card),
            child: SizedBox(
              height: 220.h,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: p.line),
                  borderRadius: BorderRadius.circular(Radii.card),
                ),
                child: CityMapView(
                  source: tiles,
                  showCoverage: false,
                  route: overlay,
                  surfaceBuilder: surfaceBuilder,
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: Insets.sm),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: Insets.md,
          runSpacing: Insets.xs,
          children: [
            for (final b in _legend) ModeBadge(b, compact: true),
            if (hasWalk) _WalkLegend(label: l.routeMapWalkLegend),
          ],
        ),
        SizedBox(height: Insets.xs),
        Text(l.routeMapCaption, style: Theme.of(context).textTheme.bodySmall),
        if (route.hasApproximate) ...[
          SizedBox(height: Insets.sm),
          HonestyPanel(text: l.routeMapApproximate, icon: Icons.timeline),
        ],
        if (route.undrawnLegs > 0) ...[
          SizedBox(height: Insets.sm),
          HonestyPanel(
            text: l.routeMapUndrawn,
            severity: HonestySeverity.warning,
            icon: Icons.route_outlined,
          ),
        ],
        if (tiles.isTemporary) ...[
          SizedBox(height: Insets.sm),
          HonestyPanel(
            text: l.mapSourceTemporary,
            severity: HonestySeverity.warning,
            icon: Icons.cloud_off_outlined,
          ),
        ],
      ],
    );
  }
}

/// A dashed sample next to the word, so "walking is dashed" is shown rather
/// than described.
class _WalkLegend extends StatelessWidget {
  const _WalkLegend({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final color = context.modeColors.walk;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: SizedBox(
            width: 28,
            height: 4,
            child: CustomPaint(painter: _DashPainter(color)),
          ),
        ),
        SizedBox(width: Insets.xs),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _DashPainter extends CustomPainter {
  const _DashPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.height
      ..strokeCap = StrokeCap.butt;
    for (var x = 0.0; x < size.width; x += 8) {
      canvas.drawLine(
        Offset(x, size.height / 2),
        Offset((x + 4).clamp(0, size.width), size.height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}
