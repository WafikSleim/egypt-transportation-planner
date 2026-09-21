import '../../data/models/models.dart';
import '../entities/trip_endpoint.dart';

/// The Model side of MVVM: the only thing a ViewModel is allowed to call for
/// transit data.
///
/// Abstract so a Cubit test can drive it without a socket. The implementation
/// lives in `data/repositories/`.
abstract class PlannerRepository {
  Future<PlanResponse> plan({
    required GeoPoint from,
    required GeoPoint to,
    required DateTime departAt,
    bool arriveBy = false,
  });

  Future<StopsResponse> searchStops(String query, {int limit = 20});

  Future<Attribution> attribution();
}
