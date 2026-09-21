import 'package:equatable/equatable.dart';

import '../../../domain/entities/trip_endpoint.dart';

/// What the search form holds.
///
/// A plain state class rather than a union: the form has no loading or error
/// state of its own — it either has enough to search with, or it doesn't.
class SearchState extends Equatable {
  const SearchState({this.from, this.to, this.departAt});

  final TripEndpoint? from;
  final TripEndpoint? to;

  /// Null means "now", resolved at the moment the search runs rather than
  /// when the screen opened. Sitting on the search screen for ten minutes
  /// should not plan a trip from ten minutes ago.
  final DateTime? departAt;

  bool get canSearch => from != null && to != null;

  DateTime resolvedDeparture(DateTime now) => departAt ?? now;

  @override
  List<Object?> get props => [from, to, departAt];
}
