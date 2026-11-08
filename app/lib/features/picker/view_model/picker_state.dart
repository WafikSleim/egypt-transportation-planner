import 'package:equatable/equatable.dart';

import '../../../core/network/api_failure.dart';
import '../../../core/presentation/place_presenter.dart';
import '../../../core/presentation/view_models.dart';
import '../../../data/models/models.dart';
import '../../../domain/entities/trip_endpoint.dart';

/// One stop row: the stop plus the marks for the modes it serves.
class StopResultVm extends Equatable {
  const StopResultVm({required this.stop, required this.badges});

  final StopSummary stop;
  final List<ModeBadgeVm> badges;

  @override
  List<Object?> get props => [stop, badges];
}

/// One row of the single list: a stop or a place, never a blend of the two.
sealed class PickerEntry {
  const PickerEntry();
}

class StopEntry extends PickerEntry {
  const StopEntry(this.result);

  final StopResultVm result;
}

class PlaceEntry extends PickerEntry {
  const PlaceEntry(this.place);

  final PlaceVm place;
}

/// Which of the two sources the list is narrowed to.
enum PickerFilter { all, stops, places }

sealed class PickerState extends Equatable {
  const PickerState();

  @override
  List<Object?> get props => const [];
}

/// Nothing typed yet, or too little to search with. Carries what is on the
/// phone, so the first frame already has something in it.
class PickerIdle extends PickerState {
  const PickerIdle({this.recents = const [], this.saved = const []});

  /// Most recent first. On-device only.
  final List<TripEndpoint> recents;

  /// Stops and places that appear in a saved trip and are not already among
  /// [recents]. There is no store of saved places of their own (#11 keeps
  /// recents and saved *trips*), so this is what the saved trips already say
  /// about where somebody goes — nothing is written for it.
  final List<TripEndpoint> saved;

  bool get isEmpty => recents.isEmpty && saved.isEmpty;

  @override
  List<Object?> get props => [recents, saved];
}

class PickerLoading extends PickerState {
  const PickerLoading();
}

/// The two sources answered, or one did and the other said why it could not.
///
/// A source that failed is a flag, not an error: stop search and the place
/// index are independent services, and the place index is the one whose
/// absence is expected and survivable — a screen that went blank because it
/// was down would take stop search down with it.
class PickerLoaded extends PickerState {
  const PickerLoaded({
    required this.query,
    required this.stops,
    required this.stopsTotal,
    required this.stopsTruncated,
    required this.stopsAttribution,
    required this.places,
    required this.placesTotal,
    required this.placesTruncated,
    required this.placesAttribution,
    required this.filter,
  });

  final String query;

  final List<StopResultVm> stops;
  final int stopsTotal;
  final bool stopsTruncated;

  /// Transit data's credit (TfC). Null when the stop search failed.
  final Attribution? stopsAttribution;

  final List<PlaceVm> places;
  final int placesTotal;
  final bool placesTruncated;

  /// OpenStreetMap's credit — a different one. Null when the place search
  /// failed, in which case nothing from it is on screen to credit.
  final Attribution? placesAttribution;

  final PickerFilter filter;

  bool get stopsUnavailable => stopsAttribution == null;
  bool get placesUnavailable => placesAttribution == null;

  bool get showsStops => filter != PickerFilter.places;
  bool get showsPlaces => filter != PickerFilter.stops;

  /// Nothing to list **under the current filter**.
  bool get isEmpty =>
      (!showsStops || stops.isEmpty) && (!showsPlaces || places.isEmpty);

  /// The one list. Under "all" the two sources are **interleaved**, best of
  /// each first, rather than one after the other: a stop search can return
  /// twenty prefix matches, and stacking them above the places would push the
  /// mall somebody typed three screens down. Each source keeps its own order —
  /// stops as OTP ranks them, places by distance or relevance — because the
  /// two rankings are not comparable and are not merged into one.
  List<PickerEntry> get entries {
    final s = showsStops ? stops : const <StopResultVm>[];
    final p = showsPlaces ? places : const <PlaceVm>[];
    final out = <PickerEntry>[];
    for (var i = 0; i < s.length || i < p.length; i++) {
      if (i < s.length) out.add(StopEntry(s[i]));
      if (i < p.length) out.add(PlaceEntry(p[i]));
    }
    return out;
  }

  PickerLoaded withFilter(PickerFilter f) => PickerLoaded(
    query: query,
    stops: stops,
    stopsTotal: stopsTotal,
    stopsTruncated: stopsTruncated,
    stopsAttribution: stopsAttribution,
    places: places,
    placesTotal: placesTotal,
    placesTruncated: placesTruncated,
    placesAttribution: placesAttribution,
    filter: f,
  );

  @override
  List<Object?> get props => [
    query,
    stops,
    stopsTotal,
    stopsTruncated,
    stopsAttribution,
    places,
    placesTotal,
    placesTruncated,
    placesAttribution,
    filter,
  ];
}

/// Both sources failed. The stop search's failure is the one reported — it is
/// the primary index, and the offline/timeout kinds it carries are the same
/// for both.
class PickerFailed extends PickerState {
  const PickerFailed(this.failure);

  final ApiFailure failure;

  @override
  List<Object?> get props => [failure.kind, failure.status];
}
