import 'package:egypt_transport/data/models/models.dart';
import 'package:egypt_transport/data/models/place_models.dart';
import 'package:egypt_transport/domain/entities/trip_endpoint.dart';
import 'package:egypt_transport/domain/repositories/places_repository.dart';

/// The OSM place index, as a ViewModel test sees it.
///
/// Separate from `FakeRepository` for the reason the two interfaces are
/// separate in the app: different dataset, different licence.
class FakePlacesRepository implements PlacesRepository {
  FakePlacesRepository({this.searchResponse, this.reverseResponse, this.error});

  PlacesResponse? searchResponse;
  PlacesResponse? reverseResponse;

  /// Thrown by both calls when set — a 503 from an index that is not up.
  Object? error;

  /// Held per query, so a test can make an early request finish last.
  final Map<String, Duration> delays = {};

  final List<String> queries = [];
  final List<GeoPoint?> nearValues = [];
  final List<GeoPoint> reverseCalls = [];

  static const osm = Attribution(
    text: '© OpenStreetMap contributors',
    licence: 'ODbL 1.0',
    sourceUrl: 'https://www.openstreetmap.org/copyright',
  );

  PlacesResponse _empty(String q) =>
      PlacesResponse(query: q, places: const [], attribution: osm);

  @override
  Future<PlacesResponse> search(
    String query, {
    GeoPoint? near,
    int limit = 20,
  }) async {
    queries.add(query);
    nearValues.add(near);
    final delay = delays[query];
    if (delay != null) await Future<void>.delayed(delay);
    if (error != null) throw error!;
    return searchResponse ?? _empty(query);
  }

  @override
  Future<PlacesResponse> reverse(
    GeoPoint at, {
    int radiusMetres = 500,
    int limit = 5,
  }) async {
    reverseCalls.add(at);
    if (error != null) throw error!;
    return reverseResponse ?? _empty(at.wire);
  }
}
