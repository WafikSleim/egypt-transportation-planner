import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/location/location_service.dart';
import '../../../core/notifications/notification_permission_prompt.dart';
import '../../../core/text/bidi.dart';
import '../../../core/text/formatting.dart';
import '../../../core/theme/mode_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/tracking/tracked_trip.dart';
import '../../../core/tracking/trip_tracker.dart';
import '../../../core/widgets/honesty_panel.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../view_model/tracking_cubit.dart';

/// "تابع الرحلة" (#24), and what following says while it runs (#25).
///
/// Everything on this panel is written to the rules in the issue: it starts
/// only from a tap, it says GPS and battery in the moment it is switched on,
/// it says the position stays on the phone, and it never says when a vehicle
/// will arrive - there is nothing in the app that could back such a sentence.
class TrackingSection extends StatelessWidget {
  const TrackingSection({super.key, required this.tripKey, required this.trip});

  final String tripKey;
  final TrackedTrip trip;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return BlocBuilder<TrackingCubit, TrackingState>(
      builder: (context, state) {
        final mine = state.tripKey == tripKey;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.trackingStart,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SizedBox(height: Insets.sm),
            if (mine && state.isRunning)
              _Running(state: state)
            else if (mine && state.phase == TrackingPhase.arrived)
              HonestyPanel(
                icon: Icons.check_circle_outline,
                text: l.trackingArrived,
              )
            else if (state.isRunning)
              // One session at a time, and the other one's notice is already
              // on screen. Offering a second start here would either replace
              // it silently or run two subscriptions.
              Text(
                l.trackingOtherTrip,
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else ...[
              Text(
                l.trackingIntro,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              SizedBox(height: Insets.md),
              FilledButton.icon(
                icon: const Icon(Icons.my_location_outlined),
                label: Text(l.trackingStart),
                onPressed: () => _begin(context),
              ),
              if (mine && state.failure != null) ...[
                SizedBox(height: Insets.sm),
                _Failure(failure: state.failure!),
              ],
            ],
          ],
        );
      },
    );
  }

  Future<void> _begin(BuildContext context) async {
    final cubit = context.read<TrackingCubit>();

    // The disclosure is the moment of switching on: GPS, battery, nothing
    // leaves the phone. Asked every time, not once - it is cheap, and this is
    // the one control in the app that can use the battery for an hour.
    final agreed = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _Disclosure(continuesInBackground: cubit.continuesInBackground),
    );
    if (agreed != true || !context.mounted) return;

    // The tracking notice cannot be silenced and is what makes the GPS
    // visible, so notifications are asked for here, in context, and a refusal
    // ends the attempt in `start`.
    await askToNotify(context);
    await cubit.start(trip, tripKey: tripKey);
  }
}

class _Disclosure extends StatelessWidget {
  const _Disclosure({required this.continuesInBackground});

  final bool continuesInBackground;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final lines = [
      l.trackingDisclosureGps,
      l.trackingDisclosureOnDevice,
      l.trackingDisclosureNotLive,
      l.trackingDisclosureStop,
      if (!continuesInBackground) l.trackingDisclosureIosForeground,
    ];

    return AlertDialog(
      title: Text(l.trackingDisclosureTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in lines)
              Padding(
                padding: EdgeInsetsDirectional.only(bottom: Insets.md),
                child: Text(line),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l.notNow),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l.trackingDisclosureStart),
        ),
      ],
    );
  }
}

class _Running extends StatelessWidget {
  const _Running({required this.state});

  final TrackingState state;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final estimate = state.estimate;
    final unsure = estimate is Unsure;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A live region, so a screen reader announces "not sure" when the
        // estimate degrades rather than leaving the old sentence standing.
        Semantics(
          liveRegion: true,
          child: HonestyPanel(
            severity: unsure
                ? HonestySeverity.warning
                : HonestySeverity.neutral,
            icon: unsure ? Icons.help_outline : Icons.my_location_outlined,
            text: _text(l, estimate),
          ),
        ),
        SizedBox(height: Insets.sm),
        // Always, whatever the estimate: where this number comes from.
        Text(l.trackingBasis, style: Theme.of(context).textTheme.bodySmall),
        SizedBox(height: Insets.md),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(A11y.minTapTarget),
          ),
          icon: const Icon(Icons.stop_circle_outlined, size: 18),
          label: Text(l.notificationsStopTrip),
          onPressed: context.read<TrackingCubit>().stop,
        ),
      ],
    );
  }

  String _text(AppLocalizations l, TrackingEstimate e) => switch (e) {
    Searching() => l.trackingSearching,
    Unsure(:final reason) => switch (reason) {
      UnsureReason.poorFix => l.trackingUnsurePoorFix,
      UnsureReason.offRoute => l.trackingUnsureOffRoute,
      UnsureReason.noSignal => l.trackingUnsureNoSignal,
    },
    OnRoute(:final alightName, :final distanceM) =>
      isKilometres(distanceM)
          ? l.trackingOnRouteKm(bidiIsolate(alightName), distance(distanceM))
          : l.trackingOnRouteM(bidiIsolate(alightName), distanceM),
    NearAlight(:final alightName) => l.trackingNear(bidiIsolate(alightName)),
    TripDone() => l.trackingArrived,
  };
}

class _Failure extends StatelessWidget {
  const _Failure({required this.failure});

  final TrackingFailure failure;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = switch (failure) {
      TrackingFailure.notificationsOff => l.trackingFailNotifications,
      TrackingFailure.locationDenied => l.trackingFailDenied,
      TrackingFailure.locationDeniedForever => l.trackingFailDeniedForever,
      TrackingFailure.locationOff => l.trackingFailOff,
      TrackingFailure.unavailable => l.trackingFailUnavailable,
    };
    final settings =
        failure == TrackingFailure.locationDeniedForever ||
        failure == TrackingFailure.locationOff;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: context.colors.ink),
        ),
        if (settings)
          TextButton(
            onPressed: context.read<LocationService>().openSettings,
            child: Text(l.openSettings),
          ),
      ],
    );
  }
}
