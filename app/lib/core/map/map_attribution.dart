import 'package:flutter/material.dart';

import '../text/bidi.dart';
import '../theme/mode_theme.dart';
import '../theme/tokens.dart';
import 'tile_source.dart';

/// The basemap's credit, drawn on the map itself.
///
/// ### Why this is not `AttributionNote`
///
/// It looks like the same widget and it is deliberately not one.
/// `core/widgets/attribution_note.dart` carries **the transit data's**
/// attribution: Transport for Cairo, CC BY-NC 4.0, wording fixed by the
/// licence, fetched from `/attribution` at runtime so the app's wording
/// cannot drift from the server's.
///
/// This one carries **the basemap's**: OpenStreetMap, ODbL, plus Protomaps
/// whose build of OSM the tiles are. Four things differ, and each of them
/// would be a bug if the two were merged:
///
/// - Different works under different licences. ODbL and CC BY-NC cannot be
///   presented as one credit any more than they can be merged into one
///   database — that is the same rule that keeps the `places` table separate
///   from the TfC data.
/// - This one is known at build time, from the tile source. Asking the
///   transit API for it would be asking the wrong server.
/// - ODbL wants the credit where the map is, not on an About screen two taps
///   away. So this is an overlay on the map surface, not a paragraph at the
///   bottom of a scroll view.
/// - A screen can show one, the other, or both. An itinerary drawn over a
///   basemap owes both credits, to two different projects.
///
/// If the tile source ever changes to one with different terms, change
/// [MapAttribution] — not this widget, which only draws what it is handed.
class MapAttributionNote extends StatelessWidget {
  const MapAttributionNote(this.attribution, {super.key});

  final MapAttribution attribution;

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    return Container(
      padding: EdgeInsetsDirectional.symmetric(
        horizontal: Insets.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        // Legible over whatever the map happens to be showing underneath,
        // without being a solid block on top of the cartography.
        color: p.bg.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(Radii.chip),
      ),
      // An English credit inside an RTL page. Isolated and explicitly
      // left-to-right, or the `©` and the `·` reorder around the words.
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Text(
          bidiIsolate(attribution.text),
          textAlign: TextAlign.start,
          style: TextStyle(
            fontFamily: Faces.ui,
            fontSize: 10.5,
            height: 1.4,
            color: p.ink2,
          ),
        ),
      ),
    );
  }
}
