import 'package:egypt_transport/core/location/location_service.dart';
import 'package:egypt_transport/domain/entities/trip_endpoint.dart';
import 'package:egypt_transport/features/search/view_model/my_location_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_location_service.dart';

void main() {
  // Tahrir. Inside the covered box.
  const cairo = GeoPoint(30.0444, 31.2357);

  // Luxor. A real place, with no transit data anywhere in the country's
  // feeds, which is the normal case outside Greater Cairo.
  const luxor = GeoPoint(25.6872, 32.6396);

  MyLocationCubit build(FakeLocationService service) =>
      MyLocationCubit(service);

  test('a good fix becomes an endpoint the search form can use', () async {
    final cubit = build(
      FakeLocationService(result: const LocationFound(cairo, accuracyM: 20)),
    );
    await cubit.locate(label: 'مكاني');

    final state = cubit.state as MyLocationResolved;
    expect(state.endpoint.point, cairo);
    expect(state.endpoint.label, 'مكاني');
    expect(state.endpoint.isStop, isFalse);
    expect(state.approximate, isFalse);
  });

  test('a coarse fix is flagged rather than quietly used', () async {
    // 400 m in a dense part of Cairo is several stops. The user may walk to
    // the wrong one, so they are told.
    final cubit = build(
      FakeLocationService(result: const LocationFound(cairo, accuracyM: 400)),
    );
    await cubit.locate(label: 'مكاني');

    expect((cubit.state as MyLocationResolved).approximate, isTrue);
  });

  test('a fix outside coverage is caught before a request is spent', () async {
    // The API would answer the same way, but spending a round trip and a
    // spinner to be told "no data for Luxor" is worse - much worse on a bad
    // connection.
    final cubit = build(
      FakeLocationService(result: const LocationFound(luxor, accuracyM: 20)),
    );
    await cubit.locate(label: 'مكاني');

    expect(cubit.state, isA<MyLocationOutsideCoverage>());
  });

  group('refusal is a supported state, not a dead end', () {
    test('a plain denial can be retried in the app', () async {
      final cubit = build(
        FakeLocationService(result: const LocationDenied(permanently: false)),
      );
      await cubit.locate(label: 'مكاني');

      final state = cubit.state as MyLocationFailed;
      expect(state.canRetryInApp, isTrue);
    });

    test('a permanent denial cannot, and needs system settings', () async {
      final service = FakeLocationService(
        result: const LocationDenied(permanently: true),
      );
      final cubit = build(service);
      await cubit.locate(label: 'مكاني');

      expect((cubit.state as MyLocationFailed).canRetryInApp, isFalse);

      await cubit.openSettings();
      expect(service.settingsOpened, 1);
    });

    test('location switched off for the whole phone is its own case', () async {
      // Not a refusal, and not something an in-app prompt can fix - so it
      // must not be reported as one.
      final cubit = build(FakeLocationService(result: const LocationOff()));
      await cubit.locate(label: 'مكاني');

      expect((cubit.state as MyLocationFailed).reason, isA<LocationOff>());
    });

    test('a failure to get a fix at all', () async {
      final cubit = build(
        FakeLocationService(result: const LocationUnavailable('timeout')),
      );
      await cubit.locate(label: 'مكاني');

      expect(cubit.state, isA<MyLocationFailed>());
    });
  });

  group('the explanation is shown only when the OS will prompt', () {
    test('needed when permission has not been granted', () async {
      final cubit = build(FakeLocationService(granted: false));
      expect(await cubit.needsExplaining, isTrue);
    });

    test('not needed once it has', () async {
      // Repeating it after the user has already agreed is nagging.
      final cubit = build(FakeLocationService(granted: true));
      expect(await cubit.needsExplaining, isFalse);
    });
  });
}
