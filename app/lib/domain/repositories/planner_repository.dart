import '../../data/cache/plan_cache.dart';
import '../../data/models/models.dart';
import '../../data/models/place_models.dart';
import '../entities/trip_endpoint.dart';

/// The Model side of MVVM: the only thing a ViewModel is allowed to call for
/// transit data.
///
/// Abstract so a Cubit test can drive it without a socket. The implementation
/// lives in `data/repositories/`.
abstract class PlannerRepository {
  /// [fromLabel] and [toLabel] are not sent to the router. They are recorded
  /// with the saved copy of this plan so that, offline, the app can say which
  /// trip the saved answer was an answer to — see [lastPlan].
  Future<PlanResponse> plan({
    required GeoPoint from,
    required GeoPoint to,
    required DateTime departAt,
    bool arriveBy = false,
    String fromLabel,
    String toLabel,
  });

  /// The last plan saved on this phone, if there is one and it answers this
  /// same question recently enough to be worth showing. Null otherwise —
  /// including when it is simply too old, because a stale itinerary is worse
  /// than an honest "no".
  ///
  /// Synchronous, like every other read in `core/storage`: the value is
  /// already in memory, and making it async would put a second loading state
  /// in front of a failure the user is already waiting on.
  CachedPlan? lastPlan({
    required GeoPoint from,
    required GeoPoint to,
    required DateTime departAt,
    bool arriveBy = false,
  });

  Future<StopsResponse> searchStops(String query, {int limit = 20});

  /// The stops nearest to [at], nearest first, with straight-line distances.
  /// Transit data — it belongs here and not on `PlacesRepository`, and the
  /// map-pick screen asks for it separately from the place's name.
  Future<NearbyStopsResponse> nearbyStops(
    GeoPoint at, {
    int radiusMetres,
    int limit,
  });

  Future<Attribution> attribution();
}
