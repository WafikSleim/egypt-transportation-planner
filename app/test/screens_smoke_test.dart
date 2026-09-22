import 'package:egypt_transport/core/presentation/trip_presenter.dart';
import 'package:egypt_transport/core/settings/settings_cubit.dart';
import 'package:egypt_transport/core/location/location_service.dart';
import 'package:egypt_transport/core/storage/key_value_store.dart';
import 'package:egypt_transport/core/theme/app_theme.dart';
import 'package:egypt_transport/data/models/models.dart';
import 'package:egypt_transport/domain/repositories/planner_repository.dart';
import 'package:egypt_transport/features/itinerary/view/itinerary_page.dart';
import 'package:egypt_transport/features/results/view/results_page.dart';
import 'package:egypt_transport/domain/entities/trip_endpoint.dart';
import 'package:egypt_transport/features/search/view/search_page.dart';
import 'package:egypt_transport/features/stops/view/stop_picker_page.dart';
import 'package:egypt_transport/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_location_service.dart';
import 'fake_repository.dart';
import 'fixtures.dart';

/// Does it actually build and render?
///
/// These are deliberately shallow. They exist to catch the failures that are
/// invisible in a unit test and obvious on a phone: a theme extension that
/// was never registered, a localisation key that does not exist, a layout
/// that overflows, a `const` widget reading a screenutil-scaled token before
/// screenutil is initialised.
void main() {
  Widget host(
    Widget child, {
    Locale locale = const Locale('ar'),
    Brightness brightness = Brightness.light,
  }) {
    return ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      builder: (context, _) => MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: brightness == Brightness.light
            ? AppTheme.light()
            : AppTheme.dark(),
        home: child,
      ),
    );
  }

  Widget withRepo(Widget child, PlannerRepository repo) {
    return MultiBlocProvider(
      providers: [BlocProvider(create: (_) => SettingsCubit(InMemoryStore()))],
      child: MultiRepositoryProvider(
        providers: [
          RepositoryProvider<PlannerRepository>.value(value: repo),
          RepositoryProvider<LocationService>.value(
            value: FakeLocationService(),
          ),
        ],
        child: child,
      ),
    );
  }

  group('search screen', () {
    for (final brightness in Brightness.values) {
      testWidgets('renders in ${brightness.name} without overflowing', (
        tester,
      ) async {
        await tester.pumpWidget(
          host(
            withRepo(const SearchPage(), FakeRepository()),
            brightness: brightness,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('رايح فين النهاردة؟'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the English port renders too', (tester) async {
      await tester.pumpWidget(
        host(
          withRepo(const SearchPage(), FakeRepository()),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Where are you going today?'), findsOneWidget);
    });

    testWidgets('cannot search with nothing chosen', (tester) async {
      await tester.pumpWidget(
        host(withRepo(const SearchPage(), FakeRepository())),
      );
      await tester.pumpAndSettle();

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });
  });

  group('itinerary screen', () {
    const presenter = TripPresenter(languageCode: 'ar');

    testWidgets('a microbus trip shows no route-number badge', (tester) async {
      final plan = presenter.plan(PlanResponse.fromJson(planMicrobus));

      await tester.pumpWidget(
        host(
          ItineraryPage(
            itinerary: plan.itineraries.first,
            attribution: plan.attribution,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The mode chip is present, and the route is named by its endpoints.
      expect(find.textContaining('ميكروباص'), findsWidgets);
      expect(find.textContaining('→'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a metro trip shows its line badges', (tester) async {
      final plan = presenter.plan(PlanResponse.fromJson(planMetro));

      await tester.pumpWidget(
        host(
          ItineraryPage(
            itinerary: plan.itineraries.first,
            attribution: plan.attribution,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Exactly one M1: the circular line badge, with no duplicate number
      // chip beside it. M2 is further down the list, so it has to be
      // scrolled to before it is built.
      expect(find.text('M1'), findsOneWidget);

      await tester.dragUntilVisible(
        find.text('M2'),
        find.byType(ListView),
        const Offset(0, -240),
      );
      expect(find.text('M2'), findsOneWidget);
    });

    testWidgets('the attribution is rendered verbatim', (tester) async {
      final plan = presenter.plan(PlanResponse.fromJson(planMetro));

      await tester.pumpWidget(
        host(
          ItineraryPage(
            itinerary: plan.itineraries.first,
            attribution: plan.attribution,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // It lives at the foot of a long list, so it has to be scrolled to
      // before it is built at all.
      await tester.dragUntilVisible(
        find.textContaining('Transport for Cairo'),
        find.byType(ListView),
        const Offset(0, -300),
      );

      expect(find.textContaining('Transport for Cairo'), findsWidgets);
    });
  });

  group('nothing-found screen', () {
    Widget results(FakeRepository repo, {Locale locale = const Locale('ar')}) =>
        host(
          withRepo(
            ResultsPage(
              from: const TripEndpoint(
                label: 'A',
                point: GeoPoint(25.68, 32.63),
              ),
              to: const TripEndpoint(label: 'B', point: GeoPoint(25.70, 32.65)),
              departAt: DateTime(2026, 9, 21, 8),
            ),
            repo,
          ),
          locale: locale,
        );

    testWidgets('speaks Arabic rather than the server diagnostic', (
      tester,
    ) async {
      // The emptiest screen in the app, and the most common one outside the
      // covered area. Showing the server's diagnostic here would make it the
      // one place an Arabic-first app switches to English - with a bounding
      // box in decimal degrees, inside an RTL column.
      final repo = FakeRepository(
        planResponse: PlanResponse.fromJson(planNoCoverage),
      );

      await tester.pumpWidget(results(repo));
      await tester.pumpAndSettle();

      expect(find.text('لسه مامعندناش بيانات عن المنطقة دي'), findsOneWidget);
      expect(find.textContaining('Coverage is Greater Cairo'), findsNothing);
    });

    testWidgets('a late-night search blames the hour, in Arabic', (
      tester,
    ) async {
      final repo = FakeRepository(
        planResponse: PlanResponse.fromJson(planWalkOnly),
      );

      await tester.pumpWidget(results(repo));
      await tester.pumpAndSettle();

      expect(find.text('مفيش مواصلات دلوقتي'), findsOneWidget);
    });
  });

  group('stop picker', () {
    testWidgets('states that search matches from the start of a name', (
      tester,
    ) async {
      final repo = FakeRepository(
        stopsResponse: StopsResponse.fromJson(stopsMoneeb),
      );

      await tester.pumpWidget(
        host(
          StopPickerPage(
            title: 'من فين',
            repository: repo,
            presenter: const TripPresenter(languageCode: 'ar'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('البحث بيبدأ من أول الاسم'), findsOneWidget);
    });

    testWidgets('shows stops once a query is typed', (tester) async {
      final repo = FakeRepository(
        stopsResponse: StopsResponse.fromJson(stopsMoneeb),
      );

      await tester.pumpWidget(
        host(
          StopPickerPage(
            title: 'من فين',
            repository: repo,
            presenter: const TripPresenter(languageCode: 'ar'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'المنيب');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.textContaining('المنيب'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}
