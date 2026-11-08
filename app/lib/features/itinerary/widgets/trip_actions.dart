import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/notifications/notification_service.dart';
import '../../../core/notifications/notifications_cubit.dart';
import '../../../core/presentation/view_models.dart';
import '../../../core/text/bidi.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/tracking/tracked_trip.dart';
import '../../../data/repositories/reminder_ledger.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../reminders/view/reminder_section.dart';
import '../../tracking/view/tracking_section.dart';
import '../../reminders/view_model/reminder_cubit.dart';

/// What a passenger can ask of this trip beyond reading it: be reminded before
/// it, and follow it with GPS while riding (#24, #25).
///
/// Passed to `ItineraryPage` as a widget rather than built inside it. The
/// detail screen is a pure function of a view model - it is what the goldens
/// and the accessibility pass photograph - and these actions need services
/// the screen has no reason to know about.
class TripActions extends StatelessWidget {
  const TripActions({super.key, required this.itinerary});

  final ItineraryVm itinerary;

  /// Identifies this itinerary across screens and restarts, so reopening it
  /// finds the reminder that was set on it.
  static String keyFor(ItineraryVm itinerary) =>
      '${itinerary.startTime.toIso8601String()}|'
      '${itinerary.legs.first.fromName}|${itinerary.legs.last.toName}';

  /// "المنيب ← رمسيس" - the trip as the passenger read it, and all the
  /// notification layer is ever told about it.
  static String labelFor(AppLocalizations l, ItineraryVm itinerary) =>
      l.tripArrow(
        bidiIsolate(itinerary.legs.first.fromName),
        bidiIsolate(itinerary.legs.last.toName),
      );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (itinerary.legs.isEmpty) return const SizedBox.shrink();

    final service = context.read<NotificationService>();
    final tripKey = keyFor(itinerary);
    final label = labelFor(l, itinerary);
    final trackable = TrackedTrip.fromItinerary(itinerary, label);

    return MultiBlocProvider(
      providers: [
        // For the permission explanation, the same way About provides it.
        BlocProvider(create: (_) => NotificationsCubit(service)..refresh()),
        BlocProvider(
          create: (context) => ReminderCubit(
            notifications: service,
            ledger: context.read<ReminderLedger>(),
            target: ReminderTarget(
              tripKey: tripKey,
              tripLabel: label,
              departureAt: itinerary.startTime,
              isFromCache: itinerary.isFromCache,
            ),
          ),
        ),
      ],
      child: Padding(
        padding: EdgeInsetsDirectional.only(top: Insets.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ReminderSection(),
            if (trackable != null) ...[
              SizedBox(height: Insets.xl),
              TrackingSection(tripKey: tripKey, trip: trackable),
            ],
          ],
        ),
      ),
    );
  }
}
