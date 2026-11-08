import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../domain/entities/trip_endpoint.dart';

/// One reading of where the phone is. Lives in memory for as long as it takes
/// to compare it with the next stop, and is never written anywhere.
class LocationFix extends Equatable {
  const LocationFix({
    required this.point,
    required this.accuracyM,
    required this.at,
  });

  final GeoPoint point;

  /// Metres, as the OS reports it. A fix this app cannot trust says so here,
  /// and the tracker degrades to "not sure" rather than rounding it away.
  final double accuracyM;

  final DateTime at;

  @override
  List<Object?> get props => [point, accuracyM, at];
}

/// Why following could not start. Each leads to different advice.
enum TrackingAccess { granted, denied, deniedForever, serviceOff, unavailable }

/// A stream of fixes, for following a trip.
///
/// **Separate from `LocationService` on purpose.** That class's contract is
/// one fix, on demand, and nothing running afterwards; its tests and its
/// manifest comment hold that. A subscription that stays open is a different
/// promise with a different consent - the "تابع الرحلة" disclosure - and it
/// must not arrive by accident through the "my location" button. Two types is
/// how that stays true.
///
/// **Nothing here talks to the network, and nothing here records a track.**
/// A fix goes from the OS to the tracker to a distance comparison and is then
/// garbage. `test/tracking_test.dart` holds that this directory imports no
/// HTTP client and no repository.
abstract class TrackingLocationSource {
  /// Whether fixes keep arriving with the app out of sight. True on Android,
  /// where the visible foreground-service notice keeps the process alive.
  /// False on iOS, where doing it would need `UIBackgroundModes: location` -
  /// a background mode this project has ruled out in `Info.plist` - so
  /// following there works only while the app is open, and the disclosure
  /// says so.
  bool get continuesInBackground;

  /// Checks the OS permission, asking if it has not been asked. Must succeed
  /// *before* the tracking notice is posted: Android 14 refuses to start a
  /// location foreground service without it.
  Future<TrackingAccess> requestAccess();

  /// Starts the subscription. Listen only after [requestAccess] said granted
  /// **and** the tracking notice is on screen - the cubit's job to order.
  Stream<LocationFix> fixes();
}

class GeolocatorTrackingSource implements TrackingLocationSource {
  const GeolocatorTrackingSource();

  @override
  bool get continuesInBackground =>
      defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<TrackingAccess> requestAccess() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return TrackingAccess.serviceOff;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      return switch (permission) {
        LocationPermission.always ||
        LocationPermission.whileInUse => TrackingAccess.granted,
        LocationPermission.deniedForever => TrackingAccess.deniedForever,
        _ => TrackingAccess.denied,
      };
    } catch (_) {
      return TrackingAccess.unavailable;
    }
  }

  @override
  Stream<LocationFix> fixes() {
    return Geolocator.getPositionStream(locationSettings: _settings()).map(
      (p) => LocationFix(
        point: GeoPoint(p.latitude, p.longitude),
        accuracyM: p.accuracy,
        at: p.timestamp,
      ),
    );
  }

  /// High accuracy with a distance filter: the alert radius is a few hundred
  /// metres, so there is no use in a reading every second, and the filter is
  /// what lets the GPS idle between stops. This is the first number to tune
  /// on a real phone - battery cost is what the disclosure promises to be
  /// honest about, and it has never been measured.
  LocationSettings _settings() {
    const filter = 25;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: filter,
          intervalDuration: const Duration(seconds: 10),
          // Deliberately no `foregroundNotificationConfig`. That option makes
          // geolocator start a foreground service of its own with a title and
          // body passed as plain strings - a notification outside the copy
          // layer, in addition to ours. The visible foreground service is the
          // one `LocalNotificationService` starts for `TripInProgressNotice`.
        );
      case TargetPlatform.iOS || TargetPlatform.macOS:
        return AppleSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: filter,
          activityType: ActivityType.automotiveNavigation,
          pauseLocationUpdatesAutomatically: true,
          // No background updates: that needs the `UIBackgroundModes`
          // location entry this project does not declare.
          allowBackgroundLocationUpdates: false,
        );
      default:
        return const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: filter,
        );
    }
  }
}
