import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/network/api_failure.dart';
import '../../../core/presentation/place_presenter.dart';
import '../../../core/presentation/trip_presenter.dart';
import '../../../data/repositories/trip_history.dart';
import '../../../domain/entities/trip_endpoint.dart';
import '../../../domain/repositories/places_repository.dart';
import '../../../domain/repositories/planner_repository.dart';
import 'picker_state.dart';

/// ViewModel for the picker: one field over stops, places and recents.
///
/// Stops and places are **two indexes behind two services**, asked in
/// parallel and shown in one list. They are never merged into one dataset —
/// a stop is TfC's (CC BY-NC) and a place is OpenStreetMap's (ODbL) — so each
/// result keeps its own source, its own mark and its own credit all the way
/// to the screen.
class PickerCubit extends Cubit<PickerState> {
  PickerCubit({
    required PlannerRepository planner,
    required PlacesRepository places,
    required TripPresenter tripPresenter,
    required PlacePresenter placePresenter,
    this.history,
    this.near,
    this.debounce = const Duration(milliseconds: 280),
  }) : _planner = planner,
       _places = places,
       _tripPresenter = tripPresenter,
       _placePresenter = placePresenter,
       super(_idle(history));

  /// Optional: without it the picker opens on the typing hint, which is also
  /// what a first-ever launch looks like.
  final TripHistory? history;

  /// Orders place results by distance when set. **A point the passenger
  /// already chose** — the other end of the trip — never a fix taken for this
  /// search. See [PlacesRepository.search].
  final GeoPoint? near;

  /// A two-letter prefix matches hundreds of stops and a two-letter substring
  /// matches thousands of places, so typing is debounced rather than fired per
  /// keystroke. The target is a low-end phone on patchy data.
  final Duration debounce;

  static const minimumQueryLength = 2;

  final PlannerRepository _planner;
  final PlacesRepository _places;
  final TripPresenter _tripPresenter;
  final PlacePresenter _placePresenter;

  Timer? _timer;
  int _generation = 0;
  PickerFilter _filter = PickerFilter.all;

  static PickerIdle _idle(TripHistory? history) {
    final recents = history?.recents() ?? const <TripEndpoint>[];
    final shown = {for (final r in recents) _same(r)};
    return PickerIdle(
      recents: recents,
      saved: [
        for (final e in history?.savedEndpoints() ?? const <TripEndpoint>[])
          if (!shown.contains(_same(e))) e,
      ],
    );
  }

  /// Identity for "already on screen": same stop, same place, or the same spot.
  static String _same(TripEndpoint e) =>
      e.stopId ??
      e.placeId ??
      '${e.point.lat.toStringAsFixed(4)},${e.point.lon.toStringAsFixed(4)}';

  void queryChanged(String raw) {
    _timer?.cancel();
    final query = raw.trim();
    if (query.length < minimumQueryLength) {
      _generation++;
      emit(_idle(history));
      return;
    }
    _timer = Timer(debounce, () => search(query));
  }

  Future<void> search(String query) async {
    final generation = ++_generation;
    emit(const PickerLoading());

    // Both are started before either is awaited: this is the whole point of a
    // single field, and a serial pair would double the wait on exactly the
    // connections where the wait is already the problem.
    final stopsFuture = _attempt(() => _planner.searchStops(query));
    final placesFuture = _attempt(() => _places.search(query, near: near));
    final stops = await stopsFuture;
    final places = await placesFuture;

    // A slower earlier request must not overwrite a newer answer.
    if (generation != _generation || isClosed) return;

    if (stops.failure != null && places.failure != null) {
      emit(PickerFailed(stops.failure!));
      return;
    }

    final stopsResponse = stops.value;
    final placesResponse = places.value;
    emit(
      PickerLoaded(
        query: query,
        stops: stopsResponse == null
            ? const []
            : stopsResponse.stops
                  .map(
                    (s) => StopResultVm(
                      stop: s,
                      badges: _tripPresenter.stopBadges(s),
                    ),
                  )
                  .toList(growable: false),
        stopsTotal: stopsResponse?.totalMatches ?? 0,
        stopsTruncated: stopsResponse?.truncated ?? false,
        stopsAttribution: stopsResponse?.attribution,
        places: placesResponse == null
            ? const []
            : _placePresenter.places(placesResponse.places),
        placesTotal: placesResponse?.totalMatches ?? 0,
        placesTruncated: placesResponse?.truncated ?? false,
        placesAttribution: placesResponse?.attribution,
        filter: _filter,
      ),
    );
  }

  void setFilter(PickerFilter filter) {
    _filter = filter;
    final current = state;
    if (current is PickerLoaded) emit(current.withFilter(filter));
  }

  Future<void> clearRecents() async {
    await history?.clearRecents();
    if (isClosed) return;
    if (state is PickerIdle) emit(_idle(history));
  }

  Future<_Attempt<T>> _attempt<T>(Future<T> Function() call) async {
    try {
      return _Attempt(value: await call());
    } on ApiFailure catch (e) {
      return _Attempt(failure: e);
    } catch (e) {
      return _Attempt(
        failure: ApiFailure(FailureKind.unexpected, detail: '$e'),
      );
    }
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}

class _Attempt<T> {
  const _Attempt({this.value, this.failure});

  final T? value;
  final ApiFailure? failure;
}
