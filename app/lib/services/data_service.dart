import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../models/models.dart';

class DataException implements Exception {
  DataException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Reads the pipeline output (JSON + PNG) from Firebase Hosting, with an in-memory cache.
class DataService {
  DataService(this.baseUrl);
  final String baseUrl;
  final Map<String, Future<dynamic>> _cache = {};

  String _v = ''; // data version (catalog time stamp): new pipeline output -> new URLs -> no stale cache

  String url(String rel) => _v.isEmpty ? '$baseUrl$rel' : '$baseUrl$rel?v=$_v';

  void clear() => _cache.clear();

  Future<Map<String, dynamic>> _freshCatalog() async {
    final u = '${baseUrl}catalog.json?t=${DateTime.now().millisecondsSinceEpoch}';
    final res = await http.get(Uri.parse(u)).timeout(const Duration(seconds: 40));
    if (res.statusCode != 200) throw DataException('HTTP ${res.statusCode} for catalog.json');
    try {
      return Map<String, dynamic>.from(jsonDecode(utf8.decode(res.bodyBytes)) as Map);
    } catch (e) {
      throw DataException('Bad JSON in catalog.json');
    }
  }

  /// Time stamp of the catalog on the server right now (used by live mode).
  Future<String?> peekGeneratedAt() async {
    final m = await _freshCatalog();
    final app = m['app'];
    return app is Map ? '${app['generated_at']}' : null;
  }

  Future<dynamic> json(String rel) {
    return _cache.putIfAbsent(rel, () async {
      final res = await http.get(Uri.parse(url(rel))).timeout(const Duration(seconds: 40));
      if (res.statusCode != 200) {
        _cache.remove(rel);
        throw DataException('HTTP ${res.statusCode} for $rel');
      }
      try {
        return jsonDecode(utf8.decode(res.bodyBytes));
      } catch (e) {
        _cache.remove(rel);
        throw DataException('Bad JSON in $rel');
      }
    });
  }

  Future<Catalog> catalog({bool fresh = false}) async {
    final c = Catalog.fromJson(await _freshCatalog());
    final v = c.generatedAt.replaceAll(RegExp(r'[^0-9]'), '');
    if (v != _v) {
      _v = v;
      _cache.clear();
    }
    return c;
  }

  Future<CaseFile> caseFile(String rel) async => CaseFile.fromJson(await json(rel));

  Future<LayerMeta> layerMeta(String path) async => LayerMeta.fromJson(path, await json('$path/meta.json'));

  Future<LayerCells> layerCells(String path) async => LayerCells.fromJson(await json('$path/cells.json'));

  /// Time series of one map cell (anomalies), loaded from its 16x16 block file.
  Future<Series?> cellSeries(LayerMeta meta, int i, int j) async {
    final b = meta.seriesBlock;
    final bi = i ~/ b, bj = j ~/ b;
    try {
      final m = await json('${meta.path}/series/${bi}_$bj.json') as Map;
      final years = (m['years'] as List).map((e) => (e as num).toInt()).toList();
      final nj = (m['nj'] as num).toInt();
      final k = (i - (m['i0'] as num).toInt()) * nj + (j - (m['j0'] as num).toInt());
      final vals = m['v'] as List;
      if (k < 0 || k >= vals.length || vals[k] == null) return null;
      return Series(years, (vals[k] as List).map((e) => e == null ? null : (e as num).toDouble()).toList());
    } catch (_) {
      return null;
    }
  }

  /// Area-weighted mean series of all map cells inside a box (west, south, east, north).
  /// Returns the series and the number of cells used.
  Future<(Series, int)?> regionSeries(LayerMeta meta, LayerCells cells, List<double> bbox) async {
    final w = bbox[0], s = bbox[1], e = bbox[2], n = bbox[3];
    final picked = <(int, int, double)>[];
    for (var i = 0; i < meta.nlat; i++) {
      final lat = meta.lat0 + i * meta.dlat;
      if (lat < s || lat > n) continue;
      for (var j = 0; j < meta.nlon; j++) {
        var lon = meta.lon0 + j * meta.dlon;
        if (lon > 180) lon -= 360;
        final inside = w <= e ? (lon >= w && lon <= e) : (lon >= w || lon <= e);
        if (!inside) continue;
        final grid = i * meta.nlon + j;
        if (cells.position != null && !cells.position!.containsKey(grid)) continue;
        picked.add((i, j, math.cos(lat * math.pi / 180)));
      }
    }
    if (picked.isEmpty) return null;
    // thin very large regions so the phone never loads hundreds of files
    final stride = math.max(1, (picked.length / 1500).ceil());
    final use = [for (var k = 0; k < picked.length; k += stride) picked[k]];
    final b = meta.seriesBlock;
    final blocks = <String>{for (final c in use) '${c.$1 ~/ b}_${c.$2 ~/ b}'};
    if (blocks.length > 80) return null;
    final loaded = <String, Map>{};
    await Future.wait(blocks.map((key) async {
      try {
        loaded[key] = await json('${meta.path}/series/$key.json') as Map;
      } catch (_) {}
    }));
    List<int>? years;
    List<double>? sum, wsum;
    var used = 0;
    for (final c in use) {
      final m = loaded['${c.$1 ~/ b}_${c.$2 ~/ b}'];
      if (m == null) continue;
      final nj = (m['nj'] as num).toInt();
      final k = (c.$1 - (m['i0'] as num).toInt()) * nj + (c.$2 - (m['j0'] as num).toInt());
      final vals = m['v'] as List;
      if (k < 0 || k >= vals.length || vals[k] == null) continue;
      final row = vals[k] as List;
      years ??= (m['years'] as List).map((x) => (x as num).toInt()).toList();
      sum ??= List<double>.filled(years.length, 0);
      wsum ??= List<double>.filled(years.length, 0);
      if (row.length != years.length) continue;
      used++;
      for (var t = 0; t < row.length; t++) {
        final v = row[t];
        if (v == null) continue;
        sum[t] += (v as num).toDouble() * c.$3;
        wsum[t] += c.$3;
      }
    }
    if (years == null || used == 0) return null;
    // a year counts only when most of the region has data
    final wmax = wsum!.reduce(math.max);
    final out = <double?>[for (var t = 0; t < years.length; t++) wsum[t] >= 0.6 * wmax && wsum[t] > 0 ? sum![t] / wsum[t] : null];
    return (Series(years, out), used * stride);
  }

  Future<PlaceReport> place(String rel) async => PlaceReport.fromJson(await json(rel));

  Future<Map<String, dynamic>> map(String rel) async => Map<String, dynamic>.from(await json(rel) as Map);
}
