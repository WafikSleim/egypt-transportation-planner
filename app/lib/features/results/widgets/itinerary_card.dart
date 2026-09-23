import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/presentation/view_models.dart';
import '../../../core/text/formatting.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/mode_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/mode_badge.dart';
import '../../../l10n/generated/app_localizations.dart';

/// One itinerary, summarised.
///
/// Everything drawn here came off a [ItineraryVm]. No field of the wire
/// model is read, so there is no rule for this widget to get wrong — the
/// badges already know their shape, and a walk-only itinerary never reaches
/// a card at all.
class ItineraryCard extends StatelessWidget {
  const ItineraryCard({super.key, required this.itinerary, this.onTap});

  final ItineraryVm itinerary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final p = context.colors;

    // One node, announced as a button. Unmerged, a screen reader stopped
    // eight times on one card — "45 minutes", "08:00 – 08:45", "Metro", "M1",
    // "Microbus", "one change", "700 metres walk" — which is not a summary of
    // anything. Merged, it is the sentence a sighted reader takes off the
    // card at a glance.
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: Material(
          color: p.surface,
          borderRadius: BorderRadius.circular(Radii.card),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(Radii.card),
            child: Container(
              padding: EdgeInsetsDirectional.all(Insets.lg),
              decoration: BoxDecoration(
                border: Border.all(color: p.line),
                borderRadius: BorderRadius.circular(Radii.card),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // A Wrap, not a Row with a Spacer. At 200% text the duration
                  // and the clock range cannot share a line on a small phone, and
                  // a Row clips the one on the end rather than moving it.
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    alignment: WrapAlignment.spaceBetween,
                    spacing: Insets.md,
                    runSpacing: Insets.xs,
                    children: [
                      // The one figure that decides which trip to take, so it
                      // gets the display treatment and nothing else on the card
                      // competes with it.
                      Text(
                        l.durationMinutes(itinerary.durationMinutes),
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                      ),
                      Text(
                        '${clockTime(itinerary.startTime)} – ${clockTime(itinerary.endTime)}',
                        textDirection: TextDirection.ltr,
                        style: dataStyle(context, size: 13.sp, color: p.ink2),
                      ),
                    ],
                  ),
                  SizedBox(height: Insets.md),
                  Wrap(
                    spacing: Insets.sm,
                    runSpacing: Insets.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (
                        var i = 0;
                        i < itinerary.transitBadges.length;
                        i++
                      ) ...[
                        // `arrow_forward_rounded`, not `arrow_back_rounded`. Both
                        // carry `matchTextDirection: true`, so both are mirrored
                        // in Arabic — which means `back` pointed against the flow
                        // in *both* locales: left in English, right in Arabic.
                        if (i > 0)
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 13.r,
                            color: p.ink3,
                          ),
                        ModeBadge(itinerary.transitBadges[i]),
                      ],
                    ],
                  ),
                  SizedBox(height: Insets.md),
                  // One Text rather than three in a Row: the separator is
                  // punctuation inside a sentence, not a third item. A Row of
                  // three unbounded Texts clips at 200%, and a screen reader read
                  // the middle one aloud as "dot".
                  Text(
                    '${l.transfersCount(itinerary.transfers)}'
                    '  ·  '
                    '${l.walkTotal(itinerary.walkDistanceM)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  // No fare. Not omitted for space — the fares in the source feed
                  // are from 2018, and the API does not even request the fields.
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
