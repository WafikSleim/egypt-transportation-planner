import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/network/api_failure.dart';
import '../../../core/presentation/trip_presenter.dart';
import '../../../domain/repositories/planner_repository.dart';
import 'stop_search_state.dart';

/// ViewModel for the stop picker.
class StopSearchCubit extends Cubit<StopSearchState> {
  StopSearchCubit({
    required PlannerRepository repository,
    required TripPresenter presenter,
    this.debounce = const Duration(milliseconds: 280),
  })  : _repository = repository,
        _presenter = presenter,
        super(const StopSearchIdle());

  /// The search is prefix-based and a two-letter prefix matches hundreds of
  /// stops, so typing is debounced rather than fired per keystroke. The
  /// target is a low-end phone on patchy data.
  final Duration debounce;

  static const minimumQueryLength = 2;

  final PlannerRepository _repository;
  final TripPresenter _presenter;

  Timer? _timer;
  int _generation = 0;

  void queryChanged(String raw) {
    _timer?.cancel();
    final query = raw.trim();
    if (query.length < minimumQueryLength) {
      _generation++;
      emit(const StopSearchIdle());
      return;
    }
    _timer = Timer(debounce, () => search(query));
  }

  Future<void> search(String query) async {
    final generation = ++_generation;
    emit(const StopSearchLoading());
    try {
      final response = await _repository.searchStops(query);
      // A slower earlier request must not overwrite a newer answer.
      if (generation != _generation || isClosed) return;
      emit(StopSearchLoaded(
        query: query,
        results: response.stops
            .map((s) => StopResultVm(stop: s, badges: _presenter.stopBadges(s)))
            .toList(growable: false),
        totalMatches: response.totalMatches,
        truncated: response.truncated,
        attribution: response.attribution,
      ));
    } on ApiFailure catch (e) {
      if (generation != _generation || isClosed) return;
      emit(StopSearchFailed(e));
    } catch (e) {
      if (generation != _generation || isClosed) return;
      emit(StopSearchFailed(ApiFailure(FailureKind.unexpected, detail: '$e')));
    }
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}
