import 'package:egypt_transport/core/presentation/mode_catalog.dart';
import 'package:egypt_transport/core/presentation/trip_presenter.dart';
import 'package:egypt_transport/core/presentation/view_models.dart';
import 'package:egypt_transport/data/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

/// These are the tests that matter most in this codebase.
///
/// The presenter is where four rules from `docs/design-system.md` are
/// enforced, and all four fail *plausibly*: a microbus with a number badge, a
/// metro line drawn as a pill, a two-hour walk presented as a trip. None of
/// those look like bugs on screen — they look like answers. So they are
/// pinned here rather than left to review.
void main() {
  const ar = TripPresenter(languageCode: 'ar');
  const en = TripPresenter(languageCode: 'en');

  group('rule: no route-number badge when has_line_number is false', () {
    test('a microbus leg gets no number badge', () {
      final plan = ar.plan(PlanResponse.fromJson(planMicrobus));
      final transit = plan.itineraries.first.legs.where((l) => l.isTransit);

      expect(transit, isNotEmpty);
      for (final leg in transit) {
        expect(leg.showNumberBadge, isFalse);
        expect(leg.numberBadgeText, isNull);
      }
    });

    test('and is identified by origin and destination instead', () {
      final plan = ar.plan(PlanResponse.fromJson(planMicrobus));
      final leg = plan.itineraries.first.legs.firstWhere((l) => l.isTransit);
      expect(leg.routeLabel, contains('→'));
    });

    test('a metro leg carries its line on the badge, not a second chip', () {
      // The metro does have line numbers, but the circular badge already
      // shows them. A number chip as well would print M1 twice.
      final plan = ar.plan(PlanResponse.fromJson(planMetro));
      final metro = plan.itineraries.first.legs
          .where((l) => l.badge.modeId == 'metro')
          .toList();

      expect(metro, isNotEmpty);
      expect(metro.map((l) => l.showNumberBadge), everyElement(false));
      expect(metro.map((l) => l.badge.metroLine), containsAll(['M1', 'M2']));
    });

    test('a numbered bus route does get a chip', () {
      final leg = ar.leg(Leg(
        mode: const ModeInfo(
            id: 'cta_bus', labelEn: 'CTA bus', labelAr: 'أتوبيس', otpMode: 'BUS'),
        isTransit: true,
        startTime: DateTime(2026, 9, 21, 8),
        endTime: DateTime(2026, 9, 21, 8, 30),
        durationMinutes: 30,
        distanceM: 5000,
        from: const Place(name: 'A', lat: 30, lon: 31),
        to: const Place(name: 'B', lat: 30, lon: 31),
        route: const RouteInfo(
            id: 'r', displayName: '381', hasLineNumber: true, shortName: '381'),
      ));

      expect(leg.showNumberBadge, isTrue);
      expect(leg.numberBadgeText, '381');
    });

    test('a route claiming a number but having none still gets no badge', () {
      // Defensive: a feed can set has_line_number with an empty short_name,
      // and an empty badge reads as missing data rather than as no number.
      final leg = ar.leg(Leg(
        mode: const ModeInfo(
            id: 'cta_bus', labelEn: 'CTA bus', labelAr: 'أتوبيس', otpMode: 'BUS'),
        isTransit: true,
        startTime: DateTime(2026, 9, 21, 8),
        endTime: DateTime(2026, 9, 21, 8, 30),
        durationMinutes: 30,
        distanceM: 5000,
        from: const Place(name: 'A', lat: 30, lon: 31),
        to: const Place(name: 'B', lat: 30, lon: 31),
        route: const RouteInfo(
          id: 'r',
          displayName: 'A → B',
          hasLineNumber: true,
          shortName: '   ',
        ),
      ));

      expect(leg.showNumberBadge, isFalse);
    });
  });

  group('rule: metro is a circle, everything else is a pill', () {
    test('metro legs take the circular badge and carry their line', () {
      final plan = ar.plan(PlanResponse.fromJson(planMetro));
      final metro = plan.itineraries.first.legs
          .where((l) => l.badge.modeId == 'metro');

      for (final leg in metro) {
        expect(leg.badge.shape, ModeBadgeShape.metroCircle);
        expect(leg.badge.metroLine, isNotNull);
      }
    });

    test('microbus legs take the pill and carry no line', () {
      final plan = ar.plan(PlanResponse.fromJson(planMicrobus));
      final bus = plan.itineraries.first.legs.where((l) => l.isTransit);

      for (final leg in bus) {
        expect(leg.badge.shape, ModeBadgeShape.pill);
        expect(leg.badge.metroLine, isNull);
      }
    });
  });

  group('rule: a walk-only itinerary is not a result', () {
    test('an out-of-coverage plan yields no itineraries at all', () {
      final plan = ar.plan(PlanResponse.fromJson(planNoCoverage));
      expect(plan.itineraries, isEmpty);
      expect(plan.hasResults, isFalse);
    });

    test('and keeps the server note so the screen can say why', () {
      final plan = ar.plan(PlanResponse.fromJson(planNoCoverage));
      expect(plan.note, contains('Greater Cairo'));
    });

    test('a late-night plan is dropped the same way', () {
      final plan = ar.plan(PlanResponse.fromJson(planWalkOnly));
      expect(plan.itineraries, isEmpty);
      expect(plan.note, isNotNull);
    });

    test('a real plan survives intact', () {
      final plan = ar.plan(PlanResponse.fromJson(planMetro));
      expect(plan.hasResults, isTrue);
      expect(plan.itineraries, hasLength(3));
    });
  });

  group('labels follow the requested language', () {
    test('Arabic uses the Arabic label', () {
      final plan = ar.plan(PlanResponse.fromJson(planMicrobus));
      final leg = plan.itineraries.first.legs.firstWhere((l) => l.isTransit);
      expect(leg.badge.label, 'ميكروباص');
    });

    test('English uses the English one', () {
      final plan = en.plan(PlanResponse.fromJson(planMicrobus));
      final leg = plan.itineraries.first.legs.firstWhere((l) => l.isTransit);
      expect(leg.badge.label, 'Microbus');
    });
  });

  group('summary badges', () {
    test('show transit only — a row of walk chips says nothing', () {
      final plan = ar.plan(PlanResponse.fromJson(planMetro));
      final badges = plan.itineraries.first.transitBadges;

      expect(badges, hasLength(2));
      expect(badges.map((b) => b.modeId), everyElement('metro'));
    });
  });

  group('stop badges', () {
    test('name every mode a real stop serves', () {
      final stops = StopsResponse.fromJson(stopsMoneeb);
      final badges = ar.stopBadges(stops.stops.first);

      expect(badges, isNotEmpty);
      expect(badges.map((b) => b.label), isNot(contains(anyOf(['', null]))));
      // A label that falls back to the raw id means the catalogue is missing
      // an entry the API can actually return.
      for (final badge in badges) {
        expect(ModeCatalog.knows(badge.modeId), isTrue,
            reason: '${badge.modeId} has no label in ModeCatalog');
      }
    });
  });
}
