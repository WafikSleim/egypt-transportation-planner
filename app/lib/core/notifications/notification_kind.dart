/// Everything this app is allowed to put on a phone's lock screen.
///
/// ### Why this is an enum and not a string
///
/// Issue #21's hardest acceptance criterion is that no growth,
/// re-engagement or marketing notification is possible **by construction,
/// not by policy**. Three things carry that, and this file is the first two:
///
/// 1. [NotificationKind] is closed. There is no "other", no string channel
///    id crossing the seam, and every `switch` over it is exhaustive — so a
///    fifth kind cannot be introduced without editing this enum, which is a
///    diff a reviewer sees.
/// 2. [NotificationRequest] is sealed and carries **data, not words**. No
///    call site anywhere can hand the notification layer a title and a body;
///    the words are derived from the request in one place
///    (`notification_copy.dart`), the way `TripPresenter` derives everything
///    a widget is allowed to draw.
/// 3. There is no remote push package in `pubspec.yaml` and there never will
///    be. This project has no push server, no accounts and nothing to send
///    — a notification can only be created on the device, by something the
///    passenger started.
///
/// `test/notifications_test.dart` pins the set, so a fifth member arrives as
/// a failing test rather than as a quiet new capability.
library;

import 'package:equatable/equatable.dart';

/// The four notifications that exist. Three of them are messages; the fourth
/// is the ongoing notice that makes trip tracking visible.
enum NotificationKind {
  /// #22 — P-16. "Your trip is soon", at the lead time the passenger chose.
  departureReminder,

  /// #24 — P-17. The persistent notice shown for as long as the passenger is
  /// following a trip. Not a message: it exists so that GPS tracking can
  /// never run without something on screen saying so, and so stopping it is
  /// one tap from wherever they are.
  ///
  /// This is why the enum has four members where the issue text says three.
  tripInProgress,

  /// #25 — P-17. "Get ready to get off", derived from the passenger's own
  /// GPS against the recorded route.
  nextStopAlert,

  /// #23 — P-16. One question after a trip, and never a second one.
  postTripQuestion;

  /// Whether the passenger may switch this kind off and keep using the app.
  ///
  /// [tripInProgress] may not, and that is not a dark pattern in the other
  /// direction: silencing it would let the app hold a GPS subscription with
  /// nothing on screen admitting it. The way to be rid of it is to stop
  /// following the trip, which the notification's own action does.
  bool get canBeSilenced => this != NotificationKind.tripInProgress;

  /// One Android channel per kind, so the OS's own per-channel switch is a
  /// second opt-out that does not depend on this app behaving.
  String get channelId => 'masar.$name';
}

/// A notification this app wants to show, described by what it is about.
///
/// Deliberately no `title` and no `body`. A request carries the trip, the
/// stop or the time; the copy is looked up from it. That is what stops "post
/// a notification" from being a way to say anything at all.
sealed class NotificationRequest extends Equatable {
  const NotificationRequest();

  NotificationKind get kind;

  /// When it should appear. `null` means now.
  ///
  /// Only [DepartureReminder] is ever in the future; everything else is a
  /// response to something happening on the phone at that moment.
  DateTime? get showAt => null;

  /// Distinguishes several live notifications of the same kind — a reminder
  /// for each of two saved trips, say. 0–999.
  int get slot => 0;

  /// The platform id. Derived from the kind rather than chosen by the caller,
  /// so two features cannot collide on a number and cancel each other's
  /// notifications.
  int get id => kind.index * 1000 + slot;

  @override
  List<Object?> get props => [kind, slot, showAt];
}

/// #22. Fires before a planned departure.
///
/// [tripLabel] is the trip as the passenger saved it — "المنيب ← رمسيس" —
/// and is the only thing about the trip the notification layer is told.
final class DepartureReminder extends NotificationRequest {
  const DepartureReminder({
    required this.at,
    required this.tripLabel,
    this.slot = 0,
  });

  final DateTime at;
  final String tripLabel;

  @override
  final int slot;

  @override
  NotificationKind get kind => NotificationKind.departureReminder;

  @override
  DateTime? get showAt => at;

  @override
  List<Object?> get props => [kind, slot, at, tripLabel];
}

/// #24. The ongoing notice, for as long as a trip is being followed.
final class TripInProgressNotice extends NotificationRequest {
  const TripInProgressNotice({required this.tripLabel});

  final String tripLabel;

  @override
  NotificationKind get kind => NotificationKind.tripInProgress;

  @override
  List<Object?> get props => [kind, tripLabel];
}

/// #25. "Get ready to get off."
final class NextStopAlert extends NotificationRequest {
  const NextStopAlert({required this.stopName});

  final String stopName;

  @override
  NotificationKind get kind => NotificationKind.nextStopAlert;

  @override
  List<Object?> get props => [kind, stopName];
}

/// #23. The single post-trip question.
///
/// "At most one unsolicited prompt per trip" is #23's rule to enforce and
/// #23's test to write. This type only says that such a notification exists.
final class PostTripQuestion extends NotificationRequest {
  const PostTripQuestion();

  @override
  NotificationKind get kind => NotificationKind.postTripQuestion;
}

/// Something the passenger did to a notification, handed back to whichever
/// feature owns that kind.
///
/// The silence action never reaches here — it is handled inside
/// `NotificationService` itself, so switching a kind off cannot depend on a
/// feature remembering to implement it.
class NotificationAction extends Equatable {
  const NotificationAction({
    required this.kind,
    required this.slot,
    this.actionId,
  });

  final NotificationKind kind;
  final int slot;

  /// `null` when the passenger simply tapped the notification body.
  final String? actionId;

  @override
  List<Object?> get props => [kind, slot, actionId];
}
