// Tolerant JSON helpers: pipeline output uses null for NaN and may omit keys.

double? toD(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse('$v');
}

int? toI(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  return int.tryParse('$v');
}

String toS(dynamic v, [String def = '']) => v == null ? def : '$v';

bool toB(dynamic v) => v == true || v == 1 || v == 'true';

List<double?> toDL(dynamic v) => v is List ? v.map(toD).toList() : <double?>[];

List<int> toIL(dynamic v) => v is List ? v.map((e) => toI(e) ?? 0).toList() : <int>[];

List<String> toSL(dynamic v) => v is List ? v.map((e) => '$e').toList() : <String>[];

Map<String, dynamic> toM(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<Map<String, dynamic>> toML(dynamic v) =>
    v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];
