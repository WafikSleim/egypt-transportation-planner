import '../storage/key_value_store.dart';
import 'notification_kind.dart';

/// Which kinds of notification the passenger still wants.
///
/// Stored per kind rather than as one master switch, because the three
/// messages are not one thing: someone may want a reminder before a trip and
/// nothing at all afterwards, and making them choose all-or-nothing is how an
/// app ends up with everything switched off.
///
/// **Default is on.** The real opt-in is the OS permission, which is asked in
/// context and refused by doing nothing; a second off-by-default switch
/// underneath it would mean granting permission and then getting silence.
/// This is the opt-out, and it is reachable from the notification itself and
/// from the About screen.
class NotificationPreferences {
  NotificationPreferences(this._store);

  static const _key = 'notifications';

  /// Stored beside the per-kind flags. Safe because no [NotificationKind] is
  /// named `asked`, and the switch over the enum would have to change for one
  /// ever to be.
  static const _askedKey = 'asked';

  final KeyValueStore _store;

  /// Whether the OS prompt has been shown once already.
  ///
  /// Android does not tell an app that POST_NOTIFICATIONS was refused for
  /// good — the plugin answers `false` for "not yet" and for "never again"
  /// alike. So the app remembers that it asked, and a refusal after that is
  /// treated as permanent, which is the difference between offering the
  /// prompt again and offering the settings screen. Getting this wrong in
  /// the safe direction costs a settings link nobody needed; getting it
  /// wrong the other way is a button that does nothing.
  bool get hasBeenAsked => _store.readJson(_key)?[_askedKey] == true;

  Future<void> markAsked() async {
    final stored = _store.readJson(_key) ?? <String, dynamic>{};
    await _store.writeJson(_key, {...stored, _askedKey: true});
  }

  bool isAllowed(NotificationKind kind) {
    // The ongoing tracking notice is not a preference. Tracking without it
    // would be GPS running with nothing on screen saying so.
    if (!kind.canBeSilenced) return true;

    final stored = _store.readJson(_key);
    final value = stored?[kind.name];
    // Anything that is not an explicit `false` — a missing key, a value
    // written by a newer build, a hand-edited file — means on. Bad stored
    // data must not silently disable a reminder somebody is relying on.
    return value is bool ? value : true;
  }

  /// Returns false, and writes nothing, for a kind that may not be silenced.
  Future<bool> setAllowed(
    NotificationKind kind, {
    required bool allowed,
  }) async {
    if (!kind.canBeSilenced) return false;

    final stored = _store.readJson(_key) ?? <String, dynamic>{};
    await _store.writeJson(_key, {...stored, kind.name: allowed});
    return true;
  }

  Map<NotificationKind, bool> get all => {
    for (final kind in NotificationKind.values) kind: isAllowed(kind),
  };

  // ------------------------------------------------------ the post-trip cap

  static const _askedTripsKey = 'post_trip_asked';

  /// How many trips the ledger remembers. Session keys are minted from a
  /// microsecond clock and never reused, so forgetting an old one cannot let
  /// it be asked again — the bound only keeps the file small.
  static const maxRememberedTrips = 50;

  List<String> get _askedTrips {
    final items = _store.readJson(_askedTripsKey)?['items'];
    return items is List ? items.whereType<String>().toList() : <String>[];
  }

  /// The trip the most recent question was about — what a tap on that
  /// notification refers to, since a payload carries a kind and a slot and
  /// deliberately nothing about the trip.
  String? get lastPostTripSession => _askedTrips.lastOrNull;

  /// Whether the one question for this trip has already been spent.
  bool postTripQuestionSpent(String sessionKey) =>
      _askedTrips.contains(sessionKey);

  /// Spend the one question this trip is allowed. **True exactly once per
  /// key.**
  ///
  /// Called by `NotificationService.post` immediately before delivery, and
  /// written *before* the notification is shown rather than after: the point
  /// of the cap is that an ignored question is a spent one, so the record
  /// must not depend on the passenger doing anything. An empty key is
  /// refused, because "no trip" would otherwise be one shared key that every
  /// later question could be waved through under — or blocked by.
  Future<bool> claimPostTripQuestion(String sessionKey) async {
    if (sessionKey.isEmpty) return false;

    final asked = _askedTrips;
    if (asked.contains(sessionKey)) return false;

    final kept = [...asked, sessionKey];
    final trimmed = kept.length > maxRememberedTrips
        ? kept.sublist(kept.length - maxRememberedTrips)
        : kept;
    await _store.writeJson(_askedTripsKey, {'items': trimmed});
    return true;
  }

  // -------------------------------------------------- the post-trip answers

  static const _answersKey = 'post_trip_answers';

  /// "Was it right?" answers, kept **on this phone only**.
  ///
  /// There is no contribution pipeline yet (it is Phase 4), so there is
  /// nowhere to send these and the app says so rather than implying a
  /// correction was filed. They are recorded so that the pipeline, when it
  /// exists, has something to offer to send — with the passenger's say-so.
  Map<String, bool> get postTripAnswers {
    final raw = _store.readJson(_answersKey);
    return {
      for (final e in raw?.entries ?? const <MapEntry<String, dynamic>>[])
        if (e.value is bool) e.key: e.value as bool,
    };
  }

  Future<void> recordPostTripAnswer(
    String sessionKey, {
    required bool wasRight,
  }) async {
    final answers = postTripAnswers;
    answers[sessionKey] = wasRight;
    // Newest last; keep the tail so the map cannot grow without limit.
    final entries = answers.entries.toList();
    final tail = entries.length > maxRememberedTrips
        ? entries.sublist(entries.length - maxRememberedTrips)
        : entries;
    await _store.writeJson(_answersKey, {for (final e in tail) e.key: e.value});
  }
}
