import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Current weather at a point from Open-Meteo (free, no key). Used only for the
/// "here and now" strip - never for any trend verdict.
class WeatherNow {
  WeatherNow(this.tempC, this.humidity, this.wind, this.code, this.isDay);
  final double tempC, wind;
  final int humidity, code;
  final bool isDay;

  IconData get icon {
    if (code == 0) return isDay ? Icons.wb_sunny : Icons.nightlight_round;
    if (code <= 2) return isDay ? Icons.wb_cloudy_outlined : Icons.nights_stay_outlined;
    if (code == 3) return Icons.cloud;
    if (code == 45 || code == 48) return Icons.foggy;
    if (code >= 51 && code <= 67) return Icons.grain;
    if (code >= 71 && code <= 77) return Icons.ac_unit;
    if (code >= 80 && code <= 82) return Icons.water_drop;
    if (code >= 95) return Icons.thunderstorm;
    return Icons.cloud_queue;
  }

  (String, String) get words {
    if (code == 0) return ('Clear', 'साफ़');
    if (code <= 2) return ('Partly cloudy', 'आंशिक बादल');
    if (code == 3) return ('Cloudy', 'बादल');
    if (code == 45 || code == 48) return ('Fog', 'कोहरा');
    if (code >= 51 && code <= 57) return ('Drizzle', 'फुहार');
    if (code >= 61 && code <= 67) return ('Rain', 'बारिश');
    if (code >= 71 && code <= 77) return ('Snow', 'बर्फ़बारी');
    if (code >= 80 && code <= 82) return ('Showers', 'बौछारें');
    if (code >= 95) return ('Thunderstorm', 'आँधी-तूफ़ान');
    return ('Cloudy', 'बादल');
  }
}

class WeatherService {
  Future<WeatherNow?> now(double lat, double lon) async {
    try {
      final uri = Uri.parse('https://api.open-meteo.com/v1/forecast').replace(queryParameters: {
        'latitude': lat.toStringAsFixed(3),
        'longitude': lon.toStringAsFixed(3),
        'current': 'temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m,is_day',
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final c = (jsonDecode(utf8.decode(res.bodyBytes)) as Map)['current'] as Map;
      return WeatherNow((c['temperature_2m'] as num).toDouble(), (c['relative_humidity_2m'] as num).round(), (c['wind_speed_10m'] as num).toDouble(),
          (c['weather_code'] as num).toInt(), (c['is_day'] as num?) != 0);
    } catch (_) {
      return null;
    }
  }
}
