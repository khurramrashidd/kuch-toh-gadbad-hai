import 'package:flutter/foundation.dart' show kIsWeb;

/// Optional build-time override:  flutter build apk --dart-define=DATA_BASE_URL=https://<project>.web.app/data/
const String kDataBaseUrlOverride = String.fromEnvironment('DATA_BASE_URL');

const String kAppName = 'Kuch Toh Gadbad Hai';
const String kAppVersion = '1.8.1';
const String kTeamName = 'Xplorer';
const String kTeamMembers = 'Khurram Rashid (Team Lead), Kinza Zahra';
const String kLocalEvent = 'Panaji, Goa';

/// Team admin (may clear the shared caches). Must match firestore.rules.
const String kAdminEmail = 'khurramrashid0786@gmail.com';

/// Where the pipeline output (catalog.json, layers/, cases/ ...) lives.
/// Web: next to the app (Firebase Hosting serves web/data at /data/).
/// Android: the same Hosting site, found from the Firebase project id.
String resolveDataBaseUrl({String? firebaseProjectId}) {
  String slash(String s) => s.endsWith('/') ? s : '$s/';
  if (kDataBaseUrlOverride.isNotEmpty) return slash(kDataBaseUrlOverride);
  if (kIsWeb) return Uri.base.resolve('data/').toString();
  if (firebaseProjectId != null && firebaseProjectId.isNotEmpty) {
    return 'https://$firebaseProjectId.web.app/data/';
  }
  return '';
}
