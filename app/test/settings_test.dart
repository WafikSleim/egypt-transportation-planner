import 'package:egypt_transport/core/settings/settings_cubit.dart';
import 'package:egypt_transport/core/storage/key_value_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('first run, with nothing stored', () {
    test('an Egyptian phone gets Arabic', () {
      final cubit = SettingsCubit(
        InMemoryStore(),
        systemLocale: const Locale('ar', 'EG'),
      );
      expect(cubit.state.locale.languageCode, 'ar');
      expect(cubit.state.themeMode, ThemeMode.system);
    });

    test('an English phone gets the English port', () {
      final cubit = SettingsCubit(
        InMemoryStore(),
        systemLocale: const Locale('en', 'GB'),
      );
      expect(cubit.state.locale.languageCode, 'en');
    });

    test('any other locale gets Arabic, not English', () {
      // Arabic is this app's source language rather than a translation of it,
      // so it is the default for everything that is not explicitly English.
      final cubit = SettingsCubit(
        InMemoryStore(),
        systemLocale: const Locale('fr', 'FR'),
      );
      expect(cubit.state.locale.languageCode, 'ar');
    });
  });

  group('a stored choice wins over the phone', () {
    test('language', () {
      final store = InMemoryStore({'settings': '{"language":"en"}'});
      final cubit = SettingsCubit(store, systemLocale: const Locale('ar'));
      expect(cubit.state.locale.languageCode, 'en');
    });

    test('theme', () {
      final store = InMemoryStore({'settings': '{"theme":"dark"}'});
      final cubit = SettingsCubit(store, systemLocale: const Locale('ar'));
      expect(cubit.state.themeMode, ThemeMode.dark);
    });
  });

  group('choices are persisted', () {
    test('language is written, and read back by the next launch', () async {
      final store = InMemoryStore();
      SettingsCubit(store, systemLocale: const Locale('ar')).setLanguage('en');
      await Future<void>.delayed(Duration.zero);

      expect(store.read('settings'), contains('"language":"en"'));

      final relaunched = SettingsCubit(store, systemLocale: const Locale('ar'));
      expect(relaunched.state.locale.languageCode, 'en');
    });

    test('theme is written, and read back by the next launch', () async {
      final store = InMemoryStore();
      SettingsCubit(
        store,
        systemLocale: const Locale('ar'),
      ).setThemeMode(ThemeMode.dark);
      await Future<void>.delayed(Duration.zero);

      final relaunched = SettingsCubit(store, systemLocale: const Locale('ar'));
      expect(relaunched.state.themeMode, ThemeMode.dark);
    });

    test('changing one does not clear the other', () {
      final store = InMemoryStore({
        'settings': '{"language":"en","theme":"dark"}',
      });
      final cubit = SettingsCubit(store, systemLocale: const Locale('ar'))
        ..setLanguage('ar');

      expect(cubit.state.themeMode, ThemeMode.dark);
    });
  });

  group('bad stored data does not stop the app starting', () {
    // Every one of these is a phone that would otherwise fail to launch, for
    // data the user cannot see and cannot clear without reinstalling.

    test('text that is not JSON', () {
      final cubit = SettingsCubit(
        InMemoryStore({'settings': 'not json at all'}),
        systemLocale: const Locale('ar'),
      );
      expect(cubit.state.locale.languageCode, 'ar');
    });

    test('JSON that is not an object', () {
      final cubit = SettingsCubit(
        InMemoryStore({'settings': '["ar"]'}),
        systemLocale: const Locale('en'),
      );
      expect(cubit.state.locale.languageCode, 'en');
    });

    test('a language this build does not have', () {
      // Written by a newer build that supports more languages.
      final cubit = SettingsCubit(
        InMemoryStore({'settings': '{"language":"fr"}'}),
        systemLocale: const Locale('en'),
      );
      expect(cubit.state.locale.languageCode, 'en');
    });

    test('a language of the wrong type', () {
      final cubit = SettingsCubit(
        InMemoryStore({'settings': '{"language":7}'}),
        systemLocale: const Locale('ar'),
      );
      expect(cubit.state.locale.languageCode, 'ar');
    });
  });

  test('an unsupported language cannot be set', () {
    final cubit = SettingsCubit(
      InMemoryStore(),
      systemLocale: const Locale('ar'),
    )..setLanguage('fr');
    expect(cubit.state.locale.languageCode, 'ar');
  });

  group('KeyValueStore.readJson', () {
    test('returns null rather than throwing on rubbish', () {
      expect(InMemoryStore({'k': '{oops'}).readJson('k'), isNull);
      expect(InMemoryStore().readJson('missing'), isNull);
    });

    test('round-trips an object', () async {
      final store = InMemoryStore();
      await store.writeJson('k', {'a': 1});
      expect(store.readJson('k'), {'a': 1});
    });
  });
}
