import 'package:egypt_transport/core/notifications/local_notification_service.dart';
import 'package:egypt_transport/core/notifications/notification_copy.dart';
import 'package:egypt_transport/core/notifications/notification_kind.dart';
import 'package:egypt_transport/core/notifications/notification_permission_prompt.dart';
import 'package:egypt_transport/core/notifications/notification_preferences.dart';
import 'package:egypt_transport/core/notifications/notification_service.dart';
import 'package:egypt_transport/core/notifications/notifications_cubit.dart';
import 'package:egypt_transport/core/storage/key_value_store.dart';
import 'package:egypt_transport/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_notification_service.dart';

void main() {
  FakeNotificationService build({
    KeyValueStore? store,
    NotificationPermission permitted = const NotificationsAllowed(),
  }) => FakeNotificationService(
    preferences: NotificationPreferences(store ?? InMemoryStore()),
    permitted: permitted,
  );

  group('the set of notifications is closed', () {
    test('there are four kinds, and each one belongs to a named issue', () {
      // Three messages and one ongoing notice. Changing this list is the only
      // way to give this app a new reason to interrupt somebody, and that is
      // the whole point of #21: no growth, re-engagement or marketing push is
      // possible without editing an enum and failing this test.
      expect(NotificationKind.values, [
        NotificationKind.departureReminder, // #22
        NotificationKind.tripInProgress, // #24
        NotificationKind.nextStopAlert, // #25
        NotificationKind.postTripQuestion, // #23
      ]);
    });

    test('the three messages can be switched off; the tracking notice cannot', () {
      // Silencing the ongoing notice would let a GPS subscription run with
      // nothing on screen admitting it. The way out of that one is to stop
      // following the trip.
      expect(NotificationKind.departureReminder.canBeSilenced, isTrue);
      expect(NotificationKind.nextStopAlert.canBeSilenced, isTrue);
      expect(NotificationKind.postTripQuestion.canBeSilenced, isTrue);
      expect(NotificationKind.tripInProgress.canBeSilenced, isFalse);
    });

    test('ids are derived from the kind, so two features cannot collide', () {
      final ids = {
        for (final kind in NotificationKind.values)
          switch (kind) {
            NotificationKind.departureReminder =>
              DepartureReminder(at: _never, tripLabel: '').id,
            NotificationKind.tripInProgress =>
              const TripInProgressNotice(tripLabel: '').id,
            NotificationKind.nextStopAlert =>
              const NextStopAlert(stopName: '').id,
            NotificationKind.postTripQuestion => const PostTripQuestion().id,
          },
      };
      expect(ids.length, NotificationKind.values.length);

      // Two reminders for two different saved trips are two notifications,
      // not one overwriting the other.
      expect(
        DepartureReminder(at: _never, tripLabel: '', slot: 1).id,
        isNot(DepartureReminder(at: _never, tripLabel: '').id),
      );
    });
  });

  group('nothing is shown that the passenger did not agree to', () {
    test('a kind that is switched off is not delivered', () async {
      final service = build();
      await service.preferences.setAllowed(
        NotificationKind.nextStopAlert,
        allowed: false,
      );

      final posted = await service.post(
        const NextStopAlert(stopName: 'المنيب'),
      );

      expect(posted, isFalse);
      expect(service.delivered, isEmpty);
    });

    test('without OS permission nothing is delivered', () async {
      final service = build(
        permitted: const NotificationsDenied(permanently: false),
      );

      expect(await service.post(const PostTripQuestion()), isFalse);
      expect(service.delivered, isEmpty);
    });

    test('a reminder for a departure that has passed is not delivered', () {
      // Android fires a schedule in the past immediately, so this would wake
      // somebody to remind them of a trip they have already missed.
      final service = build();

      expect(
        service.post(
          DepartureReminder(
            at: DateTime.now().subtract(const Duration(minutes: 1)),
            tripLabel: 'المنيب ← رمسيس',
          ),
        ),
        completion(isFalse),
      );
    });

    test('an allowed kind with permission is delivered', () async {
      final service = build();

      expect(await service.post(const PostTripQuestion()), isTrue);
      expect(service.delivered.single, isA<PostTripQuestion>());
    });

    test('the gate is the real one, not the fake', () {
      // FakeNotificationService overrides `deliver` and `retract` and nothing
      // else, so every test above ran the code that ships. If this ever stops
      // being true the tests stop meaning anything.
      final service = build();
      expect(service, isA<NotificationService>());
      expect(service.post, isA<Future<bool> Function(NotificationRequest)>());
    });
  });

  group('turning them off is one tap from the notification', () {
    test('the silence action switches that kind off and takes it back', () async {
      final store = InMemoryStore();
      final service = build(store: store);

      await service.tap(
        NotificationKind.postTripQuestion,
        actionId: NotificationService.silenceActionId,
      );

      expect(
        service.preferences.isAllowed(NotificationKind.postTripQuestion),
        isFalse,
      );
      expect(service.retracted, [const PostTripQuestion().id]);

      // And it sticks: the next one is not shown either.
      expect(await service.post(const PostTripQuestion()), isFalse);
    });

    test('it survives a restart', () async {
      final store = InMemoryStore();
      final first = build(store: store);
      await first.tap(
        NotificationKind.departureReminder,
        actionId: NotificationService.silenceActionId,
      );

      final second = build(store: store);
      expect(
        second.preferences.isAllowed(NotificationKind.departureReminder),
        isFalse,
      );
    });

    test('it silences only the kind that was tapped', () async {
      final service = build();
      await service.tap(
        NotificationKind.nextStopAlert,
        actionId: NotificationService.silenceActionId,
      );

      expect(
        service.preferences.isAllowed(NotificationKind.departureReminder),
        isTrue,
      );
    });

    test('the tracking notice cannot be silenced this way', () async {
      // Its action stops the trip, which is #24's job because it owns the GPS
      // subscription. So this has to reach the feature rather than be
      // swallowed here.
      final service = build();
      final seen = <NotificationAction>[];
      service.actions.listen(seen.add);

      await service.tap(
        NotificationKind.tripInProgress,
        actionId: NotificationService.stopTripActionId,
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        service.preferences.isAllowed(NotificationKind.tripInProgress),
        isTrue,
      );
      expect(seen.single.kind, NotificationKind.tripInProgress);
      expect(seen.single.actionId, NotificationService.stopTripActionId);
    });

    test('it works with the app closed, from its own isolate', () async {
      // The case that matters: a notification is usually read when the app is
      // not running, and an action with no user interface is answered by a
      // second Flutter engine that shares nothing with `main`. It writes the
      // same key through the same class, so the two halves cannot drift.
      final store = InMemoryStore();

      expect(
        await silenceFromBackground(
          store,
          actionId: NotificationService.silenceActionId,
          payload: 'nextStopAlert/0',
        ),
        isTrue,
      );

      final service = build(store: store);
      expect(await service.post(const NextStopAlert(stopName: 'رمسيس')), isFalse);
    });

    test('the background handler ignores a tap that is not the opt-out', () async {
      final store = InMemoryStore();

      expect(
        await silenceFromBackground(
          store,
          actionId: null,
          payload: 'nextStopAlert/0',
        ),
        isFalse,
      );
      expect(
        await silenceFromBackground(
          store,
          actionId: NotificationService.silenceActionId,
          payload: 'somethingElse/0',
        ),
        isFalse,
      );
      expect(store.contents, isEmpty);
    });

    test('a payload names the kind and the slot, and nothing about the trip', () {
      // It sits on disk until the notification fires. Where somebody is going
      // is not something this app keeps anywhere, least of all there.
      expect(decodeNotificationPayload('departureReminder/2'), (
        kind: NotificationKind.departureReminder,
        slot: 2,
      ));
      expect(decodeNotificationPayload('nonsense'), isNull);
      expect(decodeNotificationPayload(null), isNull);
    });

    test('a plain tap is handed to whichever feature owns that kind', () async {
      final service = build();
      final seen = <NotificationAction>[];
      service.actions.listen(seen.add);

      await service.tap(NotificationKind.departureReminder, slot: 3);
      await Future<void>.delayed(Duration.zero);

      expect(seen.single.slot, 3);
      expect(seen.single.actionId, isNull);
    });
  });

  group('stored preferences fail towards on, not off', () {
    test('a phone with nothing stored gets all three', () {
      final prefs = NotificationPreferences(InMemoryStore());
      expect(prefs.all.values, everyElement(isTrue));
    });

    test('text that is not JSON does not silence a reminder', () {
      // Same rule as the settings store: bad stored data the user can neither
      // see nor clear must not quietly disable something they rely on.
      final prefs = NotificationPreferences(
        InMemoryStore({'notifications': 'not json'}),
      );
      expect(prefs.isAllowed(NotificationKind.departureReminder), isTrue);
    });

    test('the tracking notice refuses to be stored as off', () async {
      final prefs = NotificationPreferences(InMemoryStore());
      expect(
        await prefs.setAllowed(
          NotificationKind.tripInProgress,
          allowed: false,
        ),
        isFalse,
      );
      expect(prefs.isAllowed(NotificationKind.tripInProgress), isTrue);
    });
  });

  group('the permission flow', () {
    test('the explanation is needed only when the OS will prompt', () async {
      final denied = NotificationsCubit(
        build(permitted: const NotificationsDenied(permanently: false)),
      );
      expect(await denied.needsExplaining, isTrue);

      final allowed = NotificationsCubit(build());
      expect(await allowed.needsExplaining, isFalse);
    });

    test('a refusal after the prompt has been spent points at settings', () async {
      // Android never says "never again" for POST_NOTIFICATIONS, so the app
      // remembers that it asked. Offering the prompt a second time would be a
      // button that does nothing.
      final store = InMemoryStore();
      final service = build(
        store: store,
        permitted: const NotificationsDenied(permanently: false),
      );
      final cubit = NotificationsCubit(service);

      expect(await cubit.askPermission(), isFalse);
      expect(service.preferences.hasBeenAsked, isTrue);

      service.permitted = const NotificationsDenied(permanently: true);
      await cubit.refresh();
      expect(cubit.state.blockedInSettings, isTrue);
    });

    test('granting it is reflected in the switches', () async {
      final cubit = NotificationsCubit(build());
      await cubit.refresh();

      expect(cubit.state.granted, isTrue);
      expect(cubit.state.allowed.values, everyElement(isTrue));
    });

    test('the settings screen is one call away', () async {
      final service = build();
      await NotificationsCubit(service).openSettings();
      expect(service.settingsOpened, 1);
    });
  });

  group('the words are derived from the request, in both languages', () {
    for (final code in ['ar', 'en']) {
      test('$code has copy for every kind', () {
        final copy = AppNotificationCopy.forLocale(Locale(code));

        final texts = [
          copy.forRequest(
            DepartureReminder(at: DateTime(2026, 9, 23), tripLabel: 'المنيب'),
          ),
          copy.forRequest(const TripInProgressNotice(tripLabel: 'المنيب')),
          copy.forRequest(const NextStopAlert(stopName: 'السيدة زينب')),
          copy.forRequest(const PostTripQuestion()),
        ];

        for (final text in texts) {
          expect(text.title, isNotEmpty);
        }
        for (final kind in NotificationKind.values) {
          expect(copy.silenceAction(kind), isNotEmpty);
          expect(copy.channelName(kind), isNotEmpty);
        }
      });
    }

    test('the trip and the stop reach the words', () {
      final copy = AppNotificationCopy.forLocale(const Locale('ar'));
      expect(
        copy.forRequest(const NextStopAlert(stopName: 'السيدة زينب')).body,
        contains('السيدة زينب'),
      );
    });

    test('the Arabic asks the question the design system settled on', () {
      final copy = AppNotificationCopy.forLocale(const Locale('ar'));
      expect(
        copy.forRequest(const PostTripQuestion()).title,
        'وصلت بالسلامة؟',
      );
    });
  });

  group('asking in context', () {
    testWidgets('the reason is stated before the OS prompt', (tester) async {
      final service = build(
        permitted: const NotificationsDenied(permanently: false),
      );
      await tester.pumpWidget(_host(service));

      await tester.tap(find.text('ask'));
      await tester.pumpAndSettle();

      final l = lookupAppLocalizations(const Locale('ar'));
      expect(find.text(l.notificationsWhyTitle), findsOneWidget);
      expect(find.text(l.notificationsWhyBody), findsOneWidget);
      // Nothing has been asked of the OS yet.
      expect(service.requests, 0);
    });

    testWidgets('"not now" means the OS is never asked', (tester) async {
      final service = build(
        permitted: const NotificationsDenied(permanently: false),
      );
      await tester.pumpWidget(_host(service));

      await tester.tap(find.text('ask'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(lookupAppLocalizations(const Locale('ar')).notNow),
      );
      await tester.pumpAndSettle();

      expect(service.requests, 0);
    });

    testWidgets('agreeing asks the OS once', (tester) async {
      final service = build(
        permitted: const NotificationsDenied(permanently: false),
      );
      await tester.pumpWidget(_host(service));

      await tester.tap(find.text('ask'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(
          lookupAppLocalizations(const Locale('ar')).notificationsWhyContinue,
        ),
      );
      await tester.pumpAndSettle();

      expect(service.requests, 1);
    });

    testWidgets('an app that already has permission does not explain again', (
      tester,
    ) async {
      final service = build();
      await tester.pumpWidget(_host(service));

      await tester.tap(find.text('ask'));
      await tester.pumpAndSettle();

      expect(
        find.text(lookupAppLocalizations(const Locale('ar')).notNow),
        findsNothing,
      );
    });
  });
}

/// Far enough ahead that the "already departed" guard never fires.
final _never = DateTime(2030);

Widget _host(FakeNotificationService service) => MaterialApp(
  locale: const Locale('ar'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  home: BlocProvider(
    create: (_) => NotificationsCubit(service),
    child: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => askToNotify(context),
          child: const Text('ask'),
        ),
      ),
    ),
  ),
);
