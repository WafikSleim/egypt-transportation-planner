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

    return Material(
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  // The one figure that decides which trip to take, so it
                  // gets the display treatment and nothing else on the card
                  // competes with it.
                  Text(
                    l.durationMinutes(itinerary.durationMinutes),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                  ),
                  const Spacer(),
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
                  for (var i = 0; i < itinerary.transitBadges.length; i++) ...[
                    if (i > 0)
                      Icon(Icons.arrow_back_rounded, size: 13.r, color: p.ink3),
                    ModeBadge(itinerary.transitBadges[i]),
                  ],
                ],
              ),
              SizedBox(height: Insets.md),
              Row(
                children: [
                  Text(l.transfersCount(itinerary.transfers),
                      style: Theme.of(context).textTheme.bodySmall),
                  Text('  ·  ', style: Theme.of(context).textTheme.bodySmall),
                  Text(l.walkTotal(itinerary.walkDistanceM),
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
              // No fare. Not omitted for space — the fares in the source feed
              // are from 2018, and the API does not even request the fields.
            ],
          ),
        ),
      ),
    );
  }
}
