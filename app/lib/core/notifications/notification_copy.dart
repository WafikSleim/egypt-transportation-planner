import 'dart:ui' show Locale;

import '../../l10n/generated/app_localizations.dart';
import 'notification_kind.dart';

/// The words on a notification.
class NotificationText {
  const NotificationText({required this.title, required this.body});

  final String title;
  final String body;
}

/// Turns a [NotificationRequest] into the words shown, and nothing else can.
///
/// This is the third leg of "no fourth kind by construction". A request
/// carries a trip label or a stop name; the sentence around it is chosen
/// here, from the app's own localisations, by an exhaustive switch over the
/// closed set. There is no `show(title, body)` anywhere in this layer, so
/// there is no call site that can put arbitrary words on a phone.
abstract class NotificationCopy {
  NotificationText forRequest(NotificationRequest request);

  /// The label of the action that switches this kind off, drawn on the
  /// notification itself.
  String silenceAction(NotificationKind kind);

  /// What Android calls this kind in the phone's own notification settings.
  /// One channel per kind, so the OS switch and the in-app switch say the
  /// same thing.
  String channelName(NotificationKind kind);
}

/// The one implementation, over the app's own strings.
///
/// **Resolved when the notification is posted, not when it is scheduled**,
/// and from the language the passenger has chosen rather than the phone's.
/// This is the same trap as `lang` on API requests: a reminder scheduled in
/// Arabic and fired after a switch to English would be the one screen in the
/// app speaking the wrong language, and it would look like a working app.
class AppNotificationCopy implements NotificationCopy {
  const AppNotificationCopy(this._l);

  factory AppNotificationCopy.forLocale(Locale locale) =>
      AppNotificationCopy(lookupAppLocalizations(locale));

  final AppLocalizations _l;

  @override
  NotificationText forRequest(NotificationRequest request) => switch (request) {
    // The wording of the three messages belongs to the issues that build
    // them — #22 has to say plainly that a departure time is an estimate off
    // a recorded schedule, and #23 has to ask its one question kindly rather
    // than demand a rating. What is here is a placeholder honest enough to
    // ship behind a feature that does not exist yet.
    DepartureReminder(:final tripLabel) => NotificationText(
      title: _l.notifyDepartureTitle,
      body: _l.notifyDepartureBody(tripLabel),
    ),
    TripInProgressNotice(:final tripLabel) => NotificationText(
      title: _l.notifyTrackingTitle,
      body: _l.notifyTrackingBody(tripLabel),
    ),
    NextStopAlert(:final stopName) => NotificationText(
      title: _l.notifyNextStopTitle,
      body: _l.notifyNextStopBody(stopName),
    ),
    PostTripQuestion() => NotificationText(
      title: _l.notifyPostTripTitle,
      body: _l.notifyPostTripBody,
    ),
  };

  @override
  String silenceAction(NotificationKind kind) =>
      kind.canBeSilenced ? _l.notificationsSilence : _l.notificationsStopTrip;

  @override
  String channelName(NotificationKind kind) => switch (kind) {
    NotificationKind.departureReminder => _l.notifyDepartureReminder,
    NotificationKind.tripInProgress => _l.notifyTripInProgress,
    NotificationKind.nextStopAlert => _l.notifyNextStopAlert,
    NotificationKind.postTripQuestion => _l.notifyPostTripQuestion,
  };
}
