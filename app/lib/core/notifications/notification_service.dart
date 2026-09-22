import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import 'notification_copy.dart';
import 'notification_kind.dart';
import 'notification_preferences.dart';

/// Whether the OS will let this app show anything at all.
///
/// Explicit about the ways it fails, like `LocationResult` next door, because
/// each one leads to different advice: a plain refusal can be asked again in
/// the app, a permanent one only from system settings, and a platform that
/// has no notion of the permission at all needs neither.
sealed class NotificationPermission extends Equatable {
  const NotificationPermission();

  bool get isAllowed => this is NotificationsAllowed;

  @override
  List<Object?> get props => const [];
}

class NotificationsAllowed extends NotificationPermission {
  const NotificationsAllowed();
}

/// The passenger said no, or has not been asked.
///
/// [permanently] means the OS will not show the prompt again — Android 13+
/// after two refusals — so the only route left is the system settings screen.
class NotificationsDenied extends NotificationPermission {
  const NotificationsDenied({required this.permanently});

  final bool permanently;

  @override
  List<Object?> get props => [permanently];
}

class NotificationsUnavailable extends NotificationPermission {
  const NotificationsUnavailable([this.detail]);

  final String? detail;

  @override
  List<Object?> get props => [detail];
}

/// The only way this app can put a notification on a phone.
///
/// ### Why this is a base class and not an interface
///
/// `LocationService` next door is a bare `abstract class`, and a notifier
/// could have been too. It is not, because two rules have to hold for every
/// notification this app ever shows, and both of them are the kind of rule
/// that is obeyed four times and forgotten the fifth:
///
/// - nothing is shown for a kind the passenger has switched off;
/// - the action that switches a kind off works, without the feature that
///   scheduled it implementing anything.
///
/// So [post] and [handleResponse] are written once, here, and the platform
/// gets only [deliver] and [retract] to fill in. `implements` is blocked by
/// `base`; a subclass could still override [post], and the test suite holds
/// that neither the real implementation nor the fake does.
abstract base class NotificationService {
  NotificationService({
    required NotificationPreferences preferences,
    required NotificationCopy Function() copy,
  }) : _preferences = preferences,
       _copy = copy;

  /// The action id carried by the opt-out button on every silenceable
  /// notification. Handled here; features never see it.
  static const silenceActionId = 'silence';

  /// The action id on the ongoing tracking notice. Handled by #24, because
  /// stopping a trip means releasing a GPS subscription, which is that
  /// feature's business and not this layer's.
  static const stopTripActionId = 'stop_trip';

  final NotificationPreferences _preferences;
  final NotificationCopy Function() _copy;

  final _actions = StreamController<NotificationAction>.broadcast();

  /// Taps and buttons, for whichever feature owns that kind.
  Stream<NotificationAction> get actions => _actions.stream;

  NotificationPreferences get preferences => _preferences;

  /// The localisations as they are *now*. Resolved per notification rather
  /// than captured once, so a reminder scheduled in Arabic and fired after a
  /// switch to English speaks English.
  @protected
  NotificationCopy get copyNow => _copy();

  /// The current state, without prompting. Used to decide whether this app's
  /// own explanation is a courtesy or an interruption.
  Future<NotificationPermission> permission();

  /// Asks the OS. Android 13+ shows the runtime prompt; iOS shows the
  /// authorisation alert; below Android 13 there is nothing to ask and this
  /// answers [NotificationsAllowed].
  Future<NotificationPermission> request();

  /// The app's notification settings page, for the permanently-denied case.
  Future<void> openSettings();

  /// Show or schedule [request]. The single entry point.
  ///
  /// Returns false when nothing was shown, which is not an error: a kind that
  /// is switched off and a permission that was refused both land here, and
  /// both are the passenger's decision rather than a failure.
  Future<bool> post(NotificationRequest request) async {
    if (!_preferences.isAllowed(request.kind)) return false;
    if (!(await permission()).isAllowed) return false;

    final at = request.showAt;
    // A reminder for a departure that has already gone is not worth waking
    // somebody for, and on Android a past schedule fires immediately.
    if (at != null && !at.isAfter(DateTime.now())) return false;

    final words = copyNow;
    await deliver(
      request,
      words.forRequest(request),
      silenceLabel: words.silenceAction(request.kind),
    );
    return true;
  }

  /// Take a notification back — the trip was cancelled, the reminder is no
  /// longer wanted, the tracking session ended.
  Future<void> cancel(NotificationRequest request) => retract(request.id);

  /// Called by the platform when the passenger touches a notification.
  ///
  /// The opt-out is applied here rather than routed to a feature, so it works
  /// the same for all four kinds and cannot be forgotten by any of them.
  @protected
  @visibleForTesting
  Future<void> handleResponse(
    NotificationKind kind, {
    required int slot,
    String? actionId,
  }) async {
    if (actionId == silenceActionId && kind.canBeSilenced) {
      await _preferences.setAllowed(kind, allowed: false);
      await retract(kind.index * 1000 + slot);
      return;
    }
    _actions.add(
      NotificationAction(kind: kind, slot: slot, actionId: actionId),
    );
  }

  /// Put it on the phone. The only thing a platform implementation decides.
  @protected
  Future<void> deliver(
    NotificationRequest request,
    NotificationText text, {
    required String silenceLabel,
  });

  @protected
  Future<void> retract(int id);

  @mustCallSuper
  Future<void> dispose() => _actions.close();
}
