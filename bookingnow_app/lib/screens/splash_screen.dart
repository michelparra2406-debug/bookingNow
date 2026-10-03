import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../config.dart';
import '../l10n/gen/app_localizations.dart';
import '../services/app_session.dart';
import '../services/push_service.dart';
import 'auth/login_screen.dart';
import 'business/business_shell.dart';
import 'client/client_shell.dart';

/// Pantalla inicial: carga la sesión y decide a qué modo entrar.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final session = AppSession.instance;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await Future.delayed(const Duration(milliseconds: 400));
    try {
      await session.load();
    } catch (_) {}
    if (!mounted) return;
    if (!session.isLoggedIn) {
      _go(const LoginScreen());
      return;
    }
    PushService.register();
    _go(session.isBusinessMode ? const BusinessShell() : const ClientShell());
  }

  void _go(Widget w) => Navigator.of(context)
      .pushReplacement(MaterialPageRoute(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppTheme.ink,
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: AppTheme.primary,
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(Icons.event_available, color: Colors.white, size: 48),
          ),
          const SizedBox(height: 20),
          Text(l.appName,
              style: const TextStyle(
                  color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('Reservas para cualquier servicio',
              style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 32),
          const SizedBox(
              width: 24, height: 24,
              child: CircularProgressIndicator(color: Colors.white70, strokeWidth: 2)),
          if (!AppConfig.isConfigured) ...[
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(l.notConfigured,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.warning, fontSize: 12)),
            ),
          ],
        ]),
      ),
    );
  }
}
