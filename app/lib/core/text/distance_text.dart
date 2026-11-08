import '../../l10n/generated/app_localizations.dart';
import 'formatting.dart';

/// `240 م` / `7.1 كم` — metres under a kilometre, kilometres above.
///
/// Digits come out of [distance] as Western ones (see `formatting.dart`), and
/// the unit comes from the copy deck so it is in the right language and on
/// the right side of the number.
String distanceText(AppLocalizations l, int metres) {
  if (!isKilometres(metres)) return l.distanceMetres(distance(metres));
  // `1.0 كم` is a precision nobody asked for; a round kilometre is `1 كم`.
  final km = distance(metres);
  return l.distanceKilometres(
    km.endsWith('.0') ? km.substring(0, km.length - 2) : km,
  );
}

/// `30.0312, 31.4601` — four decimals is about eleven metres, which is as
/// fine as a pin dropped by a thumb is. Western digits, always.
String coordinateText(double lat, double lon) =>
    '${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}';
