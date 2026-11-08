import 'package:egypt_transport/core/storage/key_value_store.dart';
import 'package:egypt_transport/data/repositories/trip_history.dart';
import 'package:egypt_transport/domain/entities/trip_endpoint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TripEndpoint stop(String id, String name) => TripEndpoint(
    label: name,
    point: const GeoPoint(30.04, 31.23),
    stopId: id,
  );

  TripEndpoint point(double lat, double lon, [String label = 'مكاني']) =>
      TripEndpoint(label: label, point: GeoPoint(lat, lon));

  group('recents', () {
    test('most recent first', () async {
      final history = TripHistory(InMemoryStore());
      await history.remember(stop('1', 'المنيب'));
      await history.remember(stop('2', 'الجيزة'));

      expect(history.recents().map((e) => e.label), ['الجيزة', 'المنيب']);
    });

    test('choosing the same place again moves it up, not in twice', () async {
      final history = TripHistory(InMemoryStore());
      await history.remember(stop('1', 'المنيب'));
      await history.remember(stop('2', 'الجيزة'));
      await history.remember(stop('1', 'المنيب'));

      expect(history.recents().map((e) => e.label), ['المنيب', 'الجيزة']);
    });

    test(
      'de-duplicates by place, not by the label it was shown under',
      () async {
        // The same stop can arrive spelled differently - Arabic from the picker,
        // Latin from a metro leg. Two entries for one place is the bug.
        final history = TripHistory(InMemoryStore());
        await history.remember(stop('2:1145', 'المنيب'));
        await history.remember(stop('2:1145', 'El-Mounib'));

        expect(history.recents(), hasLength(1));
        expect(history.recents().single.label, 'El-Mounib');
      },
    );

    test('two fixes of the same doorway count as one place', () async {
      // A raw point has no stop id, and GPS never returns the same numbers
      // twice. Without rounding, "my location" fills the whole list.
      final history = TripHistory(InMemoryStore());
      await history.remember(point(30.044412, 31.235711));
      await history.remember(point(30.044418, 31.235715));

      expect(history.recents(), hasLength(1));
    });

    test('is capped, dropping the oldest', () async {
      final history = TripHistory(InMemoryStore());
      for (var i = 0; i < TripHistory.maxRecents + 3; i++) {
        await history.remember(stop('$i', 'stop $i'));
      }

      expect(history.recents(), hasLength(TripHistory.maxRecents));
      expect(history.recents().first.label, 'stop 10');
      expect(history.recents().map((e) => e.label), isNot(contains('stop 0')));
    });

    test('clearing leaves nothing behind', () async {
      final store = InMemoryStore();
      final history = TripHistory(store);
      await history.remember(stop('1', 'المنيب'));
      await history.clearRecents();

      expect(history.recents(), isEmpty);
      expect(store.read('recent_endpoints'), isNull);
    });
  });

  group('saved trips', () {
    test('survive being written and read back', () async {
      final store = InMemoryStore();
      await TripHistory(store).save(stop('1', 'المنيب'), stop('2', 'الجيزة'));

      final relaunched = TripHistory(store).saved();
      expect(relaunched, hasLength(1));
      expect(relaunched.single.from.label, 'المنيب');
      expect(relaunched.single.to.label, 'الجيزة');
      expect(relaunched.single.from.stopId, '1');
    });

    test(
      'saving the same pair twice replaces rather than duplicates',
      () async {
        final history = TripHistory(InMemoryStore());
        await history.save(stop('1', 'المنيب'), stop('2', 'الجيزة'));
        await history.save(stop('1', 'المنيب'), stop('2', 'الجيزة'));

        expect(history.saved(), hasLength(1));
      },
    );

    test('direction matters - there and back are different trips', () async {
      final history = TripHistory(InMemoryStore());
      await history.save(stop('1', 'المنيب'), stop('2', 'الجيزة'));
      await history.save(stop('2', 'الجيزة'), stop('1', 'المنيب'));

      expect(history.saved(), hasLength(2));
    });

    test('isSaved recognises the pair currently in the form', () async {
      final history = TripHistory(InMemoryStore());
      final from = stop('1', 'المنيب');
      final to = stop('2', 'الجيزة');

      expect(history.isSaved(from, to), isFalse);
      await history.save(from, to);
      expect(history.isSaved(from, to), isTrue);
      expect(history.isSaved(to, from), isFalse);
    });

    test('unsaving removes only that one', () async {
      final history = TripHistory(InMemoryStore());
      await history.save(stop('1', 'a'), stop('2', 'b'));
      await history.save(stop('3', 'c'), stop('4', 'd'));

      await history.unsave(history.saved().first.id);
      expect(history.saved(), hasLength(1));
    });

    test('newest first', () async {
      final history = TripHistory(InMemoryStore());
      await history.save(stop('1', 'first'), stop('2', 'b'));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await history.save(stop('3', 'second'), stop('4', 'd'));

      expect(history.saved().first.from.label, 'second');
    });

    test('what is kept is the places, not the itinerary', () async {
      // The point of the whole design: an itinerary saved on Tuesday has
      // Tuesday's departure times in it. Only the endpoints are durable.
      final store = InMemoryStore();
      await TripHistory(store).save(stop('1', 'a'), stop('2', 'b'));

      final raw = store.read('saved_trips')!;
      expect(raw, contains('"label":"a"'));
      expect(raw, isNot(contains('start_time')));
      expect(raw, isNot(contains('legs')));
    });
  });

  group('corrupt storage degrades to empty rather than crashing', () {
    // A phone cannot clear this without reinstalling, so nothing in here may
    // throw on the way to drawing a screen.

    test('text that is not JSON', () {
      final history = TripHistory(InMemoryStore({'recent_endpoints': 'nope'}));
      expect(history.recents(), isEmpty);
    });

    test('the right shape with the wrong contents', () {
      final history = TripHistory(
        InMemoryStore({'saved_trips': '{"items":[{"from":{"label":7}}]}'}),
      );
      expect(history.saved(), isEmpty);
    });

    test('a half-written entry is dropped, the rest survive', () async {
      final store = InMemoryStore();
      await TripHistory(store).save(stop('1', 'good'), stop('2', 'also good'));

      final poisoned = store
          .read('saved_trips')!
          .replaceFirst('{"items":[', '{"items":[{"from":{}},');
      await store.write('saved_trips', poisoned);

      expect(TripHistory(store).saved(), hasLength(1));
      expect(TripHistory(store).saved().single.from.label, 'good');
    });
  });

  group('places in storage (#17)', () {
    const mall = TripEndpoint(
      label: 'كايرو فستيفال',
      point: GeoPoint(30.0287, 31.4079),
      placeId: 'w101',
    );

    test('a place survives the round trip and is still a place', () async {
      final history = TripHistory(InMemoryStore());
      await history.remember(mall);

      final back = history.recents().single;
      expect(back.kind, EndpointKind.place);
      expect(back.placeId, 'w101');
      expect(back, mall);
    });

    test('a recent saved by a build before places existed still loads', () {
      // The shape #11 wrote: no `place_id`. A phone updating the app must not
      // lose, or crash on, what it already holds.
      final history = TripHistory(
        InMemoryStore({
          'recent_endpoints':
              '{"items":[{"label":"المنيب","lat":29.98,"lon":31.21,'
              '"stop_id":"2:1145","modes":["microbus"]},'
              '{"label":"مكاني","lat":30.04,"lon":31.23}]}',
        }),
      );

      final recents = history.recents();
      expect(recents, hasLength(2));
      expect(recents[0].kind, EndpointKind.stop);
      expect(recents[0].placeId, isNull);
      expect(recents[1].kind, EndpointKind.point);
    });

    test('a record claiming to be both a stop and a place is a stop', () {
      final history = TripHistory(
        InMemoryStore({
          'recent_endpoints':
              '{"items":[{"label":"x","lat":30.0,"lon":31.2,'
              '"stop_id":"2:1","place_id":"w9"}]}',
        }),
      );
      expect(history.recents().single.kind, EndpointKind.stop);
    });

    test('a place and a stop at the same spot are two recents', () async {
      final history = TripHistory(InMemoryStore());
      await history.remember(stop('2:1', 'محطة'));
      await history.remember(
        const TripEndpoint(
          label: 'مكان',
          point: GeoPoint(30.04, 31.23),
          placeId: 'n7',
        ),
      );
      // Keyed on the stop id and on the rounded point respectively, so they
      // do not collapse into one.
      expect(history.recents(), hasLength(2));
    });

    test('an endpoint cannot be a stop and a place at once', () {
      expect(
        () => TripEndpoint(
          label: 'x',
          point: const GeoPoint(30, 31),
          stopId: '2:1',
          placeId: 'w1',
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('savedEndpoints are stops and places from saved trips, newest first, '
        'each once, never a plain point', () async {
      final history = TripHistory(InMemoryStore());
      await history.save(point(30.05, 31.25), mall);
      await history.save(stop('2:1', 'المنيب'), mall);

      expect(history.savedEndpoints().map((e) => e.label), [
        'كايرو فستيفال',
        'المنيب',
      ]);
    });
  });
}
