import 'dart:ui' show Locale;

import '../../l10n/generated/app_localizations.dart';
import '../text/formatting.dart';
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
/// **Resolved when the notification is posted**, and from the language the
/// passenger has chosen rather than the phone's. That is the same trap as
/// `lang` on API requests. One honest limit: a *scheduled* reminder is
/// resolved when it is scheduled, because the OS is handed the finished words
/// then - a reminder set in Arabic and fired after a switch to English still
/// speaks Arabic. Everything shown immediately uses the language of the
/// moment.
class AppNotificationCopy implements NotificationCopy {
  const AppNotificationCopy(this._l);

  factory AppNotificationCopy.forLocale(Locale locale) =>
      AppNotificationCopy(lookupAppLocalizations(locale));

  final AppLocalizations _l;

  @override
  NotificationText forRequest(NotificationRequest request) => switch (request) {
    // Each sentence carries the honesty its feature owes: #22 says the time
    // is an estimate off a recorded schedule, #24's notice says GPS, battery
    // and that nothing leaves the phone, #25 says the estimate comes from the
    // passenger's own GPS, and #23 asks kindly and promises not to ask again.
    DepartureReminder(:final tripLabel, :final departureTime) =>
      NotificationText(
        title: _l.notifyDepartureTitle,
        body: _l.notifyDepartureBody(tripLabel, clockTime(departureTime)),
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
