import 'package:egypt_transport/core/location/location_service.dart';

/// A location service a test can point wherever it likes.
class FakeLocationService implements LocationService {
  FakeLocationService({
    this.result = const LocationUnavailable('not configured'),
    this.granted = true,
  });

  LocationResult result;
  bool granted;
  int settingsOpened = 0;

  @override
  Future<bool> hasPermission() async => granted;

  @override
  Future<LocationResult> current() async => result;

  @override
  Future<void> openSettings() async => settingsOpened++;
}
