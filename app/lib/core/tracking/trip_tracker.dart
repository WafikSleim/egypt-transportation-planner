import 'dart:math' as math;

import 'package:equatable/equatable.dart';

import '../../domain/entities/trip_endpoint.dart';
import 'tracked_trip.dart';
import 'tracking_source.dart';

/// Why the tracker will not say where the passenger is.
enum UnsureReason {
  /// The latest fix is too coarse to compare with a stop.
  poorFix,

  /// A good fix, but a long way from the recorded ride. Either the passenger
  /// took something else or the recorded route is not the road - the tracker
  /// cannot tell which, so it says so instead of guessing.
  offRoute,

  /// Nothing new for a while, or the OS reported the signal gone.
  noSignal,
}

/// What the tracker is prepared to claim. Never a time, and never a vehicle.
///
/// There is no ETA anywhere in this type, and that is the point of it: the app
/// has no real-time data for Cairo's paratransit and nothing to compute an
/// arrival from. The most it can honestly say is how far the passenger's *own*
/// phone is from the stop they get off at.
sealed class TrackingEstimate extends Equatable {
  const TrackingEstimate();

  @override
  List<Object?> get props => const [];
}

/// No usable fix yet.
class Searching extends TrackingEstimate {
  const Searching();
}

/// Low confidence, stated as such. The screen says "مش متأكدين إنك في السكة
/// الصح" and shows no distance - a number here would be false precision.
class Unsure extends TrackingEstimate {
  const Unsure(this.reason);

  final UnsureReason reason;

  @override
  List<Object?> get props => [reason];
}

/// A confident fix, still some way from the stop.
class OnRoute extends TrackingEstimate {
  const OnRoute({required this.alightName, required this.distanceM});

  final String alightName;

  /// Straight-line metres from the phone to the stop, **rounded to 100** -
  /// finer than the GPS can back up.
  final int distanceM;

  @override
  List<Object?> get props => [alightName, distanceM];
}

/// Close to the stop to get off at; the alert has been raised.
class NearAlight extends TrackingEstimate {
  const NearAlight({required this.alightName});

  final String alightName;

  @override
  List<Object?> get props => [alightName];
}

/// The last ride is over.
class TripDone extends TrackingEstimate {
  const TripDone();
}

/// What one fix (or a tick of the clock) did.
class TrackerUpdate extends Equatable {
  const TrackerUpdate(this.estimate, {this.alertFor, this.finished = false});

  final TrackingEstimate estimate;

  /// Set exactly once per ride: the stop to tell the passenger they are
  /// approaching.
  final TrackedLeg? alertFor;

  final bool finished;

  @override
  List<Object?> get props => [estimate, alertFor, finished];
}

/// Compares the passenger's own GPS with the recorded stops (#24, #25).
///
/// Pure: it takes fixes and returns what it is willing to claim, with no
/// clock, no platform and no I/O, so the whole policy is testable without a
/// phone. **Every threshold below is a first guess that has never met a real
/// road.** They are named and documented so the first ride on real hardware
/// has somewhere to tune; none is derived from data.
///
/// What it does *not* do: it does not know the road. A microbus does not
/// follow the straight line between its two stops, so "on route" is a wide
/// corridor around that line, and anything outside is called *unsure* rather
/// than *wrong*.
class TripTracker {
  TripTracker(this.trip);

  final TrackedTrip trip;

  /// Worse than this and the fix is not compared with anything: a reading that
  /// could be 150 m out cannot say whether the stop is 300 m away or 100.
  static const maxUsableAccuracyM = 100.0;

  /// Distance at which "get ready to get off" is raised. About a minute's
  /// travel for a microbus in traffic, and far enough that the passenger can
  /// reach the door.
  static const alertRadiusM = 400.0;

  /// Distance at which a ride counts as finished.
  static const arriveRadiusM = 150.0;

  /// Consecutive confident fixes inside a radius before the tracker acts on
  /// it. One fix is a reading; two is a pattern. Stops a single multipath
  /// spike from waking someone, and from ending a trip that has not ended.
  static const confirmFixes = 2;

  /// The corridor around the straight line between two stops inside which a
  /// fix still counts as "on route": the larger of this and a third of the
  /// line's own length, because a long ride wanders further from its chord.
  static const minCorridorM = 600.0;
  static const corridorFraction = 0.35;

  /// Past this long without a fix the estimate is withdrawn.
  static const staleAfter = Duration(seconds: 90);

  int _index = 0;
  int _inAlert = 0;
  int _inArrive = 0;
  bool _alerted = false;
  double _closestM = double.infinity;
  DateTime? _lastFixAt;
  TrackingEstimate _estimate = const Searching();
  bool _done = false;

  TrackingEstimate get estimate => _estimate;

  /// Index of the ride being followed, for tests.
  int get legIndex => _index;

  TrackerUpdate onFix(LocationFix fix) {
    if (_done) return TrackerUpdate(_estimate, finished: true);
    _lastFixAt = fix.at;

    if (fix.accuracyM > maxUsableAccuracyM) {
      _inAlert = 0;
      _inArrive = 0;
      return _set(const Unsure(UnsureReason.poorFix));
    }

    // A ride can end because the passenger got off, or because they went
    // past. Either way it is over once they are clearly moving away from a
    // stop they had already been told about, and the next ride is the one to
    // compare against. Looped because one fix may finish a ride and begin
    // the next.
    while (true) {
      final leg = trip.legs[_index];
      final d = _metres(fix.point, leg.alight);
      if (d < _closestM) _closestM = d;

      final passed =
          _alerted && d > math.max(alertRadiusM * 2, _closestM + 300);
      if (passed) {
        if (_advance()) return TrackerUpdate(_estimate, finished: true);
        continue;
      }

      _inArrive = d <= arriveRadiusM ? _inArrive + 1 : 0;
      if (_inArrive >= confirmFixes) {
        if (_advance()) return TrackerUpdate(_estimate, finished: true);
        continue;
      }

      if (d <= alertRadiusM) {
        _inAlert++;
        if (_inAlert >= confirmFixes) {
          final first = !_alerted;
          _alerted = true;
          return TrackerUpdate(
            _set(NearAlight(alightName: leg.alightName)).estimate,
            alertFor: first ? leg : null,
          );
        }
        // Inside the radius but not yet confirmed: still just on the way.
        return _set(
          OnRoute(alightName: leg.alightName, distanceM: _rounded(d)),
        );
      }
      _inAlert = 0;

      final from = _index == 0 ? leg.board : trip.legs[_index - 1].alight;
      final chord = _metres(from, leg.alight);
      final corridor = math.max(minCorridorM, chord * corridorFraction);
      if (_distanceToSegment(fix.point, from, leg.alight) > corridor) {
        return _set(const Unsure(UnsureReason.offRoute));
      }

      return _set(OnRoute(alightName: leg.alightName, distanceM: _rounded(d)));
    }
  }

  /// The OS said the stream failed - location switched off mid-ride, say.
  TrackerUpdate onSignalLost() => _done
      ? TrackerUpdate(_estimate)
      : _set(const Unsure(UnsureReason.noSignal));

  /// Called on a timer. Withdraws the estimate when nothing has arrived for
  /// [staleAfter], because the last good fix stays on screen looking current
  /// for exactly as long as nobody checks.
  TrackerUpdate onTick(DateTime now) {
    final last = _lastFixAt;
    if (_done || last == null) return TrackerUpdate(_estimate);
    if (now.difference(last) > staleAfter) {
      return _set(const Unsure(UnsureReason.noSignal));
    }
    return TrackerUpdate(_estimate);
  }

  /// Moves to the next ride. Returns true when there is none left.
  bool _advance() {
    _inAlert = 0;
    _inArrive = 0;
    _alerted = false;
    _closestM = double.infinity;
    if (_index + 1 >= trip.legs.length) {
      _done = true;
      _estimate = const TripDone();
      return true;
    }
    _index++;
    return false;
  }

  TrackerUpdate _set(TrackingEstimate e) {
    _estimate = e;
    return TrackerUpdate(e);
  }

  /// To the nearest 100 m, never below 100 - the GPS cannot back up more.
  static int _rounded(double metres) =>
      math.max(100, (metres / 100).round() * 100);
}

const _earthM = 6371000.0;

double _rad(double deg) => deg * math.pi / 180;

/// Great-circle distance in metres.
double _metres(GeoPoint a, GeoPoint b) {
  final dLat = _rad(b.lat - a.lat);
  final dLon = _rad(b.lon - a.lon);
  final h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(_rad(a.lat)) *
          math.cos(_rad(b.lat)) *
          math.pow(math.sin(dLon / 2), 2);
  return 2 * _earthM * math.asin(math.min(1, math.sqrt(h)));
}

/// Metres from [p] to the segment [a]-[b], on a local flat projection - good
/// to well under a percent over the few tens of kilometres of a Cairo trip.
double _distanceToSegment(GeoPoint p, GeoPoint a, GeoPoint b) {
  final lat0 = _rad((a.lat + b.lat) / 2);
  double x(GeoPoint g) => _rad(g.lon) * math.cos(lat0) * _earthM;
  double y(GeoPoint g) => _rad(g.lat) * _earthM;

  final ax = x(a), ay = y(a), bx = x(b), by = y(b), px = x(p), py = y(p);
  final dx = bx - ax, dy = by - ay;
  final len2 = dx * dx + dy * dy;
  final t = len2 == 0
      ? 0.0
      : (((px - ax) * dx + (py - ay) * dy) / len2).clamp(0.0, 1.0);
  final cx = ax + t * dx, cy = ay + t * dy;
  return math.sqrt(math.pow(px - cx, 2) + math.pow(py - cy, 2));
}
