import 'package:equatable/equatable.dart';

import '../../data/models/models.dart';

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

  @override
  List<Object?> get props => [
        badge, isTransit, isWalk, fromName, toName, startTime, endTime,
        durationMinutes, distanceM, intermediateStops, routeLabel,
        showNumberBadge, numberBadgeText, operatorName,
      ];
}

class ItineraryVm extends Equatable {
  const ItineraryVm({
    required this.startTime,
    required this.endTime,
    required this.durationMinutes,
    required this.walkDistanceM,
    required this.transfers,
    required this.legs,
  });

  final DateTime startTime;
  final DateTime endTime;
  final int durationMinutes;
  final int walkDistanceM;
  final int transfers;
  final List<LegVm> legs;

  /// The badges worth showing on a summary card: transit only. A row of walk
  /// chips between every leg says nothing and crowds out what does.
  List<ModeBadgeVm> get transitBadges =>
      legs.where((l) => l.isTransit).map((l) => l.badge).toList(growable: false);

  @override
  List<Object?> get props =>
      [startTime, endTime, durationMinutes, walkDistanceM, transfers, legs];
}

class PlanVm extends Equatable {
  const PlanVm({
    required this.itineraries,
    required this.attribution,
    this.note,
    this.noteCode,
  });

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
  List<Object?> get props => [itineraries, attribution, note, noteCode];
}
