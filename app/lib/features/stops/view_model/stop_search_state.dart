import 'package:equatable/equatable.dart';

import '../../../core/network/api_failure.dart';
import '../../../core/presentation/view_models.dart';
import '../../../data/models/models.dart';

/// One row in the picker: a stop plus the marks for the modes it serves.
class StopResultVm extends Equatable {
  const StopResultVm({required this.stop, required this.badges});

  final StopSummary stop;
  final List<ModeBadgeVm> badges;

  @override
  List<Object?> get props => [stop, badges];
}

sealed class StopSearchState extends Equatable {
  const StopSearchState();

  @override
  List<Object?> get props => const [];
}

/// Nothing typed yet, or too little to search with.
class StopSearchIdle extends StopSearchState {
  const StopSearchIdle();
}

class StopSearchLoading extends StopSearchState {
  const StopSearchLoading();
}

class StopSearchLoaded extends StopSearchState {
  const StopSearchLoaded({
    required this.query,
    required this.results,
    required this.totalMatches,
    required this.truncated,
    required this.attribution,
  });

  final String query;
  final List<StopResultVm> results;

  /// How many matched before the limit. A broad prefix matches hundreds, and
  /// [truncated] is what lets the screen ask for a longer query rather than
  /// imply these twenty are all of them.
  final int totalMatches;
  final bool truncated;

  final Attribution attribution;

  bool get isEmpty => results.isEmpty;

  @override
  List<Object?> get props => [query, results, totalMatches, truncated];
}

class StopSearchFailed extends StopSearchState {
  const StopSearchFailed(this.failure);

  final ApiFailure failure;

  @override
  List<Object?> get props => [failure.kind, failure.status];
}
