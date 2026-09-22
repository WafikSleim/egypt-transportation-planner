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
  Future<bool> setAllowed(NotificationKind kind, {required bool allowed}) async {
    if (!kind.canBeSilenced) return false;

    final stored = _store.readJson(_key) ?? <String, dynamic>{};
    await _store.writeJson(_key, {...stored, kind.name: allowed});
    return true;
  }

  Map<NotificationKind, bool> get all => {
    for (final kind in NotificationKind.values) kind: isAllowed(kind),
  };
}
