import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_state.dart';
import 'env.dart';
import 'lan_sync_host.dart';
import 'pages/home_page.dart';
import 'pages/login_page.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AirportApp());
}

class AirportApp extends StatefulWidget {
  const AirportApp({super.key});

  @override
  State<AirportApp> createState() => _AirportAppState();
}

class _AirportAppState extends State<AirportApp> with WidgetsBindingObserver {
  final AppState _state = AppState();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _state.init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _state.dispose();
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: _state,
      child: AnimatedBuilder(
        animation: Listenable.merge([_state.appLocale, _state.themeMode]),
        builder: (context, _) {
          final mode = resolveThemeMode(
            _state.themeMode.value,
            WidgetsBinding.instance.platformDispatcher.platformBrightness,
          );
          AppColors.dark = mode == ThemeMode.dark;
          return MaterialApp(
            title: 'ClashNova',
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(Brightness.light),
            darkTheme: buildAppTheme(Brightness.dark),
            themeMode: mode,
            locale: _state.appLocale.value,
            supportedLocales: const [
              Locale('en'),
              Locale('zh'),
              Locale('ja'),
              Locale('ko'),
              Locale('de'),
              Locale('fr'),
              Locale('ru'),
            ],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            // The palette is applied above, from the same mode as themeMode, so a
            // page rebuild cannot paint dark cards on a light background.
            home: const RootShell(),
          );
        },
      ),
    );
  }
}

/// Chooses the entry surface: the login screen until the user signs in or
/// enters local mode, then the single-page home with its menu list.
class RootShell extends StatelessWidget {
  const RootShell({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (AppEnv.enableLogin && !state.loggedIn && !state.localMode) {
      return const LoginPage();
    }
    // 包一层全局「拉取同步」确认宿主，任意页面都能收到并弹确认。
    return const LanSyncHost(child: HomePage());
  }
}
