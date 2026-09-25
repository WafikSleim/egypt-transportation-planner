import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/location/location_service.dart';
import 'core/network/api_client.dart';
import 'core/notifications/local_notification_service.dart';
import 'core/notifications/notification_copy.dart';
import 'core/notifications/notification_preferences.dart';
import 'core/notifications/notification_service.dart';
import 'core/settings/settings_cubit.dart';
import 'core/storage/key_value_store.dart';
import 'data/cache/plan_cache.dart';
import 'data/repositories/planner_repository_impl.dart';
import 'data/repositories/trip_history.dart';
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

  // Nothing is scheduled here and no permission is asked — that happens in
  // context, from the screen that needs it. This only opens the channels and
  // wires the copy, which has to resolve through the settings the same way
  // `lang` does: the notification is written in the language the passenger
  // chose, at the moment it fires.
  final notifications = LocalNotificationService(
    preferences: NotificationPreferences(store),
    copy: () => AppNotificationCopy.forLocale(settings.state.locale),
  );
  await notifications.initialise();

  runApp(
    MultiBlocProvider(
      providers: [BlocProvider<SettingsCubit>.value(value: settings)],
      child: MultiRepositoryProvider(
        providers: [
          RepositoryProvider<KeyValueStore>.value(value: store),
          RepositoryProvider<TripHistory>(create: (_) => TripHistory(store)),
          RepositoryProvider<LocationService>(
            create: (_) => const GeolocatorLocationService(),
          ),
          RepositoryProvider<NotificationService>.value(value: notifications),
          RepositoryProvider<PlannerRepository>(
            // The plan cache goes in here rather than being provided
            // separately: the repository is what plans a trip, so it is what
            // records the answer, and no screen can plan one and forget to.
            create: (_) => PlannerRepositoryImpl(api, cache: PlanCache(store)),
          ),
        ],
        child: const EgyptTransportApp(),
      ),
    ),
  );
}
