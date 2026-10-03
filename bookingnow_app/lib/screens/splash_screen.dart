import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../config.dart';
import '../l10n/gen/app_localizations.dart';
import '../services/app_session.dart';
import '../services/push_service.dart';
import '../widgets/app_logo.dart';
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
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.heroGradient),
        child: Stack(children: [
          const Positioned(
            right: -60,
            bottom: -60,
            child: Opacity(
              opacity: 0.10,
              child: BnLogoMark(size: 320, withBackground: false, dotColor: Colors.white),
            ),
          ),
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const BnLogoMark(size: 96, withBackground: false),
              const SizedBox(height: 22),
              Text.rich(
                const TextSpan(children: [
                  TextSpan(text: 'Booking'),
                  TextSpan(text: 'Now', style: TextStyle(color: AppTheme.primaryLight)),
                ]),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: -0.8),
              ),
              const SizedBox(height: 6),
              const Text('Reservas para cualquier servicio',
                  style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 36),
              const SizedBox(
                  width: 22, height: 22,
                  child: CircularProgressIndicator(color: Colors.white70, strokeWidth: 2)),
              if (!AppConfig.isConfigured) ...[
                const SizedBox(height: 32),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(l.notConfigured,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFFFDE68A), fontSize: 12)),
                ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}
