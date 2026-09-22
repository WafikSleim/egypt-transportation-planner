import '../../core/network/api_client.dart';
import '../../domain/entities/trip_endpoint.dart';
import '../../domain/repositories/planner_repository.dart';
import '../cache/plan_cache.dart';
import '../models/models.dart';

class PlannerRepositoryImpl implements PlannerRepository {
  PlannerRepositoryImpl(this._api, {PlanCache? cache}) : _cache = cache;

  final ApiClient _api;

  /// Null in the tests that only care about the wire, and on a phone where
  /// storage could not be opened. Everything below treats "no cache" as an
  /// ordinary state, because for a phone on its first run it is one.
  final PlanCache? _cache;

  @override
  Future<PlanResponse> plan({
    required GeoPoint from,
    required GeoPoint to,
    required DateTime departAt,
    bool arriveBy = false,
    String fromLabel = '',
    String toLabel = '',
  }) async {
    final json = await _api.getJson(
      '/plan',
      query: {
        'from': from.wire,
        'to': to.wire,
        'date': _date(departAt),
        'time': _time(departAt),
        if (arriveBy) 'arrive_by': 'true',
      },
      timeout: ApiClient.planTimeout,
    );
    final response = PlanResponse.fromJson(json);

    // Saved here rather than by the ViewModel, for the reason `lang` is added
    // by ApiClient rather than by call sites: there is no screen that may
    // plan a trip and forget to record it. Awaited — the request has already
    // cost a round trip, and an unawaited write is a race in every test that
    // reads the thing back.
    await _cache?.save(
      from: from,
      to: to,
      fromLabel: fromLabel,
      toLabel: toLabel,
      departAt: departAt,
      arriveBy: arriveBy,
      lang: _api.languageCode,
      parsed: response,
      body: json,
    );

    return response;
  }

  @override
  CachedPlan? lastPlan({
    required GeoPoint from,
    required GeoPoint to,
    required DateTime departAt,
    bool arriveBy = false,
  }) => _cache?.read(
    from: from,
    to: to,
    departAt: departAt,
    arriveBy: arriveBy,
    lang: _api.languageCode,
  );

  @override
  Future<StopsResponse> searchStops(String query, {int limit = 20}) async {
    final json = await _api.getJson(
      '/stops',
      query: {'q': query, 'limit': '$limit'},
    );
    return StopsResponse.fromJson(json);
  }

  @override
  Future<Attribution> attribution() async =>
      Attribution.fromJson(await _api.getJson('/attribution'));

  // Local wall-clock, which is what the traveller means. The service runs in
  // Africa/Cairo and so, in practice, does the phone.
  String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  String _time(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
