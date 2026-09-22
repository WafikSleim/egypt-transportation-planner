/// On-device storage.
///
/// ### Why `shared_preferences` and not `drift`
///
/// Settled 2026-09-22. The three things this app will ever keep on a phone
/// are the language and theme choice, a short list of recent endpoints, and a
/// handful of saved trips. All of them are read whole and shown in order;
/// none of them is ever queried. A few dozen JSON-serialisable entries do not
/// need SQL, and `drift` would bring `build_runner`, generated code and a
/// native SQLite dependency to hold them.
///
/// **What would change the answer:** wanting to *query* history rather than
/// list it — "trips I take on weekday mornings", or a trip history long
/// enough that reading it whole becomes wasteful. Neither is on the backlog.
/// If one arrives, this interface is the seam: swapping the implementation is
/// one class, because nothing above it knows what is underneath.
///
/// ### Why reads are synchronous
///
/// `SharedPreferences` loads everything into memory once, so a read after
/// [open] costs nothing. Making reads async would force a loading state onto
/// the very first frame, and the app would flash the wrong theme and the
/// wrong language before settling — for data that was already in memory.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

abstract class KeyValueStore {
  String? read(String key);

  Future<void> write(String key, String value);

  Future<void> remove(String key);

  /// Convenience for the JSON blobs everything here actually stores.
  ///
  /// Returns null rather than throwing when the stored text is not valid
  /// JSON. A phone that once held a half-written or older-format value should
  /// fall back to defaults, not fail to start.
  Map<String, dynamic>? readJson(String key) {
    final raw = read(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> writeJson(String key, Map<String, dynamic> value) =>
      write(key, jsonEncode(value));
}

class SharedPreferencesStore extends KeyValueStore {
  SharedPreferencesStore._(this._prefs);

  /// Call once, before `runApp`, so the first frame already knows the
  /// language and theme.
  static Future<SharedPreferencesStore> open() async =>
      SharedPreferencesStore._(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  @override
  String? read(String key) => _prefs.getString(key);

  @override
  Future<void> write(String key, String value) => _prefs.setString(key, value);

  @override
  Future<void> remove(String key) => _prefs.remove(key);
}

/// For tests, and for a first run where storage is unavailable.
///
/// The app must work with nothing persisted — that is simply the state of
/// every phone before it is opened for the first time.
class InMemoryStore extends KeyValueStore {
  InMemoryStore([Map<String, String>? seed]) : _values = {...?seed};

  final Map<String, String> _values;

  Map<String, String> get contents => Map.unmodifiable(_values);

  @override
  String? read(String key) => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> remove(String key) async => _values.remove(key);
}
