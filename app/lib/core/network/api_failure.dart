/// What went wrong, in terms the UI can act on.
///
/// Deliberately small. Each member exists because it leads to different
/// advice for the user, and the three the passenger actually meets are the
/// three this issue asks the app to tell apart: the phone has no connection,
/// the connection was too slow to finish, or the service itself is down.
///
/// [offline] and [timedOut] are separate on purpose. Reporting a timeout as
/// "no internet connection" is the plausible-lie class this project keeps
/// refusing: the phone has four bars, the app says there is no signal, and
/// the user goes looking for a fault that is not on their side.
enum FailureKind {
  /// No route to the server at all — aeroplane mode, no signal, wrong host.
  offline,

  /// The request was still running when its ceiling ran out. Either end can
  /// cause it, so the copy says both rather than picking one.
  timedOut,

  /// The server answered, but not usefully: 5xx, or OTP behind it is down.
  /// `/health` reports `degraded` in this state.
  serverDown,

  /// The request itself was rejected — 4xx. A bug on our side, or a
  /// coordinate the API refused.
  badRequest,

  unexpected,
}

class ApiFailure implements Exception {
  const ApiFailure(this.kind, {this.status, this.detail});

  final FailureKind kind;
  final int? status;
  final String? detail;

  @override
  String toString() => 'ApiFailure($kind, status: $status, detail: $detail)';
}
