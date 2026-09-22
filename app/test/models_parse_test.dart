import 'package:egypt_transport/data/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  group('PlanResponse parses a real metro itinerary', () {
    late PlanResponse response;

    setUp(() => response = PlanResponse.fromJson(planMetro));

    test('legs carry their endpoints under the `from` key', () {
      // FastAPI serialises by alias, so the wire key is `from`, not the
      // `from_` the Python model declares. Guessing this wrong produces a leg
      // with an empty origin and no error anywhere.
      final leg = response.itineraries.first.legs.first;
      expect(leg.from.name, isNotEmpty);
      expect(leg.to.name, isNotEmpty);
    });

    test('the metro is SUBWAY and resolves to the metro mode', () {
      final transit = response.itineraries.first.legs
          .where((l) => l.isTransit)
          .toList();
      expect(transit.map((l) => l.mode.id), everyElement('metro'));
      expect(transit.map((l) => l.mode.otpMode), everyElement('SUBWAY'));
      expect(transit.map((l) => l.route?.shortName), containsAll(['M1', 'M2']));
    });

    test('metro routes do have line numbers', () {
      final metro = response.itineraries.first.legs.firstWhere(
        (l) => l.mode.id == 'metro',
      );
      expect(metro.route!.hasLineNumber, isTrue);
    });

    test('no itinerary is walk-only', () {
      expect(
        response.itineraries.map((i) => i.isWalkOnly),
        everyElement(false),
      );
      expect(response.note, isNull);
    });

    test('attribution comes through verbatim', () {
      expect(response.attribution.text, contains('Transport for Cairo'));
      expect(response.attribution.licence, 'CC BY-NC 4.0');
    });
  });

  group('PlanResponse parses a real microbus itinerary', () {
    late PlanResponse response;

    setUp(() => response = PlanResponse.fromJson(planMicrobus));

    test('microbus legs are BUS on the wire but resolve to microbus', () {
      // Every route in the road feed is route_type 3. The distinction lives
      // in agency_id, which the server has already resolved.
      final transit = response.itineraries.first.legs
          .where((l) => l.isTransit)
          .toList();
      expect(transit, isNotEmpty);
      expect(transit.map((l) => l.mode.otpMode), everyElement('BUS'));
      expect(transit.map((l) => l.mode.id), everyElement('microbus'));
    });

    test('microbus routes declare that they have no line number', () {
      final transit = response.itineraries.first.legs.where((l) => l.isTransit);
      for (final leg in transit) {
        expect(
          leg.route!.hasLineNumber,
          isFalse,
          reason: 'paratransit carries no public route numbers',
        );
      }
    });

    test('the display name is built from origin and destination', () {
      final leg = response.itineraries.first.legs.firstWhere(
        (l) => l.mode.id == 'microbus',
      );
      expect(leg.route!.displayName, contains('→'));
      expect(leg.route!.displayName, isNot(equals(leg.route!.shortName)));
    });
  });

  group('empty results explain themselves', () {
    test('out of coverage says so, and offers only a walk', () {
      final response = PlanResponse.fromJson(planNoCoverage);
      expect(response.itineraries.map((i) => i.isWalkOnly), everyElement(true));
      expect(response.note, contains('Greater Cairo'));
    });

    test('a 03:00 departure is explained as a service-hours problem', () {
      final response = PlanResponse.fromJson(planWalkOnly);
      expect(response.itineraries.map((i) => i.isWalkOnly), everyElement(true));
      expect(response.note, contains('Late-night'));
    });
  });

  group('StopsResponse', () {
    late StopsResponse response;

    setUp(() => response = StopsResponse.fromJson(stopsMoneeb));

    test('road-feed stop names arrive in Arabic', () {
      // translations.txt covers all 2,997 road stops. If this ever fails,
      // `lang` has stopped reaching the server.
      expect(response.stops.first.name, 'المنيب');
    });

    test('reports more matches than it returned', () {
      expect(response.truncated, isTrue);
      expect(response.totalMatches, greaterThan(response.stops.length));
    });

    test('stops list the modes they serve', () {
      expect(response.stops.first.modes, contains('microbus'));
    });
  });
}
