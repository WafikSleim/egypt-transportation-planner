// Regression for #38: every clock was drawn three hours early because
// `DateTime.parse` yields a UTC instant and `clockTime` printed `.hour` off it.
// These assert the RENDERED string, from the real captured response, so they
// hold on any machine timezone.
import 'dart:convert';
import 'dart:io';

import 'package:egypt_transport/core/text/formatting.dart';
import 'package:egypt_transport/data/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('plan fixture renders the Cairo clock the API sent', () {
    final json =
        jsonDecode(File('test/fixtures/plan_bus_ar.json').readAsStringSync())
            as Map<String, dynamic>;
    final it = PlanResponse.fromJson(json).itineraries.first;
    expect(clockTime(it.startTime), '08:00');
    expect(clockTime(it.endTime), '10:10');
    expect(it.legs.map((l) => clockTime(l.startTime)).toList(), [
      '08:00',
      '08:05',
      '08:13',
      '08:34',
      '09:18',
      '09:34',
    ]);
  });

  test('summer (+03:00) and winter (+02:00) offsets both read as sent', () {
    expect(clockTime(DateTime.parse('2026-09-21T08:00:00+03:00')), '08:00');
    expect(clockTime(DateTime.parse('2026-12-01T08:00:00+02:00')), '08:00');
  });

  test('a wall-clock (non-UTC) value is printed as it is', () {
    expect(clockTime(DateTime(2026, 9, 21, 8, 5)), '08:05');
  });
}
