import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'config.dart';
import 'firebase_options.dart';
import 'screens/shell.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var firebaseReady = false;
  String? projectId;
  try {
    final app = await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    firebaseReady = true;
    projectId = app.options.projectId;
  } catch (_) {
    // Not configured yet (see lib/firebase_options.dart) - the app still works without Firebase.
  }
  final state = AppState(firebaseReady: firebaseReady, dataBaseUrl: resolveDataBaseUrl(firebaseProjectId: projectId));
  runApp(KtghApp(state: state));
  state.init();
}

final ThemeData _lightTheme = buildTheme(Palette.light);
final ThemeData _darkTheme = buildTheme(Palette.darkPalette);

class KtghApp extends StatelessWidget {
  const KtghApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) => MaterialApp(
          title: kAppName,
          scaffoldMessengerKey: state.messenger,
          debugShowCheckedModeBanner: false,
          theme: _lightTheme,
          darkTheme: _darkTheme,
          themeMode: state.dark ? ThemeMode.dark : ThemeMode.light, // light by default, dark on toggle
          home: const Shell(),
        ),
      ),
    );
  }
}
