/// What went wrong, in terms the UI can act on.
///
/// Deliberately small. The screens distinguish only three situations, because
/// only three lead to different advice for the user: the network is not
/// there, the server is not there, or something else happened.
enum FailureKind {
  /// No route to the server at all — aeroplane mode, no signal, wrong host.
  offline,

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
