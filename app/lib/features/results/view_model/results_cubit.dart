import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/network/api_failure.dart';
import '../../../core/presentation/trip_presenter.dart';
import '../../../domain/entities/trip_endpoint.dart';
import '../../../domain/repositories/planner_repository.dart';
import 'results_state.dart';

/// ViewModel for the results screen.
///
/// The View receives only [PlanVm] — no wire models reach it, so there is no
/// `has_line_number` or `is_walk_only` left for a widget to interpret. Every
/// such decision was made by [TripPresenter] before this state was emitted.
class ResultsCubit extends Cubit<ResultsState> {
  ResultsCubit({
    required PlannerRepository repository,
    required TripPresenter presenter,
    required this.from,
    required this.to,
    required this.departAt,
    this.arriveBy = false,
  }) : _repository = repository,
       _presenter = presenter,
       super(const ResultsLoading());

  final PlannerRepository _repository;
  final TripPresenter _presenter;

  final TripEndpoint from;
  final TripEndpoint to;
  final DateTime departAt;
  final bool arriveBy;

  Future<void> load() async {
    emit(const ResultsLoading());
    try {
      final response = await _repository.plan(
        from: from.point,
        to: to.point,
        departAt: departAt,
        arriveBy: arriveBy,
      );
      emit(ResultsLoaded(_presenter.plan(response)));
    } on ApiFailure catch (e) {
      emit(ResultsFailed(e));
    } catch (e) {
      emit(ResultsFailed(ApiFailure(FailureKind.unexpected, detail: '$e')));
    }
  }
}
