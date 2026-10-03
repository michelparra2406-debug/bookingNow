import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../config.dart';
import '../../services/app_session.dart';
import '../../services/push_service.dart';
import '../../utils/friendly_errors.dart';
import '../../widgets/common.dart';
import '../business/business_shell.dart';
import '../business/onboarding_screen.dart';
import '../client/client_shell.dart';
import 'register_screen.dart';

/// Navegación común tras iniciar sesión: carga la sesión, registra push y
/// entra en el modo que corresponda. Si [wantsBusiness] y el usuario aún no
/// tiene negocio, abre el alta de negocio.
Future<void> afterLogin(BuildContext context, {bool wantsBusiness = false}) async {
  final session = AppSession.instance;
  await session.load();
  PushService.register();
  if (!context.mounted) return;
  final nav = Navigator.of(context);
  if (session.isBusinessMode) {
    nav.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const BusinessShell()), (_) => false);
    return;
  }
  nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ClientShell()), (_) => false);
  if (wantsBusiness && !session.hasBusinesses) {
    nav.push(MaterialPageRoute(builder: (_) => const OnboardingScreen()));
  }
}

/// Cabecera de marca compartida por las pantallas de acceso.
class AuthHeader extends StatelessWidget {
  final String? subtitle;
  const AuthHeader({super.key, this.subtitle});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(children: [
      Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: AppTheme.primary,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(Icons.event_available, color: Colors.white, size: 40),
      ),
      const SizedBox(height: 14),
      Text('BookingNow',
          style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      Text(subtitle ?? 'Reservas para cualquier servicio',
          style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.outline),
          textAlign: TextAlign.center),
    ]);
  }
}

/// Envuelve un formulario de acceso: en web (≥ 900 px) lo centra en una
/// tarjeta de 420 px; en móvil ocupa todo el ancho.
class AuthScaffold extends StatelessWidget {
  final Widget child;
  final String? title;
  const AuthScaffold({super.key, required this.child, this.title});
  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= AppConfig.desktopBreakpoint;
    final body = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: child,
    );
    return Scaffold(
      appBar: title == null ? null : AppBar(title: Text(title!)),
      body: SafeArea(
        child: wide
            ? Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: SizedBox(
                    width: 420,
                    child: Card(
                      child: Padding(
                          padding: const EdgeInsets.all(8), child: body),
                    ),
                  ),
                ),
              )
            : body,
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  bool _otpMode = false; // "Entrar con código por email"
  bool _otpSent = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    await _run(() async {
      await AppSession.instance.auth
          .signIn(email: _email.text.trim(), password: _password.text);
      if (!mounted) return;
      await afterLogin(context);
    });
  }

  Future<void> _forgot() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      showSnack(context, 'Escribe tu email para enviarte el enlace.');
      return;
    }
    await _run(() async {
      await AppSession.instance.auth.resetPassword(email);
      if (!mounted) return;
      showSnack(context, 'Te hemos enviado un email para restablecer la contraseña.');
    });
  }

  Future<void> _sendOtp() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      showSnack(context, 'Escribe un email válido.', error: true);
      return;
    }
    await _run(() async {
      await AppSession.instance.auth.signInWithOtp(email);
      if (!mounted) return;
      setState(() => _otpSent = true);
      showSnack(context, 'Código enviado a $email.');
    });
  }

  Future<void> _verifyOtp() async {
    final token = _code.text.trim();
    if (token.length != 6) {
      showSnack(context, 'El código tiene 6 dígitos.', error: true);
      return;
    }
    await _run(() async {
      await AppSession.instance.auth
          .verifyLoginOtp(email: _email.text.trim(), token: token);
      if (!mounted) return;
      await afterLogin(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return AuthScaffold(
      child: Form(
        key: _formKey,
        child: AutofillGroup(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SizedBox(height: 16),
            const AuthHeader(),
            const SizedBox(height: 32),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                  labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
              validator: (v) => (v == null || !v.contains('@'))
                  ? 'Introduce un email válido'
                  : null,
            ),
            const SizedBox(height: 14),
            if (!_otpMode) ...[
              TextFormField(
                controller: _password,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _busy ? null : _signIn(),
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Introduce tu contraseña' : null,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _busy ? null : _forgot,
                  child: const Text('¿Olvidaste la contraseña?'),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _busy ? null : _signIn,
                child: _busy
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Entrar'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _otpMode = true;
                          _otpSent = false;
                        }),
                icon: const Icon(Icons.pin_outlined),
                label: const Text('Entrar con código por email'),
              ),
            ] else ...[
              if (_otpSent) ...[
                TextFormField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: t.textTheme.headlineSmall?.copyWith(letterSpacing: 8),
                  autofillHints: const [AutofillHints.oneTimeCode],
                  decoration: const InputDecoration(
                      labelText: 'Código de 6 dígitos', counterText: ''),
                  onFieldSubmitted: (_) => _busy ? null : _verifyOtp(),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _busy ? null : _verifyOtp,
                  child: const Text('Verificar y entrar'),
                ),
                TextButton(
                  onPressed: _busy ? null : _sendOtp,
                  child: const Text('Reenviar código'),
                ),
              ] else ...[
                Text(
                  'Te enviaremos un código de 6 dígitos a tu email. Sin contraseña.',
                  style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _sendOtp,
                  icon: const Icon(Icons.send_outlined),
                  label: const Text('Enviar código'),
                ),
              ],
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy ? null : () => setState(() => _otpMode = false),
                child: const Text('Entrar con contraseña'),
              ),
            ],
            const SizedBox(height: 24),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('¿No tienes cuenta?', style: t.textTheme.bodyMedium),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const RegisterScreen())),
                child: const Text('Regístrate'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
