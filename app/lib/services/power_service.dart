import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../models/models.dart';
import '../stats/trend.dart';
import 'device_service.dart';

/// Live "My Place" analysis straight from the NASA POWER API (no key needed),
/// using the same statistics as the pipeline (see pipeline/detective/places.py).
class PowerService {
  PowerService({this.device, this.firebaseReady = false});
  final DeviceService? device;
  final bool firebaseReady;
  final Map<String, String> _mem = {};

  /// NASA POWER cells are 0.5 x 0.625 degrees: one cache entry per half-degree box.
  static String cacheKey(double lat, double lon, int end) => 'power_${(lat * 2).round()}_${(lon * 2).round()}_$end';

  Future<String?> _cached(String key) async {
    if (_mem.containsKey(key)) return _mem[key];
    final local = await device?.loadString(key);
    if (local != null && local.length > 50) return _mem[key] = local;
    if (firebaseReady) {
      try {
        final snap = await FirebaseFirestore.instance.collection('place_cache').doc(key).get().timeout(const Duration(seconds: 6));
        final j = snap.data()?['json'];
        if (j is String && j.length > 50) {
          device?.saveString(key, j);
          return _mem[key] = j;
        }
      } catch (_) {}
    }
    return null;
  }

  Future<void> _store(String key, String json) async {
    _mem[key] = json;
    device?.saveString(key, json);
    if (!firebaseReady) return;
    try {
      if (FirebaseAuth.instance.currentUser == null) await FirebaseAuth.instance.signInAnonymously();
      await FirebaseFirestore.instance.collection('place_cache').doc(key).set({'json': json, 'created': FieldValue.serverTimestamp()});
    } catch (_) {
      // best effort
    }
  }

  static List<PlaceVariable> _fromCache(String json) {
    final list = jsonDecode(json) as List;
    return [
      for (final e in list)
        _variable('${e['key']}', '${e['title']}', '${e['title_hi']}', '${e['units']}', [for (final y in e['years'] as List) (y as num).toInt()],
            [for (final v in e['values'] as List) v == null ? null : (v as num).toDouble()],
            threshold: e['threshold'] == null ? null : (e['threshold'] as num).toDouble())
    ];
  }

  static String _toCache(List<PlaceVariable> vars) => jsonEncode([
        for (final v in vars)
          {'key': v.key, 'title': v.title, 'title_hi': v.titleHi, 'units': v.units, 'years': v.series.years, 'values': v.series.values, 'threshold': v.threshold}
      ]);
  static const _monthly = 'https://power.larc.nasa.gov/api/temporal/monthly/point';
  static const _daily = 'https://power.larc.nasa.gov/api/temporal/daily/point';
  static const _monthDays = [31, 28.25, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

  static const _vars = [
    {'key': 'temp', 'param': 'T2M', 'months': [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12], 'how': 'mean', 'units': '°C', 'scale': 1.0,
      'title': 'Average temperature', 'title_hi': 'औसत तापमान'},
    {'key': 'rain', 'param': 'PRECTOTCORR', 'months': [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12], 'how': 'total', 'units': 'mm', 'scale': 1.0,
      'title': 'Rainfall in a year', 'title_hi': 'साल भर की बारिश'},
    {'key': 'monsoon', 'param': 'PRECTOTCORR', 'months': [6, 7, 8, 9], 'how': 'total', 'units': 'mm', 'scale': 1.0,
      'title': 'Monsoon rainfall (Jun-Sep)', 'title_hi': 'मानसून की बारिश (जून-सितंबर)'},
    {'key': 'soil', 'param': 'GWETROOT', 'months': [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12], 'how': 'mean', 'units': '%', 'scale': 100.0,
      'title': 'Soil wetness (root zone)', 'title_hi': 'मिट्टी की नमी (जड़ तक)'},
    {'key': 'humid', 'param': 'RH2M', 'months': [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12], 'how': 'mean', 'units': '%', 'scale': 1.0,
      'title': 'Humidity', 'title_hi': 'नमी (हवा में)'},
  ];

  int get lastFullYear => DateTime.now().year - 1;

  Future<Map<String, dynamic>> _get(String base, Map<String, String> q) async {
    final uri = Uri.parse(base).replace(queryParameters: q);
    final res = await http.get(uri).timeout(const Duration(seconds: 90));
    if (res.statusCode != 200) throw Exception('NASA POWER HTTP ${res.statusCode}');
    return Map<String, dynamic>.from(jsonDecode(utf8.decode(res.bodyBytes)) as Map);
  }

  Future<PlaceReport> analyse(double lat, double lon, {required String name, String nameHi = ''}) async {
    final end = lastFullYear;
    final key = cacheKey(lat, lon, end);
    try {
      final hit = await _cached(key);
      if (hit != null) {
        return PlaceReport(name: name, nameHi: nameHi.isEmpty ? name : nameHi, country: '', lat: lat, lon: lon,
            source: 'NASA POWER (cached)', fetchedAt: DateTime.now().toUtc().toIso8601String(), variables: _fromCache(hit), live: true);
      }
    } catch (_) {}
    final common = {'community': 'AG', 'latitude': lat.toStringAsFixed(4), 'longitude': lon.toStringAsFixed(4), 'format': 'JSON'};
    final results = await Future.wait([
      _get(_monthly, {...common, 'parameters': 'GWETROOT,PRECTOTCORR,RH2M,T2M', 'start': '1981', 'end': '$end'}),
      _get(_daily, {...common, 'parameters': 'T2M_MAX', 'start': '19810101', 'end': '${end}1231'}),
    ]);
    final vars = analysePower(results[0], results[1]);
    if (vars.isNotEmpty) _store(key, _toCache(vars));
    return PlaceReport(
      name: name,
      nameHi: nameHi.isEmpty ? name : nameHi,
      country: '',
      lat: lat,
      lon: lon,
      source: 'NASA POWER (live)',
      fetchedAt: DateTime.now().toUtc().toIso8601String(),
      variables: vars,
      live: true,
    );
  }

  static double _fill(Map<String, dynamic> obj) {
    final h = obj['header'];
    if (h is Map && h['fill_value'] is num) return (h['fill_value'] as num).toDouble();
    return -999.0;
  }

  static List<PlaceVariable> analysePower(Map<String, dynamic> monthly, Map<String, dynamic> daily) {
    final out = <PlaceVariable>[];
    final params = (monthly['properties'] as Map)['parameter'] as Map;
    final fill = _fill(monthly);
    for (final v in _vars) {
      final data = params[v['param']];
      if (data is! Map) continue;
      final years = <int>{};
      for (final k in data.keys) {
        years.add(int.parse('$k'.substring(0, 4)));
      }
      final ys = years.toList()..sort();
      final grid = {for (final y in ys) y: List<double?>.filled(12, null)};
      data.forEach((k, val) {
        final key = '$k';
        final m = int.parse(key.substring(4));
        if (m > 12 || val == null) return;
        final d = (val as num).toDouble();
        if (d == fill || d <= -998) return;
        grid[int.parse(key.substring(0, 4))]![m - 1] = d;
      });
      final months = (v['months'] as List).cast<int>();
      final scale = (v['scale'] as num).toDouble();
      final values = <double?>[];
      for (final y in ys) {
        final row = grid[y]!;
        final sel = [for (final m in months) row[m - 1]];
        if (sel.any((e) => e == null)) {
          values.add(null);
          continue;
        }
        double agg;
        if (v['how'] == 'total') {
          agg = 0;
          for (var i = 0; i < months.length; i++) {
            agg += sel[i]! * _monthDays[months[i] - 1];
          }
        } else {
          agg = sel.fold<double>(0, (a, b) => a + b!) / sel.length;
        }
        values.add(agg * scale);
      }
      out.add(_variable(v['key'] as String, v['title'] as String, v['title_hi'] as String, v['units'] as String, ys, values));
    }
    // very hot days above this place's own 1981-2010 90th percentile
    try {
      final d = ((daily['properties'] as Map)['parameter'] as Map)['T2M_MAX'] as Map;
      final dfill = _fill(daily);
      final keys = d.keys.map((e) => '$e').toList()..sort();
      final yrs = <int>[];
      final tx = <double?>[];
      for (final k in keys) {
        final val = d[k];
        yrs.add(int.parse(k.substring(0, 4)));
        tx.add(val == null || (val as num).toDouble() == dfill ? null : val.toDouble());
      }
      final ref = <double>[];
      for (var i = 0; i < tx.length; i++) {
        if (yrs[i] >= 1981 && yrs[i] <= 2010 && tx[i] != null) ref.add(tx[i]!);
      }
      final pool = ref.length > 3000 ? ref : tx.whereType<double>().toList();
      final thr = _percentile(pool, 90);
      final uy = yrs.toSet().toList()..sort();
      final counts = <double?>[];
      for (final y in uy) {
        var valid = 0, hot = 0;
        for (var i = 0; i < yrs.length; i++) {
          if (yrs[i] != y || tx[i] == null) continue;
          valid++;
          if (tx[i]! > thr) hot++;
        }
        counts.add(valid >= 330 ? hot.toDouble() : null);
      }
      out.insert(
          1,
          _variable('hotdays', 'Very hot days (above ${thr.toStringAsFixed(1)} °C)',
              'बहुत गर्म दिन (${thr.toStringAsFixed(1)} °C से ऊपर)', 'days', uy, counts,
              threshold: thr));
    } catch (_) {}
    return out;
  }

  static double _percentile(List<double> v, double q) {
    final s = List<double>.from(v)..sort();
    if (s.isEmpty) return double.nan;
    final pos = (s.length - 1) * q / 100.0;
    final lo = pos.floor(), hi = pos.ceil();
    return s[lo] + (s[hi] - s[lo]) * (pos - lo);
  }

  static PlaceVariable _variable(String key, String title, String titleHi, String units, List<int> years, List<double?> values,
      {double? threshold}) {
    // anomalies vs the 1991-2020 normal (does not change the slope, kept for parity with Python)
    final base = <double>[];
    for (var i = 0; i < years.length; i++) {
      if (years[i] >= 1991 && years[i] <= 2020 && values[i] != null) base.add(values[i]!);
    }
    final b = base.isEmpty ? 0.0 : base.reduce((a, c) => a + c) / base.length;
    final anom = values.map((v) => v == null ? null : v - b).toList();
    final r = mkTrend(anom, years, minYears: 10);
    final pt = pettitt(anom, years);
    final verdict = r.verdict();
    final early = meanOf(values, count: 10);
    final late = meanOf(values, count: 10, fromEnd: true);
    double? fin(double x) => x.isFinite ? x : null;
    return PlaceVariable(
      key: key,
      title: title,
      titleHi: titleHi,
      units: units,
      series: Series(years, values),
      trend: TrendInfo(
        slopeDec: fin(r.slope * 10),
        ciLoDec: fin(r.ciLo * 10),
        ciHiDec: fin(r.ciHi * 10),
        p: fin(r.p),
        snr: fin(r.snr),
        toe1: fin(r.toe1),
        emerged: r.emerged,
        yearsNeeded: fin(r.yearsNeeded),
        verdict: verdict,
        verdictEn: verdict,
        verdictHi: verdict,
        pettitt: pt == null ? null : Pettitt(pt.year, pt.p),
        n: r.n.toDouble(),
        t0: fin(r.t0),
        t1: fin(r.t1),
      ),
      early: [years.isEmpty ? null : years.first.toDouble(), years.isEmpty ? null : years[math.min(9, years.length - 1)].toDouble(), early],
      late: [years.isEmpty ? null : years[math.max(0, years.length - 10)].toDouble(), years.isEmpty ? null : years.last.toDouble(), late],
      threshold: threshold,
    );
  }
}
