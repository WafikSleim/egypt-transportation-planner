/// Build-time configuration.
///
/// Pass a base URL at build or run time:
///
///     flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
///
/// The default is the Android emulator's alias for the host machine, **not**
/// `localhost` — inside the emulator `localhost` is the emulated device
/// itself, so a default of `http://localhost:8000` fails on every developer's
/// first run and looks like a bug in the app.
class AppConfig {
  const AppConfig({required this.apiBaseUrl});

  factory AppConfig.fromEnvironment() => const AppConfig(
        apiBaseUrl: String.fromEnvironment(
          'API_BASE_URL',
          defaultValue: 'http://10.0.2.2:8000',
        ),
      );

  final String apiBaseUrl;
}

/// Coverage, mirrored from `api/main.py`.
///
/// Held here only so the app can say "we have no data there" before spending
/// a request. The API is still the authority — it returns the same judgement
/// in `note`, and that text is what the user is shown.
class Coverage {
  static const minLat = 29.745;
  static const maxLat = 30.352;
  static const minLon = 30.846;
  static const maxLon = 31.775;

  static bool contains(double lat, double lon) =>
      lat >= minLat && lat <= maxLat && lon >= minLon && lon <= maxLon;
}
