import 'dart:convert';
import 'dart:io';

/// Real responses, captured from the live API on 2026-09-21 against the built
/// graph.
///
/// The client's models are hand-written rather than generated, so these are
/// what keeps them honest: if the server's shape changes, a parse test fails
/// here rather than a screen failing on someone's phone.
///
/// Recapture with, for example:
///
///     curl "http://localhost:8000/plan?from=29.8490,31.3340&to=30.1220,31.2450\
///     &date=2026-09-21&time=08:00&lang=ar" -o test/fixtures/plan_metro_ar.json
Map<String, dynamic> fixture(String name) {
  final file = File('test/fixtures/$name.json');
  return jsonDecode(utf8.decode(file.readAsBytesSync()))
      as Map<String, dynamic>;
}

/// Helwan to Shubra El-Kheima: M1, interchange at Al-Shohadaa, M2.
Map<String, dynamic> get planMetro => fixture('plan_metro_ar');

/// Giza to New Cairo: three microbus legs, no route numbers anywhere.
Map<String, dynamic> get planMicrobus => fixture('plan_bus_ar');

/// A trip in Luxor. Outside the only part of Egypt with transit data, so the
/// router offers a walk and the API explains why.
Map<String, dynamic> get planNoCoverage => fixture('plan_no_coverage_ar');

/// A 03:00 departure. Service is daytime across most of the network.
Map<String, dynamic> get planWalkOnly => fixture('plan_walk_only_ar');

Map<String, dynamic> get stopsMoneeb => fixture('stops_ar');

// ---------------------------------------------------------------------------
// Places and nearby stops (#15, #16, #17).
//
// **Provenance, stated plainly: these are not live captures.** There was no
// OTP, no graph and no Postgres on the machine they were made on. They are the
// *real* `api/` code — the real routes, the real `_place_result` name
// resolution, the real response models and JSON encoding — run in-process over
// a stubbed place index (`api.places.EXECUTOR`) and a stubbed OTP, exactly as
// `tests/` does. What that guarantees is the **shape** the server emits,
// including the three-way name resolution (`name_language`,
// `name_is_fallback`). What it does not guarantee is that the names,
// coordinates and distances are what OSM holds: the rows were written by hand
// to be plausible, so do not quote them as data about Cairo.
//
// Regenerate against a live API when one is up:
//
//     curl "http://localhost:8000/places?q=كايرو فستيفال&near=30.0444,31.2357&lang=ar"
//     curl "http://localhost:8000/places/reverse?at=30.0312,31.4601&lang=ar"
//     curl "http://localhost:8000/stops/nearby?at=30.0312,31.4601&lang=ar"
// ---------------------------------------------------------------------------

/// Three places, lang=ar, ordered from a point: a mall with an Arabic name, a
/// university with **no Arabic name** (a fallback to Latin) and a street.
Map<String, dynamic> get placesAr => fixture('places_ar');

/// The same rows asked for in English: the street has **no English name**, so
/// it comes back in Arabic with `name_is_fallback` set — the mirror case.
Map<String, dynamic> get placesEn => fixture('places_en');

/// One place and no `near` point, so `distance_m` is null.
Map<String, dynamic> get placesNoNear => fixture('places_ar_no_near');

Map<String, dynamic> get placesEmpty => fixture('places_empty_ar');

/// Two places from `/places/reverse`, nearest first.
Map<String, dynamic> get placesReverse => fixture('places_reverse_ar');

/// Nothing named within 500 m — a real answer, not an error.
Map<String, dynamic> get placesReverseEmpty =>
    fixture('places_reverse_empty_ar');

Map<String, dynamic> get stopsNearby => fixture('stops_nearby_ar');
Map<String, dynamic> get stopsNearbyEmpty => fixture('stops_nearby_empty_ar');
