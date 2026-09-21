/// Mode labels by id, mirrored from `api/modes.py`.
///
/// The server sends full labels on an itinerary leg, so this is **not** used
/// there. It exists for `/stops`, which returns mode ids only — a stop lists
/// `['microbus', 'tomnaya']` and the picker has to name them.
///
/// Because this duplicates a server-side table, it is covered by a test that
/// fails if an id the API can return has no entry here.
class ModeCatalog {
  static const _labels = <String, ({String en, String ar})>{
    // Paratransit — no route numbers, identified by origin and destination.
    'microbus': (en: 'Microbus', ar: 'ميكروباص'),
    'tomnaya': (en: 'Tomnaya', ar: 'تمنايا'),
    'coop_minibus': (en: 'Cooperative minibus', ar: 'ميني باص تعاوني'),
    'box': (en: 'Box', ar: 'بوكس'),
    'peugeot': (en: 'Peugeot', ar: 'بيجو'),
    // Formal operators — these do carry numbers.
    'cta_bus': (en: 'CTA bus', ar: 'أتوبيس النقل العام'),
    'cta_minibus': (en: 'CTA minibus', ar: 'ميني باص النقل العام'),
    'ltra_minibus': (en: 'Minibus', ar: 'ميني باص'),
    'mwasalat_misr': (en: 'Mwasalat Misr', ar: 'مواصلات مصر'),
    'green_bus': (en: 'Green Bus', ar: 'الأتوبيس الأخضر'),
    'metro': (en: 'Cairo Metro', ar: 'مترو الأنفاق'),
    'walk': (en: 'Walk', ar: 'سيرًا'),
    'transit': (en: 'Transit', ar: 'مواصلات'),
  };

  static Iterable<String> get knownIds => _labels.keys;

  static bool knows(String id) => _labels.containsKey(id);

  static String label(String id, String languageCode) {
    final entry = _labels[id];
    if (entry == null) return id;
    return languageCode == 'ar' ? entry.ar : entry.en;
  }
}
