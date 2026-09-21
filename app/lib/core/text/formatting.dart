/// Number and time formatting.
///
/// **Western digits everywhere** — `8:15`, `102 دقيقة`. That is what Egyptian
/// phones, road signs and ticket machines use, and it is why these are
/// formatted by hand rather than through `intl`: `DateFormat` under an `ar`
/// locale renders Arabic-Indic digits (٨:١٥), which would be correct for
/// Modern Standard Arabic typography and wrong for this audience.
library;

String clockTime(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Metres, rounded the way a person would say it.
String distance(int metres) {
  if (metres < 1000) return '$metres';
  final km = metres / 1000;
  return km >= 10 ? km.round().toString() : km.toStringAsFixed(1);
}

bool isKilometres(int metres) => metres >= 1000;
