import 'package:flutter/material.dart';

import '../../services/app_session.dart';
import '../../utils/friendly_errors.dart';
import '../../widgets/common.dart';
import 'email_verify_screen.dart';
import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  bool _acceptPrivacy = false;
  bool _wantsBusiness = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_acceptPrivacy) {
      showSnack(context, 'Debes aceptar la política de privacidad.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final phone = _phone.text.trim();
      final email = _email.text.trim();
      final hasSession = await AppSession.instance.auth.signUp(
        email: email,
        password: _password.text,
        fullName: _name.text.trim(),
        phone: phone.isEmpty ? null : phone,
      );
      if (!mounted) return;
      if (!hasSession) {
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) =>
                EmailVerifyScreen(email: email, wantsBusiness: _wantsBusiness)));
        return;
      }
      await afterLogin(context, wantsBusiness: _wantsBusiness);
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
      title: 'Crear cuenta',
      child: Form(
        key: _formKey,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const AuthHeader(subtitle: 'Crea tu cuenta en un minuto'),
          const SizedBox(height: 28),
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.name],
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
                labelText: 'Nombre completo', prefixIcon: Icon(Icons.person_outline)),
            validator: (v) =>
                (v == null || v.trim().length < 2) ? 'Introduce tu nombre' : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
                labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
            validator: (v) =>
                (v == null || !v.contains('@')) ? 'Introduce un email válido' : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
                labelText: 'Teléfono (opcional)',
                hintText: '+34…',
                prefixIcon: Icon(Icons.phone_outlined)),
            validator: (v) {
              final s = (v ?? '').trim();
              if (s.isEmpty) return null;
              return RegExp(r'^\+[1-9]\d{6,14}$').hasMatch(s)
                  ? null
                  : 'Formato internacional: +34612345678';
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _password,
            obscureText: _obscure,
            autofillHints: const [AutofillHints.newPassword],
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _busy ? null : _submit(),
            decoration: InputDecoration(
              labelText: 'Contraseña',
              helperText: 'Mínimo 6 caracteres',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            validator: (v) =>
                (v == null || v.length < 6) ? 'Mínimo 6 caracteres' : null,
          ),
          const SizedBox(height: 10),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _wantsBusiness,
            onChanged: (v) => setState(() => _wantsBusiness = v),
            title: const Text('Quiero gestionar mi negocio'),
            subtitle: const Text('Agenda, clientes, facturación y reservas online'),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _acceptPrivacy,
            onChanged: (v) => setState(() => _acceptPrivacy = v ?? false),
            title: Text(
              'He leído y acepto la política de privacidad y el tratamiento de mis datos (RGPD).',
              style: t.textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Crear cuenta'),
          ),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('¿Ya tienes cuenta?', style: t.textTheme.bodyMedium),
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: const Text('Inicia sesión'),
            ),
          ]),
        ]),
      ),
    );
  }
}
