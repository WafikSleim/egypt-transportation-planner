import 'dart:io';
import 'dart:math' as math;

import 'package:egypt_transport/core/notifications/notification_kind.dart';
import 'package:egypt_transport/core/presentation/trip_presenter.dart';
import 'package:egypt_transport/data/models/models.dart';
import 'package:egypt_transport/core/notifications/notification_preferences.dart';
import 'package:egypt_transport/core/notifications/notification_service.dart';
import 'package:egypt_transport/core/notifications/notifications_cubit.dart';
import 'package:egypt_transport/core/storage/key_value_store.dart';
import 'package:egypt_transport/core/theme/app_theme.dart';
import 'package:egypt_transport/core/tracking/tracked_trip.dart';
import 'package:egypt_transport/core/tracking/tracking_source.dart';
import 'package:egypt_transport/core/tracking/trip_tracker.dart';
import 'package:egypt_transport/domain/entities/trip_endpoint.dart';
import 'package:egypt_transport/features/tracking/view/tracking_section.dart';
import 'package:egypt_transport/features/tracking/view_model/tracking_cubit.dart';
import 'package:egypt_transport/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_notification_service.dart';
import 'fixtures.dart';
import 'fake_tracking_source.dart';

/// #24 and #25.
///
/// Every threshold exercised here is a guess that has not met a road; these
/// tests pin the *policy* - what is claimed, what is withheld, what is never
/// said - not the calibration.
void main() {
  // A straight ride due east: board in the west, alight 5 km to the east, at
  // Cairo's latitude. `east` offsets a point by metres along that line.
  const lat = 30.0;
  const board = GeoPoint(lat, 31.20);
  final alight = east(const GeoPoint(lat, 31.20), 5000);

  TrackedLeg leg({GeoPoint? from, GeoPoint? to, String name = 'العتبة'}) =>
      TrackedLeg(board: from ?? board, alight: to ?? alight, alightName: name);

  TripTracker tracker([List<TrackedLeg>? legs]) =>
      TripTracker(TrackedTrip(label: 'المنيب ← رمسيس', legs: legs ?? [leg()]));

  LocationFix fix(GeoPoint p, {double accuracy = 20, DateTime? at}) =>
      LocationFix(
        point: p,
        accuracyM: accuracy,
        at: at ?? DateTime(2026, 11, 8, 8),
      );

  group('the recorded route comes from the plan, via the presenter', () {
    test('only rides are followed, each with both endpoints', () {
      final plan = const TripPresenter(
        languageCode: 'ar',
      ).plan(PlanResponse.fromJson(planMetro));
      final itinerary = plan.itineraries.first;

      final trip = TrackedTrip.fromItinerary(itinerary, 'x')!;

      final rides = itinerary.legs.where((l) => l.isTransit).toList();
      expect(trip.legs, hasLength(rides.length));
      for (var i = 0; i < rides.length; i++) {
        expect(trip.legs[i].board, rides[i].fromPoint);
        expect(trip.legs[i].alight, rides[i].toPoint);
        expect(trip.legs[i].alightName, rides[i].toName);
      }
      expect(rides.every((l) => l.fromPoint != null), isTrue);
    });
  });

  group('what the tracker will claim', () {
    test('a good fix gives a distance rounded to 100 m', () {
      final t = tracker();

      final u = t.onFix(fix(east(alight, -2340)));

      final e = u.estimate as OnRoute;
      expect(e.alightName, 'العتبة');
      expect(e.distanceM % 100, 0);
      expect(e.distanceM, closeTo(2300, 100));
      expect(u.alertFor, isNull);
    });

    test('a poor fix gets "not sure", never a distance', () {
      final t = tracker();

      // Right on top of the stop, but 150 m out: it could be anywhere.
      final u = t.onFix(fix(alight, accuracy: 150));

      expect(u.estimate, const Unsure(UnsureReason.poorFix));
      expect(u.alertFor, isNull);
    });

    test('a long way off the line gets "not sure", not a guess', () {
      final t = tracker();

      // 3 km north of the middle of a 5 km ride.
      final u = t.onFix(fix(const GeoPoint(lat + 0.027, 31.2233)));

      expect(u.estimate, const Unsure(UnsureReason.offRoute));
    });

    test('a wandering road inside the corridor is still on route', () {
      final t = tracker();

      // 800 m off the chord: a real road bends further than that.
      final u = t.onFix(fix(GeoPoint(lat + 800 / 111320, board.lon + 0.02)));

      expect(u.estimate, isA<OnRoute>());
    });

    test('a stale estimate is withdrawn rather than left looking live', () {
      final t = tracker();
      final at = DateTime(2026, 11, 8, 8);
      t.onFix(fix(east(alight, -2000), at: at));

      expect(
        t.onTick(at.add(const Duration(seconds: 30))).estimate,
        isA<OnRoute>(),
      );
      expect(
        t.onTick(at.add(const Duration(minutes: 3))).estimate,
        const Unsure(UnsureReason.noSignal),
      );

      // And a fresh fix brings it back.
      expect(
        t
            .onFix(
              fix(east(alight, -1900), at: at.add(const Duration(minutes: 4))),
            )
            .estimate,
        isA<OnRoute>(),
      );
    });

    test('a lost signal is reported as such', () {
      final t = tracker();

      expect(t.onSignalLost().estimate, const Unsure(UnsureReason.noSignal));
    });

    test('there is nowhere in an estimate to put a time', () {
      // The sealed set is the whole vocabulary; none has an ETA. Adding one
      // means adding a type here and a branch in the screen, in plain sight.
      String kind(TrackingEstimate e) => switch (e) {
        Searching() => 'searching',
        Unsure() => 'unsure',
        OnRoute() => 'onRoute',
        NearAlight() => 'near',
        TripDone() => 'done',
      };
      expect(kind(const Searching()), 'searching');

      final source = File('lib/core/tracking/trip_tracker.dart')
          .readAsStringSync()
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(
        source,
        isNot(matches(RegExp(r'\b(eta|ETA|arrivesIn|minutesAway)\b'))),
      );
    });
  });

  group('the next-stop alert', () {
    test('needs two confident fixes inside the radius, then fires once', () {
      final t = tracker();

      final first = t.onFix(fix(east(alight, -350)));
      final second = t.onFix(fix(east(alight, -300)));
      final third = t.onFix(fix(east(alight, -250)));

      expect(first.alertFor, isNull);
      expect(second.alertFor?.alightName, 'العتبة');
      expect(second.estimate, const NearAlight(alightName: 'العتبة'));
      expect(third.alertFor, isNull, reason: 'once per ride');
      expect(third.estimate, isA<NearAlight>());
    });

    test('one noisy reading does not raise it', () {
      final t = tracker();

      t.onFix(fix(east(alight, -350)));
      final out = t.onFix(fix(east(alight, -1500)));
      final again = t.onFix(fix(east(alight, -350)));

      expect(out.alertFor, isNull);
      expect(again.alertFor, isNull, reason: 'the count started over');
    });

    test('a poor fix near the stop never raises it', () {
      final t = tracker();

      for (var i = 0; i < 5; i++) {
        expect(t.onFix(fix(alight, accuracy: 200)).alertFor, isNull);
      }
    });

    test('the trip finishes when the last stop is reached', () {
      final t = tracker();

      t.onFix(fix(east(alight, -100)));
      final done = t.onFix(fix(east(alight, -50)));

      expect(done.finished, isTrue);
      expect(done.estimate, const TripDone());
    });

    test('with a transfer, each ride gets its own alert', () {
      final second = east(alight, 4000);
      final t = tracker([
        leg(name: 'العتبة'),
        leg(from: alight, to: second, name: 'رمسيس'),
      ]);

      t.onFix(fix(east(alight, -100)));
      final arrived = t.onFix(fix(east(alight, -50)));
      expect(arrived.finished, isFalse);
      expect(t.legIndex, 1);

      t.onFix(fix(east(second, -300)));
      final alert = t.onFix(fix(east(second, -250)));
      expect(alert.alertFor?.alightName, 'رمسيس');
    });

    test('going past a stop that was announced moves on to the next ride', () {
      final second = east(alight, 4000);
      final t = tracker([
        leg(name: 'العتبة'),
        leg(from: alight, to: second, name: 'رمسيس'),
      ]);

      t.onFix(fix(east(alight, -350)));
      t.onFix(fix(east(alight, -300)));
      expect(t.legIndex, 0);

      // Never within 150 m, then clearly beyond: the passenger has passed it.
      final u = t.onFix(fix(east(alight, 1500)));

      expect(t.legIndex, 1);
      expect(u.finished, isFalse);
    });
  });

  group('following a trip, as the cubit runs it', () {
    late FakeTrackingSource source;
    late FakeNotificationService service;
    late TrackingCubit cubit;

    final trip = TrackedTrip(label: 'المنيب ← رمسيس', legs: [leg()]);

    setUp(() {
      source = FakeTrackingSource();
      service = FakeNotificationService(
        preferences: NotificationPreferences(InMemoryStore()),
      );
      cubit = TrackingCubit(source: source, notifications: service);
    });

    tearDown(() => cubit.close());

    Future<void> settle() => Future<void>.delayed(Duration.zero);

    test('permission first, then the notice, then the GPS', () async {
      await cubit.start(trip, tripKey: 'k');

      expect(source.calls, ['access', 'fixes']);
      expect(service.delivered.single, isA<TripInProgressNotice>());
      expect(cubit.state.phase, TrackingPhase.active);
    });

    test('a notice that cannot be shown means no GPS at all', () async {
      // The rule behind the persistent notification being a guarantee:
      // Android runs a foreground service with a refused notification
      // invisibly, which is exactly tracking nobody can see.
      service.permitted = const NotificationsDenied(permanently: true);

      await cubit.start(trip, tripKey: 'k');

      expect(source.subscriptions, 0);
      expect(source.listening, isFalse);
      expect(cubit.state.phase, TrackingPhase.idle);
      expect(cubit.state.failure, TrackingFailure.notificationsOff);
    });

    test(
      'the notice is shown even with every other kind switched off',
      () async {
        for (final kind in NotificationKind.values) {
          await service.setAllowed(kind, allowed: false);
        }

        await cubit.start(trip, tripKey: 'k');

        expect(service.delivered.single, isA<TripInProgressNotice>());
      },
    );

    for (final entry in {
      TrackingAccess.denied: TrackingFailure.locationDenied,
      TrackingAccess.deniedForever: TrackingFailure.locationDeniedForever,
      TrackingAccess.serviceOff: TrackingFailure.locationOff,
      TrackingAccess.unavailable: TrackingFailure.unavailable,
    }.entries) {
      test('${entry.key.name} starts nothing and shows no notice', () async {
        source.access = entry.key;

        await cubit.start(trip, tripKey: 'k');

        expect(source.subscriptions, 0);
        expect(service.delivered, isEmpty);
        expect(cubit.state.failure, entry.value);
      });
    }

    test('stopping releases the GPS and takes the notice down', () async {
      await cubit.start(trip, tripKey: 'k');

      await cubit.stop();

      expect(source.listening, isFalse);
      expect(service.retracted, [const TripInProgressNotice(tripLabel: '').id]);
      expect(cubit.state.phase, TrackingPhase.idle);
    });

    test('stopping yourself is not followed by a question', () async {
      await cubit.start(trip, tripKey: 'k');
      await cubit.stop();

      expect(service.delivered.whereType<PostTripQuestion>(), isEmpty);
    });

    test('the button on the notice stops it, from any screen', () async {
      await cubit.start(trip, tripKey: 'k');

      await service.tap(
        NotificationKind.tripInProgress,
        actionId: NotificationService.stopTripActionId,
      );
      await settle();

      expect(cubit.state.phase, TrackingPhase.idle);
      expect(source.listening, isFalse);
      expect(service.retracted, isNotEmpty);
    });

    test('a second start while following is ignored', () async {
      await cubit.start(trip, tripKey: 'k');
      await cubit.start(trip, tripKey: 'other');

      expect(source.subscriptions, 1);
      expect(cubit.state.tripKey, 'k');
    });

    test('a signal that fails mid-ride becomes "not sure"', () async {
      await cubit.start(trip, tripKey: 'k');

      source.fail();
      await settle();

      expect(cubit.state.estimate, const Unsure(UnsureReason.noSignal));
      expect(cubit.state.phase, TrackingPhase.active);
    });

    test('the alert is posted once, through the gate', () async {
      await cubit.start(trip, tripKey: 'k');

      source.emit(alight.lat, alight.lon - 350 / 96400);
      await settle();
      source.emit(alight.lat, alight.lon - 300 / 96400);
      await settle();
      source.emit(alight.lat, alight.lon - 250 / 96400);
      await settle();

      expect(service.delivered.whereType<NextStopAlert>(), hasLength(1));
      expect(
        service.delivered.whereType<NextStopAlert>().single.stopName,
        'العتبة',
      );
    });

    test(
      'a passenger who switched the alert off gets none, and still sees the screen',
      () async {
        await service.setAllowed(
          NotificationKind.nextStopAlert,
          allowed: false,
        );
        await cubit.start(trip, tripKey: 'k');

        source.emit(alight.lat, alight.lon - 300 / 96400);
        await settle();
        source.emit(alight.lat, alight.lon - 250 / 96400);
        await settle();

        expect(service.delivered.whereType<NextStopAlert>(), isEmpty);
        expect(cubit.state.estimate, isA<NearAlight>());
      },
    );

    test('arriving stops following and asks the one question, once', () async {
      await cubit.start(trip, tripKey: 'k');

      source.emit(alight.lat, alight.lon - 100 / 96400);
      await settle();
      source.emit(alight.lat, alight.lon - 50 / 96400);
      await settle();
      await settle();

      expect(cubit.state.phase, TrackingPhase.arrived);
      expect(source.listening, isFalse);
      expect(
        service.retracted,
        contains(const TripInProgressNotice(tripLabel: '').id),
      );
      final question = service.delivered.whereType<PostTripQuestion>().single;

      // Nothing - not this class, not another feature - can ask again.
      expect(await service.post(question), isFalse);
      expect(service.delivered.whereType<PostTripQuestion>(), hasLength(1));
    });

    test('the session key is not made of the route or a place', () async {
      await cubit.start(trip, tripKey: 'k');
      source.emit(alight.lat, alight.lon - 100 / 96400);
      await settle();
      source.emit(alight.lat, alight.lon - 50 / 96400);
      await settle();
      await settle();

      final key = service.delivered
          .whereType<PostTripQuestion>()
          .single
          .sessionKey;

      expect(int.tryParse(key), isNotNull, reason: 'a clock reading, only');
    });
  });

  group('the position stays on the phone', () {
    // The cubit is handed a location source and a notifier - no repository,
    // no HTTP client - so there is nothing in reach to send a fix with. These
    // hold that for everything that ever sees one.
    final files = [
      ...Directory(
        'lib/core/tracking',
      ).listSync().whereType<File>().map((f) => f.path),
      'lib/features/tracking/view_model/tracking_cubit.dart',
    ];

    String code(String path) => File(path)
        .readAsStringSync()
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    test('nothing that sees a fix imports a network client', () {
      for (final path in files) {
        final imports = RegExp(
          r"import '([^']+)'",
        ).allMatches(code(path)).map((m) => m.group(1)!);
        for (final i in imports) {
          expect(i, isNot(contains('package:http')), reason: path);
          expect(i, isNot(contains('api_client')), reason: path);
          expect(i, isNot(contains('planner_repository')), reason: path);
          expect(i, isNot(contains('network/')), reason: path);
        }
      }
    });

    test('nothing that sees a fix writes it down', () {
      for (final path in files) {
        final src = code(path);
        expect(src, isNot(contains('KeyValueStore')), reason: path);
        expect(src, isNot(contains('shared_preferences')), reason: path);
        expect(src, isNot(contains('dart:io')), reason: path);
      }
    });

    test('nothing that sees a fix logs it', () {
      for (final path in files) {
        expect(
          code(path),
          isNot(matches(RegExp(r'\b(print|debugPrint|log|developer\.log)\('))),
          reason: path,
        );
      }
    });

    test('the tracking source is not the one-off location service', () {
      // A subscription that stays open must not arrive by accident through
      // "my location": different type, different consent.
      expect(
        File('lib/core/location/location_service.dart').readAsStringSync(),
        isNot(contains('getPositionStream')),
      );
    });

    test('the Android source starts no service of its own', () {
      final src = code('lib/core/tracking/tracking_source.dart');

      expect(src, isNot(contains('foregroundNotificationConfig:')));
    });
  });

  group('the section on the itinerary screen', () {
    final l = lookupAppLocalizations(const Locale('ar'));

    late FakeTrackingSource source;
    late FakeNotificationService service;
    late TrackingCubit cubit;

    final trip = TrackedTrip(label: 'المنيب ← رمسيس', legs: [leg()]);

    /// The title above it carries the same words, so this finds the button.
    Finder startButton() => find.byWidgetPredicate((w) => w is FilledButton);

    Future<void> pump(WidgetTester tester, {bool background = true}) async {
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      source = FakeTrackingSource(background: background);
      service = FakeNotificationService(
        preferences: NotificationPreferences(InMemoryStore()),
      );
      cubit = TrackingCubit(source: source, notifications: service);
      addTearDown(cubit.close);

      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            locale: const Locale('ar'),
            theme: AppTheme.light(),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: MultiBlocProvider(
              providers: [
                BlocProvider.value(value: cubit),
                BlocProvider(create: (_) => NotificationsCubit(service)),
              ],
              child: Scaffold(
                body: SingleChildScrollView(
                  child: TrackingSection(tripKey: 'k', trip: trip),
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets(
      'nothing starts until the passenger asks, and the disclosure comes first',
      (tester) async {
        await pump(tester);

        expect(source.accessRequests, 0);
        expect(service.delivered, isEmpty);

        await tester.tap(startButton());
        await tester.pumpAndSettle();

        // GPS and battery, the position staying on the phone, and no live
        // vehicle data - all said before anything runs.
        expect(find.text(l.trackingDisclosureGps), findsOneWidget);
        expect(find.text(l.trackingDisclosureOnDevice), findsOneWidget);
        expect(find.text(l.trackingDisclosureNotLive), findsOneWidget);
        expect(find.text(l.trackingDisclosureStop), findsOneWidget);
        expect(source.accessRequests, 0);
      },
    );

    testWidgets('"not now" starts nothing', (tester) async {
      await pump(tester);

      await tester.tap(startButton());
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.notNow));
      await tester.pumpAndSettle();

      expect(source.accessRequests, 0);
      expect(cubit.state.phase, TrackingPhase.idle);
    });

    testWidgets('agreeing starts it, and the panel names its basis', (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(startButton());
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.trackingDisclosureStart));
      await tester.pumpAndSettle();

      expect(cubit.state.phase, TrackingPhase.active);
      expect(find.text(l.trackingSearching), findsOneWidget);
      expect(find.text(l.trackingBasis), findsOneWidget);
      expect(find.text(l.notificationsStopTrip), findsOneWidget);
      await tester.runAsync(cubit.stop);
    });

    testWidgets('low confidence is said in words, with no distance', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(startButton());
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.trackingDisclosureStart));
      await tester.pumpAndSettle();

      // 3 km off the line.
      source.emit(lat + 0.027, 31.2233);
      await tester.pumpAndSettle();

      expect(find.text(l.trackingUnsureOffRoute), findsOneWidget);
      expect(
        find.textContaining('مش متأكدين إنك في السكة الصح'),
        findsOneWidget,
      );
      expect(find.textContaining('متر'), findsNothing);
      await tester.runAsync(cubit.stop);
    });

    testWidgets(
      'a distance is shown with its stop, rounded, and never as a time',
      (tester) async {
        await pump(tester);
        await tester.tap(startButton());
        await tester.pumpAndSettle();
        await tester.tap(find.text(l.trackingDisclosureStart));
        await tester.pumpAndSettle();

        source.emit(alight.lat, alight.lon - 2000 / 96400);
        await tester.pumpAndSettle();

        expect(find.textContaining('العتبة'), findsWidgets);
        expect(find.textContaining('كم'), findsOneWidget);
        expect(find.textContaining('دقيقة'), findsNothing);
        await tester.runAsync(cubit.stop);
      },
    );

    testWidgets('the stop button ends it and removes the notice', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(startButton());
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.trackingDisclosureStart));
      await tester.pumpAndSettle();

      await tester.tap(find.text(l.notificationsStopTrip));
      // Releasing the subscription is real async work, which a widget test's
      // fake clock does not run on its own.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      expect(cubit.state.phase, TrackingPhase.idle);
      expect(source.listening, isFalse);
      expect(service.retracted, isNotEmpty);
      expect(find.text(l.trackingStart), findsWidgets);
    });

    testWidgets(
      'on iPhone the disclosure says it only works with the app open',
      (tester) async {
        await pump(tester, background: false);

        await tester.tap(startButton());
        await tester.pumpAndSettle();

        expect(find.text(l.trackingDisclosureIosForeground), findsOneWidget);
      },
    );

    testWidgets('on Android it does not say that', (tester) async {
      await pump(tester);

      await tester.tap(startButton());
      await tester.pumpAndSettle();

      expect(find.text(l.trackingDisclosureIosForeground), findsNothing);
    });

    testWidgets('refused notifications explain why nothing started', (
      tester,
    ) async {
      await pump(tester);
      service.permitted = const NotificationsDenied(permanently: true);

      await tester.tap(startButton());
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.trackingDisclosureStart));
      await tester.pumpAndSettle();
      // The in-context explanation, then the OS says no.
      await tester.tap(find.text(l.notificationsWhyContinue));
      await tester.pumpAndSettle();

      expect(find.text(l.trackingFailNotifications), findsOneWidget);
      expect(source.subscriptions, 0);
    });
  });
}

/// [base] moved [metres] due east at its own latitude.
GeoPoint east(GeoPoint base, double metres) => GeoPoint(
  base.lat,
  base.lon + metres / (111320 * math.cos(base.lat * math.pi / 180)),
);
