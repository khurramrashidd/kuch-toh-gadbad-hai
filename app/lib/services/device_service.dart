import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class LocationFailure implements Exception {
  LocationFailure(this.key);
  final String key; // string key for the UI ('gps_off' / 'gps_denied')
}

class DeviceService {
  Future<(double, double)> currentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) throw LocationFailure('gps_off');
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) throw LocationFailure('gps_denied');
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 20)),
    );
    return (pos.latitude, pos.longitude);
  }

  Future<void> openUrl(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> shareWhatsApp(String text) => openUrl('https://wa.me/?text=${Uri.encodeComponent(text)}');

  Future<String?> loadLang() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getString('lang');
    } catch (_) {
      return null;
    }
  }

  Future<bool> loadDark() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getBool('dark') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> saveDark(bool dark) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('dark', dark);
    } catch (_) {}
  }

  Future<void> saveLang(String lang) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('lang', lang);
    } catch (_) {}
  }

  Future<bool> loadBool(String key) async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getBool(key) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> saveBool(String key, bool v) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(key, v);
    } catch (_) {}
  }

  Future<String?> loadString(String key) async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getString(key);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveString(String key, String v) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(key, v);
    } catch (_) {}
  }
}
