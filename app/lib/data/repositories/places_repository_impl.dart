import '../../core/network/api_client.dart';
import '../../domain/entities/trip_endpoint.dart';
import '../../domain/repositories/places_repository.dart';
import '../models/place_models.dart';

/// `/places` and `/places/reverse`, over the same [ApiClient] as everything
/// else — which is what adds `lang`. Nothing here sets it, and nothing here
/// may: the server resolves which of the two names to return from it.
class PlacesRepositoryImpl implements PlacesRepository {
  PlacesRepositoryImpl(this._api);

  final ApiClient _api;

  @override
  Future<PlacesResponse> search(
    String query, {
    GeoPoint? near,
    int limit = 20,
  }) async {
    final json = await _api.getJson(
      '/places',
      query: {
        'q': query,
        'limit': '$limit',
        if (near != null) 'near': near.wire,
      },
    );
    return PlacesResponse.fromJson(json);
  }

  @override
  Future<PlacesResponse> reverse(
    GeoPoint at, {
    int radiusMetres = 500,
    int limit = 5,
  }) async {
    final json = await _api.getJson(
      '/places/reverse',
      query: {'at': at.wire, 'radius_m': '$radiusMetres', 'limit': '$limit'},
    );
    return PlacesResponse.fromJson(json);
  }
}
