import 'package:flutter/material.dart';

import '../../services/app_session.dart';
import '../../utils/friendly_errors.dart';
import '../../widgets/common.dart';
import 'login_screen.dart';

/// Verificación del email tras el registro mediante código de 6 dígitos.
class EmailVerifyScreen extends StatefulWidget {
  final String email;
  final bool wantsBusiness;
  const EmailVerifyScreen(
      {super.key, required this.email, this.wantsBusiness = false});
  @override
  State<EmailVerifyScreen> createState() => _EmailVerifyScreenState();
}

class _EmailVerifyScreenState extends State<EmailVerifyScreen> {
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final token = _code.text.trim();
    if (token.length != 6) {
      showSnack(context, 'El código tiene 6 dígitos.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await AppSession.instance.auth
          .verifyEmailCode(email: widget.email, token: token);
      if (!mounted) return;
      await afterLogin(context, wantsBusiness: widget.wantsBusiness);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _busy = true);
    try {
      await AppSession.instance.auth.resendEmailCode(widget.email);
      if (mounted) showSnack(context, 'Código reenviado a ${widget.email}.');
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return AuthScaffold(
      title: 'Verifica tu email',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 8),
        Icon(Icons.mark_email_read_outlined, size: 64, color: t.colorScheme.primary),
        const SizedBox(height: 16),
        Text('Revisa tu bandeja de entrada',
            textAlign: TextAlign.center,
            style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(
          'Hemos enviado un código de 6 dígitos a\n${widget.email}',
          textAlign: TextAlign.center,
          style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.outline),
        ),
        const SizedBox(height: 28),
        TextField(
          controller: _code,
          keyboardType: TextInputType.number,
          maxLength: 6,
          autofocus: true,
          textAlign: TextAlign.center,
          style: t.textTheme.headlineSmall?.copyWith(letterSpacing: 8),
          autofillHints: const [AutofillHints.oneTimeCode],
          decoration: const InputDecoration(labelText: 'Código', counterText: ''),
          onSubmitted: (_) => _busy ? null : _verify(),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _verify,
          child: _busy
              ? const SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Verificar'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : _resend,
          child: const Text('Reenviar código'),
        ),
        const SizedBox(height: 8),
        Text(
          'Si no lo encuentras, mira en la carpeta de spam.',
          textAlign: TextAlign.center,
          style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline),
        ),
      ]),
    );
  }
}
