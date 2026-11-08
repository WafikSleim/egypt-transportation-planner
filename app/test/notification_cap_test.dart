import 'dart:io';

import 'package:egypt_transport/core/notifications/notification_kind.dart';
import 'package:egypt_transport/core/notifications/notification_preferences.dart';
import 'package:egypt_transport/core/notifications/notification_service.dart';
import 'package:egypt_transport/core/storage/key_value_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_notification_service.dart';

/// #23 and the "no fifth kind" guarantees, through the real gate.
void main() {
  FakeNotificationService build({
    KeyValueStore? store,
    NotificationPermission permitted = const NotificationsAllowed(),
  }) => FakeNotificationService(
    preferences: NotificationPreferences(store ?? InMemoryStore()),
    permitted: permitted,
  );

  group('at most one unsolicited prompt per trip, enforced in code', () {
    test('the second question for a trip is refused', () async {
      final service = build();

      expect(
        await service.post(const PostTripQuestion(sessionKey: 'trip-a')),
        isTrue,
      );
      expect(
        await service.post(const PostTripQuestion(sessionKey: 'trip-a')),
        isFalse,
      );
      expect(service.delivered, hasLength(1));
    });

    test('however many times a caller tries, one is delivered', () async {
      final service = build();

      for (var i = 0; i < 25; i++) {
        await service.post(const PostTripQuestion(sessionKey: 'trip-a'));
      }

      expect(service.delivered, hasLength(1));
    });

    test('an ignored question is a spent one', () async {
      // Nothing taps it, dismisses it or answers it. The cap must not depend
      // on the passenger doing anything, or "never a second ask if the first
      // is ignored" would only hold for people who respond.
      final service = build();

      await service.post(const PostTripQuestion(sessionKey: 'trip-a'));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(
        await service.post(const PostTripQuestion(sessionKey: 'trip-a')),
        isFalse,
      );
    });

    test('the cap survives a restart', () async {
      final store = InMemoryStore();
      await build(
        store: store,
      ).post(const PostTripQuestion(sessionKey: 'trip-a'));

      final afterRestart = build(store: store);

      expect(
        await afterRestart.post(const PostTripQuestion(sessionKey: 'trip-a')),
        isFalse,
      );
      expect(afterRestart.delivered, isEmpty);
    });

    test('a different trip gets its own one question', () async {
      final service = build();

      await service.post(const PostTripQuestion(sessionKey: 'trip-a'));

      expect(
        await service.post(const PostTripQuestion(sessionKey: 'trip-b')),
        isTrue,
      );
    });

    test('a question with no trip behind it is refused', () async {
      // Otherwise "" would be one shared key: the first empty question would
      // pass and every later one would be blocked, or the reverse.
      final service = build();

      expect(
        await service.post(const PostTripQuestion(sessionKey: '')),
        isFalse,
      );
    });

    test('a question that was never shown does not spend the trip', () async {
      // Switched off, or no OS permission: nothing reached the passenger, so
      // nothing was asked. Turning notifications on later must not find the
      // one question already used up.
      final store = InMemoryStore();
      final off = build(store: store);
      await off.preferences.setAllowed(
        NotificationKind.postTripQuestion,
        allowed: false,
      );
      expect(
        await off.post(const PostTripQuestion(sessionKey: 'trip-a')),
        isFalse,
      );

      final denied = build(
        store: store,
        permitted: const NotificationsDenied(permanently: false),
      );
      expect(
        await denied.post(const PostTripQuestion(sessionKey: 'trip-a')),
        isFalse,
      );

      expect(
        NotificationPreferences(store).postTripQuestionSpent('trip-a'),
        isFalse,
      );
    });

    test('the ledger is bounded, and forgets the oldest first', () async {
      final prefs = NotificationPreferences(InMemoryStore());

      for (var i = 0; i < NotificationPreferences.maxRememberedTrips + 5; i++) {
        await prefs.claimPostTripQuestion('trip-$i');
      }

      expect(prefs.postTripQuestionSpent('trip-0'), isFalse);
      expect(
        prefs.postTripQuestionSpent(
          'trip-${NotificationPreferences.maxRememberedTrips + 4}',
        ),
        isTrue,
      );
    });

    test('an answer is kept on the phone and nowhere else', () async {
      final prefs = NotificationPreferences(InMemoryStore());

      await prefs.recordPostTripAnswer('trip-a', wasRight: false);

      expect(prefs.postTripAnswers, {'trip-a': false});
    });
  });

  group('turning a kind off reaches what is already scheduled', () {
    test('switching reminders off takes back the pending ones', () async {
      final service = build();

      await service.setAllowed(
        NotificationKind.departureReminder,
        allowed: false,
      );

      expect(service.retractedKinds, [NotificationKind.departureReminder]);
    });

    test('switching one back on takes nothing back', () async {
      final service = build();

      await service.setAllowed(
        NotificationKind.departureReminder,
        allowed: true,
      );

      expect(service.retractedKinds, isEmpty);
    });

    test('the tracking notice cannot be switched off this way', () async {
      final service = build();

      expect(
        await service.setAllowed(
          NotificationKind.tripInProgress,
          allowed: false,
        ),
        isFalse,
      );
      expect(service.retractedKinds, isEmpty);
    });

    test('the opt-out on a notification takes back the whole kind', () async {
      final service = build();

      await service.tap(
        NotificationKind.departureReminder,
        slot: 2,
        actionId: NotificationService.silenceActionId,
      );

      expect(service.retractedKinds, [NotificationKind.departureReminder]);
    });
  });

  group('a fifth kind cannot arrive silently', () {
    test('every request type belongs to exactly one of the four kinds', () {
      // An exhaustive switch over the sealed request type: adding a fifth
      // subclass fails to compile here, and the list below is then what a
      // reviewer has to touch alongside the enum.
      NotificationKind kindOf(NotificationRequest r) => switch (r) {
        DepartureReminder() => NotificationKind.departureReminder,
        TripInProgressNotice() => NotificationKind.tripInProgress,
        NextStopAlert() => NotificationKind.nextStopAlert,
        PostTripQuestion() => NotificationKind.postTripQuestion,
      };

      final requests = <NotificationRequest>[
        DepartureReminder(
          at: DateTime(2030),
          departureTime: DateTime(2030),
          tripLabel: '',
        ),
        const TripInProgressNotice(tripLabel: ''),
        const NextStopAlert(stopName: ''),
        const PostTripQuestion(sessionKey: 'x'),
      ];

      expect(requests.map(kindOf).toSet(), NotificationKind.values.toSet());
      for (final r in requests) {
        expect(r.kind, kindOf(r));
      }
    });

    test('no request carries a title or a body', () {
      // The words live in notification_copy.dart. A request that could carry
      // its own would be a way to say anything at all.
      final source = File(
        'lib/core/notifications/notification_kind.dart',
      ).readAsStringSync();
      final code = source
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('///'))
          .join('\n');

      expect(
        code,
        isNot(matches(RegExp(r'\b(final\s+String\s+(title|body))'))),
      );
    });
  });

  group('the project is configured so that push and background are absent', () {
    test('there is no remote push package in the lockfile', () {
      final lock = File('pubspec.lock').readAsStringSync();

      for (final forbidden in [
        'firebase_messaging',
        'onesignal_flutter',
        'flutter_apns',
        'awesome_notifications_fcm',
      ]) {
        expect(lock, isNot(contains('$forbidden:')), reason: forbidden);
      }
    });

    test('iOS declares no background modes', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();

      expect(plist, isNot(contains('<key>UIBackgroundModes</key>')));
    });

    test('Android asks for no background location and no exact alarms', () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      // Comments in the manifest name these on purpose, to explain their
      // absence; only a real declaration counts.
      final declared = RegExp(
        r'<uses-permission[^>]*android:name="([^"]+)"',
      ).allMatches(manifest).map((m) => m.group(1)).toSet();

      expect(
        declared,
        isNot(contains('android.permission.ACCESS_BACKGROUND_LOCATION')),
      );
      expect(
        declared,
        isNot(contains('android.permission.SCHEDULE_EXACT_ALARM')),
      );
      expect(declared, isNot(contains('android.permission.USE_EXACT_ALARM')));
      // And the boot receiver's permission stays, or a reminder set the night
      // before is silently gone by morning.
      expect(declared, contains('android.permission.RECEIVE_BOOT_COMPLETED'));
    });
  });
}
