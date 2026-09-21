import 'dart:convert';

import 'package:egypt_transport/core/network/api_client.dart';
import 'package:egypt_transport/core/network/api_failure.dart';
import 'package:egypt_transport/data/repositories/planner_repository_impl.dart';
import 'package:egypt_transport/domain/entities/trip_endpoint.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fixtures.dart';

void main() {
  late List<Uri> requested;

  ApiClient clientReturning(
    Object body, {
    int status = 200,
    String language = 'ar',
  }) {
    requested = [];
    return ApiClient(
      baseUrl: 'http://test',
      languageCode: () => language,
      client: MockClient((request) async {
        requested.add(request.url);
        return http.Response.bytes(
          utf8.encode(jsonEncode(body)),
          status,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  }

  group('lang reaches the server on every request', () {
    // This is the wiring most worth a test. Stop names, route display names
    // and the origin/destination labels are all localised server-side, so a
    // request that forgets `lang` produces a fully Arabic screen with Latin
    // stop names — which reads as a working app, not a bug.

    test('/plan carries it', () async {
      final repo = PlannerRepositoryImpl(clientReturning(planMetro));
      await repo.plan(
        from: const GeoPoint(29.8490, 31.3340),
        to: const GeoPoint(30.1220, 31.2450),
        departAt: DateTime(2026, 9, 21, 8),
      );
      expect(requested.single.queryParameters['lang'], 'ar');
    });

    test('/stops carries it', () async {
      final repo = PlannerRepositoryImpl(clientReturning(stopsMoneeb));
      await repo.searchStops('المنيب');
      expect(requested.single.queryParameters['lang'], 'ar');
    });

    test('/attribution carries it', () async {
      final repo = PlannerRepositoryImpl(
          clientReturning({'text': 'x', 'licence': 'y', 'source_url': 'z'}));
      await repo.attribution();
      expect(requested.single.queryParameters['lang'], 'ar');
    });

    test('and follows the current setting rather than a captured value', () async {
      var language = 'ar';
      final client = ApiClient(
        baseUrl: 'http://test',
        languageCode: () => language,
        client: MockClient((request) async {
          requested.add(request.url);
          return http.Response('{}', 200);
        }),
      );
      requested = [];

      await client.getJson('/stops', query: {'q': 'a'});
      language = 'en';
      await client.getJson('/stops', query: {'q': 'a'});

      expect(requested.map((u) => u.queryParameters['lang']), ['ar', 'en']);
    });
  });

  group('the plan request is shaped the way the API expects', () {
    test('coordinates are lat,lon and the time is split from the date', () async {
      final repo = PlannerRepositoryImpl(clientReturning(planMetro));
      await repo.plan(
        from: const GeoPoint(29.849, 31.334),
        to: const GeoPoint(30.122, 31.245),
        departAt: DateTime(2026, 9, 21, 8, 5),
      );

      final q = requested.single.queryParameters;
      expect(q['from'], '29.849,31.334');
      expect(q['to'], '30.122,31.245');
      expect(q['date'], '2026-09-21');
      expect(q['time'], '08:05');
      expect(q.containsKey('arrive_by'), isFalse);
    });
  });

  group('failures are classified into something the UI can act on', () {
    test('5xx is the server being down, not the user being wrong', () async {
      final repo = PlannerRepositoryImpl(clientReturning({}, status: 503));
      expect(
        () => repo.searchStops('a'),
        throwsA(isA<ApiFailure>()
            .having((f) => f.kind, 'kind', FailureKind.serverDown)),
      );
    });

    test('4xx is a bad request', () async {
      final repo = PlannerRepositoryImpl(
          clientReturning({'detail': 'nope'}, status: 422));
      expect(
        () => repo.searchStops('a'),
        throwsA(isA<ApiFailure>()
            .having((f) => f.kind, 'kind', FailureKind.badRequest)
            .having((f) => f.detail, 'detail', 'nope')),
      );
    });

    test('no socket at all is offline', () async {
      final client = ApiClient(
        baseUrl: 'http://test',
        languageCode: () => 'ar',
        client: MockClient((_) => throw http.ClientException('no route')),
      );
      expect(
        () => client.getJson('/health'),
        throwsA(isA<ApiFailure>()
            .having((f) => f.kind, 'kind', FailureKind.offline)),
      );
    });
  });

  test('Arabic survives the decode', () async {
    // Decoding `response.body` rather than the bytes guesses latin-1 when the
    // server omits a charset, which turns every stop name into mojibake.
    final repo = PlannerRepositoryImpl(clientReturning(stopsMoneeb));
    final stops = await repo.searchStops('المنيب');
    expect(stops.stops.first.name, 'المنيب');
  });
}
