import 'dart:convert';

import 'package:egypt_transport/core/network/api_client.dart';
import 'package:egypt_transport/core/presentation/place_presenter.dart';
import 'package:egypt_transport/data/models/place_models.dart';
import 'package:egypt_transport/data/repositories/places_repository_impl.dart';
import 'package:egypt_transport/data/repositories/planner_repository_impl.dart';
import 'package:egypt_transport/domain/entities/trip_endpoint.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fixtures.dart';

/// The wire contract for the place index, the presenter that turns it into
/// something a screen may draw, and the requests the client makes for it.
void main() {
  group('parsing /places', () {
    test('an Arabic-named place', () {
      final r = PlacesResponse.fromJson(placesAr);
      final mall = r.places.first;

      expect(mall.name, 'كايرو فستيفال سيتي مول');
      expect(mall.nameLanguage, 'ar');
      expect(mall.nameIsFallback, isFalse);
      expect(mall.category.id, 'mall');
      expect(mall.category.labelAr, 'مول');
      expect(mall.area, 'التجمع الخامس');
      expect(mall.distanceM, 18420);
      expect(r.matching, 'substring');
    });

    test('a place with no Arabic name is flagged, not dropped', () {
      final r = PlacesResponse.fromJson(placesAr);
      final auc = r.places.firstWhere((p) => p.id == 'w102');

      expect(auc.name, 'American University in Cairo');
      expect(auc.nameLanguage, 'en');
      expect(auc.nameIsFallback, isTrue);
      expect(auc.nameAr, isNull);
    });

    test('distance is null, not zero, when no point was sent', () {
      final r = PlacesResponse.fromJson(placesNoNear);
      expect(r.places.single.distanceM, isNull);
    });

    test('carries OpenStreetMap\'s attribution, not the transit data\'s', () {
      final r = PlacesResponse.fromJson(placesAr);
      expect(r.attribution.text, '© OpenStreetMap contributors');
      expect(r.attribution.licence, 'ODbL 1.0');
      expect(r.attribution.text, isNot(contains('Transport for Cairo')));
    });

    test('an empty answer parses to an empty list', () {
      final r = PlacesResponse.fromJson(placesReverseEmpty);
      expect(r.places, isEmpty);
      expect(r.matching, 'nearest');
    });

    test('nearby stops carry TfC\'s attribution and a distance', () {
      final r = NearbyStopsResponse.fromJson(stopsNearby);
      expect(r.stops.single.name, 'المصراوية');
      expect(r.stops.single.distanceM, 239);
      expect(r.attribution.text, contains('Transport for Cairo'));
    });
  });

  group('PlacePresenter', () {
    const ar = PlacePresenter(languageCode: 'ar');
    const en = PlacePresenter(languageCode: 'en');

    test('an Arabic name reads right to left and has no note', () {
      final vm = ar.place(PlacesResponse.fromJson(placesAr).places.first);
      expect(vm.nameDirection, TextDirection.rtl);
      expect(vm.nameNote, isNull);
      expect(vm.categoryLabel, 'مول');
    });

    test('a Latin fallback is set left to right and says there is no '
        'Arabic name — never transliterated', () {
      final vm = ar.place(PlacesResponse.fromJson(placesAr).places[1]);
      expect(vm.name, 'American University in Cairo');
      expect(vm.nameDirection, TextDirection.ltr);
      expect(vm.nameNote, NameNote.noArabicName);
    });

    test('the mirror case: Arabic on an English screen says so', () {
      final street = PlacesResponse.fromJson(placesEn).places[2];
      final vm = en.place(street);
      expect(vm.name, 'شارع التسعين الجنوبي');
      expect(vm.nameDirection, TextDirection.rtl);
      expect(vm.nameNote, NameNote.noEnglishName);
    });

    test('the category label follows the app language', () {
      final mall = PlacesResponse.fromJson(placesAr).places.first;
      expect(ar.place(mall).categoryLabel, 'مول');
      expect(en.place(mall).categoryLabel, 'Mall');
    });

    test('picking a place yields a place endpoint, never a stop', () {
      final vm = ar.place(PlacesResponse.fromJson(placesAr).places.first);
      expect(vm.endpoint.kind, EndpointKind.place);
      expect(vm.endpoint.placeId, 'w101');
      expect(vm.endpoint.stopId, isNull);
      expect(vm.endpoint.label, 'كايرو فستيفال سيتي مول');
    });
  });

  group('requests', () {
    late List<Uri> requested;

    ApiClient client(Object body, {String language = 'ar'}) {
      requested = [];
      return ApiClient(
        baseUrl: 'http://test',
        languageCode: () => language,
        client: MockClient((request) async {
          requested.add(request.url);
          return http.Response.bytes(
            utf8.encode(jsonEncode(body)),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
    }

    test('/places carries lang without the call site adding it', () async {
      final repo = PlacesRepositoryImpl(client(placesAr));
      await repo.search('كايرو');
      expect(requested.single.queryParameters['lang'], 'ar');
    });

    test('/places/reverse carries lang', () async {
      final repo = PlacesRepositoryImpl(client(placesReverse));
      await repo.reverse(const GeoPoint(30.0312, 31.4601));
      expect(requested.single.queryParameters['lang'], 'ar');
    });

    test('/stops/nearby carries lang', () async {
      final repo = PlannerRepositoryImpl(client(stopsNearby));
      await repo.nearbyStops(const GeoPoint(30.0312, 31.4601));
      expect(requested.single.queryParameters['lang'], 'ar');
    });

    test('lang follows the language, so English asks for English', () async {
      final repo = PlacesRepositoryImpl(client(placesEn, language: 'en'));
      await repo.search('festival');
      expect(requested.single.queryParameters['lang'], 'en');
    });

    test('near is sent only when there is one, as lat,lon', () async {
      final repo = PlacesRepositoryImpl(client(placesAr));
      await repo.search('كايرو');
      expect(requested.single.queryParameters.containsKey('near'), isFalse);

      await repo.search('كايرو', near: const GeoPoint(30.0444, 31.2357));
      expect(requested.last.queryParameters['near'], '30.0444,31.2357');
    });

    test(
      'the query goes to /places, the stops index is not consulted',
      () async {
        final repo = PlacesRepositoryImpl(client(placesAr));
        await repo.search('كايرو');
        expect(requested.single.path, '/places');
        expect(requested.single.queryParameters['q'], 'كايرو');
      },
    );

    test('reverse asks for the point it was given', () async {
      final repo = PlacesRepositoryImpl(client(placesReverse));
      await repo.reverse(const GeoPoint(30.0312, 31.4601), limit: 1);
      expect(requested.single.path, '/places/reverse');
      expect(requested.single.queryParameters['at'], '30.0312,31.4601');
      expect(requested.single.queryParameters['limit'], '1');
    });
  });
}
