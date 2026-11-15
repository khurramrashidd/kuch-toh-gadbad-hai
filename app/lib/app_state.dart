import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'l10n/strings.dart';
import 'models/models.dart';
import 'services/ai_service.dart';
import 'services/data_service.dart';
import 'services/device_service.dart';
import 'services/power_service.dart';
import 'services/weather_service.dart';

/// Land outline + city list bundled in assets/geo (Natural Earth, public domain).
class WorldAssets {
  WorldAssets(this.rings, this.cities);
  final List<List<List<double>>> rings; // [ring][point][lon, lat]
  final List<City> cities;

  static Future<WorldAssets> load() async {
    final land = jsonDecode(await rootBundle.loadString('assets/geo/land_110m.json')) as Map;
    final rings = <List<List<double>>>[];
    for (final r in land['rings'] as List) {
      rings.add([for (final p in r as List) [((p as List)[0] as num).toDouble(), (p[1] as num).toDouble()]]);
    }
    final cj = jsonDecode(await rootBundle.loadString('assets/geo/cities.json')) as Map;
    final cities = <City>[];
    for (final c in cj['cities'] as List) {
      final l = c as List;
      cities.add(City('${l[0]}', '${l[1]}', (l[2] as num).toDouble(), (l[3] as num).toDouble(), (l[4] as num).toInt()));
    }
    return WorldAssets(rings, cities);
  }
}

class City {
  City(this.name, this.country, this.lat, this.lon, this.pop);
  final String name, country;
  final double lat, lon;
  final int pop;
}

class AppState extends ChangeNotifier {
  AppState({required this.firebaseReady, required this.dataBaseUrl});
  final bool firebaseReady;
  final String dataBaseUrl;
  final DeviceService device = DeviceService();
  late final PowerService power = PowerService(device: device, firebaseReady: firebaseReady);
  late final DataService data = DataService(dataBaseUrl);
  AiService ai = AiService(firebaseReady: false, models: const []);

  /// Link to the Android APK, set by the team admin in the Lab tab (Firestore settings/app).
  String apkUrl = '';

  /// Link to the 30-second demo video, set by the admin; shows a menu entry and a floating banner.
  String demoUrl = '';
  bool recapDismissed = false;
  void dismissRecap() {
    recapDismissed = true;
    notifyListeners();
  }

  Future<void> loadSettings() async {
    if (!firebaseReady) return;
    try {
      final snap = await FirebaseFirestore.instance.collection('settings').doc('app').get().timeout(const Duration(seconds: 8));
      final v = snap.data()?['apkUrl'], d = snap.data()?['demoUrl'];
      final next = v is String ? v : '', nextDemo = d is String ? d : '';
      if (next != apkUrl || nextDemo != demoUrl) {
        apkUrl = next;
        demoUrl = nextDemo;
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Turns a Google Drive "view" link into a direct download link; other links are kept as they are.
  static String directLink(String url) {
    final u = url.trim();
    final m = RegExp(r'drive\.google\.com/file/d/([^/]+)').firstMatch(u) ?? RegExp(r'drive\.google\.com/open\?id=([^&]+)').firstMatch(u);
    return m == null ? u : 'https://drive.google.com/uc?export=download&id=${m.group(1)}';
  }

  Future<void> saveApkUrl(String url) async {
    final clean = directLink(url);
    await FirebaseFirestore.instance.collection('settings').doc('app').set({'apkUrl': clean, 'updated': DateTime.now().toUtc().toIso8601String()}, SetOptions(merge: true));
    apkUrl = clean;
    notifyListeners();
  }

  Future<void> saveDemoUrl(String url) async {
    final clean = url.trim();
    await FirebaseFirestore.instance.collection('settings').doc('app').set({'demoUrl': clean, 'updated': DateTime.now().toUtc().toIso8601String()}, SetOptions(merge: true));
    demoUrl = clean;
    recapDismissed = false;
    notifyListeners();
  }

  String lang = 'en';
  bool dark = false; // light mode by default
  bool expert = false; // Simple mode first; Scientist mode shows every number
  int tab = 0;
  ExploreRequest? exploreRequest; // set by the guided investigation, consumed by the Explore tab

  // ---- here and now (header / sidebar strip)
  final WeatherService weatherService = WeatherService();
  (double, double)? here; // lat, lon of the device
  String? hereName;
  WeatherNow? weather;
  bool locating = false;
  String? locateError; // string key
  DateTime now = DateTime.now();
  Timer? _clock;
  Catalog? catalog;
  WorldAssets? world;
  String? error;
  bool loading = true;
  int dataVersion = 0; // bumps when new pipeline output is loaded; screens rebuild on it
  bool live = false; // poll the catalog and reload when the pipeline publishes
  Timer? _liveTimer;
  final GlobalKey<ScaffoldMessengerState> messenger = GlobalKey<ScaffoldMessengerState>();

  String t(String key) => tr(lang, key);

  Future<void> init() async {
    lang = await device.loadLang() ?? 'en';
    dark = await device.loadDark();
    expert = await device.loadBool('expert');
    await load();
    if (kDebugMode || (kIsWeb && Uri.base.queryParameters['live'] == '1')) setLive(true);
    _clock = Timer.periodic(const Duration(seconds: 20), (_) {
      final t = DateTime.now();
      if (t.minute != now.minute) {
        now = t;
        notifyListeners();
      }
    });
    locate(); // asks for location once; the app works without it
  }

  /// Find the device, name the nearest city and fetch the current weather.
  Future<(double, double)?> locate() async {
    if (locating) return here;
    locating = true;
    locateError = null;
    notifyListeners();
    try {
      final ll = await device.currentLocation();
      here = ll;
      hereName = nearestCity(ll.$1, ll.$2);
      notifyListeners();
      weather = await weatherService.now(ll.$1, ll.$2);
    } on LocationFailure catch (e) {
      locateError = e.key;
    } catch (_) {
      locateError = 'gps_off';
    }
    locating = false;
    notifyListeners();
    return here;
  }

  String? nearestCity(double lat, double lon) {
    final cities = world?.cities;
    if (cities == null || cities.isEmpty) return null;
    City? best;
    var bd = double.infinity;
    for (final c in cities) {
      final dx = ((c.lon - lon + 540) % 360 - 180) * 0.9, dy = c.lat - lat;
      final d = dx * dx + dy * dy;
      if (d < bd) {
        bd = d;
        best = c;
      }
    }
    return best == null || bd > 9 ? null : best.name; // within about 3 degrees
  }

  /// Fetch everything again (after a pipeline run).
  Future<void> reload() async {
    data.clear();
    await load();
  }

  void setLive(bool on) {
    live = on;
    _liveTimer?.cancel();
    _liveTimer = on ? Timer.periodic(const Duration(seconds: 12), (_) => _poll()) : null;
    notifyListeners();
  }

  Future<void> _poll() async {
    if (loading || dataBaseUrl.isEmpty) return;
    try {
      final g = await data.peekGeneratedAt();
      if (g == null || g == catalog?.generatedAt) return;
      await reload();
      messenger.currentState?.showSnackBar(SnackBar(content: Text('${t('data_updated')} $g'), duration: const Duration(seconds: 3)));
    } catch (_) {
      // server busy or offline: try again next tick
    }
  }

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      world ??= await WorldAssets.load();
      if (dataBaseUrl.isEmpty) {
        throw DataException('No data URL: configure Firebase (run: flutterfire configure) or build with --dart-define=DATA_BASE_URL=...');
      }
      final before = catalog?.generatedAt;
      catalog = await data.catalog(fresh: true);
      if (catalog!.generatedAt != before) dataVersion++;
      ai = AiService(firebaseReady: firebaseReady, models: catalog!.aiModels);
      unawaited(loadSettings());
    } catch (e) {
      error = '$e';
    }
    loading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _clock?.cancel();
    _liveTimer?.cancel();
    super.dispose();
  }

  void toggleLang() {
    lang = lang == 'en' ? 'hi' : 'en';
    device.saveLang(lang);
    notifyListeners();
  }

  void toggleExpert() {
    expert = !expert;
    device.saveBool('expert', expert);
    notifyListeners();
  }

  void goTab(int i) {
    tab = i;
    notifyListeners();
  }

  /// Open the Explore tab on a dataset / season / region.
  void explore({String? dataset, String? season, List<double>? bbox, String? regionName}) {
    exploreRequest = ExploreRequest(dataset: dataset, season: season, bbox: bbox, regionName: regionName);
    tab = 3;
    notifyListeners();
  }

  void toggleTheme() {
    dark = !dark;
    device.saveDark(dark);
    notifyListeners();
  }
}

class ExploreRequest {
  ExploreRequest({this.dataset, this.season, this.bbox, this.regionName});
  final String? dataset, season, regionName;
  final List<double>? bbox; // west, south, east, north
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope missing');
    return scope!.notifier!;
  }

  static AppState read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    return scope!.notifier!;
  }
}

extension AppContext on BuildContext {
  AppState get app => AppScope.of(this);
  String get lang => AppScope.of(this).lang;
  String t(String key) => tr(AppScope.of(this).lang, key);
}
