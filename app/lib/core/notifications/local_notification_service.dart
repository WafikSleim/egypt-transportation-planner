import 'dart:async';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../storage/key_value_store.dart';
import 'notification_copy.dart';
import 'notification_kind.dart';
import 'notification_preferences.dart';
import 'notification_service.dart';

/// `flutter_local_notifications`, and nothing else.
///
/// **Local, in the literal sense.** There is no `firebase_messaging` here and
/// no push token anywhere in the project: this app has no server that could
/// send anything, no account to send it to, and a licence that forbids the
/// revenue a growth notification would exist to chase. Everything on this
/// class is a notification the phone creates for itself, from something the
/// passenger started. Adding a remote push package would not be a new
/// feature — it would be the one capability #21 exists to rule out.
final class LocalNotificationService extends NotificationService {
  LocalNotificationService({
    required super.preferences,
    required super.copy,
    FlutterLocalNotificationsPlugin? plugin,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// Call once, after the settings are restored so the channel names and the
  /// iOS action labels come out in the passenger's own language.
  Future<void> initialise() async {
    tz_data.initializeTimeZones();
    // One timezone, named rather than detected. Coverage is Greater Cairo and
    // only Greater Cairo — a trip this app can plan is a trip in Africa/Cairo
    // — so `flutter_timezone`, another native plugin, would be a dependency
    // to learn something already known. What would reverse it: coverage
    // reaching a second timezone, which for Egypt means never, or a phone
    // that plans a Cairo trip from abroad.
    tz.setLocalLocation(tz.getLocation('Africa/Cairo'));

    final words = copyNow;

    await _plugin.initialize(
      settings: InitializationSettings(
        // The launcher icon, which is a monochrome mark by design — Android
        // draws a notification's small icon as a silhouette, so anything with
        // internal colour arrives as a blob.
        android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          // Asked in context later, never at launch. A permission dialog on
          // first run, before the app has done anything, is the one most
          // likely to be refused.
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          notificationCategories: [
            for (final kind in NotificationKind.values)
              DarwinNotificationCategory(
                kind.channelId,
                actions: [
                  DarwinNotificationAction.plain(
                    kind.canBeSilenced
                        ? NotificationService.silenceActionId
                        : NotificationService.stopTripActionId,
                    words.silenceAction(kind),
                  ),
                ],
              ),
          ],
        ),
      ),
      onDidReceiveNotificationResponse: _onResponse,
      // The opt-out has to work when the app is closed, which is when a
      // notification is usually read. An action with no user interface taps
      // through to a *separate* Flutter engine with none of this app's state
      // in it, so it gets its own entry point below rather than this one.
      onDidReceiveBackgroundNotificationResponse:
          notificationBackgroundResponse,
    );

    await _createChannels(words);
  }

  /// One Android channel per kind, so the phone's own settings screen lists
  /// the three messages separately and can switch each off without this app
  /// being involved. That is the opt-out that keeps working even if this app
  /// stops honouring its own.
  Future<void> _createChannels(NotificationCopy words) async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return;

    for (final kind in NotificationKind.values) {
      await android.createNotificationChannel(
        AndroidNotificationChannel(
          kind.channelId,
          words.channelName(kind),
          importance: _importance(kind),
        ),
      );
    }
  }

  @override
  Future<NotificationPermission> permission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      final enabled = await android.areNotificationsEnabled();
      return _verdict(enabled ?? false);
    }

    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      final options = await ios.checkPermissions();
      return _verdict(options?.isEnabled ?? false);
    }

    return const NotificationsUnavailable('no notification support here');
  }

  @override
  Future<NotificationPermission> request() async {
    // Recorded before the answer, not after: the point of the flag is that
    // the prompt has been spent, and it has been spent whichever way the
    // passenger answered.
    await preferences.markAsked();

    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      // Below Android 13 there is no runtime permission and this answers
      // true without showing anything.
      return _verdict(await android.requestNotificationsPermission() ?? false);
    }

    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return _verdict(
        await ios.requestPermissions(alert: true, badge: false, sound: true) ??
            false,
      );
    }

    return const NotificationsUnavailable('no notification support here');
  }

  NotificationPermission _verdict(bool granted) => granted
      ? const NotificationsAllowed()
      : NotificationsDenied(permanently: preferences.hasBeenAsked);

  @override
  Future<void> openSettings() async {
    await _plugin.openAppNotificationSettings();
  }

  @override
  Future<void> deliver(
    NotificationRequest request,
    NotificationText text, {
    required String silenceLabel,
  }) async {
    final details = NotificationDetails(
      android: _androidDetails(request.kind, silenceLabel),
      iOS: DarwinNotificationDetails(
        categoryIdentifier: request.kind.channelId,
        presentSound: request.kind != NotificationKind.tripInProgress,
      ),
    );

    final at = request.showAt;
    if (at == null) {
      await _plugin.show(
        id: request.id,
        title: text.title,
        body: text.body,
        notificationDetails: details,
        payload: _payload(request.kind, request.slot),
      );
      return;
    }

    await _plugin.zonedSchedule(
      id: request.id,
      scheduledDate: tz.TZDateTime.from(at, tz.local),
      title: text.title,
      body: text.body,
      notificationDetails: details,
      payload: _payload(request.kind, request.slot),
      // Inexact on purpose. An exact alarm needs SCHEDULE_EXACT_ALARM, which
      // Play grants to alarm clocks and calendars and not to a trip planner,
      // and a reminder that arrives a minute either side of its lead time is
      // still the reminder. Asking for a permission the app does not need is
      // also how a review gets refused.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  AndroidNotificationDetails _androidDetails(
    NotificationKind kind,
    String silenceLabel,
  ) {
    final ongoing = kind == NotificationKind.tripInProgress;
    return AndroidNotificationDetails(
      kind.channelId,
      // The channel's real name is set once in [_createChannels]; this is the
      // fallback the plugin uses if the channel somehow does not exist yet.
      kind.name,
      importance: _importance(kind),
      priority: ongoing ? Priority.low : Priority.high,
      // The tracking notice stays until tracking stops. Everything else is
      // dismissible by swiping it away, like any other message.
      ongoing: ongoing,
      autoCancel: !ongoing,
      silent: ongoing,
      actions: [
        AndroidNotificationAction(
          kind.canBeSilenced
              ? NotificationService.silenceActionId
              : NotificationService.stopTripActionId,
          silenceLabel,
          // Stopping a trip has to reach the app to release the GPS
          // subscription; switching a kind off is handled without waking a
          // screen.
          showsUserInterface: !kind.canBeSilenced,
          cancelNotification: true,
        ),
      ],
    );
  }

  Importance _importance(NotificationKind kind) => switch (kind) {
    // "Get off at the next stop" is worth interrupting for; missing it means
    // being carried past the stop.
    NotificationKind.nextStopAlert => Importance.high,
    NotificationKind.departureReminder => Importance.high,
    // Present, quiet, and impossible to dismiss while tracking runs.
    NotificationKind.tripInProgress => Importance.low,
    // A question, asked once. It waits in the shade rather than interrupting.
    NotificationKind.postTripQuestion => Importance.defaultImportance,
  };

  @override
  Future<void> retract(int id) => _plugin.cancel(id: id);

  static String _payload(NotificationKind kind, int slot) =>
      '${kind.name}/$slot';

  void _onResponse(NotificationResponse response) {
    final parsed = decodeNotificationPayload(response.payload);
    if (parsed == null) return;

    // Not awaited: this is a platform callback, and the work behind it is a
    // preference write and a cancel.
    unawaited(
      handleResponse(
        parsed.kind,
        slot: parsed.slot,
        actionId: response.actionId,
      ),
    );
  }
}

/// What travels with a notification: the kind it is and which one of that
/// kind. Nothing about the trip, because a payload survives on disk until the
/// notification fires and this app does not keep where people are going.
({NotificationKind kind, int slot})? decodeNotificationPayload(String? raw) {
  final parts = raw?.split('/');
  if (parts == null || parts.length != 2) return null;

  final kind = NotificationKind.values
      .where((k) => k.name == parts.first)
      .firstOrNull;
  final slot = int.tryParse(parts.last);
  if (kind == null || slot == null) return null;

  return (kind: kind, slot: slot);
}

/// The opt-out, for when the app is not running.
///
/// An action that shows no user interface can be tapped while this app is
/// asleep or terminated — which is most of the time a notification is read.
/// Android and iOS answer that by starting a **second Flutter engine** in its
/// own isolate, sharing nothing with `main`: no `NotificationService`, no
/// open store, none of the state the foreground path relies on. So "turn
/// these off" is implemented twice, and this is the half that matters.
///
/// It writes the same key through the same class as the in-app switch, so
/// the two cannot drift. The notification itself is dismissed by the
/// platform, because every action is declared `cancelNotification: true`.
@pragma('vm:entry-point')
Future<void> notificationBackgroundResponse(
  NotificationResponse response,
) async {
  // Nothing is registered in a fresh isolate, including shared_preferences.
  DartPluginRegistrant.ensureInitialized();

  await silenceFromBackground(
    await SharedPreferencesStore.open(),
    actionId: response.actionId,
    payload: response.payload,
  );
}

/// The decision behind [notificationBackgroundResponse], with the storage
/// handed in so it can be tested without a phone.
///
/// Returns whether anything was switched off.
@visibleForTesting
Future<bool> silenceFromBackground(
  KeyValueStore store, {
  required String? actionId,
  required String? payload,
}) async {
  if (actionId != NotificationService.silenceActionId) return false;

  final parsed = decodeNotificationPayload(payload);
  if (parsed == null) return false;

  return NotificationPreferences(store).setAllowed(parsed.kind, allowed: false);
}
