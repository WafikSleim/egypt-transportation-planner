import 'package:egypt_transport/core/notifications/notification_kind.dart';
import 'package:egypt_transport/core/notifications/notification_preferences.dart';
import 'package:egypt_transport/core/notifications/notification_service.dart';
import 'package:egypt_transport/core/storage/key_value_store.dart';
import 'package:egypt_transport/features/post_trip/view/post_trip_listener.dart';
import 'package:egypt_transport/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_notification_service.dart';

/// #23: kind wording, dismissible without answering, one ask per trip.
void main() {
  final l = lookupAppLocalizations(const Locale('ar'));

  late FakeNotificationService service;
  final navigatorKey = GlobalKey<NavigatorState>();

  Future<void> pump(WidgetTester tester) async {
    service = FakeNotificationService(
      preferences: NotificationPreferences(InMemoryStore()),
    );
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (context, child) => PostTripListener(
          service: service,
          navigatorKey: navigatorKey,
          child: child!,
        ),
        home: const Scaffold(body: Text('home')),
      ),
    );
    // The question was asked for this trip.
    await tester.runAsync(
      () => service.post(const PostTripQuestion(sessionKey: 'trip-a')),
    );
  }

  Future<void> tapNotification(WidgetTester tester, {String? actionId}) async {
    await tester.runAsync(
      () => service.tap(NotificationKind.postTripQuestion, actionId: actionId),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('tapping the question opens it, in kind words', (tester) async {
    await pump(tester);

    await tapNotification(tester);

    expect(find.text(l.notifyPostTripTitle), findsOneWidget);
    expect(find.text(l.postTripDialogQuestion), findsOneWidget);
    // It says where the answer goes, and that it will not be asked again.
    expect(find.text(l.postTripLocalOnly), findsOneWidget);
  });

  testWidgets('"not now" records nothing and the question stays spent', (
    tester,
  ) async {
    await pump(tester);
    await tapNotification(tester);

    await tester.tap(find.text(l.notNow));
    await tester.pumpAndSettle();

    expect(service.preferences.postTripAnswers, isEmpty);
    expect(
      await tester.runAsync(
        () => service.post(const PostTripQuestion(sessionKey: 'trip-a')),
      ),
      isFalse,
    );
  });

  testWidgets('an answer is recorded against that trip, on the phone', (
    tester,
  ) async {
    await pump(tester);
    await tapNotification(tester);

    await tester.tap(find.text(l.postTripNo));
    await tester.pumpAndSettle();

    expect(service.preferences.postTripAnswers, {'trip-a': false});
  });

  testWidgets('turning the question off does not open it', (tester) async {
    await pump(tester);

    await tapNotification(
      tester,
      actionId: NotificationService.silenceActionId,
    );

    expect(find.text(l.postTripDialogQuestion), findsNothing);
    expect(
      service.preferences.isAllowed(NotificationKind.postTripQuestion),
      isFalse,
    );
  });

  testWidgets('another kind being tapped does not open it', (tester) async {
    await pump(tester);

    await tester.runAsync(() => service.tap(NotificationKind.nextStopAlert));
    await tester.pumpAndSettle();

    expect(find.text(l.postTripDialogQuestion), findsNothing);
  });

  test('the wording asks, and does not demand a rating', () {
    // No stars, no score, and the Arabic is the phrase the design system set.
    expect(l.notifyPostTripTitle, 'وصلت بالسلامة؟');
    expect(l.notifyPostTripBody, contains('مش لازم تردّ'));
    expect(l.postTripDialogQuestion, isNot(contains('قيّم')));
  });
}
