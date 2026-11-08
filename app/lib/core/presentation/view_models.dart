import 'package:equatable/equatable.dart';

import '../../data/models/models.dart';
import '../map/geo.dart';

/// How a mode is drawn.
///
/// The metro's M1 blue sits very close to the tomnaya's plate blue. They are
/// never confused because **the metro uses a circular line badge and
/// everything else uses a pill chip** — form separates the register, colour
/// separates the member within it. Rendering a metro line as a pill removes
/// the only thing keeping those two apart.
enum ModeBadgeShape { pill, metroCircle }

class ModeBadgeVm extends Equatable {
  const ModeBadgeVm({
    required this.modeId,
    required this.label,
    required this.shape,
    this.metroLine,
  });

  /// Used for the colour lookup. Comes from `agency_id`, server-side.
  final String modeId;

  /// Already localised.
  final String label;

  final ModeBadgeShape shape;

  /// `M1`, `M2` — only set for [ModeBadgeShape.metroCircle].
  final String? metroLine;

  @override
  List<Object?> get props => [modeId, label, shape, metroLine];
}

class LegVm extends Equatable {
  const LegVm({
    required this.badge,
    required this.isTransit,
    required this.isWalk,
    required this.fromName,
    required this.toName,
    required this.startTime,
    required this.endTime,
    required this.durationMinutes,
    required this.distanceM,
    required this.intermediateStops,
    required this.routeLabel,
    required this.showNumberBadge,
    this.numberBadgeText,
    this.operatorName,
    this.path = const [],
    this.pathApproximate = false,
    this.fromPoint,
    this.toPoint,
  });

  final ModeBadgeVm badge;
  final bool isTransit;
  final bool isWalk;
  final String fromName;
  final String toName;
  final DateTime startTime;
  final DateTime endTime;
  final int durationMinutes;
  final int distanceM;
  final int intermediateStops;

  /// What to call this leg's route. For paratransit this is already
  /// origin → destination, built server-side.
  final String routeLabel;

  /// Decided once, here. A View must not re-read `has_line_number` and
  /// decide for itself — there are four screens that show a leg, and one of
  /// them would eventually get it wrong.
  final bool showNumberBadge;

  final String? numberBadgeText;
  final String? operatorName;

  /// The leg's path, decoded. **Empty means there is no path** — never "draw
  /// a line from [fromPoint] to [toPoint]": between two stops that is a claim
  /// about the route that nobody made. A path of fewer than two points is
  /// dropped to empty by the presenter for the same reason.
  final List<GeoPoint> path;

  /// The server said this path is stations joined by straight lines (metro
  /// line 3), not a surveyed track.
  final bool pathApproximate;

  final GeoPoint? fromPoint;
  final GeoPoint? toPoint;

  @override
  List<Object?> get props => [
    path,
    pathApproximate,
    fromPoint,
    toPoint,
    badge,
    isTransit,
    isWalk,
    fromName,
    toName,
    startTime,
    endTime,
    durationMinutes,
    distanceM,
    intermediateStops,
    routeLabel,
    showNumberBadge,
    numberBadgeText,
    operatorName,
  ];
}

/// Why a stop is marked on the map.
enum RouteStopRole { origin, destination, board, alight }

/// One leg's line on the map.
///
/// Carries the badge, not a colour: which colour a badge means depends on the
/// theme, and the one function that resolves it is `ModeColors.forBadge`. The
/// map and the leg list both go through it, so a leg cannot be orange in one
/// and blue in the other.
class RouteSegmentVm extends Equatable {
  const RouteSegmentVm({
    required this.badge,
    required this.isWalk,
    required this.points,
    required this.approximate,
  });

  final ModeBadgeVm badge;

  /// Walking is drawn dashed: it is not a vehicle, and that should read
  /// without reading.
  final bool isWalk;
  final List<GeoPoint> points;

  /// Straight lines between stations. Drawn fainter, and the screen says why.
  final bool approximate;

  @override
  List<Object?> get props => [badge, isWalk, points, approximate];
}

/// A marked stop. [badge] is set for boarding and alighting stops, so a metro
/// boarding is a circle carrying its line and not a bare dot or, worse, a
/// pill, and every ring takes its leg's colour.
class RouteStopVm extends Equatable {
  const RouteStopVm({required this.point, required this.role, this.badge});

  final GeoPoint point;
  final RouteStopRole role;
  final ModeBadgeVm? badge;

  @override
  List<Object?> get props => [point, role, badge];
}

/// What the itinerary map draws, and what it admits it cannot.
///
/// There is no vehicle in here and no field that could hold one: there is no
/// real-time feed for Cairo paratransit, so a moving dot would be invented.
class RouteMapVm extends Equatable {
  const RouteMapVm({
    this.segments = const [],
    this.stops = const [],
    this.undrawnLegs = 0,
  });

  static const empty = RouteMapVm();

  final List<RouteSegmentVm> segments;
  final List<RouteStopVm> stops;

  /// Legs with no usable path — left off the map rather than joined up with a
  /// guess. The screen says how many.
  final int undrawnLegs;

  /// Nothing drawable means no map at all, not an empty one.
  bool get hasRoute => segments.isNotEmpty;

  bool get hasApproximate => segments.any((s) => s.approximate);

  GeoBounds? get bounds => GeoBounds.around([
    for (final s in segments) ...s.points,
    for (final s in stops) s.point,
  ]);

  @override
  List<Object?> get props => [segments, stops, undrawnLegs];
}

class ItineraryVm extends Equatable {
  const ItineraryVm({
    required this.startTime,
    required this.endTime,
    required this.durationMinutes,
    required this.walkDistanceM,
    required this.transfers,
    required this.legs,
    this.cachedAt,
    this.routeMap = RouteMapVm.empty,
  });

  final RouteMapVm routeMap;

  final DateTime startTime;
  final DateTime endTime;
  final int durationMinutes;
  final int walkDistanceM;
  final int transfers;
  final List<LegVm> legs;

  /// When this answer was saved, or null if it came from the server just
  /// now.
  ///
  /// Carried on the itinerary and not only on the plan because an itinerary
  /// travels on its own: the results screen hands one to the detail screen,
  /// and later to a saved trip and to tracking. A cached itinerary shown as a
  /// live one is the same class of lie as a walk-only result shown as a trip,
  /// so the fact travels with the object rather than with the screen that
  /// happened to fetch it.
  final DateTime? cachedAt;

  bool get isFromCache => cachedAt != null;

  /// The badges worth showing on a summary card: transit only. A row of walk
  /// chips between every leg says nothing and crowds out what does.
  List<ModeBadgeVm> get transitBadges => legs
      .where((l) => l.isTransit)
      .map((l) => l.badge)
      .toList(growable: false);

  @override
  List<Object?> get props => [
    startTime,
    endTime,
    durationMinutes,
    walkDistanceM,
    transfers,
    legs,
    cachedAt,
    routeMap,
  ];
}

class PlanVm extends Equatable {
  const PlanVm({
    required this.itineraries,
    required this.attribution,
    this.note,
    this.noteCode,
    this.cachedAt,
  });

  /// When this plan was saved on the phone, or null for a live answer. Every
  /// itinerary in [itineraries] carries the same value.
  final DateTime? cachedAt;

  bool get isFromCache => cachedAt != null;

  /// Walk-only itineraries have already been removed. What is left are
  /// answers.
  final List<ItineraryVm> itineraries;

  final Attribution attribution;

  /// Why there is nothing to show, as a key the screen can write Arabic copy
  /// for. Comes from the server, which knows whether the cause was coverage
  /// or the time of day.
  final NoteCode? noteCode;

  /// The server's English prose. Shown only when [noteCode] is missing or
  /// unrecognised — an English sentence beats a blank screen, but it loses
  /// to Arabic copy.
  final String? note;

  bool get hasResults => itineraries.isNotEmpty;

  @override
  List<Object?> get props => [
    itineraries,
    attribution,
    note,
    noteCode,
    cachedAt,
  ];
}
