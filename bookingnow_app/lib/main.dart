import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_theme.dart';
import 'config.dart';
import 'l10n/gen/app_localizations.dart';
import 'screens/splash_screen.dart';
import 'services/push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es');
  await initializeDateFormatting('en');
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseAnonKey,
  );
  await PushService.init();
  runApp(const BookingNowApp());
}

class BookingNowApp extends StatelessWidget {
  const BookingNowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('es'),
      home: const SplashScreen(),
    );
  }
}
