// Entrada de previsualización para depurar pantallas públicas sin iniciar
// sesión (solo datos de negocios publicados, legibles de forma anónima).
//
//   flutter run -d chrome -t lib/main_preview.dart \
//     --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... \
//     --dart-define=PREVIEW_BUSINESS_ID=<uuid>
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_theme.dart';
import 'config.dart';
import 'l10n/gen/app_localizations.dart';
import 'screens/client/business_detail_screen.dart';

const _previewBusinessId = String.fromEnvironment('PREVIEW_BUSINESS_ID');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es');
  await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabaseAnonKey);
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('es'),
    home: const BusinessDetailScreen(businessId: _previewBusinessId),
  ));
}
