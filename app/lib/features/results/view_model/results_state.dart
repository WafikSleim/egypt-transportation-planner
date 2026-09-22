import 'package:equatable/equatable.dart';

import '../../../core/network/api_failure.dart';
import '../../../core/presentation/view_models.dart';

sealed class ResultsState extends Equatable {
  const ResultsState();

  @override
  List<Object?> get props => const [];
}

/// Waiting, with a ceiling.
///
/// [slow] flips on once the wait has gone past the point where a healthy
/// request would have answered. It is not a second kind of loading — it is
/// the same wait, admitting to itself. The wait ends either way: the request
/// carries a hard timeout, so this state cannot outlive it.
class ResultsLoading extends ResultsState {
  const ResultsLoading({this.slow = false});

  final bool slow;

  @override
  List<Object?> get props => [slow];
}

/// Note that "loaded" does not mean "found something".
///
/// A plan can come back with nothing to show — the walk-only itineraries
/// having been dropped as non-answers — and that is a successful request
/// with an explanation attached, not a failure. `plan.hasResults` and
/// `plan.note` are what the screen branches on.
class ResultsLoaded extends ResultsState {
  const ResultsLoaded(this.plan);

  final PlanVm plan;

  @override
  List<Object?> get props => [plan];
}

/// The request failed and there is a saved answer to this same question.
///
/// A separate state rather than a flag on [ResultsLoaded], because the state
/// is sealed: a screen that renders results has to name this case, and cannot
/// fall into it by accident. `plan.cachedAt` carries the same fact onward to
/// every screen the itinerary is handed to afterwards.
///
/// [failure] is kept because the user is owed both halves: what went wrong
/// just now, and how old the thing they are looking at is.
class ResultsFromCache extends ResultsState {
  const ResultsFromCache({
    required this.plan,
    required this.failure,
    required this.fromLabel,
    required this.toLabel,
  });

  final PlanVm plan;
  final ApiFailure failure;

  /// The endpoints of the **saved** trip, which are not necessarily the
  /// labels on screen: a saved plan matches a question asked from within
  /// about a block of it, so the two can differ by a stop. Showing the saved
  /// trip's own names is what keeps that match honest rather than silent.
  final String fromLabel;
  final String toLabel;

  DateTime get savedAt => plan.cachedAt!;

  @override
  List<Object?> get props => [plan, failure.kind, fromLabel, toLabel];
}

class ResultsFailed extends ResultsState {
  const ResultsFailed(this.failure);

  final ApiFailure failure;

  @override
  List<Object?> get props => [failure.kind, failure.status];
}
