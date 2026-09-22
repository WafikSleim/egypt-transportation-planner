import 'dart:ui' show PlatformDispatcher;

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../storage/key_value_store.dart';

class Settings extends Equatable {
  const Settings({required this.locale, required this.themeMode});

  final Locale locale;
  final ThemeMode themeMode;

  @override
  List<Object?> get props => [locale, themeMode];
}

/// App-wide settings. Deliberately tiny: passengers get no settings screen,
/// and this exists only for the two choices that genuinely belong to them.
///
/// The language here also becomes the `lang` on every API request, via the
/// callback handed to `ApiClient`. Stop names are localised server-side, so
/// this single value decides whether itineraries come back Arabic or Latin.
class SettingsCubit extends Cubit<Settings> {
  SettingsCubit(this._store, {Locale? systemLocale})
    : super(_restore(_store, systemLocale ?? _platformLocale()));

  static const _key = 'settings';
  static const _supported = {'ar', 'en'};

  final KeyValueStore _store;

  static Locale _platformLocale() => PlatformDispatcher.instance.locale;

  /// What to show before anybody has chosen anything.
  ///
  /// **Arabic unless the phone is set to English.** Arabic is the source
  /// language of this app rather than a translation of it, so it is the
  /// default for every locale that is not explicitly English — a phone set to
  /// French belongs to someone in Cairo more often than not, and Arabic is
  /// the better guess for them than the English port.
  static Settings _restore(KeyValueStore store, Locale systemLocale) {
    final stored = store.readJson(_key);

    final language =
        _oneOf(stored?['language'], _supported)
        // A value written by a newer build, or a hand-edited file, falls back
        // rather than crashing the app on launch.
        ??
        (systemLocale.languageCode == 'en' ? 'en' : 'ar');

    final theme = switch (stored?['theme']) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

    return Settings(locale: Locale(language), themeMode: theme);
  }

  static String? _oneOf(Object? value, Set<String> allowed) =>
      value is String && allowed.contains(value) ? value : null;

  void setLanguage(String code) {
    if (!_supported.contains(code)) return;
    _emitAndPersist(Settings(locale: Locale(code), themeMode: state.themeMode));
  }

  void setThemeMode(ThemeMode mode) {
    _emitAndPersist(Settings(locale: state.locale, themeMode: mode));
  }

  void _emitAndPersist(Settings next) {
    emit(next);
    // Deliberately not awaited: the UI has already changed, and a write that
    // loses a race with a force-quit costs the user one tap. Blocking the
    // toggle on a disk write would be worse.
    _store.writeJson(_key, {
      'language': next.locale.languageCode,
      'theme': next.themeMode.name,
    });
  }
}
