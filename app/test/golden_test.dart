import 'dart:convert';
import 'dart:io';

import 'package:egypt_transport/core/presentation/trip_presenter.dart';
import 'package:egypt_transport/core/presentation/view_models.dart';
import 'package:egypt_transport/core/theme/app_theme.dart';
import 'package:egypt_transport/core/theme/tokens.dart';
import 'package:egypt_transport/core/widgets/mode_badge.dart';
import 'package:egypt_transport/data/models/models.dart';
import 'package:egypt_transport/features/itinerary/view/itinerary_page.dart';
import 'package:egypt_transport/features/results/widgets/itinerary_card.dart';
import 'package:egypt_transport/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

/// Pictures of the colour system.
///
/// ### What these protect
///
/// The mode colours are the one colour system in this product, and every one
/// of them is a real Egyptian licence-plate colour — orange for the microbus,
/// blue for the tomnaya, grey for the cooperative. Beside them sit two rules
/// with no textual trace at all: **metro lines are circles and everything
/// else is a pill**, which is the only thing keeping M1's blue apart from the
/// tomnaya's, and **a metro leg gets no number chip**, because the circle
/// already is the line number.
///
/// None of that can be asserted in words. A unit test can check that
/// `TripPresenter` returned `ModeBadgeShape.metroCircle`; it cannot notice
/// that a refactor swapped two entries in `ModeColors`, dropped the 13% tint,
/// or let the dark theme fall back to the light palette. Those are the
/// failures that look plausible on screen — a microbus in tomnaya blue is
/// still a chip with a colour in it.
///
/// So: a catalogue, in both themes, drawn by the real widgets.
///
/// ### Everything here comes out of `TripPresenter`
///
/// No `ModeBadgeVm` is constructed by hand anywhere in this file. Badges are
/// built by handing the presenter wire models, because the thing most worth
/// catching is a presenter rule that silently stops firing — a metro leg
/// drawn as a pill, a microbus that grows a route-number badge. Building the
/// view models directly would photograph the widgets while skipping the layer
/// that decides what they are handed.
///
/// ### Regenerating
///
///     cd app && flutter test --update-goldens test/golden_test.dart
///
/// Then look at the diff before committing it. A golden is worth exactly what
/// the person regenerating it looked at, which is why these images are
/// cropped to their subject: the badges golden contains badges and nothing
/// else, so there is no app chrome for a real change to hide behind.
///
/// **These PNGs go stale the moment #27 (accessibility) lands.** That branch
/// changes two things captured here: the metro numeral stops being hardcoded
/// white and becomes whichever of near-black and white has more contrast
/// against the line colour — M3 in light, all three lines in dark — and
/// `bodySmall` moves from `ink3` to `ink2`, which is the card's
/// "transfers · walk" line. Regenerate after that rebase and check the diff
/// shows those two things and nothing else. That check is the point of the
/// collision, not an inconvenience caused by it.
///
/// ### Fonts: the real ones, because the test font invents a bug
///
/// A widget test renders with Flutter's own test font unless the bundled
/// faces are loaded explicitly through a `FontLoader`. The first draft of
/// this file let the test font stand, on the theory that a glyph drawn as a
/// solid block in the text colour makes a wrong hue easier to see. That was
/// wrong, and the images said so: the test font advances roughly one em per
/// codepoint, so `ميني باص تعاوني` came out two to three times wider than
/// IBM Plex draws it. Every one of the six tests failed on overflow — 93 and
/// 168 pixels in the catalogue's own rows, and `_LegTile` inside the real
/// `ItineraryPage` over its width too. The goldens would have been pictures
/// of a layout failure that does not exist, with debug stripes across the
/// part that matters.
///
/// So the three bundled faces are loaded from `assets/fonts/` below. Note
/// what this does *not* buy: portability. A golden is tied to the machine
/// that rasterised it whatever font is in it, which is why the regeneration
/// line above exists and why these are reviewed by eye rather than trusted
/// blind. What it buys is that the pixels are the app's pixels — Arabic set
/// in the face the app ships, at the width it really occupies, which is the
/// only version of these screens worth photographing.
///
/// This also means a font file changing is a golden failure. That is correct:
/// swapping the UI face is not a silent change in a product whose Arabic
/// legibility is the reason Readex Pro and IBM Plex Sans Arabic were chosen.
///
/// Icons are the exception and stay as empty squares: the Material icon font
/// is not part of a widget test's asset bundle, and loading it would mean
/// reaching into whatever `FLUTTER_ROOT` happens to be on this machine —
/// a real portability problem traded for a glyph. No mode colour is carried
/// by an icon, so nothing here depends on it.
///
/// ### Two things in the images that are the app's, not the test's
///
/// The clock lines read `05:00 – 07:10` for a trip the fixture departs at
/// `08:00+03:00`. `DateTime.parse` returns a **UTC** `DateTime` when the
/// string carries an offset, and `clockTime` prints `.hour` off it, so every
/// time in the app is drawn three hours early in Cairo. It is captured here
/// rather than worked around because that is what the screen does today, and
/// a golden that quietly corrected it would be the only place the bug is
/// invisible. (It does mean these images do not depend on the machine's
/// timezone, which is a genuine help — but it is a side effect, not a
/// design.)
///
/// The microbus card shows three chips for an itinerary the API calls two
/// transfers, because two of its three microbus legs are consecutive with no
/// walk between them. That is the real captured response, not a fixture
/// edited to look tidy.
/// Where this platform's golden set lives, and whether it exists.
///
/// **Goldens are per-platform here, and that is not paranoia.** Run this
/// suite on Linux against a set rasterised on Windows and `badges_*` fails
/// with *"image sizes do not match"* — not a tolerance problem, a layout
/// difference: the same Arabic string measures differently, so the catalogue
/// sizes itself differently. `cards_*` and `legs_*` come out 2.75%–5.84%
/// apart. Measured on `ubuntu-latest` against the Windows set, 2026-09-23.
///
/// A single shared set would therefore be green in exactly one place. Since
/// CLAUDE.md asks for `flutter test` before and after every change, and CI
/// gates every push, "one place" is not good enough for either.
final String _platform = Platform.operatingSystem;

String _golden(String name) => 'goldens/$_platform/$name.png';

/// `null` to run, or the reason these are being skipped.
///
/// A platform with no committed golden set **skips with a reason** rather
/// than failing. A red suite on a platform nobody has generated for asserts
/// nothing, and a permanently red check is one people learn to ignore — at
/// which point it stops catching the thing it exists for. A skip says what is
/// missing and how to supply it, and shows up in the CI log either way.
///
/// `--update-goldens` writes whatever set is missing, so generating one is
/// the documented one-liner below rather than a special mode.
final String? _skipReason = Directory('test/goldens/$_platform').existsSync()
    ? null
    : 'No golden set for $_platform. Generate one with '
          '`flutter test --update-goldens test/golden_test.dart` on this '
          'platform and commit `app/test/goldens/$_platform/`. A set from '
          'another platform cannot stand in: see the note above `_golden`.';

/// Call first in every golden body: skips with the reason, or returns false.
///
/// `markTestSkipped` rather than `testWidgets(skip:)`, which takes a bool and
/// so cannot carry the reason -- and the reason is the whole point. Without
/// it a skipped golden is indistinguishable from a golden nobody wrote.
bool _skippedForPlatform() {
  final reason = _skipReason;
  if (reason == null) return false;
  markTestSkipped(reason);
  return true;
}

void main() {
  const presenter = TripPresenter(languageCode: 'ar');

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // The families and files declared in `pubspec.yaml`. Kept in that order
    // so that adding a weight there and forgetting it here shows up as a
    // golden diff rather than as nothing at all.
    await _loadFont('ReadexPro', ['ReadexPro-Variable.ttf']);
    await _loadFont('IBMPlexSansArabic', [
      'IBMPlexSansArabic-Regular.ttf',
      'IBMPlexSansArabic-Medium.ttf',
      'IBMPlexSansArabic-SemiBold.ttf',
      'IBMPlexSansArabic-Bold.ttf',
    ]);
    await _loadFont('IBMPlexMono', [
      'IBMPlexMono-Regular.ttf',
      'IBMPlexMono-SemiBold.ttf',
    ]);
  });

  /// The design frame, pinned.
  ///
  /// `Insets`, `Radii` and every `.sp` in the app are screenutil-scaled
  /// against 390x844, and screenutil takes its scale from the surface it is
  /// built on. A widget test's default surface is 800x600, so an unpinned
  /// golden would capture a layout at roughly double the design figures — a
  /// picture of something no phone renders. One device pixel per logical
  /// pixel keeps the images small and their measurements readable.
  void useDesignFrame(WidgetTester tester) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
  }

  Widget host(Widget child, {required Brightness brightness}) {
    return ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        // Arabic is the product's first language, not a variant of it. The
        // direction follows from the locale, as it does in the app.
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: brightness == Brightness.light
            ? AppTheme.light()
            : AppTheme.dark(),
        home: child,
      ),
    );
  }

  // --------------------------------------------------------------- material

  /// A leg of exactly the shape the server sends, with its mode and route
  /// swapped out.
  ///
  /// The captured fixtures hold microbus and metro legs only — nobody ever
  /// captured a plan containing a tomnaya, a cooperative minibus or a CTA
  /// bus, and the catalogue needs all of them. Hand-writing a wire map here
  /// would create a second, drifting copy of the contract in `api/models.py`;
  /// deep-copying a real leg and replacing two keys leaves every other field
  /// exactly what the live API produced on 2026-09-21.
  Map<String, dynamic> legLike(
    Map<String, dynamic> source, {
    required String modeId,
    required String labelAr,
    required String labelEn,
    String otpMode = 'BUS',
    bool withRoute = true,
    String? shortName,
    bool hasLineNumber = false,
    String? displayName,
  }) {
    final leg = jsonDecode(jsonEncode(source)) as Map<String, dynamic>;
    leg['mode'] = <String, dynamic>{
      'id': modeId,
      'label_en': labelEn,
      'label_ar': labelAr,
      'otp_mode': otpMode,
    };
    if (!withRoute) {
      leg['route'] = null;
      return leg;
    }
    leg['route'] =
        (leg['route'] as Map<String, dynamic>? ?? <String, dynamic>{})
          ..['short_name'] = shortName
          ..['has_line_number'] = hasLineNumber
          ..['display_name'] = displayName ?? labelAr;
    return leg;
  }

  Map<String, dynamic> legOf(Map<String, dynamic> plan, int index) =>
      ((plan['itineraries'] as List).first
              as Map<String, dynamic>)['legs'][index]
          as Map<String, dynamic>;

  /// Every pill in the system, in the order `ModeColors` declares them.
  ///
  /// `box` and `peugeot` are absent on purpose: they share the microbus
  /// orange because they carry orange plates too, and are told apart by their
  /// label rather than their hue. A picture of them would be a picture of
  /// microbus.
  ///
  /// The last row is the one that must *not* acquire a colour — `transit` is
  /// what the client falls back to for a mode this build has never heard of,
  /// and it resolves to `unknown`. A guess there would be a lie about which
  /// vehicle to board.
  List<ModeBadgeVm> pillBadges() {
    final microbus = legOf(planMicrobus, 1);
    final walk = legOf(planMicrobus, 0);

    final legs = <Map<String, dynamic>>[
      microbus,
      legLike(
        microbus,
        modeId: 'tomnaya',
        labelAr: 'تمنايا',
        labelEn: 'Tomnaya',
      ),
      legLike(
        microbus,
        modeId: 'coop_minibus',
        labelAr: 'ميني باص تعاوني',
        labelEn: 'Cooperative minibus',
      ),
      legLike(
        microbus,
        modeId: 'cta_bus',
        labelAr: 'أتوبيس النقل العام',
        labelEn: 'CTA bus',
        shortName: '381',
        hasLineNumber: true,
      ),
      legLike(
        walk,
        modeId: 'walk',
        labelAr: 'سيرًا',
        labelEn: 'Walk',
        otpMode: 'WALK',
        withRoute: false,
      ),
      legLike(
        microbus,
        modeId: 'transit',
        labelAr: 'مواصلات',
        labelEn: 'Transit',
        withRoute: false,
      ),
    ];

    return legs
        .map((json) => presenter.leg(Leg.fromJson(json)).badge)
        .toList(growable: false);
  }

  /// M1, M2, M3 — and a metro leg whose line cannot be resolved.
  ///
  /// M3 is here although no captured plan uses it: it is our own feed, its
  /// teal sits on the same hue as the formal-bus pill, and the circle is the
  /// only thing separating those two. The fourth badge must stay `unknown`
  /// grey rather than borrow M1's blue.
  List<ModeBadgeVm> metroBadges() {
    final m1 = legOf(planMetro, 1);
    final m2 = legOf(planMetro, 3);

    final legs = <Map<String, dynamic>>[
      m1,
      m2,
      legLike(
        m1,
        modeId: 'metro',
        labelAr: 'مترو الأنفاق',
        labelEn: 'Cairo Metro',
        otpMode: 'SUBWAY',
        shortName: 'M3',
        hasLineNumber: true,
        displayName: 'M3',
      ),
      legLike(
        m1,
        modeId: 'metro',
        labelAr: 'مترو الأنفاق',
        labelEn: 'Cairo Metro',
        otpMode: 'SUBWAY',
        withRoute: false,
      ),
    ];

    return legs
        .map((json) => presenter.leg(Leg.fromJson(json)).badge)
        .toList(growable: false);
  }

  /// One itinerary carrying all three number-badge outcomes at once: a
  /// microbus that must not have a chip, a CTA bus that must, and a metro leg
  /// that must not although its route does have a number.
  ItineraryVm mixedItinerary() {
    final source =
        jsonDecode(jsonEncode((planMicrobus['itineraries'] as List).first))
            as Map<String, dynamic>;
    final microbus = legOf(planMicrobus, 1);

    source['legs'] = <Map<String, dynamic>>[
      microbus,
      legLike(
        microbus,
        modeId: 'cta_bus',
        labelAr: 'أتوبيس النقل العام',
        labelEn: 'CTA bus',
        shortName: '381',
        hasLineNumber: true,
      ),
      legOf(planMetro, 1),
    ];

    return presenter.itinerary(Itinerary.fromJson(source));
  }

  // ------------------------------------------------------------------ tests

  group('badge catalogue', () {
    for (final brightness in Brightness.values) {
      testWidgets('every mode, in ${brightness.name}', (tester) async {
        if (_skippedForPlatform()) return;
        useDesignFrame(tester);

        final pills = pillBadges();
        final metros = metroBadges();

        // Drawn *and* asserted: a golden regenerated carelessly would
        // swallow this, and it is the rule the picture exists to hold.
        expect(
          metros.every((b) => b.shape == ModeBadgeShape.metroCircle),
          isTrue,
        );
        expect(pills.every((b) => b.shape == ModeBadgeShape.pill), isTrue);

        await tester.pumpWidget(
          host(
            Center(
              child: _Catalogue(pills: pills, metros: metros),
            ),
            brightness: brightness,
          ),
        );
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(_Catalogue),
          matchesGoldenFile(_golden('badges_${brightness.name}')),
        );
      });
    }
  });

  group('itinerary card', () {
    for (final brightness in Brightness.values) {
      testWidgets('metro transfer and microbus chain, in ${brightness.name}', (
        tester,
      ) async {
        if (_skippedForPlatform()) return;
        useDesignFrame(tester);

        final metro = presenter.plan(PlanResponse.fromJson(planMetro));
        final microbus = presenter.plan(PlanResponse.fromJson(planMicrobus));

        // The metro itinerary is M1 → interchange → M2, so its card is the
        // one place a transfer arrow sits between two circles. The microbus
        // itinerary is three legs with no route numbers anywhere, which is
        // what most of this network looks like.
        expect(metro.itineraries.first.transfers, 1);
        expect(microbus.itineraries.first.transitBadges.length, 3);

        await tester.pumpWidget(
          host(
            Center(
              child: _Cards(
                itineraries: [
                  metro.itineraries.first,
                  microbus.itineraries.first,
                ],
              ),
            ),
            brightness: brightness,
          ),
        );
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(_Cards),
          matchesGoldenFile(_golden('cards_${brightness.name}')),
        );
      });
    }
  });

  group('itinerary screen', () {
    for (final brightness in Brightness.values) {
      testWidgets('the number-badge rule, in ${brightness.name}', (
        tester,
      ) async {
        if (_skippedForPlatform()) return;
        useDesignFrame(tester);

        final itinerary = mixedItinerary();
        final attribution = PlanResponse.fromJson(planMetro).attribution;

        expect(itinerary.legs.map((l) => l.showNumberBadge), [
          false,
          true,
          false,
        ]);

        await tester.pumpWidget(
          host(
            ItineraryPage(itinerary: itinerary, attribution: attribution),
            brightness: brightness,
          ),
        );
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(ItineraryPage),
          matchesGoldenFile(_golden('legs_${brightness.name}')),
        );
      });
    }
  });
}

/// The badges, laid out as plainly as they can be.
///
/// Deliberately not a screen. Nothing here is app chrome, so a change to the
/// scaffold, the app bar or a page's padding cannot move these pixels — the
/// only things that can are the badge widgets and the colours they read.
/// Each badge appears at both sizes the app uses it at, because `compact` is
/// a second set of measurements that nothing else checks.
class _Catalogue extends StatelessWidget {
  const _Catalogue({required this.pills, required this.metros});

  final List<ModeBadgeVm> pills;
  final List<ModeBadgeVm> metros;

  @override
  Widget build(BuildContext context) {
    // The boundary is what crops the PNG. `matchesGoldenFile` captures the
    // nearest enclosing repaint boundary, so without one every golden would
    // be the whole 390x844 surface with the subject somewhere in the middle.
    return RepaintBoundary(
      child: Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        padding: EdgeInsets.all(Insets.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final badge in pills) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ModeBadge(badge),
                  SizedBox(width: Insets.sm),
                  ModeBadge(badge, compact: true),
                ],
              ),
              SizedBox(height: Insets.sm),
            ],
            SizedBox(height: Insets.md),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final badge in metros) ...[
                  ModeBadge(badge),
                  SizedBox(width: Insets.xs),
                  ModeBadge(badge, compact: true),
                  SizedBox(width: Insets.lg),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Registers one bundled family from `assets/fonts/`.
///
/// Read off disk rather than through `rootBundle`: a widget test has no asset
/// bundle unless one is built for it, and the working directory here is the
/// package root — the same assumption `fixtures.dart` makes.
Future<void> _loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final name in files) {
    final bytes = File('assets/fonts/$name').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

/// Cards on the ground they sit on, at the width the results list gives them.
class _Cards extends StatelessWidget {
  const _Cards({required this.itineraries});

  final List<ItineraryVm> itineraries;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        // The design frame's width, so a card is as wide here as it is in
        // the results list.
        width: 390,
        color: Theme.of(context).scaffoldBackgroundColor,
        padding: EdgeInsets.all(Insets.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final itinerary in itineraries) ...[
              ItineraryCard(itinerary: itinerary),
              SizedBox(height: Insets.md),
            ],
          ],
        ),
      ),
    );
  }
}
