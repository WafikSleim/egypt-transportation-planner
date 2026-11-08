/// Number and time formatting.
///
/// **Western digits everywhere** — `8:15`, `102 دقيقة`. That is what Egyptian
/// phones, road signs and ticket machines use, and it is why these are
/// formatted by hand rather than through `intl`: `DateFormat` under an `ar`
/// locale renders Arabic-Indic digits (٨:١٥), which would be correct for
/// Modern Standard Arabic typography and wrong for this audience.
library;

import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Cairo is the one clock this app plans in: the coverage box is Greater
/// Cairo and the API renders every instant in it. Resolved lazily so no
/// caller has to remember to initialise the database first; Egypt's DST is
/// in the database, so no offset is hardcoded.
final tz.Location _cairo = () {
  tz_data.initializeTimeZones();
  return tz.getLocation('Africa/Cairo');
}();

/// `HH:mm` on the Cairo clock.
///
/// `DateTime.parse` turns any string carrying an offset into a **UTC**
/// instant, so reading `.hour` off a parsed API time prints it three hours
/// early (#38). A UTC value is therefore an instant and is converted to
/// Cairo. A non-UTC value is a wall-clock time already (the departure the
/// passenger picked, or the moment the phone saved a plan) and is printed as
/// it is. Rendering never depends on the device's timezone.
String clockTime(DateTime t) {
  final c = t.isUtc ? tz.TZDateTime.from(t, _cairo) : t;
  return '${c.hour.toString().padLeft(2, '0')}:${c.minute.toString().padLeft(2, '0')}';
}

/// Metres, rounded the way a person would say it.
String distance(int metres) {
  if (metres < 1000) return '$metres';
  final km = metres / 1000;
  return km >= 10 ? km.round().toString() : km.toStringAsFixed(1);
}

bool isKilometres(int metres) => metres >= 1000;
