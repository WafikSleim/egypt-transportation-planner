import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/notifications/notification_kind.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/tracking/tracked_trip.dart';
import '../../../core/tracking/tracking_source.dart';
import '../../../core/tracking/trip_tracker.dart';

enum TrackingPhase {
  /// Nothing is running: no subscription, no notice, no GPS.
  idle,

  /// Between the tap and the first fix being possible - permission, notice.
  starting,

  /// A subscription is open and the notice is on screen.
  active,

  /// The last ride finished and following stopped itself. Nothing is running.
  arrived,
}

/// Why following would not start.
enum TrackingFailure {
  /// No notice can be shown, so no GPS may run. This is the rule that makes
  /// the persistent notification a guarantee rather than a courtesy.
  notificationsOff,
  locationDenied,
  locationDeniedForever,
  locationOff,
  unavailable,
}

class TrackingState extends Equatable {
  const TrackingState({
    this.phase = TrackingPhase.idle,
    this.tripKey,
    this.estimate = const Searching(),
    this.failure,
  });

  final TrackingPhase phase;

  /// Which itinerary is being followed, so only its screen shows the live
  /// panel.
  final String? tripKey;

  final TrackingEstimate estimate;

  final TrackingFailure? failure;

  bool get isRunning =>
      phase == TrackingPhase.starting || phase == TrackingPhase.active;

  @override
  List<Object?> get props => [phase, tripKey, estimate, failure];
}

/// ViewModel for following a trip (#24) and its stop alert (#25).
///
/// **Owned app-wide**, provided in `main.dart` rather than per screen: one
/// subscription at a time, and the "stop" button on the notification has to
/// work from wherever the passenger has navigated to.
///
/// ### What this class is careful about
///
/// - **Explicit start only.** [start] is called from a button; nothing else
///   can begin a session.
/// - **No notice, no GPS.** The order is: location permission, then the
///   tracking notice, then the subscription - and a notice that was not
///   shown (notifications refused) ends the attempt. Android runs a
///   foreground service with a refused notification invisibly, which would be
///   exactly the silent tracking the notice exists to rule out.
/// - **Nothing leaves the phone.** This class is given a location source and
///   a notifier. It is not given a repository or an HTTP client, so a fix
///   cannot be sent anywhere from here, and `test/tracking_test.dart` checks
///   that nothing in `core/tracking/` or this directory imports one. Fixes
///   are compared with a stop and dropped; the track is not stored, not
///   logged, not kept for the next session.
/// - **Stopping removes the notice.** Whether the passenger stops it, the
///   notice's own button does, or the trip ends.
class TrackingCubit extends Cubit<TrackingState> {
  TrackingCubit({
    required TrackingLocationSource source,
    required NotificationService notifications,
    DateTime Function()? now,
    Duration tick = const Duration(seconds: 30),
  }) : _source = source,
       _notifications = notifications,
       _now = now ?? DateTime.now,
       _tick = tick,
       super(const TrackingState()) {
    // The stop button on the ongoing notice. `NotificationService` hands this
    // to the feature that owns the GPS subscription rather than handling it,
    // because releasing the subscription is this class's business.
    _actions = _notifications.actions.listen((action) {
      if (action.kind == NotificationKind.tripInProgress &&
          action.actionId == NotificationService.stopTripActionId) {
        unawaited(stop());
      }
    });
  }

  final TrackingLocationSource _source;
  final NotificationService _notifications;
  final DateTime Function() _now;
  final Duration _tick;

  late final StreamSubscription<NotificationAction> _actions;
  StreamSubscription<LocationFix>? _fixes;
  Timer? _timer;
  String? _sessionKey;
  TripInProgressNotice? _notice;

  /// Whether the OS keeps delivering fixes with the app out of sight. The
  /// disclosure reads this, because "tracking works with the screen off" is
  /// not true on iOS here.
  bool get continuesInBackground => _source.continuesInBackground;

  /// Begins following [trip]. Call only from an explicit tap, after the
  /// disclosure has been shown and agreed to.
  Future<void> start(TrackedTrip trip, {required String tripKey}) async {
    if (state.isRunning) return;
    emit(TrackingState(phase: TrackingPhase.starting, tripKey: tripKey));

    final access = await _source.requestAccess();
    // Stopped, or closed, while the OS prompt was up.
    if (isClosed || state.phase != TrackingPhase.starting) return;
    final denied = switch (access) {
      TrackingAccess.granted => null,
      TrackingAccess.denied => TrackingFailure.locationDenied,
      TrackingAccess.deniedForever => TrackingFailure.locationDeniedForever,
      TrackingAccess.serviceOff => TrackingFailure.locationOff,
      TrackingAccess.unavailable => TrackingFailure.unavailable,
    };
    if (denied != null) {
      emit(TrackingState(tripKey: tripKey, failure: denied));
      return;
    }

    final notice = TripInProgressNotice(tripLabel: trip.label);
    final shown = await _notifications.post(notice);
    if (isClosed || state.phase != TrackingPhase.starting) {
      if (shown) await _notifications.cancel(notice);
      return;
    }
    if (!shown) {
      emit(
        TrackingState(
          tripKey: tripKey,
          failure: TrackingFailure.notificationsOff,
        ),
      );
      return;
    }

    _notice = notice;
    // Minted per session and used for nothing but "has this trip been asked
    // about". Not derived from the route, the places or any position.
    _sessionKey = '${_now().microsecondsSinceEpoch}';
    final tracker = TripTracker(trip);

    _fixes = _source.fixes().listen(
      (fix) => _apply(tracker.onFix(fix)),
      onError: (Object _) => _apply(tracker.onSignalLost()),
    );
    _timer = Timer.periodic(_tick, (_) => _apply(tracker.onTick(_now())));

    emit(TrackingState(phase: TrackingPhase.active, tripKey: tripKey));
  }

  void _apply(TrackerUpdate update) {
    if (isClosed || state.phase != TrackingPhase.active) return;

    final alert = update.alertFor;
    if (alert != null) {
      // Through the same gate as everything else, so a passenger who switched
      // the alert off gets none. Not awaited: the estimate on screen should
      // not wait on a notification.
      unawaited(_notifications.post(NextStopAlert(stopName: alert.alightName)));
    }

    if (update.finished) {
      unawaited(_finish());
      return;
    }

    if (update.estimate != state.estimate) {
      emit(
        TrackingState(
          phase: TrackingPhase.active,
          tripKey: state.tripKey,
          estimate: update.estimate,
        ),
      );
    }
  }

  /// The last ride is over: stop following, then ask the one question.
  Future<void> _finish() async {
    final key = _sessionKey;
    final tripKey = state.tripKey;
    await _release();
    if (isClosed) return;
    emit(
      TrackingState(
        phase: TrackingPhase.arrived,
        tripKey: tripKey,
        estimate: const TripDone(),
      ),
    );
    // After the notice is gone, so the question is not the thing on screen
    // beside a GPS notice. `post` spends the one question for this session.
    if (key != null) {
      await _notifications.post(PostTripQuestion(sessionKey: key));
    }
  }

  /// Stops following and takes the notice down. Safe to call at any time,
  /// including when nothing is running. Asks nothing: a passenger who stopped
  /// the trip themselves is not then questioned about it.
  Future<void> stop() async {
    if (!state.isRunning) return;
    await _release();
    if (isClosed) return;
    emit(const TrackingState());
  }

  Future<void> _release() async {
    await _fixes?.cancel();
    _fixes = null;
    _timer?.cancel();
    _timer = null;
    final notice = _notice;
    _notice = null;
    if (notice != null) await _notifications.cancel(notice);
  }

  @override
  Future<void> close() async {
    await _actions.cancel();
    await _release();
    return super.close();
  }
}
