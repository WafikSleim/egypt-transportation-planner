import 'dart:async';

import 'package:egypt_transport/core/tracking/tracking_source.dart';
import 'package:egypt_transport/domain/entities/trip_endpoint.dart';

/// A GPS the test drives by hand.
///
/// [subscriptions] counts how many streams were ever opened and
/// [listening] says whether one is open now, which is how a test asserts that
/// stopping a trip releases the subscription and that a refused notice never
/// started one.
class FakeTrackingSource implements TrackingLocationSource {
  FakeTrackingSource({
    this.access = TrackingAccess.granted,
    this.background = true,
  });

  TrackingAccess access;
  final bool background;

  int subscriptions = 0;
  int accessRequests = 0;

  /// Calls to the source in order, so a test can assert that permission came
  /// before the stream.
  final calls = <String>[];

  StreamController<LocationFix>? _controller;

  bool get listening => _controller?.hasListener ?? false;

  @override
  bool get continuesInBackground => background;

  @override
  Future<TrackingAccess> requestAccess() async {
    accessRequests++;
    calls.add('access');
    return access;
  }

  @override
  Stream<LocationFix> fixes() {
    subscriptions++;
    calls.add('fixes');
    final controller = _controller = StreamController<LocationFix>();
    return controller.stream;
  }

  void emit(double lat, double lon, {double accuracy = 20, DateTime? at}) {
    _controller?.add(
      LocationFix(
        point: GeoPoint(lat, lon),
        accuracyM: accuracy,
        at: at ?? DateTime(2026, 11, 8, 8),
      ),
    );
  }

  void fail() => _controller?.addError(StateError('location went away'));
}
