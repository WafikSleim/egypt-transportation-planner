import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/network/api_client.dart';
import 'core/settings/settings_cubit.dart';
import 'core/storage/key_value_store.dart';
import 'data/repositories/planner_repository_impl.dart';
import 'domain/repositories/planner_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Opened before the first frame, so the app never flashes the wrong theme
  // or the wrong language on its way to the stored one.
  final store = await SharedPreferencesStore.open();
  final settings = SettingsCubit(store);

  final config = AppConfig.fromEnvironment();

  // The one place `lang` is wired. Every request the app makes carries the
  // current language because the client adds it, not because each call site
  // remembered to — see ApiClient for why that matters.
  final api = ApiClient(
    baseUrl: config.apiBaseUrl,
    languageCode: () => settings.state.locale.languageCode,
  );

  runApp(
    MultiBlocProvider(
      providers: [BlocProvider<SettingsCubit>.value(value: settings)],
      child: RepositoryProvider<KeyValueStore>.value(
        value: store,
        child: RepositoryProvider<PlannerRepository>(
          create: (_) => PlannerRepositoryImpl(api),
          child: const EgyptTransportApp(),
        ),
      ),
    ),
  );
}
