import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/presentation/view_models.dart';
import '../../../core/text/bidi.dart';
import '../../../core/text/formatting.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mode_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/attribution_note.dart';
import '../../../core/widgets/honesty_panel.dart';
import '../../../core/widgets/mode_badge.dart';
import '../../../data/models/models.dart';
import '../../../l10n/generated/app_localizations.dart';

/// Leg by leg.
///
/// This screen is where the no-route-number rule is most visible: for a
/// microbus leg there is no number badge, and the route is named by where it
/// starts and where it ends — which is how Cairenes name them too, because
/// the vehicles carry no numbers to read.
///
/// It is also where a saved answer is easiest to mistake for a live one: the
/// itinerary arrives here on its own, with no banner from the screen it came
/// from. So the fact travels on the view model — `itinerary.cachedAt` — and
/// is stated at the top, above the times it applies to.
class ItineraryPage extends StatelessWidget {
  const ItineraryPage({
    super.key,
    required this.itinerary,
    required this.attribution,
  });

  final ItineraryVm itinerary;
  final Attribution attribution;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final anyLatin = itinerary.legs.any(
      (leg) => isLatinName(leg.fromName) || isLatinName(leg.toName),
    );

    return Scaffold(
      appBar: AppBar(title: Text(l.itineraryTitle)),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsetsDirectional.all(Insets.lg),
          children: [
            if (itinerary.cachedAt != null) ...[
              HonestyPanel(
                severity: HonestySeverity.warning,
                icon: Icons.history_rounded,
                text: l.cachedItineraryNote(clockTime(itinerary.cachedAt!)),
              ),
              SizedBox(height: Insets.lg),
            ],
            _Summary(itinerary: itinerary),
            SizedBox(height: Insets.xl),
            for (final leg in itinerary.legs) _LegTile(leg: leg),
            SizedBox(height: Insets.lg),
            HonestyPanel(text: l.honestyNoRealtime),
            if (anyLatin) ...[
              SizedBox(height: Insets.md),
              Text(
                l.honestyLatinName,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            AttributionNote(attribution),
          ],
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.itinerary});

  final ItineraryVm itinerary;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final p = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${clockTime(itinerary.startTime)} – ${clockTime(itinerary.endTime)}',
          textDirection: TextDirection.ltr,
          style: dataStyle(context, size: 22.sp),
        ),
        SizedBox(height: Insets.xs),
        Text(
          '${l.durationMinutes(itinerary.durationMinutes)}  ·  '
          '${l.transfersCount(itinerary.transfers)}  ·  '
          '${l.walkTotal(itinerary.walkDistanceM)}',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: p.ink2),
        ),
      ],
    );
  }
}

class _LegTile extends StatelessWidget {
  const _LegTile({required this.leg});

  final LegVm leg;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final p = context.colors;
    final color = leg.badge.shape == ModeBadgeShape.metroCircle
        ? context.modeColors.forMetroLine(leg.badge.metroLine)
        : context.modeColors.forModeId(leg.badge.modeId);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The spine. Walk legs are dashed because they are not a vehicle;
          // that difference should be readable without reading.
          SizedBox(
            width: 28.r,
            child: Column(
              children: [
                SizedBox(height: Insets.xs),
                Container(
                  width: 10.r,
                  height: 10.r,
                  decoration: BoxDecoration(
                    color: leg.isWalk ? p.bg : color,
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: 2),
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 2.r,
                    margin: EdgeInsets.symmetric(vertical: Insets.xs),
                    color: leg.isWalk ? p.line : color.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: Insets.sm),
          Expanded(
            child: Padding(
              padding: EdgeInsetsDirectional.only(bottom: Insets.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // A Wrap, not a Row with a Spacer. The badge's own label
                  // scales with the reader's font size — "ميكروباص" at 200%
                  // is most of a small phone's width — and a Row pushes the
                  // departure time off the edge rather than moving it down.
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    alignment: WrapAlignment.spaceBetween,
                    spacing: Insets.sm,
                    runSpacing: Insets.xs,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: Insets.sm,
                        runSpacing: Insets.xs,
                        children: [
                          ModeBadge(leg.badge),
                          // Only drawn when the route genuinely has a number.
                          // Hundreds of microbus routes are named literally
                          // "Microbus"; an empty badge would read as missing
                          // data, and a filled one as a line called Microbus.
                          if (leg.showNumberBadge)
                            Container(
                              padding: EdgeInsetsDirectional.symmetric(
                                horizontal: Insets.sm,
                                vertical: 2.h,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(color: p.line),
                                borderRadius: BorderRadius.circular(6.r),
                              ),
                              child: Text(
                                leg.numberBadgeText!,
                                textDirection: TextDirection.ltr,
                                style: dataStyle(
                                  context,
                                  size: 12.sp,
                                  color: p.ink2,
                                ),
                              ),
                            ),
                        ],
                      ),
                      Text(
                        clockTime(leg.startTime),
                        style: dataStyle(context, size: 13.sp, color: p.ink2),
                      ),
                    ],
                  ),
                  SizedBox(height: Insets.sm),
                  Text(
                    leg.isWalk
                        ? l.walkTo(bidiIsolate(leg.toName))
                        : l.boardHere(leg.badge.label),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  SizedBox(height: Insets.xs),
                  if (!leg.isWalk) ...[
                    Text(
                      bidiIsolate(leg.routeLabel),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    SizedBox(height: Insets.xs),
                    Text(
                      '${l.stopsCount(leg.intermediateStops)}  ·  '
                      '${l.durationMinutes(leg.durationMinutes)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    SizedBox(height: Insets.xs),
                    Text(
                      '${l.alightHere} — ${bidiIsolate(leg.toName)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ] else
                    Text(
                      l.walkLeg(leg.durationMinutes, leg.distanceM),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
