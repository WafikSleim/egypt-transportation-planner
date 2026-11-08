import 'package:egypt_transport/core/notifications/notification_copy.dart';
import 'package:egypt_transport/core/notifications/notification_kind.dart';
import 'package:egypt_transport/core/notifications/notification_preferences.dart';
import 'package:egypt_transport/core/notifications/notification_service.dart';
import 'package:egypt_transport/core/notifications/notifications_cubit.dart';
import 'package:egypt_transport/core/storage/key_value_store.dart';
import 'package:egypt_transport/core/theme/app_theme.dart';
import 'package:egypt_transport/data/repositories/reminder_ledger.dart';
import 'package:egypt_transport/features/reminders/view/reminder_section.dart';
import 'package:egypt_transport/features/reminders/view_model/reminder_cubit.dart';
import 'package:egypt_transport/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_notification_service.dart';

/// #22. Through the real gate, against the fake that overrides only delivery.
void main() {
  final now = DateTime(2026, 11, 8, 7);
  final departure = DateTime(2026, 11, 8, 8, 15);

  ReminderTarget target({
    String key = 'trip-1',
    DateTime? at,
    bool cached = false,
  }) => ReminderTarget(
    tripKey: key,
    tripLabel: 'المنيب ← رمسيس',
    departureAt: at ?? departure,
    isFromCache: cached,
  );

  late InMemoryStore store;
  late FakeNotificationService service;
  late ReminderLedger ledger;

  setUp(() {
    store = InMemoryStore();
    service = FakeNotificationService(
      preferences: NotificationPreferences(store),
    );
    ledger = ReminderLedger(store);
  });

  ReminderCubit cubit([ReminderTarget? t]) => ReminderCubit(
    notifications: service,
    ledger: ledger,
    target: t ?? target(),
    now: () => now,
  );

  group('setting a reminder', () {
    test('fires the lead time the passenger chose, before departure', () async {
      final c = cubit();

      await c.set(15);

      final posted = service.delivered.single as DepartureReminder;
      expect(posted.at, DateTime(2026, 11, 8, 8));
      expect(posted.departureTime, departure);
      expect(posted.tripLabel, 'المنيب ← رمسيس');
      expect(c.state.outcome, ReminderOutcome.set);
      expect(c.state.reminder?.leadMinutes, 15);
    });

    test('is remembered, with the lead time, across a restart', () async {
      await cubit().set(30);

      final reopened = cubit();
      expect(reopened.state.reminder?.leadMinutes, 30);
      expect(reopened.state.lead, 30);
      expect(
        ledger.forTrip('trip-1', now: now)?.remindAt,
        DateTime(2026, 11, 8, 7, 45),
      );
    });

    test('a second reminder for the same trip replaces the first', () async {
      final c = cubit();

      await c.set(5);
      await c.set(30);

      expect(ledger.pending(now: now), hasLength(1));
      expect(service.delivered.map((r) => r.slot).toSet(), {0});
    });

    test('two trips are two notifications, not one overwriting', () async {
      await cubit(target(key: 'a')).set(10);
      await cubit(target(key: 'b')).set(10);

      final slots = service.delivered.map((r) => r.slot).toList();
      expect(slots, [0, 1]);
      expect(service.delivered[0].id, isNot(service.delivered[1].id));
    });

    test(
      'a reminder silenced since it was set is not shown as pending',
      () async {
        await cubit().set(10);
        expect(cubit().state.reminder, isNotNull);

        // The notification's own button - which also takes the alarm back.
        await service.tap(
          NotificationKind.departureReminder,
          actionId: NotificationService.silenceActionId,
        );

        final reopened = cubit();
        expect(reopened.state.reminder, isNull);
        await Future<void>.delayed(Duration.zero);
        expect(ledger.pending(now: now), isEmpty);
      },
    );

    test('a reminder whose time has gone is not set', () async {
      final c = cubit(target(at: DateTime(2026, 11, 8, 7, 5)));

      await c.set(10);

      expect(c.state.outcome, ReminderOutcome.timePassed);
      expect(service.delivered, isEmpty);
      expect(ledger.pending(now: now), isEmpty);
    });

    test('a saved answer is never offered a reminder', () async {
      // Its times were worked out on another day. A reminder built on them
      // would be a notification, on time, for a vehicle that left yesterday.
      final c = cubit(target(cached: true));

      expect(c.canOffer, isFalse);
      await c.set(10);

      expect(service.delivered, isEmpty);
      expect(ledger.pending(now: now), isEmpty);
    });

    test('refused notifications are reported, not pretended away', () async {
      service.permitted = const NotificationsDenied(permanently: true);
      final c = cubit();

      await c.set(10);

      expect(c.state.outcome, ReminderOutcome.notificationsOff);
      expect(c.state.reminder, isNull);
      expect(ledger.pending(now: now), isEmpty);
    });

    test('asking for one turns reminders back on if they were off', () async {
      await service.setAllowed(
        NotificationKind.departureReminder,
        allowed: false,
      );

      await cubit().set(10);

      expect(service.delivered, hasLength(1));
      expect(
        service.preferences.isAllowed(NotificationKind.departureReminder),
        isTrue,
      );
    });

    test('there is a limit on how many wait at once', () async {
      for (var i = 0; i < ReminderLedger.maxPending; i++) {
        await cubit(target(key: 'trip-$i')).set(10);
      }

      final extra = cubit(target(key: 'one-too-many'));
      await extra.set(10);

      expect(extra.state.outcome, ReminderOutcome.tooMany);
      expect(service.delivered, hasLength(ReminderLedger.maxPending));
    });

    test('the last lead time chosen is where the picker starts', () async {
      await cubit().set(5);

      expect(cubit(target(key: 'other')).state.lead, 5);
    });
  });

  group('cancelling', () {
    test('takes back that reminder and no other', () async {
      await cubit(target(key: 'a')).set(10);
      final b = cubit(target(key: 'b'));
      await b.set(10);

      await b.cancel();

      expect(service.retracted, [
        DepartureReminder(
          at: departure,
          departureTime: departure,
          tripLabel: '',
          slot: 1,
        ).id,
      ]);
      expect(b.state.reminder, isNull);
      expect(b.state.outcome, ReminderOutcome.cancelled);
      expect(ledger.pending(now: now).single.tripKey, 'a');
    });

    test('cancelling with nothing set does nothing', () async {
      await cubit().cancel();

      expect(service.retracted, isEmpty);
    });
  });

  group('the ledger', () {
    test('forgets a reminder once its time has gone', () async {
      await cubit().set(10);

      final tomorrow = now.add(const Duration(days: 1));

      expect(ledger.pending(now: tomorrow), isEmpty);
      expect(ledger.freeSlot(now: tomorrow), 0);
    });

    test('survives bad stored data', () {
      final broken = ReminderLedger(
        InMemoryStore({'reminders': '{"items": [1, "x", {"slot": "no"}]}'}),
      );

      expect(broken.pending(now: now), isEmpty);
      expect(broken.lastLead, ReminderLedger.defaultLead);
    });
  });

  group('the words', () {
    test('say it is an estimate off a recorded schedule', () {
      final copy = AppNotificationCopy.forLocale(const Locale('ar'));

      final text = copy.forRequest(
        DepartureReminder(
          at: DateTime(2026, 11, 8, 8),
          departureTime: departure,
          tripLabel: 'المنيب ← رمسيس',
        ),
      );

      expect(text.body, contains('08:15'));
      expect(text.body, contains('تقدير'));
      expect(text.body, contains('جدول مسجّل'));
      expect(text.body, contains('المنيب ← رمسيس'));
    });

    test('and in English', () {
      final copy = AppNotificationCopy.forLocale(const Locale('en'));

      final text = copy.forRequest(
        DepartureReminder(
          at: DateTime(2026, 11, 8, 8),
          departureTime: departure,
          tripLabel: 'A to B',
        ),
      );

      expect(text.body, contains('estimate'));
      expect(text.body, contains('recorded schedule'));
    });
  });

  group('the section on the itinerary screen', () {
    // The caveat and the cancel button are on screen, not only in the
    // notification, so these drive the real widget.
    Future<ReminderCubit> pumpSection(
      WidgetTester tester, {
      required ReminderTarget target,
    }) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final c = ReminderCubit(
        notifications: service,
        ledger: ledger,
        target: target,
      );
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
                BlocProvider.value(value: c),
                BlocProvider(create: (_) => NotificationsCubit(service)),
              ],
              child: const Scaffold(body: ReminderSection()),
            ),
          ),
        ),
      );
      return c;
    }

    final l = lookupAppLocalizations(const Locale('ar'));

    testWidgets('states the estimate caveat before anything is set', (
      tester,
    ) async {
      await pumpSection(
        tester,
        target: target(at: DateTime.now().add(const Duration(hours: 2))),
      );

      expect(find.text(l.reminderEstimate), findsOneWidget);
      expect(find.text(l.notifyDepartureReminder), findsOneWidget);
    });

    testWidgets('setting then cancelling is two taps on this screen', (
      tester,
    ) async {
      await pumpSection(
        tester,
        target: target(at: DateTime.now().add(const Duration(hours: 2))),
      );

      await tester.tap(find.text(l.notifyDepartureReminder));
      await tester.pumpAndSettle();
      expect(find.text(l.reminderPickTitle), findsOneWidget);

      await tester.tap(find.text(l.durationMinutes(15)));
      await tester.pumpAndSettle();

      expect(service.delivered.single, isA<DepartureReminder>());
      expect(find.text(l.reminderCancel), findsOneWidget);

      await tester.tap(find.text(l.reminderCancel));
      await tester.pumpAndSettle();

      expect(service.retracted, hasLength(1));
      expect(find.text(l.reminderCancelled), findsOneWidget);
      expect(find.text(l.notifyDepartureReminder), findsOneWidget);
    });

    testWidgets('a saved answer explains why there is no button', (
      tester,
    ) async {
      await pumpSection(tester, target: target(cached: true));

      expect(find.text(l.reminderCachedUnavailable), findsOneWidget);
      expect(find.text(l.notifyDepartureReminder), findsNothing);
    });
  });
}
