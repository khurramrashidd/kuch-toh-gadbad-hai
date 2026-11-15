import 'dart:convert';

import 'package:http/http.dart' as http;

/// Point -> "Panvel, Maharashtra, India, Asia" for anywhere on Earth.
/// BigDataCloud's free client-side reverse geocoder first, OpenStreetMap Nominatim as back-up.
/// Results are cached per ~5 km box so moving the pointer does not flood the services.
class PlaceNameService {
  /// One shared instance, so every map in the app uses the same cache.
  static final PlaceNameService instance = PlaceNameService();
  final Map<String, String> _cache = {};
  DateTime _lastNominatim = DateTime.fromMillisecondsSinceEpoch(0);

  static String _key(double lat, double lon) => '${(lat * 20).round()}_${(lon * 20).round()}';

  String? cached(double lat, double lon) => _cache[_key(lat, lon)];

  Future<String> name(double lat, double lon, {String lang = 'en'}) async {
    final k = '${_key(lat, lon)}_$lang';
    final hit = _cache[k];
    if (hit != null) return hit;
    String? out;
    try {
      final uri = Uri.parse('https://api.bigdatacloud.net/data/reverse-geocode-client').replace(queryParameters: {
        'latitude': lat.toStringAsFixed(4),
        'longitude': lon.toStringAsFixed(4),
        'localityLanguage': lang,
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
        String s(String key) => '${j[key] ?? ''}'.trim();
        final parts = <String>[];
        void add(String v) {
          if (v.isNotEmpty && !parts.any((p) => p.toLowerCase() == v.toLowerCase())) parts.add(v);
        }

        add(s('city').isNotEmpty ? s('city') : s('locality'));
        add(s('principalSubdivision'));
        add(s('countryName'));
        add(s('continent'));
        if (parts.isNotEmpty) out = parts.join(', ');
      }
    } catch (_) {}
    if (out == null && DateTime.now().difference(_lastNominatim).inMilliseconds > 1100) {
      _lastNominatim = DateTime.now(); // Nominatim allows one request per second
      try {
        final uri = Uri.parse('https://nominatim.openstreetmap.org/reverse').replace(queryParameters: {
          'format': 'jsonv2',
          'lat': lat.toStringAsFixed(4),
          'lon': lon.toStringAsFixed(4),
          'zoom': '10',
          'accept-language': lang,
        });
        final res = await http.get(uri).timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
          final a = (j['address'] as Map?) ?? const {};
          final parts = <String>[
            for (final key in const ['city', 'town', 'village', 'county', 'state', 'country'])
              if ('${a[key] ?? ''}'.isNotEmpty) '${a[key]}'
          ];
          final seen = <String>{};
          final uniq = [for (final p in parts) if (seen.add(p.toLowerCase())) p];
          if (uniq.isNotEmpty) out = (uniq.length > 3 ? [uniq.first, ...uniq.sublist(uniq.length - 2)] : uniq).join(', ');
        }
      } catch (_) {}
    }
    out ??= '${lat.abs().toStringAsFixed(1)}°${lat >= 0 ? 'N' : 'S'}, ${lon.abs().toStringAsFixed(1)}°${lon >= 0 ? 'E' : 'W'}';
    _cache[k] = out;
    return out;
  }
}
