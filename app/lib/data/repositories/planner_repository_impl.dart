import '../../core/network/api_client.dart';
import '../../domain/entities/trip_endpoint.dart';
import '../../domain/repositories/planner_repository.dart';
import '../models/models.dart';

class PlannerRepositoryImpl implements PlannerRepository {
  PlannerRepositoryImpl(this._api);

  final ApiClient _api;

  @override
  Future<PlanResponse> plan({
    required GeoPoint from,
    required GeoPoint to,
    required DateTime departAt,
    bool arriveBy = false,
  }) async {
    final json = await _api.getJson('/plan', query: {
      'from': from.wire,
      'to': to.wire,
      'date': _date(departAt),
      'time': _time(departAt),
      if (arriveBy) 'arrive_by': 'true',
    });
    return PlanResponse.fromJson(json);
  }

  @override
  Future<StopsResponse> searchStops(String query, {int limit = 20}) async {
    final json = await _api.getJson('/stops', query: {
      'q': query,
      'limit': '$limit',
    });
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
