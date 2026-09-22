import 'package:egypt_transport/core/location/location_service.dart';
import 'package:egypt_transport/core/network/api_failure.dart';
import 'package:egypt_transport/core/presentation/trip_presenter.dart';
import 'package:egypt_transport/core/settings/settings_cubit.dart';
import 'package:egypt_transport/core/storage/key_value_store.dart';
import 'package:egypt_transport/core/theme/app_theme.dart';
import 'package:egypt_transport/core/theme/contrast.dart';
import 'package:egypt_transport/core/theme/mode_theme.dart';
import 'package:egypt_transport/core/theme/tokens.dart';
import 'package:egypt_transport/core/widgets/app_error_view.dart';
import 'package:egypt_transport/data/models/models.dart';
import 'package:egypt_transport/data/repositories/trip_history.dart';
import 'package:egypt_transport/domain/entities/trip_endpoint.dart';
import 'package:egypt_transport/domain/repositories/planner_repository.dart';
import 'package:egypt_transport/features/about/view/about_page.dart';
import 'package:egypt_transport/features/itinerary/view/itinerary_page.dart';
import 'package:egypt_transport/features/results/view/results_page.dart';
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

/// Accessibility (#27).
///
/// A civic tool with a broad audience, in a typeface picked partly for
/// low-literacy legibility. The rest of that argument is here.
///
/// Four of the five acceptance criteria are machine-checkable and are checked
/// below. The fifth — that a screen reader announces this in Arabic a Cairene
/// would recognise — is not, and never will be from a widget test. Nothing in
/// this project has run on a phone, so TalkBack has never read any of it.
void main() {
  // ---------------------------------------------------------------- contrast

  /// Text that fails WCAG AA 4.5:1 and whose colour cannot move.
  ///
  /// Every mode chip draws its label **in the plate colour** on a 13% tint of
  /// itself — `docs/design-system.md`, and `.mc{color:var(--m-micro)}` in the
  /// prototype. That is the product's one colour system: orange *is* the
  /// 14-seater microbus's licence plate, and a reader identifies the vehicle
  /// by it at the kerb. Darkening the label until it passes would put a colour
  /// on screen with no plate behind it, and it would fail silently — nobody
  /// reviewing a diff sees that #D2620B became something else.
  ///
  /// So the shortfall is recorded rather than removed. The levers that remain
  /// are the label's **size and weight** (13px/w600 is below WCAG's "large
  /// text" threshold of 18.66px bold, which is why 4.5 rather than 3.0 is the
  /// bar), and that is a design decision for the maintainer, not a refactor.
  ///
  /// Asserted to the measured figure, so this table records a known shortfall
  /// without hiding a regression: move a colour and the number moves with it.
  const shortfalls = <String, double>{
    'microbus label on its tint over surface': 3.27,
    'microbus label on its tint over bg': 3.14,
    'microbus label on its tint over raise': 2.94,
    'tomnaya label on its tint over surface': 4.38,
    'tomnaya label on its tint over bg': 4.21,
    'tomnaya label on its tint over raise': 3.94,
    'cooperative label on its tint over bg': 4.37,
    'cooperative label on its tint over raise': 4.10,
    'walk label on its tint over surface': 2.76,
    'walk label on its tint over bg': 2.66,
    'walk label on its tint over raise': 2.49,
    'walk label on its tint over surface (dark)': 3.35,
    'walk label on its tint over bg (dark)': 3.70,
    'walk label on its tint over raise (dark)': 3.05,
    'cooperative label on its tint over raise (dark)': 4.98,
    'unknown label on its tint over raise (dark)': 4.89,
    // The disc, not its label. M3's teal is the operator's own colour, read
    // off the legend of the official network map — it is the datum, and the
    // page behind it is the near-white `bg`. The label on top clears AA; only
    // the disc's own edge against the page is soft. A circle with a line
    // number in it is not identified by its outline.
    'metro M3 disc on bg': 2.88,
  };

  group('contrast', () {
    /// `(name, foreground, background, minimum)`. Backgrounds are already
    /// composited: a translucent tint over an unknown ground has no ratio.
    List<(String, Color, Color, double)> pairs(
      Palette p,
      ModeColors m,
      String suffix,
    ) {
      final grounds = [
        ('surface', p.surface),
        ('bg', p.bg),
        ('raise', p.raise),
      ];
      return [
        // Body and heading text: AA normal, 4.5:1.
        for (final (name, ground) in grounds) ...[
          ('ink on $name', p.ink, ground, 4.5),
          ('ink2 on $name', p.ink2, ground, 4.5),
          ('accent on $name', p.accent, ground, 4.5),
          ('critical on $name', p.critical, ground, 4.5),
        ],
        ('accentInk on accent', p.accentInk, p.accent, 4.5),
        // The warning honesty panel: its body is `ink`, its tint is 10% warn.
        (
          'ink on the warning panel',
          p.ink,
          compositeOver(p.warn.withValues(alpha: 0.10), p.bg),
          4.5,
        ),
        // The 4px stripe is a non-text indicator, so 3.0 (WCAG 1.4.11).
        (
          'warn stripe on the warning panel',
          p.warn,
          compositeOver(p.warn.withValues(alpha: 0.10), p.bg),
          3.0,
        ),
        // Mode chips: label in the plate colour on a 13% tint of itself.
        for (final (name, ground) in grounds)
          for (final entry in <String, Color>{
            'microbus': m.microbus,
            'tomnaya': m.tomnaya,
            'cooperative': m.cooperative,
            'formalBus': m.formalBus,
            'walk': m.walk,
            'unknown': m.unknown,
          }.entries)
            (
              '${entry.key} label on its tint over $name',
              entry.value,
              compositeOver(entry.value.withValues(alpha: 0.13), ground),
              4.5,
            ),
        // Metro badges. The label is chosen for legibility by `legibleOn`, so
        // this is a real assertion rather than a record of the palette.
        for (final line in m.metroLines.entries) ...[
          (
            'metro ${line.key} label on its disc',
            legibleOn(
              line.value,
              dark: Palette.light.ink,
              light: Palette.light.surface,
            ),
            line.value,
            4.5,
          ),
          // The disc itself against the page: a non-text indicator.
          ('metro ${line.key} disc on bg', line.value, p.bg, 3.0),
        ],
      ].map((e) => (e.$1 + suffix, e.$2, e.$3, e.$4)).toList();
    }

    for (final (theme, p, m) in [
      ('light', Palette.light, ModeColors.light),
      ('dark', Palette.dark, ModeColors.dark),
    ]) {
      test('$theme theme reaches WCAG AA, or records why not', () {
        final suffix = theme == 'dark' ? ' (dark)' : '';
        for (final (name, fg, bg, minimum) in pairs(p, m, suffix)) {
          final measured = contrastRatio(fg, bg);
          final recorded = shortfalls[name];
          if (recorded != null) {
            expect(
              measured,
              closeTo(recorded, 0.02),
              reason:
                  '$name measured ${measured.toStringAsFixed(2)}, recorded as '
                  '$recorded. A recorded shortfall is a fixed number: if the '
                  'colour moved, move the number in the same commit.',
            );
          } else {
            expect(
              measured,
              greaterThanOrEqualTo(minimum),
              reason:
                  '$name is ${measured.toStringAsFixed(2)}:1, below $minimum. '
                  'Either raise it or record it in `shortfalls` with the '
                  'reason the colour cannot move.',
            );
          }
        }
      });
    }

    test('every recorded shortfall is still a pair the app draws', () {
      final names = {
        for (final (theme, p, m) in [
          ('light', Palette.light, ModeColors.light),
          ('dark', Palette.dark, ModeColors.dark),
        ])
          ...pairs(p, m, theme == 'dark' ? ' (dark)' : '').map((e) => e.$1),
      };
      expect(
        shortfalls.keys.where((k) => !names.contains(k)),
        isEmpty,
        reason: 'A recorded shortfall that no longer names a real pair is a '
            'stale excuse. Delete it.',
      );
    });

    test('a metro label is never white where dark would read better', () {
      // The prototype draws every line badge with `color:#fff`. That fails on
      // M3 in light (3.00:1) and on all three lines in dark, where the line
      // colours are lightened for the dark ground. The disc keeps the
      // operator's own colour byte for byte; only the glyph on top moves.
      for (final m in [ModeColors.light, ModeColors.dark]) {
        for (final line in m.metroLines.values) {
          final white = Palette.light.surface;
          final chosen = legibleOn(
            line,
            dark: Palette.light.ink,
            light: white,
          );
          expect(
            contrastRatio(chosen, line),
            greaterThanOrEqualTo(contrastRatio(white, line)),
          );
        }
      }
    });
  });

  // ------------------------------------------------------------------ screens

  Widget host(
    Widget child, {
    Locale locale = const Locale('ar'),
    Brightness brightness = Brightness.light,
    double textScale = 1.0,
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
        // Below MaterialApp's own MediaQuery, so it is the scale the widgets
        // actually see rather than one the app rebuilds away.
        builder: (context, inner) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: inner!,
        ),
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
          RepositoryProvider<TripHistory>.value(
            value: TripHistory(InMemoryStore()),
          ),
        ],
        child: child,
      ),
    );
  }

  const presenter = TripPresenter(languageCode: 'ar');
  const from = TripEndpoint(label: 'حلوان', point: GeoPoint(29.849, 31.334));
  const to = TripEndpoint(
    label: 'شبرا الخيمة',
    point: GeoPoint(30.122, 31.245),
  );

  Widget results(Map<String, dynamic> plan) => withRepo(
    ResultsPage(
      from: from,
      to: to,
      departAt: DateTime(2026, 9, 21, 8),
    ),
    FakeRepository(planResponse: PlanResponse.fromJson(plan)),
  );

  Widget itinerary(Map<String, dynamic> json) {
    final plan = presenter.plan(PlanResponse.fromJson(json));
    return ItineraryPage(
      itinerary: plan.itineraries.first,
      attribution: plan.attribution,
    );
  }

  /// Every screen a passenger can reach, as `(name, builder)`.
  ///
  /// Built lazily: a page built once and pumped into eight tests would carry
  /// the first test's Cubit and its already-settled state into the rest.
  final screens = <String, Widget Function()>{
    'search': () => withRepo(const SearchPage(), FakeRepository()),
    'results': () => results(planMetro),
    'itinerary': () => itinerary(planMetro),
    'microbus itinerary': () => itinerary(planMicrobus),
    'nothing found': () => results(planNoCoverage),
    'stop picker': () => withRepo(
      StopPickerPage(
        title: 'من فين',
        presenter: presenter,
        repository: FakeRepository(
          stopsResponse: StopsResponse.fromJson(stopsMoneeb),
        ),
      ),
      FakeRepository(),
    ),
    'about': () => withRepo(const AboutPage(), FakeRepository()),
    'error': () => const AppErrorView(
      failure: ApiFailure(FailureKind.offline),
    ),
  };

  // ------------------------------------------------------------ text scaling

  group('text scaling to 200%', () {
    for (final entry in screens.entries) {
      for (final locale in const [Locale('ar'), Locale('en')]) {
        for (final brightness in Brightness.values) {
          testWidgets(
            '${entry.key} survives 2x in ${locale.languageCode}, '
            '${brightness.name}',
            (tester) async {
              // A small, cheap Android — the fleet this app is for. The design
              // frame is 390x844 and every spacing token is scaled to it, so a
              // layout that fits at 2x on a large phone can still clip here.
              tester.view.physicalSize = const Size(320, 640);
              tester.view.devicePixelRatio = 1.0;
              addTearDown(tester.view.reset);

              await tester.pumpWidget(
                host(
                  entry.value(),
                  locale: locale,
                  brightness: brightness,
                  textScale: 2.0,
                ),
              );
              await tester.pumpAndSettle();

              expect(
                tester.takeException(),
                isNull,
                reason:
                    'Text at 200% must not clip. A fixed height with text in '
                    'it is the usual cause.',
              );
            },
          );
        }
      }
    }
  });

  // ------------------------------------------------------------- tap targets

  group('tap targets and labels', () {
    for (final entry in screens.entries) {
      testWidgets('${entry.key} meets the 48dp minimum', (tester) async {
        await tester.pumpWidget(host(entry.value()));
        await tester.pumpAndSettle();
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      });

      testWidgets('${entry.key} has no unlabelled control', (tester) async {
        await tester.pumpWidget(host(entry.value()));
        await tester.pumpAndSettle();
        // A colour-coded row that a screen reader announces as "button" and
        // nothing else is the failure this catches.
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      });
    }
  });

  // --------------------------------------------------------------- semantics

  group('semantics', () {
    testWidgets('an itinerary card is announced as one thing, not eight', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(results(planMetro)));
      await tester.pumpAndSettle();

      // "45 min", "08:00 – 08:45", "Metro", "M1", "1 transfer", "700 m" as six
      // separate stops is not a summary of anything. Merged, it is the same
      // sentence a sighted reader gets from the card at a glance.
      final card = tester.getSemantics(
        find.byType(InkWell).first,
      );
      expect(card.label, contains('دقيقة'));
      expect(card.getSemanticsData().flagsCollection.isButton, isTrue);
      handle.dispose();
    });

    testWidgets('a metro badge says its line once', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(itinerary(planMetro)));
      await tester.pumpAndSettle();

      // The circle *is* the line number. It once printed "M1" twice on screen;
      // the same duplication in the semantics tree is just as wrong and
      // nobody can see it.
      expect(
        find.bySemanticsLabel(RegExp(r'^M1$')),
        findsNothing,
        reason: 'The disc label must be merged into the badge, not announced '
            'on its own.',
      );
      handle.dispose();
    });

    testWidgets('an endpoint field is a button that says what it holds', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(withRepo(const SearchPage(), FakeRepository())),
      );
      await tester.pumpAndSettle();

      final field = tester.getSemantics(
        find
            .ancestor(
              of: find.text('من فين'),
              matching: find.byType(InkWell),
            )
            .first,
      );
      expect(field.getSemanticsData().flagsCollection.isButton, isTrue);
      expect(field.label, contains('من فين'));
      handle.dispose();
    });
  });

  // --------------------------------------------------------------- direction

  group('reading order', () {
    testWidgets('the results header names the trip in reading order', (
      tester,
    ) async {
      for (final (locale, arrow) in const [
        (Locale('ar'), '←'),
        (Locale('en'), '→'),
      ]) {
        await tester.pumpWidget(host(results(planMetro), locale: locale));
        await tester.pumpAndSettle();

        // Arabic reads right to left, so the glyph between the endpoints is
        // not the same glyph. `tripArrow` already knows that; a hardcoded one
        // pointed backwards in English.
        expect(
          find.textContaining(arrow, findRichText: true),
          findsWidgets,
          reason: 'the ${locale.languageCode} header should use $arrow',
        );
      }
    });

    testWidgets('the leg separator points the way the card reads', (
      tester,
    ) async {
      await tester.pumpWidget(host(results(planMetro)));
      await tester.pumpAndSettle();

      // `arrow_back_rounded` carries `matchTextDirection: true`, so it is
      // mirrored into pointing *against* the flow in both locales — left in
      // English, right in Arabic. Both are backwards.
      expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
    });
  });
}
