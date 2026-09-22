import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/config/app_config.dart';
import '../../../core/location/location_service.dart';
import '../../../domain/entities/trip_endpoint.dart';

sealed class MyLocationState extends Equatable {
  const MyLocationState();

  @override
  List<Object?> get props => const [];
}

class MyLocationIdle extends MyLocationState {
  const MyLocationIdle();
}

class MyLocationLocating extends MyLocationState {
  const MyLocationLocating();
}

class MyLocationResolved extends MyLocationState {
  const MyLocationResolved(this.endpoint, {required this.accuracyM})
    : approximate = accuracyM > LocationFound.poorAccuracyM;

  final TripEndpoint endpoint;
  final double accuracyM;

  /// Worth telling the user about: a fix this coarse can pick the wrong stop
  /// in a dense part of Cairo, and they may walk to it.
  final bool approximate;

  @override
  List<Object?> get props => [endpoint, accuracyM];
}

/// A real fix, in a place this app has no data for.
///
/// Caught here rather than by sending it: the API would answer the same way,
/// but spending a request and a spinner to be told "no data for Aswan" is
/// worse than saying so immediately, and on a bad connection it is much
/// worse.
class MyLocationOutsideCoverage extends MyLocationState {
  const MyLocationOutsideCoverage();
}

class MyLocationFailed extends MyLocationState {
  const MyLocationFailed(this.reason);

  final LocationResult reason;

  bool get canRetryInApp =>
      reason is! LocationDenied || !(reason as LocationDenied).permanently;

  @override
  List<Object?> get props => [reason];
}

/// ViewModel for "use my location".
///
/// Deliberately separate from [SearchCubit]: a location that fails must not
/// disturb the endpoints the user has already chosen, and the search form
/// has no business knowing about permissions.
class MyLocationCubit extends Cubit<MyLocationState> {
  MyLocationCubit(this._service) : super(const MyLocationIdle());

  final LocationService _service;

  /// True when the OS will not show a prompt, so the app's own explanation
  /// would be an interruption rather than a warning.
  Future<bool> get needsExplaining async => !await _service.hasPermission();

  /// [label] is the localised name to give the endpoint — the copy stays in
  /// the view layer, where the rest of it lives.
  Future<void> locate({required String label}) async {
    emit(const MyLocationLocating());
    final result = await _service.current();

    switch (result) {
      case LocationFound(:final point, :final accuracyM):
        if (!Coverage.contains(point.lat, point.lon)) {
          emit(const MyLocationOutsideCoverage());
          return;
        }
        emit(
          MyLocationResolved(
            TripEndpoint(label: label, point: point),
            accuracyM: accuracyM,
          ),
        );
      case LocationDenied():
      case LocationOff():
      case LocationUnavailable():
        emit(MyLocationFailed(result));
    }
  }

  Future<void> openSettings() => _service.openSettings();

  void reset() => emit(const MyLocationIdle());
}
