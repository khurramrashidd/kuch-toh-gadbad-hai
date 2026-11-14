// Pure-Dart port of the pipeline's trend statistics (pipeline/detective/stats.py),
// so "My Place" can test ANY spot on Earth live on the phone.
// Mann-Kendall + lag-1 autocorrelation correction + Sen's slope (+95% CI),
// signal-to-noise, time of emergence, Weatherhead years-needed, Pettitt change point.
// No Flutter imports: verified against Python with tool/stats_golden_check.dart.

import 'dart:math' as math;

class TrendResult {
  TrendResult({
    required this.n,
    required this.slope,
    required this.ciLo,
    required this.ciHi,
    required this.p,
    required this.pRaw,
    required this.z,
    required this.sigma,
    required this.r1,
    required this.snr,
    required this.t0,
    required this.t1,
    required this.toe1,
    required this.toe2,
    required this.yearsNeeded,
    required this.intercept,
  });
  final int n;
  final double slope, ciLo, ciHi, p, pRaw, z, sigma, r1, snr, t0, t1, toe1, toe2, yearsNeeded, intercept;

  bool get valid => !p.isNaN;
  bool get emerged => valid && p < 0.10 && toe1.isFinite && toe1 <= t1;

  /// Same rules as pipeline/detective/verdict.py trend_verdict()
  String verdict({int minYears = 15, double alpha = 0.05, double snrConfirm = 1.0}) {
    if (n < minYears || p.isNaN) return 'insufficient';
    if (p < alpha && snr.isFinite && snr >= snrConfirm) return 'confirmed';
    if (p < alpha || p < 0.10) return 'likely';
    return 'not_proven';
  }
}

class PettittResult {
  PettittResult(this.year, this.p, this.k);
  final int year;
  final double p, k;
}

// ------------------------------------------------------------------ normal distribution
double _erfc(double x) {
  // Numerical Recipes erfc (Chebyshev), fractional error < 1.2e-7
  final z = x.abs();
  final t = 1.0 / (1.0 + 0.5 * z);
  final r = t *
      math.exp(-z * z -
          1.26551223 +
          t *
              (1.00002368 +
                  t *
                      (0.37409196 +
                          t *
                              (0.09678418 +
                                  t * (-0.18628806 + t * (0.27886807 + t * (-1.13520398 + t * (1.48851587 + t * (-0.82215223 + t * 0.17087277)))))))));
  return x >= 0 ? r : 2.0 - r;
}

/// Upper-tail probability of the standard normal.
double normSf(double z) => 0.5 * _erfc(z / math.sqrt2);

const double _z975 = 1.959963984540054;

double _median(List<double> v) {
  if (v.isEmpty) return double.nan;
  final s = List<double>.from(v)..sort();
  final n = s.length;
  return 0.5 * (s[(n - 1) ~/ 2] + s[n ~/ 2]);
}

/// Mann-Kendall / Sen trend test on yearly values (null = missing).
TrendResult mkTrend(List<double?> y, List<num> t, {String method = 'lag1', int minYears = 10}) {
  final n = y.length;
  final tt = t.map((e) => e.toDouble()).toList();
  final idx = <int>[for (var i = 0; i < n; i++) if (y[i] != null && y[i]!.isFinite) i];
  final nv = idx.length;
  TrendResult empty() => TrendResult(
      n: nv,
      slope: double.nan,
      ciLo: double.nan,
      ciHi: double.nan,
      p: double.nan,
      pRaw: double.nan,
      z: double.nan,
      sigma: double.nan,
      r1: double.nan,
      snr: double.nan,
      t0: double.nan,
      t1: double.nan,
      toe1: double.nan,
      toe2: double.nan,
      yearsNeeded: double.nan,
      intercept: double.nan);
  if (nv < math.max(3, minYears)) return empty();

  // S statistic
  var s = 0.0;
  for (var a = 0; a < nv; a++) {
    for (var b = a + 1; b < nv; b++) {
      final d = y[idx[b]]! - y[idx[a]]!;
      s += d > 0 ? 1 : (d < 0 ? -1 : 0);
    }
  }
  // ties
  final sorted = [for (final i in idx) y[i]!]..sort();
  var tie = 0.0;
  var run = 1.0;
  for (var i = 1; i < sorted.length; i++) {
    if (sorted[i] == sorted[i - 1]) {
      run += 1;
    } else {
      if (run > 1) tie += run * (run - 1) * (2 * run + 5);
      run = 1;
    }
  }
  if (run > 1) tie += run * (run - 1) * (2 * run + 5);
  final varRaw = (nv * (nv - 1) * (2 * nv + 5) - tie) / 18.0;

  // Sen slope
  final slopes = <double>[];
  for (var a = 0; a < nv; a++) {
    for (var b = a + 1; b < nv; b++) {
      final dt = tt[idx[b]] - tt[idx[a]];
      if (dt != 0) slopes.add((y[idx[b]]! - y[idx[a]]!) / dt);
    }
  }
  slopes.sort();
  final np = slopes.length;
  final slope = np == 0 ? double.nan : 0.5 * (slopes[(np - 1) ~/ 2] + slopes[np ~/ 2]);

  // residuals (time relative to the first year, like the Python code)
  final tFirst = tt.first;
  final icptRel = _median([for (final i in idx) y[i]! - slope * (tt[i] - tFirst)]);
  final resid = List<double?>.filled(n, null);
  for (final i in idx) {
    resid[i] = y[i]! - (icptRel + slope * (tt[i] - tFirst));
  }
  // lag-1 autocorrelation of residuals
  final mu = [for (final i in idx) resid[i]!].reduce((a, b) => a + b) / nv;
  var num = 0.0, den = 0.0;
  for (var i = 0; i < n; i++) {
    final r = resid[i];
    if (r == null) continue;
    den += (r - mu) * (r - mu);
    if (i + 1 < n && resid[i + 1] != null) num += (r - mu) * (resid[i + 1]! - mu);
  }
  final r1 = den > 0 ? num / den : double.nan;

  var factor = 1.0;
  if (method == 'lag1') {
    var rho = nv > 4 ? (nv * r1 + 1.0) / math.max(nv - 3.0, 1.0) : r1;
    if (rho.isNaN) rho = 0;
    rho = rho.clamp(0.0, 0.9);
    var sum = 0.0;
    for (var k = 1; k < math.max(nv, 2); k++) {
      final w = math.max(0.0, 1.0 - k / nv);
      sum += w * math.pow(rho, k);
    }
    factor = 1.0 + 2.0 * sum;
  }
  final varC = varRaw * factor;

  double zFor(double v) {
    final sd = math.sqrt(v);
    if (s > 0) return (s - 1) / sd;
    if (s < 0) return (s + 1) / sd;
    return 0;
  }

  final z = zFor(varC);
  final p = 2 * normSf(z.abs());
  final pRaw = 2 * normSf(zFor(varRaw).abs());

  // CI (Gilbert 1987) using the corrected variance
  var lo = double.nan, hi = double.nan;
  if (np > 0) {
    final c = _z975 * math.sqrt(math.max(varC, 0));
    final m1 = (((np - c) / 2.0).round() - 1).clamp(0, np - 1);
    final m2 = ((np + c) / 2.0).round().clamp(0, np - 1);
    lo = slopes[m1];
    hi = slopes[m2];
  }

  // noise, emergence, detectability
  final rv = [for (final i in idx) resid[i]!];
  final rmean = rv.reduce((a, b) => a + b) / rv.length;
  final sigma = math.sqrt(rv.map((r) => (r - rmean) * (r - rmean)).reduce((a, b) => a + b) / math.max(1, rv.length - 1));
  final t0 = tt[idx.first], t1 = tt[idx.last];
  final absS = slope.abs();
  final snr = absS * (t1 - t0) / sigma;
  final toe1 = absS > 0 ? t0 + sigma / absS : double.infinity;
  final toe2 = absS > 0 ? t0 + 2 * sigma / absS : double.infinity;
  final phi = (r1.isNaN ? 0.0 : r1).clamp(0.0, 0.95);
  final yrs = absS > 0
      ? math.pow((3.3 * math.sqrt(12.0) * sigma / absS) * math.sqrt((1 + phi) / (1 - phi)), 2.0 / 3.0).toDouble()
      : double.infinity;

  return TrendResult(
    n: nv,
    slope: slope,
    ciLo: lo,
    ciHi: hi,
    p: p,
    pRaw: pRaw,
    z: z,
    sigma: sigma,
    r1: r1,
    snr: snr,
    t0: t0,
    t1: t1,
    toe1: toe1,
    toe2: toe2,
    yearsNeeded: yrs,
    intercept: icptRel - slope * tFirst,
  );
}

List<double> _ranks(List<double> x) {
  final order = List<int>.generate(x.length, (i) => i)..sort((a, b) => x[a].compareTo(x[b]));
  final r = List<double>.filled(x.length, 0);
  var i = 0;
  while (i < order.length) {
    var j = i;
    while (j + 1 < order.length && x[order[j + 1]] == x[order[i]]) {
      j++;
    }
    final avg = (i + j) / 2.0 + 1.0;
    for (var k = i; k <= j; k++) {
      r[order[k]] = avg;
    }
    i = j + 1;
  }
  return r;
}

/// Pettitt (1979) change point; returns the first year of the new regime.
PettittResult? pettitt(List<double?> x, List<num> t) {
  final xv = <double>[];
  final tv = <num>[];
  for (var i = 0; i < x.length; i++) {
    if (x[i] != null && x[i]!.isFinite) {
      xv.add(x[i]!);
      tv.add(t[i]);
    }
  }
  final n = xv.length;
  if (n < 8) return null;
  final r = _ranks(xv);
  var cum = 0.0;
  var best = -1.0;
  var k = 0;
  for (var i = 0; i < n - 1; i++) {
    cum += r[i];
    final u = (2 * cum - (i + 1) * (n + 1)).abs();
    if (u > best) {
      best = u;
      k = i;
    }
  }
  final p = math.min(1.0, 2 * math.exp(-6 * best * best / (math.pow(n, 3) + math.pow(n, 2))));
  return PettittResult(tv[k + 1].toInt(), p, best);
}

/// Mean of the first / last [count] valid values (for "then vs now").
double? meanOf(List<double?> v, {int from = 0, int count = 10, bool fromEnd = false}) {
  final list = fromEnd ? v.sublist(math.max(0, v.length - count)) : v.sublist(0, math.min(count, v.length));
  final ok = list.whereType<double>().where((e) => e.isFinite).toList();
  if (ok.isEmpty) return null;
  return ok.reduce((a, b) => a + b) / ok.length;
}
