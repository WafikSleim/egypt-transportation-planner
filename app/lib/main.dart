import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/network/api_client.dart';
import 'core/settings/settings_cubit.dart';
import 'data/repositories/planner_repository_impl.dart';
import 'domain/repositories/planner_repository.dart';

void main() {
  final settings = SettingsCubit();
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
      child: RepositoryProvider<PlannerRepository>(
        create: (_) => PlannerRepositoryImpl(api),
        child: const EgyptTransportApp(),
      ),
    ),
  );
}
