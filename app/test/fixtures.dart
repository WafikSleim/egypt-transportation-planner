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
