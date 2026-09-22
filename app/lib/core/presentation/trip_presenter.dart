import '../../data/models/models.dart';
import 'mode_catalog.dart';
import 'view_models.dart';

/// Turns wire models into view-ready state.
///
/// ### Why this exists
///
/// Four of the rules in `docs/design-system.md` are presentation rules
/// *derived from data fields* — whether a route-number badge may be drawn,
/// whether a walk-only itinerary counts as an answer, which badge shape a
/// mode takes, which colour it gets. Read those fields inside widgets and
/// they get read again on the results card, the detail screen, the saved
/// trip, the tracking screen — and one of those will eventually get it
/// wrong, silently, in a way that makes the product lie.
///
/// So they are decided once, here, and the Views are left with no branch to
/// get wrong. This class is pure, which is what makes it testable without a
/// widget tree.
///
/// ### This maps, it does not derive
///
/// The server already resolved mode from `agency_id` and already set
/// `is_walk_only`. Nothing here re-derives either. In particular there is no
/// path from a GTFS `route_type` to a mode: the road feed types all 1,011 of
/// its routes as `3`, microbuses included.
class TripPresenter {
  const TripPresenter({required this.languageCode});

  /// Only picks between the two labels the server already sent. Stop names
  /// and route display names arrive localised and are passed through.
  final String languageCode;

  bool get _isArabic => languageCode == 'ar';

  /// [cachedAt] is passed in, never worked out here — this class maps, it
  /// does not derive. It is when the response was saved on the phone, and
  /// null for an answer that just came off the wire. Setting it marks the
  /// plan **and every itinerary in it**, so no screen downstream can render a
  /// saved answer without knowing it is one.
  PlanVm plan(PlanResponse response, {DateTime? cachedAt}) {
    // Rule: a walk-only itinerary is not a result.
    //
    // The transit feeds cover Greater Cairo; the street network covers the
    // whole country. Ask for a trip in Aswan and the router answers with a
    // walk, which looks exactly like an answer. Dropping these is the only
    // way the screen can tell the truth, and the server's `note` says why
    // there is nothing left.
    final answers = response.itineraries
        .where((i) => !i.isWalkOnly)
        .map((i) => itinerary(i, cachedAt: cachedAt))
        .toList(growable: false);

    return PlanVm(
      itineraries: answers,
      attribution: response.attribution,
      note: response.note,
      noteCode: response.noteCode,
      cachedAt: cachedAt,
    );
  }

  ItineraryVm itinerary(Itinerary it, {DateTime? cachedAt}) => ItineraryVm(
    startTime: it.startTime,
    endTime: it.endTime,
    durationMinutes: it.durationMinutes,
    walkDistanceM: it.walkDistanceM,
    transfers: it.transfers,
    legs: it.legs.map(leg).toList(growable: false),
    cachedAt: cachedAt,
  );

  LegVm leg(Leg l) {
    final route = l.route;
    final badge = modeBadge(l.mode, route);

    // Rule: no route-number badge when `has_line_number` is false.
    //
    // Hundreds of microbus routes are named literally "Microbus", because
    // real microbuses in Cairo carry no number. Showing "Microbus" in a
    // number badge would read as a line called Microbus; showing an empty
    // badge would read as missing data. Neither is true, so there is no
    // badge — the route is identified by origin and destination instead.
    //
    // The metro is the one case where a number exists and still gets no
    // separate chip: its circular badge already *is* the line number, so a
    // number chip beside it renders "M1" twice.
    final showNumber =
        route != null &&
        route.hasLineNumber &&
        (route.shortName?.trim().isNotEmpty ?? false) &&
        badge.shape != ModeBadgeShape.metroCircle;

    return LegVm(
      badge: badge,
      isTransit: l.isTransit,
      isWalk: l.mode.isWalk,
      fromName: l.from.name,
      toName: l.to.name,
      startTime: l.startTime,
      endTime: l.endTime,
      durationMinutes: l.durationMinutes,
      distanceM: l.distanceM,
      intermediateStops: l.intermediateStops,
      routeLabel: route?.displayName ?? modeLabel(l.mode),
      showNumberBadge: showNumber,
      numberBadgeText: showNumber ? route.shortName : null,
      operatorName: route?.operator,
    );
  }

  ModeBadgeVm modeBadge(ModeInfo mode, RouteInfo? route) {
    final isMetro = mode.id == 'metro';
    return ModeBadgeVm(
      modeId: mode.id,
      label: modeLabel(mode),
      shape: isMetro ? ModeBadgeShape.metroCircle : ModeBadgeShape.pill,
      metroLine: isMetro ? route?.shortName : null,
    );
  }

  String modeLabel(ModeInfo mode) {
    final label = _isArabic ? mode.labelAr : mode.labelEn;
    return label.isEmpty ? mode.labelEn : label;
  }

  /// A stop's mode marks, for the picker.
  ///
  /// `/stops` returns mode ids only, so the labels come from [ModeCatalog].
  /// Same ids, same shapes, same colours as a leg: a stop served by the
  /// metro must not show a pill any more than a metro leg may.
  List<ModeBadgeVm> stopBadges(StopSummary stop) {
    return stop.modes
        .map(
          (id) => ModeBadgeVm(
            modeId: id,
            label: ModeCatalog.label(id, languageCode),
            shape: id == 'metro'
                ? ModeBadgeShape.metroCircle
                : ModeBadgeShape.pill,
          ),
        )
        .toList(growable: false);
  }
}
