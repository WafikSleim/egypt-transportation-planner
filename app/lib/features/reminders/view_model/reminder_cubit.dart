import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/notifications/notification_kind.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../data/repositories/reminder_ledger.dart';

/// The trip a reminder would be about.
///
/// Three facts and a label, assembled by the screen from the itinerary it is
/// showing. Nothing here is a coordinate, because the notification layer is
/// never told where anyone is going beyond the label they already saw.
class ReminderTarget extends Equatable {
  const ReminderTarget({
    required this.tripKey,
    required this.tripLabel,
    required this.departureAt,
    required this.isFromCache,
  });

  final String tripKey;
  final String tripLabel;

  /// The estimated departure, off a recorded schedule.
  final DateTime departureAt;

  /// A saved answer, not a fresh one. Its times were worked out on another
  /// day, so a reminder built on them would fire for a departure that is not
  /// real - see [canOffer].
  final bool isFromCache;

  @override
  List<Object?> get props => [tripKey, tripLabel, departureAt, isFromCache];
}

/// Why the last attempt ended as it did. The screen writes the sentence.
enum ReminderOutcome {
  /// Nothing attempted yet.
  none,

  /// Set. Look at [ReminderState.reminder].
  set,

  /// Cancelled by the passenger.
  cancelled,

  /// The reminder time has already gone, so there is nothing to wait for.
  timePassed,

  /// The OS would not show it: notifications are refused for the app.
  notificationsOff,

  /// [ReminderLedger.maxPending] are already waiting.
  tooMany,
}

class ReminderState extends Equatable {
  const ReminderState({
    required this.reminder,
    required this.lead,
    this.outcome = ReminderOutcome.none,
  });

  /// The reminder pending for this trip, or null.
  final PlannedReminder? reminder;

  /// The lead time the picker starts on: the last one chosen.
  final int lead;

  final ReminderOutcome outcome;

  @override
  List<Object?> get props => [reminder, lead, outcome];
}

/// ViewModel for "remind me before this trip" (#22).
///
/// Everything goes through [NotificationService.post] and `cancel`, so the
/// switches, the permission and the opt-out apply here exactly as they do to
/// every other notification - this class decides *when* and *whether to
/// offer*, never whether to show.
class ReminderCubit extends Cubit<ReminderState> {
  ReminderCubit({
    required NotificationService notifications,
    required ReminderLedger ledger,
    required this.target,
    DateTime Function()? now,
  }) : _notifications = notifications,
       _ledger = ledger,
       _now = now ?? DateTime.now,
       super(
         ReminderState(
           reminder: ledger.forTrip(target.tripKey),
           lead: ledger.lastLead,
         ),
       );

  final NotificationService _notifications;
  final ReminderLedger _ledger;
  final DateTime Function() _now;
  final ReminderTarget target;

  /// A saved answer is never offered a reminder. Its departure times are
  /// from whenever it was last fetched, so the reminder would be a plausible
  /// lie: a notification, on time, for a bus that left yesterday.
  bool get canOffer => !target.isFromCache;

  /// Whether a reminder at [leadMinutes] would still be in the future.
  bool leadFits(int leadMinutes) => _remindAt(leadMinutes).isAfter(_now());

  DateTime _remindAt(int leadMinutes) =>
      target.departureAt.subtract(Duration(minutes: leadMinutes));

  /// Call after notification permission has been asked for, never before -
  /// see `askToNotify`.
  Future<void> set(int leadMinutes) async {
    if (!canOffer) return;

    final now = _now();
    final remindAt = _remindAt(leadMinutes);
    if (!remindAt.isAfter(now)) {
      emit(_with(ReminderOutcome.timePassed, lead: leadMinutes));
      return;
    }

    final existing = _ledger.forTrip(target.tripKey, now: now);
    final slot = existing?.slot ?? _ledger.freeSlot(now: now);
    if (slot == null) {
      emit(_with(ReminderOutcome.tooMany, lead: leadMinutes));
      return;
    }

    // Asking for a reminder is consent to reminders. If this kind was
    // switched off earlier, from a notification or from About, the passenger
    // has just told us the opposite - and a button that silently does nothing
    // because of a switch they flipped last month is worse than a switch that
    // follows their latest word.
    if (!_notifications.preferences.isAllowed(
      NotificationKind.departureReminder,
    )) {
      await _notifications.setAllowed(
        NotificationKind.departureReminder,
        allowed: true,
      );
    }

    final reminder = DepartureReminder(
      at: remindAt,
      departureTime: target.departureAt,
      tripLabel: target.tripLabel,
      slot: slot,
    );
    final shown = await _notifications.post(reminder);
    if (isClosed) return;
    if (!shown) {
      emit(_with(ReminderOutcome.notificationsOff, lead: leadMinutes));
      return;
    }

    final planned = PlannedReminder(
      slot: slot,
      tripKey: target.tripKey,
      tripLabel: target.tripLabel,
      departureAt: target.departureAt,
      remindAt: remindAt,
      leadMinutes: leadMinutes,
    );
    await _ledger.put(planned, now: now);
    await _ledger.rememberLead(leadMinutes);
    if (isClosed) return;
    emit(
      ReminderState(
        reminder: planned,
        lead: leadMinutes,
        outcome: ReminderOutcome.set,
      ),
    );
  }

  /// Take this trip's reminder back. The OS is told first, so a failure to
  /// write the ledger leaves a stale line on screen rather than a reminder
  /// that still fires after the passenger cancelled it.
  Future<void> cancel() async {
    final reminder = state.reminder;
    if (reminder == null) return;

    await _notifications.cancel(
      DepartureReminder(
        at: reminder.remindAt,
        departureTime: reminder.departureAt,
        tripLabel: reminder.tripLabel,
        slot: reminder.slot,
      ),
    );
    await _ledger.remove(target.tripKey);
    if (isClosed) return;
    emit(
      ReminderState(
        reminder: null,
        lead: state.lead,
        outcome: ReminderOutcome.cancelled,
      ),
    );
  }

  ReminderState _with(ReminderOutcome outcome, {required int lead}) =>
      ReminderState(reminder: state.reminder, lead: lead, outcome: outcome);
}
