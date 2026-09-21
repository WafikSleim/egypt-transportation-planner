import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class Settings extends Equatable {
  const Settings({required this.locale, required this.themeMode});

  /// Arabic by default, and Arabic as the source language — the English
  /// strings are a port of the Egyptian copy, not the other way round.
  static const initial = Settings(
    locale: Locale('ar'),
    themeMode: ThemeMode.system,
  );

  final Locale locale;
  final ThemeMode themeMode;

  @override
  List<Object?> get props => [locale, themeMode];
}

/// App-wide settings. Deliberately tiny: passengers get no settings screen,
/// and this exists only for the two choices that genuinely belong to them.
///
/// Not persisted yet — that lands with recents and saved trips, which is the
/// first thing needing on-device storage.
class SettingsCubit extends Cubit<Settings> {
  SettingsCubit() : super(Settings.initial);

  /// The language here also becomes the `lang` on every API request, via the
  /// callback handed to `ApiClient`. Stop names are localised server-side, so
  /// this single value decides whether itineraries come back Arabic or Latin.
  void setLanguage(String code) =>
      emit(Settings(locale: Locale(code), themeMode: state.themeMode));

  void setThemeMode(ThemeMode mode) =>
      emit(Settings(locale: state.locale, themeMode: mode));
}
