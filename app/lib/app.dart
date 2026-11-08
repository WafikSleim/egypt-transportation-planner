import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'core/notifications/notification_service.dart';
import 'core/settings/settings_cubit.dart';
import 'core/theme/app_theme.dart';
import 'features/post_trip/view/post_trip_listener.dart';
import 'features/search/view/search_page.dart';
import 'l10n/generated/app_localizations.dart';

/// One navigator for the app, held at file level so it survives the rebuilds
/// a language or theme change causes. The post-trip question is opened from a
/// notification tap, with no screen of its own to hang a context on.
final _navigatorKey = GlobalKey<NavigatorState>();

class EgyptTransportApp extends StatelessWidget {
  const EgyptTransportApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsCubit, Settings>(
      builder: (context, settings) {
        // The frame the design is drawn in. Every spacing token and type size
        // is a figure in this frame, scaled from here - see Insets in
        // core/theme/tokens.dart. `minTextAdapt` keeps type legible on the
        // small, cheap Androids this app is actually for.
        return ScreenUtilInit(
          designSize: const Size(390, 844),
          minTextAdapt: true,
          splitScreenMode: true,
          builder: (context, child) => MaterialApp(
            navigatorKey: _navigatorKey,
            builder: (context, child) => PostTripListener(
              service: context.read<NotificationService>(),
              navigatorKey: _navigatorKey,
              child: child ?? const SizedBox.shrink(),
            ),
            onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
            debugShowCheckedModeBanner: false,

            // Both themes are built from the same token set, and dark is a
            // designed palette rather than an inversion — the licence-plate
            // mode colours vibrate against a dark ground otherwise.
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: settings.themeMode,

            locale: settings.locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,

            home: const SearchPage(),
          ),
        );
      },
    );
  }
}
