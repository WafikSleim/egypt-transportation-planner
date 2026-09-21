import 'package:equatable/equatable.dart';

import '../../../core/network/api_failure.dart';
import '../../../core/presentation/view_models.dart';

sealed class ResultsState extends Equatable {
  const ResultsState();

  @override
  List<Object?> get props => const [];
}

class ResultsLoading extends ResultsState {
  const ResultsLoading();
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

class ResultsFailed extends ResultsState {
  const ResultsFailed(this.failure);

  final ApiFailure failure;

  @override
  List<Object?> get props => [failure.kind, failure.status];
}
