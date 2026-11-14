// dart run tool/stats_golden_check.dart <golden.json>
// Compares the Dart trend engine with numbers produced by the Python pipeline.
import 'dart:convert';
import 'dart:io';

import '../lib/stats/trend.dart';

void main(List<String> args) {
  final cases = jsonDecode(File(args.isEmpty ? 'golden.json' : args.first).readAsStringSync()) as List;
  var worst = <String, double>{};
  var n = 0;
  for (final c in cases) {
    final y = (c['y'] as List).map((e) => e == null ? null : (e as num).toDouble()).toList();
    final t = (c['t'] as List).cast<num>();
    final r = mkTrend(y, t, minYears: 10);
    final ref = c['r'] as Map<String, dynamic>;
    void cmp(String k, double ours) {
      final v = ref[k];
      if (v == null) return;
      final d = ((v as num).toDouble() - ours).abs();
      if (d.isNaN) return;
      worst[k] = (worst[k] ?? 0) > d ? worst[k]! : d;
    }
    cmp('p', r.p); cmp('slope', r.slope); cmp('ci_lo', r.ciLo); cmp('ci_hi', r.ciHi); cmp('sigma', r.sigma);
    cmp('r1', r.r1); cmp('snr', r.snr); cmp('toe1', r.toe1); cmp('years_needed', r.yearsNeeded);
    final pt = c['pettitt'];
    final ours = pettitt(y, t);
    if (pt != null && ours != null) {
      if (pt['year'] != ours.year) stdout.writeln('pettitt year mismatch ${pt['year']} vs ${ours.year}');
      final d = ((pt['p'] as num).toDouble() - ours.p).abs();
      worst['pettitt_p'] = (worst['pettitt_p'] ?? 0) > d ? worst['pettitt_p']! : d;
    }
    n++;
  }
  stdout.writeln('cases: $n  worst abs differences: $worst');
}
