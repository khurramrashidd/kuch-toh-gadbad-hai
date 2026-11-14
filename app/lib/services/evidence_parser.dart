// "Bring your own evidence": reads a time-series file exported by NASA Giovanni,
// AppEEARS, NOAA Climate Data Online, KNMI Climate Explorer or any simple CSV.
// Pure Dart, no Flutter imports.

import '../stats/extra.dart';

class EvidenceError implements Exception {
  EvidenceError(this.en, this.hi);
  final String en, hi;
  @override
  String toString() => en;
}

class Evidence {
  Evidence({required this.format, required this.title, required this.columns, required this.column, required this.points, required this.isMonthly, required this.rows, required this.dropped});
  final String format, title, column;
  final List<String> columns; // numeric columns the user can switch between
  final List<MonthlyPoint> points; // monthly means (month = 1 for yearly files)
  final bool isMonthly;
  final int rows, dropped;
}

const _skipCols = ['lat', 'latitude', 'lon', 'longitude', 'long', 'elevation', 'elev', 'station', 'id', 'name', 'category', 'qa', 'qc', 'quality', 'flag', 'attributes', 'doy', 'year', 'month', 'day', 'yr', 'mo', 'dy', 'hour', 'modis_tile', 'line', 'sample', 'time', 'date', 'datetime', 'timestamp'];

List<String> _split(String line, String sep) {
  if (sep == ' ') return line.trim().split(RegExp(r'\s+'));
  final out = <String>[];
  final sb = StringBuffer();
  var q = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') {
      q = !q;
    } else if (ch == sep && !q) {
      out.add(sb.toString().trim());
      sb.clear();
    } else {
      sb.write(ch);
    }
  }
  out.add(sb.toString().trim());
  return out;
}

String _sepOf(String line) {
  final c = ','.allMatches(line).length, s = ';'.allMatches(line).length, t = '\t'.allMatches(line).length;
  if (t > c && t > s) return '\t';
  if (s > c) return ';';
  if (c > 0) return ',';
  return ' ';
}

/// (year, month, hasMonth) from many date spellings; null when not a date.
(int, int, bool)? parseWhen(String raw) {
  final s = raw.trim().replaceAll('"', '');
  if (s.isEmpty) return null;
  var m = RegExp(r'^(\d{4})[-/.](\d{1,2})(?:[-/.](\d{1,2}))?').firstMatch(s);
  if (m != null) return (int.parse(m.group(1)!), int.parse(m.group(2)!), true);
  m = RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})').firstMatch(s);
  if (m != null) {
    final a = int.parse(m.group(1)!), b = int.parse(m.group(2)!);
    return (int.parse(m.group(3)!), a > 12 ? b : a, true); // MM/DD/YYYY unless impossible
  }
  if (RegExp(r'^\d{8}$').hasMatch(s)) return (int.parse(s.substring(0, 4)), int.parse(s.substring(4, 6)), true);
  if (RegExp(r'^\d{6}$').hasMatch(s)) {
    final mo = int.parse(s.substring(4, 6));
    if (mo >= 1 && mo <= 12) return (int.parse(s.substring(0, 4)), mo, true);
  }
  if (RegExp(r'^\d{7}$').hasMatch(s)) {
    // YYYYDDD (MODIS day of year)
    final y = int.parse(s.substring(0, 4)), d = int.parse(s.substring(4));
    final dt = DateTime(y, 1, 1).add(Duration(days: d - 1));
    return (y, dt.month, true);
  }
  if (RegExp(r'^\d{4}$').hasMatch(s)) return (int.parse(s), 1, false);
  final dec = double.tryParse(s);
  if (dec != null && dec > 1800 && dec < 2200) {
    final y = dec.floor();
    final frac = dec - y;
    if (frac == 0) return (y, 1, false);
    return (y, (frac * 12).floor().clamp(0, 11) + 1, true);
  }
  final dt = DateTime.tryParse(s);
  if (dt != null) return (dt.year, dt.month, true);
  return null;
}

Evidence parseEvidence(String text, {String? column, String fileName = ''}) {
  var t = text;
  if (t.startsWith('﻿')) t = t.substring(1);
  final all = t.split(RegExp(r'\r?\n'));
  if (all.where((l) => l.trim().isNotEmpty).length < 6) {
    throw EvidenceError('This file has too few lines to test a trend.', 'इस फ़ाइल में रुझान जाँचने के लिए बहुत कम पंक्तियाँ हैं।');
  }
  // ---- metadata lines (Giovanni: "Title:,...", "Fill Value (x):,-9999.9")
  var title = '';
  final fills = <double>{-9999, -9999.9, -999, -999.9, -99.99, 9999, 99999, -99999, 9.96921e36, 1e20};
  var format = 'CSV';
  for (final l in all.take(60)) {
    final low = l.toLowerCase();
    if (low.startsWith('title:')) {
      title = l.substring(6).replaceAll(RegExp(r'^[,;\s"]+|[",;\s]+$'), '');
      format = 'NASA Giovanni';
    }
    final fm = RegExp(r'fill[ _]?value[^,:=]*[:=,]\s*,?\s*([-+]?[\d.]+(?:[eE][-+]?\d+)?)', caseSensitive: false).firstMatch(l);
    if (fm != null) {
      final v = double.tryParse(fm.group(1)!);
      if (v != null) fills.add(v);
    }
  }
  // ---- header: first line whose next non-empty line starts with a date and has numbers
  var h = -1;
  var sep = ',';
  for (var i = 0; i < all.length - 1 && i < 300; i++) {
    final l = all[i];
    if (l.trim().isEmpty || l.trimLeft().startsWith('#')) continue;
    final s = _sepOf(l);
    final cells = _split(l, s);
    if (cells.length < 2) continue;
    if (cells.any((c) => double.tryParse(c) != null && parseWhen(c) == null)) continue; // a data row, not a header
    final nxt = all.skip(i + 1).firstWhere((x) => x.trim().isNotEmpty, orElse: () => '');
    final nc = _split(nxt, s);
    if (nc.length < 2) continue;
    if (nc.any((c) => parseWhen(c) != null) && nc.any((c) => double.tryParse(c) != null)) {
      h = i;
      sep = s;
      break;
    }
  }
  if (h < 0) {
    throw EvidenceError('No table with a date column was found. The file needs a header row, a date or year column and a number column.',
        'तारीख़ वाले कॉलम की तालिका नहीं मिली। फ़ाइल में शीर्षक पंक्ति, तारीख़/साल का कॉलम और संख्या का कॉलम चाहिए।');
  }
  final head = _split(all[h], sep).map((e) => e.replaceAll('"', '').trim()).toList();
  final lower = head.map((e) => e.toLowerCase()).toList();
  if (lower.contains('station') && lower.contains('date')) format = 'NOAA Climate Data Online';
  if (lower.any((c) => c.startsWith('mod') || c.startsWith('myd') || c.startsWith('vnp')) || lower.contains('modis_tile')) format = 'NASA AppEEARS';
  final rows = <List<String>>[];
  for (final l in all.skip(h + 1)) {
    if (l.trim().isEmpty || l.trimLeft().startsWith('#')) continue;
    final c = _split(l, sep);
    if (c.length >= 2) rows.add(c);
  }
  // ---- time columns
  int idx(List<String> names) {
    for (final n in names) {
      final i = lower.indexOf(n);
      if (i >= 0) return i;
    }
    return -1;
  }

  var dateCol = idx(['time', 'date', 'datetime', 'timestamp', 'decimal_year', 'decyear']);
  final yearCol = idx(['year', 'yr']);
  final monthCol = idx(['month', 'mo', 'mon']);
  if (dateCol < 0 && yearCol < 0) {
    // first column that parses as a date in most rows
    for (var c = 0; c < head.length; c++) {
      final ok = rows.take(20).where((r) => c < r.length && parseWhen(r[c]) != null).length;
      if (ok >= rows.take(20).length * 0.8) {
        dateCol = c;
        break;
      }
    }
  }
  if (dateCol < 0 && yearCol < 0) {
    throw EvidenceError('No date or year column found.', 'तारीख़ या साल का कॉलम नहीं मिला।');
  }
  // ---- numeric columns
  final numeric = <String>[];
  for (var c = 0; c < head.length; c++) {
    if (c == dateCol || c == yearCol || c == monthCol) continue;
    final name = lower[c];
    if (_skipCols.contains(name) || name.endsWith('_attributes') || name.contains('_qa') || name.contains('quality') || name.contains('pixel_reliability') || name.contains('line_y') || name.contains('sample_x')) continue;
    final sample = rows.take(60).where((r) => c < r.length).toList();
    if (sample.isEmpty) continue;
    final ok = sample.where((r) => double.tryParse(r[c]) != null).length;
    final distinct = sample.map((r) => r[c]).toSet().length;
    if (ok >= sample.length * 0.5 && distinct > 1) numeric.add(head[c]);
  }
  if (numeric.isEmpty) {
    throw EvidenceError('No number column found next to the dates.', 'तारीख़ों के साथ कोई संख्या वाला कॉलम नहीं मिला।');
  }
  final col = (column != null && numeric.contains(column)) ? column : numeric.first;
  final vc = head.indexOf(col);
  // ---- collect, average per month
  final sum = <int, double>{}, cnt = <int, int>{};
  var hasMonth = false, dropped = 0;
  for (final r in rows) {
    if (vc >= r.length) continue;
    (int, int, bool)? when;
    if (dateCol >= 0 && dateCol < r.length) {
      when = parseWhen(r[dateCol]);
    } else if (yearCol >= 0 && yearCol < r.length) {
      final y = double.tryParse(r[yearCol]);
      if (y != null) {
        final mo = monthCol >= 0 && monthCol < r.length ? int.tryParse(r[monthCol]) : null;
        when = mo != null && mo >= 1 && mo <= 12 ? (y.floor(), mo, true) : parseWhen(r[yearCol]);
      }
    }
    final v = double.tryParse(r[vc]);
    if (when == null || v == null || !v.isFinite || fills.any((f) => (v - f).abs() <= 1e-6 * (1 + f.abs()))) {
      dropped++;
      continue;
    }
    if (when.$2 < 1 || when.$2 > 12 || when.$1 < 1700 || when.$1 > 2200) {
      dropped++;
      continue;
    }
    if (when.$3) hasMonth = true;
    final key = when.$1 * 12 + (when.$2 - 1);
    sum[key] = (sum[key] ?? 0) + v;
    cnt[key] = (cnt[key] ?? 0) + 1;
  }
  final keys = sum.keys.toList()..sort();
  if (keys.length < 6) {
    throw EvidenceError('Fewer than 6 usable values were found.', '6 से कम काम के मान मिले।');
  }
  final pts = [for (final k in keys) MonthlyPoint(k ~/ 12, k % 12 + 1, sum[k]! / cnt[k]!)];
  final distinctMonths = pts.map((p) => p.month).toSet().length;
  return Evidence(
    format: format,
    title: title.isEmpty ? fileName : title,
    columns: numeric,
    column: col,
    points: pts,
    isMonthly: hasMonth && distinctMonths >= 3,
    rows: rows.length,
    dropped: dropped,
  );
}
