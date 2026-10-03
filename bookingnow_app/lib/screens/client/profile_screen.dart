import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_theme.dart';
import '../../models/models.dart';
import '../../services/app_session.dart';
import '../../services/push_service.dart';
import '../../utils/format.dart';
import '../../utils/friendly_errors.dart';
import '../../widgets/common.dart';
import '../auth/login_screen.dart';
import 'booking_detail_screen.dart';
import 'client_shell.dart';

/// Perfil del cliente: datos, bonos, facturas, notificaciones y cuenta.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final session = AppSession.instance;
  List<CustomerPackage> _packages = [];
  List<Invoice> _invoices = [];
  List<AppNotification> _notifications = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    session.addListener(_onSession);
    _load();
  }

  @override
  void dispose() {
    session.removeListener(_onSession);
    super.dispose();
  }

  void _onSession() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait<dynamic>([
        session.data.fetchMyPackages().catchError((_) => <CustomerPackage>[]),
        session.data.fetchMyInvoices().catchError((_) => <Invoice>[]),
        session.data.fetchMyNotifications().catchError((_) => <AppNotification>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _packages = results[0] as List<CustomerPackage>;
        _invoices = results[1] as List<Invoice>;
        _notifications = results[2] as List<AppNotification>;
      });
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------- Acciones ----------

  Future<void> _editProfile() async {
    final p = session.profile;
    final name = TextEditingController(text: p?.fullName ?? '');
    final phone = TextEditingController(text: p?.phone ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Editar datos'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nombre completo'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Teléfono', hintText: '+34…'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Guardar')),
        ],
      ),
    );
    final newName = name.text.trim();
    final newPhone = phone.text.trim();
    name.dispose();
    phone.dispose();
    if (ok != true || !mounted) return;
    if (newName.length < 2) {
      showSnack(context, 'El nombre es obligatorio.', error: true);
      return;
    }
    try {
      final phoneChanged = newPhone != (p?.phone ?? '');
      await session.auth.updateMyProfile({
        'full_name': newName,
        'phone': newPhone.isEmpty ? null : newPhone,
        if (phoneChanged) 'phone_verified': false,
      });
      await session.load();
      if (mounted) showSnack(context, 'Datos guardados.');
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _verifyPhone() async {
    final p = session.profile;
    final phoneCtrl = TextEditingController(text: p?.phone ?? '');
    final codeCtrl = TextEditingController();
    var sent = false;
    var busy = false;
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Verificar teléfono'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: phoneCtrl,
              enabled: !sent,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                  labelText: 'Teléfono (formato internacional)', hintText: '+34612345678'),
            ),
            if (sent) ...[
              const SizedBox(height: 12),
              TextField(
                controller: codeCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                autofocus: true,
                textAlign: TextAlign.center,
                autofillHints: const [AutofillHints.oneTimeCode],
                decoration: const InputDecoration(labelText: 'Código SMS', counterText: ''),
              ),
            ] else ...[
              const SizedBox(height: 8),
              const Text('Te enviaremos un código por SMS.', style: TextStyle(fontSize: 12)),
            ],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cerrar')),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      final phone = phoneCtrl.text.trim();
                      if (!RegExp(r'^\+[1-9]\d{6,14}$').hasMatch(phone)) {
                        showSnack(c, 'Usa el formato internacional: +34612345678', error: true);
                        return;
                      }
                      setD(() => busy = true);
                      try {
                        if (!sent) {
                          await session.auth.sendPhoneOtp(phone);
                          setD(() => sent = true);
                        } else {
                          await session.auth
                              .verifyPhoneOtp(phoneE164: phone, token: codeCtrl.text.trim());
                          await session.load();
                          if (c.mounted) Navigator.pop(c);
                          if (mounted) showSnack(context, 'Teléfono verificado.');
                        }
                      } catch (e) {
                        if (c.mounted) showSnack(c, friendlyError(e), error: true);
                      } finally {
                        if (c.mounted) setD(() => busy = false);
                      }
                    },
              child: Text(sent ? 'Verificar' : 'Enviar código'),
            ),
          ],
        ),
      ),
    );
    phoneCtrl.dispose();
    codeCtrl.dispose();
  }

  Future<void> _signOut() async {
    final ok = await confirmDialog(context,
        title: 'Cerrar sesión', message: '¿Quieres salir de tu cuenta?', confirmLabel: 'Salir');
    if (!ok) return;
    try {
      await PushService.unregister();
      await session.signOut();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  Future<void> _openInvoice(Invoice inv) async {
    final url = inv.pdfUrl;
    if (url == null || url.isEmpty) {
      showSnack(context, 'Esta factura aún no tiene PDF disponible.');
      return;
    }
    try {
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok && mounted) showSnack(context, 'No se pudo abrir la factura.', error: true);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _openNotification(AppNotification n) async {
    if (n.status != 'read') {
      try {
        await session.data.markNotificationRead(n.id);
        if (mounted) {
          setState(() {
            final i = _notifications.indexWhere((x) => x.id == n.id);
            if (i >= 0) {
              _notifications[i] = AppNotification(
                  id: n.id,
                  channel: n.channel,
                  template: n.template,
                  payload: n.payload,
                  status: 'read',
                  bookingId: n.bookingId,
                  createdAt: n.createdAt);
            }
          });
        }
      } catch (_) {}
    }
    if (n.bookingId != null && mounted) {
      Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => BookingDetailScreen(bookingId: n.bookingId!)));
    }
  }

  // ---------- UI ----------

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = session.profile;
    final name = p?.fullName.isNotEmpty == true
        ? p!.fullName
        : (session.auth.currentUser?.email ?? 'Tu cuenta');
    final email = p?.email ?? session.auth.currentUser?.email ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: MaxWidth(
        maxWidth: 760,
        child: RefreshIndicator(
          onRefresh: () async {
            await session.load();
            await _load();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              // ----- Cabecera de perfil
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      AvatarCircle(url: p?.avatarUrl, initials: _initials(name), radius: 28),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(name,
                              style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                          if (email.isNotEmpty)
                            Text(email,
                                style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
                        ]),
                      ),
                      IconButton(
                        tooltip: 'Editar datos',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: _editProfile,
                      ),
                    ]),
                    const SizedBox(height: 12),
                    Row(children: [
                      Icon(Icons.phone_outlined, size: 18, color: t.colorScheme.outline),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          (p?.phone ?? '').isEmpty ? 'Sin teléfono' : p!.phone!,
                          style: t.textTheme.bodyMedium,
                        ),
                      ),
                      if (p?.phoneVerified == true)
                        Row(children: [
                          const Icon(Icons.verified, size: 18, color: AppTheme.accent),
                          const SizedBox(width: 4),
                          Text('Verificado',
                              style: t.textTheme.labelMedium?.copyWith(color: AppTheme.accent)),
                        ])
                      else
                        TextButton(onPressed: _verifyPhone, child: const Text('Verificar')),
                    ]),
                  ]),
                ),
              ),
              const SizedBox(height: 12),

              // ----- Modo negocio
              Card(
                color: AppTheme.ink,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            color: AppTheme.primary, borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.storefront, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          session.hasBusinesses ? 'Gestiona tu negocio' : '¿Tienes un negocio?',
                          style: t.textTheme.titleMedium
                              ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Text(
                      session.hasBusinesses
                          ? 'Agenda, clientes, facturación y mucho más desde el modo negocio.'
                          : 'Agenda online, recordatorios automáticos, clientes y facturación Verifactu. Gratis para empezar.',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
                      onPressed: () => goToBusinessMode(context),
                      icon: Icon(session.hasBusinesses ? Icons.swap_horiz : Icons.add_business_outlined),
                      label: Text(session.hasBusinesses ? 'Modo negocio' : 'Crear mi negocio'),
                    ),
                  ]),
                ),
              ),

              if (_loading && _packages.isEmpty && _invoices.isEmpty && _notifications.isEmpty)
                const Padding(padding: EdgeInsets.all(24), child: LoadingView()),

              // ----- Bonos
              const SectionTitle('Mis bonos'),
              if (_packages.isEmpty)
                _emptyRow(t, Icons.confirmation_num_outlined, 'No tienes bonos activos')
              else
                for (final cp in _packages) _packageCard(t, cp),

              // ----- Facturas
              const SectionTitle('Mis facturas'),
              if (_invoices.isEmpty)
                _emptyRow(t, Icons.receipt_long_outlined, 'Todavía no tienes facturas')
              else
                Card(
                  child: Column(children: [
                    for (var i = 0; i < _invoices.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        leading: Icon(Icons.receipt_long_outlined, color: t.colorScheme.primary),
                        title: Text(_invoices[i].fullNumber,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(Fmt.date(_invoices[i].issueDate)),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(formatEuros(_invoices[i].totalCents),
                              style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                          if ((_invoices[i].pdfUrl ?? '').isNotEmpty) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.picture_as_pdf_outlined, size: 18),
                          ],
                        ]),
                        onTap: () => _openInvoice(_invoices[i]),
                      ),
                    ],
                  ]),
                ),

              // ----- Notificaciones
              const SectionTitle('Notificaciones'),
              if (_notifications.isEmpty)
                _emptyRow(t, Icons.notifications_none, 'Sin notificaciones')
              else
                Card(
                  child: Column(children: [
                    for (var i = 0; i < _notifications.length && i < 20; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      _notificationTile(t, _notifications[i]),
                    ],
                  ]),
                ),

              // ----- Cuenta
              const SectionTitle('Cuenta'),
              Card(
                child: Column(children: [
                  const ListTile(
                    leading: Icon(Icons.language),
                    title: Text('Idioma'),
                    subtitle: Text('Español (España). Pronto más idiomas.'),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.logout, color: AppTheme.danger),
                    title: const Text('Cerrar sesión', style: TextStyle(color: AppTheme.danger)),
                    onTap: _signOut,
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              Text(
                'Eliminar cuenta (RGPD): puedes solicitar la eliminación de tu cuenta y de todos tus datos escribiendo a privacidad@bookingnow.app desde tu email. Atenderemos la solicitud en un plazo máximo de 30 días.',
                style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyRow(ThemeData t, IconData icon, String text) => Card(
        child: ListTile(
          leading: Icon(icon, color: t.colorScheme.outline),
          title: Text(text, style: TextStyle(color: t.colorScheme.outline)),
        ),
      );

  Widget _packageCard(ThemeData t, CustomerPackage cp) {
    final active = cp.status == 'active';
    final String usage;
    if (cp.sessionsTotal != null) {
      usage = '${cp.sessionsUsed}/${cp.sessionsTotal} sesiones usadas';
    } else if (cp.balanceCents != null) {
      usage = 'Saldo: ${formatEuros(cp.balanceCents!)}';
    } else {
      usage = 'Sin límite de sesiones';
    }
    final progress = cp.sessionsTotal == null || cp.sessionsTotal == 0
        ? null
        : (cp.sessionsUsed / cp.sessionsTotal!).clamp(0.0, 1.0);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(cp.packageName ?? 'Bono',
                  style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: (active ? AppTheme.accent : Colors.grey).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(
                active ? 'Activo' : (cp.status == 'exhausted' ? 'Agotado' : 'Caducado'),
                style: TextStyle(
                    color: active ? AppTheme.accent : Colors.grey,
                    fontWeight: FontWeight.w700,
                    fontSize: 12),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text(usage, style: t.textTheme.bodyMedium),
          if (progress != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: progress, minHeight: 6),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            [
              'Código ${cp.code}',
              if (cp.validUntil != null) 'válido hasta ${Fmt.date(cp.validUntil!)}',
            ].join(' · '),
            style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline),
          ),
        ]),
      ),
    );
  }

  Widget _notificationTile(ThemeData t, AppNotification n) {
    final title = (n.payload['title'] ?? _templateLabel(n.template)).toString();
    final body = (n.payload['body'] ?? '').toString();
    final unread = n.status != 'read';
    return ListTile(
      leading: Icon(
        unread ? Icons.notifications_active : Icons.notifications_none,
        color: unread ? t.colorScheme.primary : t.colorScheme.outline,
      ),
      title: Text(title,
          style: TextStyle(fontWeight: unread ? FontWeight.w700 : FontWeight.w500)),
      subtitle: Text(
        [if (body.isNotEmpty) body, Fmt.dateTime(n.createdAt)].join('\n'),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: body.isNotEmpty,
      trailing: n.bookingId != null ? const Icon(Icons.chevron_right) : null,
      onTap: () => _openNotification(n),
    );
  }

  String _templateLabel(String template) {
    switch (template) {
      case 'booking_confirmed':
        return 'Cita confirmada';
      case 'booking_reminder':
        return 'Recordatorio de cita';
      case 'booking_cancelled':
        return 'Cita cancelada';
      case 'booking_rescheduled':
        return 'Cita cambiada de hora';
      case 'waitlist_slot':
        return 'Se ha liberado un hueco';
      case 'review_request':
        return 'Valora tu cita';
      default:
        return template.replaceAll('_', ' ');
    }
  }
}
