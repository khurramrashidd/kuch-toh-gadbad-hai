// Extra tests named in the challenge resources: straight-line fit with a t-test,
// Seasonal Mann-Kendall (Hirsch-Slack) and the "cherry-pick" window scan.
// Pure Dart, no Flutter imports.

import 'dart:math' as math;

import 'trend.dart';

// ------------------------------------------------------------------ Student t
double _lnGamma(double x) {
  const c = [76.18009172947146, -86.50532032941677, 24.01409824083091, -1.231739572450155, 0.1208650973866179e-2, -0.5395239384953e-5];
  var y = x;
  var tmp = x + 5.5;
  tmp -= (x + 0.5) * math.log(tmp);
  var ser = 1.000000000190015;
  for (final cj in c) {
    y += 1;
    ser += cj / y;
  }
  return -tmp + math.log(2.5066282746310005 * ser / x);
}

double _betacf(double a, double b, double x) {
  const maxIt = 200, eps = 3e-12, fpmin = 1e-300;
  final qab = a + b, qap = a + 1, qam = a - 1;
  var c = 1.0, d = 1 - qab * x / qap;
  if (d.abs() < fpmin) d = fpmin;
  d = 1 / d;
  var h = d;
  for (var m = 1; m <= maxIt; m++) {
    final m2 = 2 * m;
    var aa = m * (b - m) * x / ((qam + m2) * (a + m2));
    d = 1 + aa * d;
    if (d.abs() < fpmin) d = fpmin;
    c = 1 + aa / c;
    if (c.abs() < fpmin) c = fpmin;
    d = 1 / d;
    h *= d * c;
    aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2));
    d = 1 + aa * d;
    if (d.abs() < fpmin) d = fpmin;
    c = 1 + aa / c;
    if (c.abs() < fpmin) c = fpmin;
    d = 1 / d;
    final del = d * c;
    h *= del;
    if ((del - 1).abs() < eps) break;
  }
  return h;
}

/// Regularised incomplete beta function I_x(a, b).
double betaInc(double a, double b, double x) {
  if (x <= 0) return 0;
  if (x >= 1) return 1;
  final bt = math.exp(_lnGamma(a + b) - _lnGamma(a) - _lnGamma(b) + a * math.log(x) + b * math.log(1 - x));
  if (x < (a + 1) / (a + b + 2)) return bt * _betacf(a, b, x) / a;
  return 1 - bt * _betacf(b, a, 1 - x) / b;
}

/// Two-sided p-value of Student's t with [df] degrees of freedom.
double tTwoSided(double t, double df) {
  if (!t.isFinite || df <= 0) return double.nan;
  return betaInc(df / 2, 0.5, df / (df + t * t));
}

/// Critical t for a two-sided 95% interval (bisection on tTwoSided).
double tCrit95(double df) {
  var lo = 0.0, hi = 50.0;
  for (var i = 0; i < 60; i++) {
    final mid = (lo + hi) / 2;
    if (tTwoSided(mid, df) > 0.05) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return (lo + hi) / 2;
}

class OlsResult {
  OlsResult({required this.n, required this.slope, required this.intercept, required this.se, required this.t, required this.p, required this.pAdj, required this.ciLo, required this.ciHi, required this.r2, required this.r1, required this.nEff});
  final int n;
  final double slope, intercept, se, t, p, pAdj, ciLo, ciHi, r2, r1, nEff;
  bool get valid => p.isFinite;
}

/// Least-squares line + t-test on the slope. [pAdj] shrinks the sample size for
/// year-to-year memory (Santer et al. 2008: n_eff = n (1-r1)/(1+r1)).
OlsResult olsTTest(List<double?> y, List<num> t) {
  final xs = <double>[], ys = <double>[];
  for (var i = 0; i < y.length; i++) {
    final v = y[i];
    if (v != null && v.isFinite) {
      xs.add(t[i].toDouble());
      ys.add(v);
    }
  }
  final n = xs.length;
  OlsResult bad() => OlsResult(n: n, slope: double.nan, intercept: double.nan, se: double.nan, t: double.nan, p: double.nan, pAdj: double.nan, ciLo: double.nan, ciHi: double.nan, r2: double.nan, r1: double.nan, nEff: double.nan);
  if (n < 5) return bad();
  final mx = xs.reduce((a, b) => a + b) / n, my = ys.reduce((a, b) => a + b) / n;
  var sxx = 0.0, sxy = 0.0, syy = 0.0;
  for (var i = 0; i < n; i++) {
    sxx += (xs[i] - mx) * (xs[i] - mx);
    sxy += (xs[i] - mx) * (ys[i] - my);
    syy += (ys[i] - my) * (ys[i] - my);
  }
  if (sxx == 0) return bad();
  final slope = sxy / sxx, icpt = my - slope * mx;
  final res = [for (var i = 0; i < n; i++) ys[i] - (icpt + slope * xs[i])];
  var sse = 0.0;
  for (final r in res) {
    sse += r * r;
  }
  var num = 0.0;
  for (var i = 0; i + 1 < n; i++) {
    num += res[i] * res[i + 1];
  }
  final r1 = sse > 0 ? num / sse : 0.0;
  final df = n - 2.0;
  final se = math.sqrt(sse / df / sxx);
  final tv = se > 0 ? slope / se : double.infinity;
  final rho = r1.clamp(0.0, 0.95);
  final nEff = math.max(3.0, n * (1 - rho) / (1 + rho));
  final dfAdj = math.max(1.0, nEff - 2);
  final seAdj = math.sqrt(sse / dfAdj / sxx);
  final tAdj = seAdj > 0 ? slope / seAdj : double.infinity;
  final crit = tCrit95(dfAdj);
  return OlsResult(
    n: n,
    slope: slope,
    intercept: icpt,
    se: se,
    t: tv,
    p: tTwoSided(tv, df),
    pAdj: tTwoSided(tAdj, dfAdj),
    ciLo: slope - crit * seAdj,
    ciHi: slope + crit * seAdj,
    r2: syy > 0 ? 1 - sse / syy : 0,
    r1: r1,
    nEff: nEff,
  );
}

// ------------------------------------------------------------------ Seasonal Mann-Kendall
class MonthlyPoint {
  const MonthlyPoint(this.year, this.month, this.value);
  final int year, month; // month 1..12
  final double value;
}

class SeasonalMkResult {
  SeasonalMkResult(this.s, this.z, this.p, this.slopePerYear, this.months);
  final double s, z, p, slopePerYear;
  final int months; // calendar months that had enough years
}

/// Hirsch-Slack seasonal Kendall test: each calendar month is compared only with itself,
/// so the yearly cycle cannot fake or hide a trend.
SeasonalMkResult? seasonalMk(List<MonthlyPoint> pts) {
  var sTot = 0.0, varTot = 0.0;
  var used = 0;
  final slopes = <double>[];
  for (var m = 1; m <= 12; m++) {
    final sel = pts.where((p) => p.month == m && p.value.isFinite).toList()..sort((a, b) => a.year.compareTo(b.year));
    final n = sel.length;
    if (n < 5) continue;
    used++;
    var s = 0.0;
    for (var a = 0; a < n; a++) {
      for (var b = a + 1; b < n; b++) {
        final d = sel[b].value - sel[a].value;
        s += d > 0 ? 1 : (d < 0 ? -1 : 0);
        final dt = sel[b].year - sel[a].year;
        if (dt != 0) slopes.add(d / dt);
      }
    }
    final sorted = [for (final p in sel) p.value]..sort();
    var tie = 0.0, run = 1.0;
    for (var i = 1; i < sorted.length; i++) {
      if (sorted[i] == sorted[i - 1]) {
        run += 1;
      } else {
        if (run > 1) tie += run * (run - 1) * (2 * run + 5);
        run = 1;
      }
    }
    if (run > 1) tie += run * (run - 1) * (2 * run + 5);
    sTot += s;
    varTot += (n * (n - 1) * (2 * n + 5) - tie) / 18.0;
  }
  if (used < 2 || varTot <= 0) return null;
  final sd = math.sqrt(varTot);
  final z = sTot > 0 ? (sTot - 1) / sd : (sTot < 0 ? (sTot + 1) / sd : 0.0);
  slopes.sort();
  final np = slopes.length;
  final slope = np == 0 ? double.nan : 0.5 * (slopes[(np - 1) ~/ 2] + slopes[np ~/ 2]);
  return SeasonalMkResult(sTot, z, 2 * normSf(z.abs()), slope, used);
}

/// Monthly values -> yearly means of de-seasonalised anomalies (month climatology removed).
/// A year needs at least [minMonths] months.
(List<int>, List<double?>) yearlyFromMonthly(List<MonthlyPoint> pts, {int minMonths = 9, bool anomalies = true}) {
  if (pts.isEmpty) return (<int>[], <double?>[]);
  final clim = List<double>.filled(13, 0);
  final cnt = List<int>.filled(13, 0);
  for (final p in pts) {
    if (!p.value.isFinite) continue;
    clim[p.month] += p.value;
    cnt[p.month]++;
  }
  var overall = 0.0, on = 0;
  for (var m = 1; m <= 12; m++) {
    if (cnt[m] > 0) {
      clim[m] /= cnt[m];
      overall += clim[m];
      on++;
    }
  }
  overall = on > 0 ? overall / on : 0;
  final y0 = pts.map((p) => p.year).reduce(math.min), y1 = pts.map((p) => p.year).reduce(math.max);
  final sum = <int, double>{}, num = <int, int>{};
  for (final p in pts) {
    if (!p.value.isFinite) continue;
    // anomaly + overall mean keeps the familiar level of the variable
    final v = anomalies ? p.value - clim[p.month] + overall : p.value;
    sum[p.year] = (sum[p.year] ?? 0) + v;
    num[p.year] = (num[p.year] ?? 0) + 1;
  }
  final present = cnt.where((c) => c > 0).length;
  final need = math.min(minMonths, math.max(1, (present * 0.75).floor()));
  final years = <int>[], vals = <double?>[];
  for (var y = y0; y <= y1; y++) {
    years.add(y);
    final c = num[y] ?? 0;
    vals.add(c >= need ? sum[y]! / c : null);
  }
  return (years, vals);
}

// ------------------------------------------------------------------ cherry-pick shield
class WindowScan {
  WindowScan({required this.total, required this.sameSign, required this.sameSignSig, required this.oppositeSig, required this.cells, required this.minLen, required this.years, required this.fullSign});
  final int total, sameSign, sameSignSig, oppositeSig, minLen, fullSign;
  final List<int> years;

  /// (startIndex, endIndex, code): 2 = same direction & significant, 1 = same direction only,
  /// 0 = opposite direction, -1 = opposite & significant.
  final List<(int, int, int)> cells;

  double get agree => total == 0 ? double.nan : sameSign / total;
  double get agreeSig => total == 0 ? double.nan : sameSignSig / total;
}

/// Re-test every start/end year combination: does the conclusion depend on the window chosen?
WindowScan? windowScan(List<double?> y, List<int> years, {int minLen = 15, int maxWindows = 700}) {
  final n = y.length;
  if (n < minLen + 3) return null;
  final full = mkTrend(y, years, minYears: 8);
  if (!full.valid || full.slope == 0) return null;
  final sign = full.slope > 0 ? 1 : -1;
  var count = 0;
  for (var a = 0; a < n; a++) {
    for (var b = a + minLen - 1; b < n; b++) {
      count++;
    }
  }
  final step = math.max(1, (count / maxWindows).ceil());
  final sq = math.max(1, math.sqrt(step).round());
  var total = 0, same = 0, sameSig = 0, oppSig = 0;
  final cells = <(int, int, int)>[];
  for (var a = 0; a < n; a += sq) {
    for (var b = a + minLen - 1; b < n; b += sq) {
      final r = mkTrend(y.sublist(a, b + 1), years.sublist(a, b + 1), minYears: math.min(minLen, 10));
      if (!r.valid) continue;
      total++;
      final s = r.slope > 0 ? 1 : (r.slope < 0 ? -1 : 0);
      final sig = r.p < 0.05;
      int code;
      if (s == sign) {
        same++;
        if (sig) sameSig++;
        code = sig ? 2 : 1;
      } else {
        if (sig) oppSig++;
        code = sig ? -1 : 0;
      }
      cells.add((a, b, code));
    }
  }
  return WindowScan(total: total, sameSign: same, sameSignSig: sameSig, oppositeSig: oppSig, cells: cells, minLen: minLen, years: years, fullSign: sign);
}
