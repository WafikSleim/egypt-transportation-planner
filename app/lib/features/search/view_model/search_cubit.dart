import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/entities/trip_endpoint.dart';
import 'search_state.dart';

/// ViewModel for the search form.
///
/// Holds no repository: the form does not plan anything. It collects two
/// endpoints and a time, and the results screen does the work — which keeps
/// a failed search from wiping the form the user just filled in.
class SearchCubit extends Cubit<SearchState> {
  SearchCubit() : super(const SearchState());

  void setFrom(TripEndpoint? endpoint) =>
      emit(SearchState(from: endpoint, to: state.to, departAt: state.departAt));

  void setTo(TripEndpoint? endpoint) => emit(
    SearchState(from: state.from, to: endpoint, departAt: state.departAt),
  );

  void swap() => emit(
    SearchState(from: state.to, to: state.from, departAt: state.departAt),
  );

  /// Pass null for "now".
  void setDeparture(DateTime? when) =>
      emit(SearchState(from: state.from, to: state.to, departAt: when));
}
