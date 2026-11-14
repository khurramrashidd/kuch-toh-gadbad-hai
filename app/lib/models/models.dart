import 'dart:math' as math;
import 'dart:ui' show Color;

import 'json.dart';

/// Picks English or Hindi text.
String pick(String lang, String en, String hi) => (lang == 'hi' && hi.isNotEmpty) ? hi : en;

class Series {
  Series(this.years, this.values);
  final List<int> years;
  final List<double?> values;

  factory Series.fromJson(dynamic j) {
    final m = toM(j);
    return Series(toIL(m['years']), toDL(m['values']));
  }

  bool get isEmpty => years.isEmpty || values.every((v) => v == null);
}

class Pettitt {
  Pettitt(this.year, this.p);
  final int year;
  final double p;
  static Pettitt? fromJson(dynamic j) {
    final m = toM(j);
    if (m.isEmpty || m['year'] == null) return null;
    return Pettitt(toI(m['year']) ?? 0, toD(m['p']) ?? 1);
  }
}

class Alibi {
  Alibi({required this.flag, this.label, this.labelHi, this.survives, this.breakYear});
  final bool flag;
  final String? label;
  final String? labelHi;
  final bool? survives;
  final int? breakYear;
  static Alibi? fromJson(dynamic j) {
    final m = toM(j);
    if (m.isEmpty) return null;
    return Alibi(
      flag: toB(m['flag']),
      label: m['label'] as String?,
      labelHi: m['label_hi'] as String?,
      survives: m['survives'] is bool ? m['survives'] as bool : null,
      breakYear: toI(m['break_year']),
    );
  }
}

/// Evidence for one trend (region, series, place variable or map cell).
class TrendInfo {
  TrendInfo({
    this.slopeDec,
    this.ciLoDec,
    this.ciHiDec,
    this.p,
    this.snr,
    this.toe1,
    this.emerged = false,
    this.yearsNeeded,
    this.verdict = 'insufficient',
    this.verdictEn = 'Not enough data',
    this.verdictHi = 'डेटा कम है',
    this.pettitt,
    this.alibi,
    this.n,
    this.t0,
    this.t1,
    this.per,
  });

  final double? slopeDec, ciLoDec, ciHiDec, p, snr, toe1, yearsNeeded, n, t0, t1;
  final bool emerged;
  final String verdict, verdictEn, verdictHi;
  final Pettitt? pettitt;
  final Alibi? alibi;
  final String? per;

  factory TrendInfo.fromJson(dynamic j) {
    final m = toM(j);
    return TrendInfo(
      slopeDec: toD(m['slope_dec']),
      ciLoDec: toD(m['ci_lo_dec']),
      ciHiDec: toD(m['ci_hi_dec']),
      p: toD(m['p']),
      snr: toD(m['snr']),
      toe1: toD(m['toe1']),
      emerged: toB(m['emerged']),
      yearsNeeded: toD(m['years_needed']),
      verdict: toS(m['verdict'], 'insufficient'),
      verdictEn: toS(m['verdict_en'], 'Not enough data'),
      verdictHi: toS(m['verdict_hi'], 'डेटा कम है'),
      pettitt: Pettitt.fromJson(m['pettitt']),
      alibi: Alibi.fromJson(m['alibi']),
      n: toD(m['n']),
      t0: toD(m['t0']),
      t1: toD(m['t1']),
      per: m['per'] as String?,
    );
  }

  String verdictLabel(String lang) => pick(lang, verdictEn, verdictHi);
}

class Verdict {
  Verdict(this.code, this.en, this.hi, this.headlineEn, this.headlineHi, this.detailEn, this.detailHi);
  final String code, en, hi, headlineEn, headlineHi, detailEn, detailHi;
  factory Verdict.fromJson(dynamic j) {
    final m = toM(j);
    return Verdict(toS(m['code'], 'open'), toS(m['en']), toS(m['hi']), toS(m['headline_en']), toS(m['headline_hi']),
        toS(m['detail_en']), toS(m['detail_hi']));
  }
  String label(String lang) => pick(lang, en, hi);
  String headline(String lang) => pick(lang, headlineEn, headlineHi);
  String detail(String lang) => pick(lang, detailEn, detailHi);
}

class FieldStats {
  FieldStats(this.validAreaFrac, this.sigAreaFrac, this.sigUpFrac, this.sigDownFrac, this.nCells);
  final double validAreaFrac, sigAreaFrac, sigUpFrac, sigDownFrac;
  final int nCells;
  factory FieldStats.fromJson(dynamic j) {
    final m = toM(j);
    return FieldStats(toD(m['valid_area_frac']) ?? 0, toD(m['sig_area_frac']) ?? 0, toD(m['sig_up_frac']) ?? 0,
        toD(m['sig_down_frac']) ?? 0, toI(m['n_cells']) ?? 0);
  }
}

class LayerRef {
  LayerRef(this.season, this.path, this.period, this.field, this.unitsPer);
  final String season, path, unitsPer;
  final List<int> period;
  final FieldStats field;
  factory LayerRef.fromJson(dynamic j) {
    final m = toM(j);
    return LayerRef(toS(m['season'], 'ANN'), toS(m['path']), toIL(m['period']), FieldStats.fromJson(m['field']), toS(m['units_per']));
  }
}

class DatasetInfo {
  DatasetInfo({
    required this.id,
    required this.title,
    required this.titleHi,
    required this.short,
    required this.shortHi,
    required this.sphere,
    required this.mission,
    required this.kind,
    required this.role,
    required this.units,
    required this.citation,
    required this.urlInfo,
    required this.login,
    required this.layers,
    required this.seriesPath,
    required this.notes,
    this.explain = '',
    this.explainHi = '',
    this.qualityNote = '',
  });
  final String id, title, titleHi, short, shortHi, sphere, mission, kind, role, units, citation, urlInfo, notes, explain, explainHi, qualityNote;
  final bool login;
  final List<LayerRef> layers;
  final String? seriesPath;

  factory DatasetInfo.fromJson(dynamic j) {
    final m = toM(j);
    final series = toM(m['series']);
    return DatasetInfo(
      id: toS(m['id']),
      title: toS(m['title']),
      titleHi: toS(m['title_hi']),
      short: toS(m['short']),
      shortHi: toS(m['short_hi']),
      sphere: toS(m['sphere']),
      mission: toS(m['mission']),
      kind: toS(m['kind']),
      role: toS(m['role']),
      units: toS(m['units']),
      citation: toS(m['citation']),
      urlInfo: toS(m['url_info']),
      login: toB(m['login']),
      layers: toML(m['layers']).map(LayerRef.fromJson).toList(),
      seriesPath: series['path'] as String?,
      notes: toS(m['notes']),
      explain: toS(m['explain']),
      explainHi: toS(m['explain_hi']),
      qualityNote: toS(m['quality_note']),
    );
  }
  String name(String lang) => pick(lang, title, titleHi);
  String definition(String lang) => pick(lang, explain, explainHi.isEmpty ? explain : explainHi);
  String shortName(String lang) => pick(lang, short, shortHi);
}

class RegionSummary {
  RegionSummary(this.name, this.nameHi, this.sign, this.slopeDec, this.spark);
  final String name, nameHi;
  final int sign;
  final double? slopeDec;
  final List<double?> spark;
  factory RegionSummary.fromJson(dynamic j) {
    final m = toM(j);
    return RegionSummary(toS(m['name']), toS(m['name_hi']), toI(m['sign']) ?? 0, toD(m['slope_dec']), toDL(m['spark']));
  }
}

class CaseSummary {
  CaseSummary({
    required this.id,
    required this.title,
    required this.titleHi,
    required this.tagline,
    required this.taglineHi,
    required this.type,
    required this.spotlight,
    required this.strength,
    required this.verdict,
    required this.regions,
    required this.perDecade,
    required this.perDecadeHi,
    required this.period,
    required this.file,
    required this.isMirror,
    required this.source,
  });
  final String id, title, titleHi, tagline, taglineHi, type, spotlight, perDecade, perDecadeHi, file, source;
  final int strength;
  final Verdict verdict;
  final List<RegionSummary> regions;
  final List<int> period;
  final bool isMirror;

  factory CaseSummary.fromJson(dynamic j) {
    final m = toM(j);
    return CaseSummary(
      id: toS(m['id']),
      title: toS(m['title']),
      titleHi: toS(m['title_hi']),
      tagline: toS(m['tagline']),
      taglineHi: toS(m['tagline_hi']),
      type: toS(m['type']),
      spotlight: toS(m['spotlight'], 'global'),
      strength: toI(m['strength']) ?? 0,
      verdict: Verdict.fromJson(m['verdict']),
      regions: toML(m['regions']).map(RegionSummary.fromJson).toList(),
      perDecade: toS(m['per_decade']),
      perDecadeHi: toS(m['per_decade_hi']),
      period: toIL(m['period']),
      file: toS(m['file']),
      isMirror: toB(m['is_mirror']),
      source: toS(m['source']),
    );
  }
  String name(String lang) => pick(lang, title, titleHi);
  String tag(String lang) => pick(lang, tagline, taglineHi);
}

class PlaceInfo {
  PlaceInfo(this.slug, this.name, this.nameHi, this.country, this.lat, this.lon, this.file);
  final String slug, name, nameHi, country, file;
  final double lat, lon;
  factory PlaceInfo.fromJson(dynamic j) {
    final m = toM(j);
    return PlaceInfo(toS(m['slug']), toS(m['name']), toS(m['name_hi']), toS(m['country']), toD(m['lat']) ?? 0, toD(m['lon']) ?? 0,
        toS(m['file']));
  }
  String label(String lang) => pick(lang, name, nameHi);
}

class Catalog {
  Catalog({
    required this.demo,
    required this.generatedAt,
    required this.aiModels,
    required this.datasets,
    required this.cases,
    required this.places,
    required this.selftest,
    required this.seasons,
    required this.analysis,
  });
  final bool demo;
  final String generatedAt;
  final List<String> aiModels;
  final List<DatasetInfo> datasets;
  final List<CaseSummary> cases;
  final List<PlaceInfo> places;
  final String? selftest;
  final Map<String, List<String>> seasons;
  final Map<String, dynamic> analysis;

  factory Catalog.fromJson(dynamic j) {
    final m = toM(j);
    final app = toM(m['app']);
    final seasons = <String, List<String>>{};
    toM(m['seasons']).forEach((k, v) => seasons[k] = toSL(v));
    return Catalog(
      demo: toB(app['demo']),
      generatedAt: toS(app['generated_at']),
      aiModels: toSL(toM(m['ai'])['models']),
      datasets: toML(m['datasets']).map(DatasetInfo.fromJson).toList(),
      cases: toML(m['cases']).map(CaseSummary.fromJson).toList(),
      places: toML(m['places']).map(PlaceInfo.fromJson).toList(),
      selftest: m['selftest'] as String?,
      seasons: seasons,
      analysis: toM(m['analysis']),
    );
  }

  List<DatasetInfo> get layerDatasets => datasets.where((d) => d.layers.isNotEmpty).toList();

  DatasetInfo? dataset(String id) {
    for (final d in datasets) {
      if (d.id == id) return d;
    }
    return null;
  }

  String seasonLabel(String code, String lang) {
    final v = seasons[code];
    if (v == null || v.isEmpty) return code;
    return pick(lang, v[0], v.length > 1 ? v[1] : v[0]);
  }
}

// ---------------------------------------------------------------- case files
class Fingerprint {
  Fingerprint(this.raw);
  final Map<String, dynamic> raw;
  double? get beta => toD(raw['beta']);
  double? get r => toD(raw['r']);
  double? get p => toD(raw['p']);
  double? get explained => toD(raw['explained']);
  double? get cotrendR => toD(raw['cotrend_r']);
  double? get predictedSlope => toD(raw['predicted_slope']);
  Series? get series => raw['series'] == null ? null : Series.fromJson(raw['series']);
  Map<String, dynamic> get ownTrend => toM(raw['own_trend']);
}

class DriverTest {
  DriverTest(this.id, this.title, this.titleHi, this.units, this.kind, this.verdict, this.a, this.b, this.series);
  final String id, title, titleHi, units, kind, verdict;
  final Fingerprint a, b;
  final Series? series;
  factory DriverTest.fromJson(dynamic j) {
    final m = toM(j);
    return DriverTest(toS(m['id']), toS(m['title']), toS(m['title_hi']), toS(m['units']), toS(m['kind']), toS(m['verdict'], 'none'),
        Fingerprint(toM(m['A'])), Fingerprint(toM(m['B'])), m['series'] == null ? null : Series.fromJson(m['series']));
  }
  String name(String lang) => pick(lang, title, titleHi);
}

class Check {
  Check(this.key, this.status, this.en, this.hi, this.titleEn, this.titleHi);
  final String key, status, en, hi, titleEn, titleHi;
  factory Check.fromJson(dynamic j) {
    final m = toM(j);
    return Check(toS(m['key']), toS(m['status'], 'na'), toS(m['en']), toS(m['hi']), toS(m['title_en']), toS(m['title_hi']));
  }
  String title(String lang) => pick(lang, titleEn, titleHi);
  String text(String lang) => pick(lang, en, hi);
}

class CaseRegion {
  CaseRegion({
    required this.key,
    required this.name,
    required this.nameHi,
    required this.sign,
    required this.cells,
    required this.res,
    required this.bbox,
    required this.centroid,
    required this.areaKm2,
    required this.series,
    required this.trend,
    required this.levels,
  });
  final String key, name, nameHi;
  final int sign;
  final List<List<double>> cells;
  final List<double>? res;
  final List<double>? bbox;
  final List<double>? centroid;
  final double? areaKm2;
  final Series series;
  final TrendInfo trend;
  final List<double>? levels;

  factory CaseRegion.fromJson(dynamic j) {
    final m = toM(j);
    List<double>? dlist(dynamic v) => v is List ? v.map((e) => toD(e) ?? 0).toList() : null;
    final cells = <List<double>>[];
    if (m['cells'] is List) {
      for (final c in m['cells'] as List) {
        if (c is List && c.length >= 2) cells.add([toD(c[0]) ?? 0, toD(c[1]) ?? 0]);
      }
    }
    return CaseRegion(
      key: toS(m['key']),
      name: toS(m['name']),
      nameHi: toS(m['name_hi']),
      sign: toI(m['sign']) ?? 0,
      cells: cells,
      res: dlist(m['res']),
      bbox: dlist(m['bbox']),
      centroid: dlist(m['centroid']),
      areaKm2: toD(m['area_km2']),
      series: Series.fromJson(m['series']),
      trend: TrendInfo.fromJson(m['trend']),
      levels: dlist(m['levels']),
    );
  }
  String label(String lang) => pick(lang, name, nameHi);

  /// A point to pin on the map.
  List<double>? get pin {
    if (centroid != null && centroid!.length == 2) return centroid;
    if (bbox != null && bbox!.length == 4) return [(bbox![1] + bbox![3]) / 2, (bbox![0] + bbox![2]) / 2];
    return null;
  }

  bool contains(double lat, double lon) {
    final r = res;
    if (r != null && r.length == 2 && cells.isNotEmpty) {
      for (final c in cells) {
        if ((c[0] - lat).abs() <= r[0] / 2 + 1e-6 && _lonDiff(c[1], lon) <= r[1] / 2 + 1e-6) return true;
      }
      return false;
    }
    final b = bbox;
    if (b != null && b.length == 4) return lat >= b[1] && lat <= b[3] && lon >= b[0] && lon <= b[2];
    return false;
  }
}

double _lonDiff(double a, double b) {
  final d = ((a - b + 540) % 360) - 180;
  return d.abs();
}

class CaseFile {
  CaseFile({
    required this.id,
    required this.title,
    required this.titleHi,
    required this.tagline,
    required this.taglineHi,
    required this.question,
    required this.questionHi,
    required this.type,
    required this.sourceShort,
    required this.sourceShortHi,
    required this.sourceTitle,
    required this.sourceTitleHi,
    required this.mission,
    required this.citation,
    required this.units,
    required this.perDecade,
    required this.perDecadeHi,
    required this.season,
    required this.seasonLabel,
    required this.period,
    required this.regions,
    required this.drivers,
    required this.bestDriver,
    required this.verdict,
    required this.checks,
    required this.strength,
    required this.isMirror,
    required this.layerSource,
    required this.layerSeason,
    required this.raw,
  });
  final String id, title, titleHi, tagline, taglineHi, question, questionHi, type;
  final String sourceShort, sourceShortHi, sourceTitle, sourceTitleHi, mission, citation, units, perDecade, perDecadeHi, season;
  final List<String> seasonLabel;
  final List<int> period;
  final List<CaseRegion> regions;
  final List<DriverTest> drivers;
  final String? bestDriver;
  final Verdict verdict;
  final List<Check> checks;
  final int strength;
  final bool isMirror;
  final String? layerSource, layerSeason;
  final Map<String, dynamic> raw;

  factory CaseFile.fromJson(dynamic j) {
    final m = toM(j);
    final src = toM(m['source']);
    final layer = toM(m['layer']);
    return CaseFile(
      id: toS(m['id']),
      title: toS(m['title']),
      titleHi: toS(m['title_hi']),
      tagline: toS(m['tagline']),
      taglineHi: toS(m['tagline_hi']),
      question: toS(m['question']),
      questionHi: toS(m['question_hi']),
      type: toS(m['type']),
      sourceShort: toS(src['short']),
      sourceShortHi: toS(src['short_hi']),
      sourceTitle: toS(src['title']),
      sourceTitleHi: toS(src['title_hi']),
      mission: toS(src['mission']),
      citation: toS(src['citation']),
      units: toS(src['units']),
      perDecade: toS(src['per_decade']),
      perDecadeHi: toS(src['per_decade_hi']),
      season: toS(m['season'], 'ANN'),
      seasonLabel: toSL(m['season_label']),
      period: toIL(m['period']),
      regions: toML(m['regions']).map(CaseRegion.fromJson).toList(),
      drivers: toML(m['drivers']).map(DriverTest.fromJson).toList(),
      bestDriver: m['best_driver'] as String?,
      verdict: Verdict.fromJson(m['verdict']),
      checks: toML(m['checks']).map(Check.fromJson).toList(),
      strength: toI(m['strength']) ?? 0,
      isMirror: toB(m['is_mirror']),
      layerSource: layer['source'] as String?,
      layerSeason: layer['season'] as String?,
      raw: m,
    );
  }
  String name(String lang) => pick(lang, title, titleHi);
  String perDecadeLabel(String lang) => pick(lang, perDecade, perDecadeHi);
}

// ---------------------------------------------------------------- map layers
class LayerMeta {
  LayerMeta({
    required this.path,
    required this.source,
    required this.season,
    required this.period,
    required this.lat0,
    required this.dlat,
    required this.nlat,
    required this.lon0,
    required this.dlon,
    required this.nlon,
    required this.bounds,
    required this.unitsPer,
    required this.unitsPerHi,
    required this.vmax,
    required this.palette,
    required this.seriesBlock,
    required this.field,
  });
  final String path, source, season, unitsPer, unitsPerHi;
  final List<int> period;
  final double lat0, dlat, lon0, dlon, vmax;
  final int nlat, nlon, seriesBlock;
  final List<double> bounds; // west, south, east, north
  final List<Color> palette;
  final FieldStats field;

  factory LayerMeta.fromJson(String path, dynamic j) {
    final m = toM(j);
    final g = toM(m['grid']);
    final pal = toSL(m['palette']).map(hexColor).toList();
    final b = toDL(m['bounds']).map((e) => e ?? 0).toList();
    return LayerMeta(
      path: path,
      source: toS(m['source']),
      season: toS(m['season']),
      period: toIL(m['period']),
      lat0: toD(g['lat0']) ?? -89,
      dlat: toD(g['dlat']) ?? 2,
      nlat: toI(g['nlat']) ?? 90,
      lon0: toD(g['lon0']) ?? -179,
      dlon: toD(g['dlon']) ?? 2,
      nlon: toI(g['nlon']) ?? 180,
      bounds: b.length == 4 ? b : [-180, -90, 180, 90],
      unitsPer: toS(m['units_per']),
      unitsPerHi: toS(m['units_per_hi']),
      vmax: toD(m['vmax']) ?? 1,
      palette: pal.isEmpty ? [const Color(0xFF2166AC), const Color(0xFFF7F7F7), const Color(0xFFB2182B)] : pal,
      seriesBlock: toI(m['series_block']) ?? 16,
      field: FieldStats.fromJson(m['field']),
    );
  }

  String units(String lang) => pick(lang, unitsPer, unitsPerHi);

  /// Grid indices for a coordinate, or null when outside the grid.
  (int, int)? index(double lat, double lon) {
    final i = ((lat - lat0) / dlat).round();
    var j = ((lon - lon0) / dlon).round();
    if (j < 0) j += nlon;
    if (j >= nlon) j -= nlon;
    if (i < 0 || i >= nlat || j < 0 || j >= nlon) return null;
    return (i, j);
  }

  Color colorFor(double v) {
    final x = ((v / (vmax == 0 ? 1 : vmax)) + 1) / 2;
    final t = x.clamp(0.0, 1.0) * (palette.length - 1);
    final i0 = math.min(t.floor(), palette.length - 2);
    final f = t - i0;
    return Color.lerp(palette[i0], palette[i0 + 1], f) ?? palette[i0];
  }
}

Color hexColor(String h) {
  var s = h.replaceAll('#', '');
  if (s.length == 6) s = 'FF$s';
  return Color(int.tryParse(s, radix: 16) ?? 0xFF888888);
}

class CellInfo {
  CellInfo(this.i, this.j, this.lat, this.lon, this.values);
  final int i, j;
  final double lat, lon;
  final Map<String, double?> values;
  double? operator [](String k) => values[k];
  int get verdictCode => (values['v'] ?? 1).round();
}

class LayerCells {
  LayerCells(this.nlat, this.nlon, this.fields, this.position);
  final int nlat, nlon;
  final Map<String, List<double?>> fields;

  /// Sparse files list only cells with a result: grid index -> position in the arrays.
  final Map<int, int>? position;

  factory LayerCells.fromJson(dynamic j) {
    final m = toM(j);
    final names = toSL(m['fields']);
    final f = <String, List<double?>>{};
    for (final n in names) {
      f[n] = toDL(m[n]);
    }
    Map<int, int>? pos;
    if (toB(m['sparse'])) {
      final idx = toIL(m['idx']);
      pos = {for (var k = 0; k < idx.length; k++) idx[k]: k};
    }
    return LayerCells(toI(m['nlat']) ?? 0, toI(m['nlon']) ?? 0, f, pos);
  }

  CellInfo? cell(LayerMeta meta, double lat, double lon) {
    final ij = meta.index(lat, lon);
    if (ij == null) return null;
    final (i, j) = ij;
    final grid = i * nlon + j;
    final k = position == null ? grid : position![grid];
    if (k == null) return null;
    final vals = <String, double?>{};
    fields.forEach((name, list) => vals[name] = k < list.length ? list[k] : null);
    if (vals['p'] == null && vals['s'] == null) return null;
    return CellInfo(i, j, meta.lat0 + i * meta.dlat, meta.lon0 + j * meta.dlon, vals);
  }
}

// ---------------------------------------------------------------- places
class PlaceVariable {
  PlaceVariable({
    required this.key,
    required this.title,
    required this.titleHi,
    required this.units,
    required this.series,
    required this.trend,
    required this.early,
    required this.late,
    this.threshold,
  });
  final String key, title, titleHi, units;
  final Series series;
  final TrendInfo trend;
  final List<double?> early, late; // [y0, y1, mean]
  final double? threshold;

  factory PlaceVariable.fromJson(dynamic j) {
    final m = toM(j);
    final tn = toM(m['then_now']);
    return PlaceVariable(
      key: toS(m['key']),
      title: toS(m['title']),
      titleHi: toS(m['title_hi']),
      units: toS(m['units']),
      series: Series(toIL(m['years']), toDL(m['values'])),
      trend: TrendInfo.fromJson(m['trend']),
      early: toDL(tn['early']),
      late: toDL(tn['late']),
      threshold: toD(m['threshold']),
    );
  }
  String name(String lang) => pick(lang, title, titleHi);
}

class PlaceReport {
  PlaceReport({
    required this.name,
    required this.nameHi,
    required this.country,
    required this.lat,
    required this.lon,
    required this.source,
    required this.fetchedAt,
    required this.variables,
    this.live = false,
  });
  final String name, nameHi, country, source, fetchedAt;
  final double lat, lon;
  final List<PlaceVariable> variables;
  final bool live;
  factory PlaceReport.fromJson(dynamic j) {
    final m = toM(j);
    return PlaceReport(
      name: toS(m['name']),
      nameHi: toS(m['name_hi']),
      country: toS(m['country']),
      lat: toD(m['lat']) ?? 0,
      lon: toD(m['lon']) ?? 0,
      source: toS(m['source']),
      fetchedAt: toS(m['fetched_at']),
      variables: toML(m['variables']).map(PlaceVariable.fromJson).toList(),
    );
  }
  String label(String lang) => pick(lang, name, nameHi);
}
