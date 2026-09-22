import 'dart:async';

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
///
/// ### What happens when the request fails
///
/// On a low-end phone on patchy data — the normal case in Cairo, not the edge
/// case — a failed request is not an exceptional event. So a failure first
/// asks the repository whether there is a saved answer to this same question,
/// and shows that if there is, as [ResultsFromCache]. Only if there is none,
/// or it is too old to offer, does the screen become an error.
class ResultsCubit extends Cubit<ResultsState> {
  ResultsCubit({
    required PlannerRepository repository,
    required TripPresenter presenter,
    required this.from,
    required this.to,
    required this.departAt,
    this.arriveBy = false,
    this.slowAfter = const Duration(seconds: 4),
  }) : _repository = repository,
       _presenter = presenter,
       super(const ResultsLoading());

  final PlannerRepository _repository;
  final TripPresenter _presenter;

  final TripEndpoint from;
  final TripEndpoint to;
  final DateTime departAt;
  final bool arriveBy;

  /// When to stop pretending this is going normally.
  ///
  /// Four seconds. A healthy `/plan` answers in about one, so by four the
  /// likely outcome is the timeout rather than a result, and saying so is the
  /// difference between a spinner and an explanation. Injectable because a
  /// widget test that waits four real seconds is a widget test nobody runs.
  final Duration slowAfter;

  Timer? _slowTimer;

  Future<void> load() async {
    _slowTimer?.cancel();
    emit(const ResultsLoading());
    _slowTimer = Timer(slowAfter, () {
      if (!isClosed && state is ResultsLoading) {
        emit(const ResultsLoading(slow: true));
      }
    });

    try {
      final response = await _repository.plan(
        from: from.point,
        to: to.point,
        departAt: departAt,
        arriveBy: arriveBy,
        fromLabel: from.label,
        toLabel: to.label,
      );
      if (isClosed) return;
      emit(ResultsLoaded(_presenter.plan(response)));
    } on ApiFailure catch (e) {
      if (isClosed) return;
      emit(_afterFailure(e));
    } catch (e) {
      if (isClosed) return;
      emit(_afterFailure(ApiFailure(FailureKind.unexpected, detail: '$e')));
    } finally {
      // Cancelled on every path, success included: a pending timer outliving
      // the screen is both a leak and a test failure.
      _slowTimer?.cancel();
    }
  }

  ResultsState _afterFailure(ApiFailure failure) {
    final cached = _repository.lastPlan(
      from: from.point,
      to: to.point,
      departAt: departAt,
      arriveBy: arriveBy,
    );
    if (cached == null) return ResultsFailed(failure);

    final plan = _presenter.plan(cached.response, cachedAt: cached.savedAt);
    // Belt and braces: the cache refuses to store a plan with no answer in
    // it, but the walk-only rule lives in the presenter, and a saved plan
    // that presents to nothing must not put the empty-results screen behind a
    // banner claiming it is a saved answer.
    if (!plan.hasResults) return ResultsFailed(failure);

    return ResultsFromCache(
      // The saved time was handed to the presenter rather than set by the
      // View, so it reaches every itinerary in the plan and travels on with
      // them to the detail screen.
      plan: plan,
      failure: failure,
      fromLabel: cached.fromLabel,
      toLabel: cached.toLabel,
    );
  }

  @override
  Future<void> close() {
    _slowTimer?.cancel();
    return super.close();
  }
}
