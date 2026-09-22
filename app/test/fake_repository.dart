import 'package:egypt_transport/data/cache/plan_cache.dart';
import 'package:egypt_transport/data/models/models.dart';
import 'package:egypt_transport/domain/entities/trip_endpoint.dart';
import 'package:egypt_transport/domain/repositories/planner_repository.dart';

/// A repository a ViewModel test can drive directly.
///
/// Hand-written rather than mocked: there are three methods, and a fake that
/// can be told to be slow is what the ordering tests actually need.
class FakeRepository implements PlannerRepository {
  FakeRepository({this.planResponse, this.stopsResponse, this.error});

  PlanResponse? planResponse;
  StopsResponse? stopsResponse;
  Object? error;

  /// What `lastPlan` answers with. Null is a phone with nothing saved, which
  /// is every phone before its first successful search.
  CachedPlan? cached;

  /// Lets a test hold the request open long enough to watch the wait state.
  Duration? planDelay;

  /// The labels the ViewModel passed down to be recorded with the cache.
  String? recordedFromLabel;
  String? recordedToLabel;

  /// Held per query, so a test can make an early request finish last.
  final Map<String, Duration> delays = {};

  final List<String> stopQueries = [];
  int planCalls = 0;

  @override
  Future<PlanResponse> plan({
    required GeoPoint from,
    required GeoPoint to,
    required DateTime departAt,
    bool arriveBy = false,
    String fromLabel = '',
    String toLabel = '',
  }) async {
    planCalls++;
    recordedFromLabel = fromLabel;
    recordedToLabel = toLabel;
    if (planDelay != null) await Future<void>.delayed(planDelay!);
    if (error != null) throw error!;
    return planResponse!;
  }

  @override
  CachedPlan? lastPlan({
    required GeoPoint from,
    required GeoPoint to,
    required DateTime departAt,
    bool arriveBy = false,
  }) => cached;

  @override
  Future<StopsResponse> searchStops(String query, {int limit = 20}) async {
    stopQueries.add(query);
    final delay = delays[query];
    if (delay != null) await Future<void>.delayed(delay);
    if (error != null) throw error!;
    return stopsResponse ??
        StopsResponse(
          query: query,
          stops: const [],
          attribution: const Attribution(text: '', licence: '', sourceUrl: ''),
        );
  }

  @override
  Future<Attribution> attribution() async =>
      const Attribution(text: 't', licence: 'l', sourceUrl: 's');
}
