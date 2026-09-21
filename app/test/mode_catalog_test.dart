import 'dart:convert';
import 'dart:io';

import 'package:egypt_transport/core/presentation/mode_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

/// `ModeCatalog` duplicates a table that really lives in `api/modes.py`,
/// because `/stops` returns mode ids without labels and the picker has to
/// name them.
///
/// Duplicated tables drift. This test reads the Python source directly and
/// fails when it does — a mode added on the server and not here would
/// otherwise surface as a stop labelled `ltra_minibus` in the picker.
void main() {
  final modesPy = File('../api/modes.py');

  test('every mode id in api/modes.py has a label', () {
    if (!modesPy.existsSync()) {
      markTestSkipped('api/modes.py not reachable from here');
      return;
    }

    final source = utf8.decode(modesPy.readAsBytesSync());
    final ids = RegExp(r'Mode\(\s*"([a-z_]+)"')
        .allMatches(source)
        .map((m) => m.group(1)!)
        .toSet();

    expect(ids, isNotEmpty, reason: 'the regex should find the Mode table');

    final missing = ids.where((id) => !ModeCatalog.knows(id)).toList();
    expect(missing, isEmpty,
        reason: 'add these to ModeCatalog: ${missing.join(", ")}');
  });

  test('labels exist in both languages and are not the raw id', () {
    for (final id in ModeCatalog.knownIds) {
      for (final lang in ['ar', 'en']) {
        final label = ModeCatalog.label(id, lang);
        expect(label, isNotEmpty);
        expect(label, isNot(id), reason: '$id has no $lang label');
      }
    }
  });

  test('an unknown id falls back to itself rather than throwing', () {
    // A new operator appearing server-side should degrade to something
    // visible, not crash the picker.
    expect(ModeCatalog.label('hyperloop', 'ar'), 'hyperloop');
  });
}
