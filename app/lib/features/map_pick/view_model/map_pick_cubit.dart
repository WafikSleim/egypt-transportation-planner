import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/config/app_config.dart';
import '../../../core/presentation/place_presenter.dart';
import '../../../data/models/place_models.dart';
import '../../../domain/entities/trip_endpoint.dart';
import '../../../domain/repositories/places_repository.dart';
import '../../../domain/repositories/planner_repository.dart';
import 'map_pick_state.dart';

/// ViewModel for picking a point on the map (P-18).
///
/// Knows nothing about MapLibre: the map widget reports where the camera came
/// to rest and the page hands that to [pointSettled]. That is what keeps this
/// testable on the Dart VM, where there is no platform view to drag.
///
/// On each settle it asks **two different services two different questions**
/// and shows the answers as two labelled things:
///
/// 1. what is this place called — OSM, via `/places/reverse`;
/// 2. how far is the nearest stop — TfC, via `/stops/nearby`.
///
/// The server refuses to join them (`/places/reverse` says so in its
/// docstring: the licences forbid it), so the client does not either. A wrong
/// or missing name must never imply a wrong trip, and the structure of this
/// class is part of how that is guaranteed: the trip is planned from the
/// pin's coordinates, and the name is a label.
class MapPickCubit extends Cubit<MapPickState> {
  MapPickCubit({
    required PlacesRepository places,
    required PlannerRepository planner,
    required PlacePresenter presenter,
  }) : _places = places,
       _planner = planner,
       _presenter = presenter,
       super(const MapPickIdle());

  /// How far the stop lookup looks. Far enough that "no stop near here" is a
  /// finding — a kilometre is a walk of over ten minutes — and not so far that
  /// the answer stops being useful for judging whether the point is reachable.
  static const stopRadiusM = 1000;

  /// How far the name lookup looks. Beyond this the honest answer is that OSM
  /// has nothing named here.
  static const nameRadiusM = 500;

  final PlacesRepository _places;
  final PlannerRepository _planner;
  final PlacePresenter _presenter;

  int _generation = 0;

  /// Called by the page when the camera comes to rest.
  Future<void> pointSettled(GeoPoint point) async {
    final generation = ++_generation;

    if (!Coverage.contains(point.lat, point.lon)) {
      emit(MapPickOutside(point));
      return;
    }
    emit(MapPickLoading(point));

    // Both started before either is awaited, and each failure is its own: the
    // place index being down must not hide the nearest stop, which is the
    // half that decides whether the trip is possible at all.
    final nameFuture = _attempt(
      () => _places.reverse(point, radiusMetres: nameRadiusM, limit: 1),
    );
    final stopFuture = _attempt(
      () => _planner.nearbyStops(point, radiusMetres: stopRadiusM, limit: 1),
    );
    final name = await nameFuture;
    final stop = await stopFuture;

    // A drag that settled again while this was in flight has overtaken it.
    if (generation != _generation || isClosed) return;

    final PlacesResponse? placesResponse = name;
    final NearbyStopsResponse? stopsResponse = stop;
    emit(
      MapPickReady(
        point: point,
        place: placesResponse == null || placesResponse.places.isEmpty
            ? null
            : _presenter.place(placesResponse.places.first),
        nameUnavailable: placesResponse == null,
        nearestStop: stopsResponse == null || stopsResponse.stops.isEmpty
            ? null
            : stopsResponse.stops.first,
        stopUnavailable: stopsResponse == null,
        stopRadiusM: stopRadiusM,
        placesAttribution: placesResponse?.attribution,
        stopsAttribution: stopsResponse?.attribution,
      ),
    );
  }

  /// What confirming returns, or null while there is nothing to confirm.
  ///
  /// The **coordinates are the pin's**, not the named place's: a street's
  /// stored position can be a long way from where the passenger pointed, and
  /// the trip must go where they pointed. The name is only the label.
  /// [unnamedLabel] is the localised coordinates fallback, passed in because
  /// copy lives in the view layer.
  TripEndpoint? confirmedEndpoint({required String unnamedLabel}) {
    final s = state;
    if (s is! MapPickReady) return null;
    return TripEndpoint(label: s.place?.name ?? unnamedLabel, point: s.point);
  }

  Future<T?> _attempt<T>(Future<T> Function() call) async {
    try {
      return await call();
    } catch (_) {
      // Every kind of failure — offline, 503 from a place index that is not
      // up, a server that has no such route yet — is the same to this screen:
      // that half is unavailable, and the other half still stands.
      return null;
    }
  }
}
