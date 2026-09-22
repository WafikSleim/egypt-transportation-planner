import 'package:flutter/material.dart';

import '../../../core/map/map_view.dart';
import '../../../core/map/tile_source.dart';
import '../../../core/theme/mode_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/honesty_panel.dart';
import '../../../l10n/generated/app_localizations.dart';

/// The covered area, on a map.
///
/// ### Why the first map in this app is this screen
///
/// The obvious home for a basemap is behind an itinerary, and that is where
/// it goes next. It does not go there yet because `/plan` returns each leg's
/// endpoints and no geometry: drawing a straight line between two stops would
/// render a microbus as going through Nasr City in one hop. A wrong line on a
/// map is not a rough sketch, it is a claim about a route — and this is the
/// product that exists because other tools make claims about Cairo they
/// cannot support.
///
/// Coverage is a claim the data *does* support, exactly. The box comes from
/// the same constants the app refuses requests with, so the map cannot say
/// one thing while the planner does another. It also answers the question the
/// empty-results screen currently answers only after someone has typed a
/// destination and waited: is my city in this app at all.
class CoverageMapPage extends StatelessWidget {
  const CoverageMapPage({super.key, this.source, this.surfaceBuilder});

  /// Injected by tests, which have no platform view to draw into.
  final MapTileSource? source;
  final MapSurfaceBuilder? surfaceBuilder;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final p = context.colors;
    final tiles = source ?? MapTileSource.fromEnvironment();

    return Scaffold(
      appBar: AppBar(title: Text(l.mapCoverageTitle)),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // A fraction rather than a fixed height: on a 5" phone a 320px
            // map leaves no room for the text under it, and the text is the
            // part that is actually honest about what the map means.
            final mapHeight = (constraints.maxHeight * 0.46).clamp(
              200.0,
              420.0,
            );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: mapHeight,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: BorderDirectional(
                        bottom: BorderSide(color: p.line),
                      ),
                    ),
                    child: CityMapView(
                      source: tiles,
                      surfaceBuilder: surfaceBuilder,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: EdgeInsetsDirectional.all(Insets.lg),
                    children: [
                      HonestyPanel(
                        text: l.mapCoverageBody,
                        icon: Icons.crop_free,
                      ),
                      SizedBox(height: Insets.md),
                      // Rule 5 of the design system, said out loud on the one
                      // screen where a user would otherwise expect to see
                      // vehicles moving.
                      HonestyPanel(
                        text: l.mapNoVehicles,
                        severity: HonestySeverity.warning,
                        icon: Icons.directions_bus_outlined,
                      ),
                      SizedBox(height: Insets.md),
                      // Place names here are OSM's, under a different licence
                      // from the transit data. Saying so is the same rule that
                      // keeps the two datasets in separate tables.
                      HonestyPanel(
                        text: l.mapNamesFromOsm,
                        icon: Icons.translate,
                      ),
                      if (tiles.isTemporary) ...[
                        SizedBox(height: Insets.md),
                        HonestyPanel(
                          text: l.mapSourceTemporary,
                          severity: HonestySeverity.warning,
                          icon: Icons.cloud_off_outlined,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
