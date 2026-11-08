import 'package:equatable/equatable.dart';

import '../../domain/entities/trip_endpoint.dart';
import '../presentation/view_models.dart';

/// One vehicle ride in a followed trip: where it is boarded and where the
/// passenger gets off.
///
/// This is the whole of "the recorded route" the app has. `/plan` returns each
/// leg's two endpoints and a count of the stops in between - no geometry, no
/// list of the intermediate stops - so the app can know when the passenger is
/// near the stop they get off at, and nothing finer. A "next stop" alert is
/// therefore an alert for the *alighting* stop (and each transfer), never for
/// the stop after this one, which the data does not contain.
class TrackedLeg extends Equatable {
  const TrackedLeg({
    required this.board,
    required this.alight,
    required this.alightName,
  });

  final GeoPoint board;
  final GeoPoint alight;

  /// Already localised by the server. Shown through `bidiIsolate` by whoever
  /// draws it.
  final String alightName;

  @override
  List<Object?> get props => [board, alight, alightName];
}

/// A trip as the tracker sees it: a label and the rides, in order.
///
/// Walking legs are left out. Nothing here claims to know whether the
/// passenger is walking the right way between two rides - only whether they
/// are near the stop they need to get off at.
class TrackedTrip extends Equatable {
  const TrackedTrip({required this.label, required this.legs});

  /// Builds from the itinerary on screen. Null when no ride has both of its
  /// endpoints, in which case there is nothing to follow and the screen offers
  /// nothing.
  static TrackedTrip? fromItinerary(ItineraryVm itinerary, String label) {
    final legs = <TrackedLeg>[
      for (final leg in itinerary.legs)
        if (leg.isTransit && leg.fromPoint != null && leg.toPoint != null)
          TrackedLeg(
            board: leg.fromPoint!,
            alight: leg.toPoint!,
            alightName: leg.toName,
          ),
    ];
    return legs.isEmpty ? null : TrackedTrip(label: label, legs: legs);
  }

  final String label;
  final List<TrackedLeg> legs;

  @override
  List<Object?> get props => [label, legs];
}
