import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuchtohgadbadhai/services/evidence_parser.dart';
import 'package:kuchtohgadbadhai/stats/extra.dart';
import 'package:kuchtohgadbadhai/models/models.dart';
import 'package:kuchtohgadbadhai/stats/trend.dart';

void main() {
  test('Mann-Kendall finds a clear trend and its Sen slope', () {
    final years = List<int>.generate(40, (i) => 1981 + i);
    final y = <double?>[for (var i = 0; i < 40; i++) 0.05 * i + ((i * 7919) % 13 - 6) * 0.02];
    final r = mkTrend(y, years);
    expect(r.p, lessThan(0.001));
    expect(r.slope, closeTo(0.05, 0.01));
    expect(r.verdict(), 'confirmed');
  });

  test('flat noise is not proven', () {
    final years = List<int>.generate(30, (i) => 1990 + i);
    final y = <double?>[for (var i = 0; i < 30; i++) ((i * 37) % 11 - 5) * 0.1];
    expect(mkTrend(y, years).verdict(), isNot('confirmed'));
  });

  test('pettitt finds a step', () {
    final years = List<int>.generate(30, (i) => 2000 + i);
    final y = <double?>[for (var i = 0; i < 30; i++) (i < 15 ? 0.0 : 1.0) + ((i * 13) % 5 - 2) * 0.05];
    expect(pettitt(y, years)!.year, 2015);
  });

  test('catalog parses minimal json', () {
    final c = Catalog.fromJson({
      'app': {'demo': true, 'generated_at': 'x'},
      'datasets': [],
      'cases': [
        {'id': 'a', 'title': 'A', 'verdict': {'code': 'open', 'en': 'Open'}, 'regions': [], 'strength': 40}
      ],
      'places': [],
    });
    expect(c.demo, isTrue);
    expect(c.cases.single.strength, 40);
  });

  test('t-test, seasonal Kendall and window scan agree on a clear trend', () {
    final yrs = [for (var i = 0; i < 30; i++) 1990 + i];
    final y = <double?>[for (var i = 0; i < 30; i++) 0.1 * i + ((i * 7919) % 13 - 6) * 0.2];
    final o = olsTTest(y, yrs);
    expect(o.slope, closeTo(0.103, 0.01));
    expect(o.pAdj, lessThan(0.01));
    expect(tTwoSided(2.086, 20), closeTo(0.05, 0.001));
    final w = windowScan(y, yrs)!;
    expect(w.agree, greaterThan(0.9));
  });

  test('evidence reader understands the bundled sample layouts', () {
    final g = parseEvidence(File('assets/samples/sample_giovanni_rain.csv').readAsStringSync());
    expect(g.format, 'NASA Giovanni');
    expect(g.isMonthly, isTrue);
    expect(g.dropped, 2);
    final a = parseEvidence(File('assets/samples/sample_appeears_ndvi.csv').readAsStringSync());
    expect(a.column.contains('NDVI'), isTrue);
    final t = parseEvidence(File('assets/samples/sample_trap_looks_like_trend.csv').readAsStringSync());
    final mk = mkTrend([for (final p in t.points) p.value], [for (final p in t.points) p.year]);
    expect(mk.pRaw, lessThan(0.05)); // a naive test is fooled
    expect(mk.verdict(), 'not_proven'); // the corrected test is not
    expect(seasonalMk(g.points)!.p, lessThan(0.05));
  });
}
