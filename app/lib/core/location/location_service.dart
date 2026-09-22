import 'package:equatable/equatable.dart';
import 'package:geolocator/geolocator.dart';

import '../../domain/entities/trip_endpoint.dart';

/// A one-off location fix.
///
/// **On demand only.** Nothing here runs in the background or keeps a
/// subscription open. Following a trip is a separate feature with its own
/// consent, its own persistent notification and its own honesty about
/// battery — it must not arrive by accident through this class.
///
/// The result type is deliberately explicit about the ways this fails,
/// because each one leads to different advice for the user, and "couldn't get
/// your location" leads to none.
sealed class LocationResult extends Equatable {
  const LocationResult();

  @override
  List<Object?> get props => const [];
}

class LocationFound extends LocationResult {
  const LocationFound(this.point, {required this.accuracyM});

  final GeoPoint point;

  /// Metres. Reported to the user when it is poor rather than hidden — a fix
  /// that is half a kilometre out will plan from the wrong stop, and the
  /// person deserves to know that before they walk somewhere.
  final double accuracyM;

  /// Above this, say so. Roughly where a cell-tower or coarse fix lands, and
  /// far enough to pick the wrong stop in a dense part of Cairo.
  static const poorAccuracyM = 150.0;

  bool get isApproximate => accuracyM > poorAccuracyM;

  @override
  List<Object?> get props => [point, accuracyM];
}

/// The user said no. [permanently] means Android will not ask again, so the
/// only route left is the system settings screen.
class LocationDenied extends LocationResult {
  const LocationDenied({required this.permanently});

  final bool permanently;

  @override
  List<Object?> get props => [permanently];
}

/// Location is switched off for the whole phone. Not the user's refusal, and
/// not something an in-app permission prompt can fix.
class LocationOff extends LocationResult {
  const LocationOff();
}

class LocationUnavailable extends LocationResult {
  const LocationUnavailable([this.detail]);

  final String? detail;

  @override
  List<Object?> get props => [detail];
}

abstract class LocationService {
  /// Whether the OS would show a prompt. Used to decide whether the app's own
  /// explanation is a courtesy or an interruption.
  Future<bool> hasPermission();

  /// Asks for permission if it is not already granted, then takes one fix.
  Future<LocationResult> current();

  /// Opens the system settings page, for the permanently-denied case.
  Future<void> openSettings();
}

class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  @override
  Future<bool> hasPermission() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  @override
  Future<LocationResult> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationOff();
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return const LocationDenied(permanently: true);
      }
      if (permission == LocationPermission.denied) {
        return const LocationDenied(permanently: false);
      }

      final fix = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          // Medium accuracy and a short ceiling on purpose: this only has to
          // be good enough to find the nearest stop, and a low-end phone
          // hunting for a high-accuracy fix drains battery for precision the
          // trip does not need.
          timeLimit: Duration(seconds: 12),
        ),
      );

      return LocationFound(
        GeoPoint(fix.latitude, fix.longitude),
        accuracyM: fix.accuracy,
      );
    } catch (e) {
      return LocationUnavailable('$e');
    }
  }

  @override
  Future<void> openSettings() => Geolocator.openAppSettings();
}
