import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_theme.dart';
import '../../models/models.dart';
import '../../services/agenda_extra.dart';
import '../../services/app_session.dart';
import '../../utils/format.dart';
import '../../utils/friendly_errors.dart';
import '../../widgets/common.dart';
import 'booking_sheet.dart';
import 'new_booking_sheet.dart';

/// Ficha completa de un cliente: contacto, datos, bonos e historial.
class CustomerDetailScreen extends StatefulWidget {
  final String customerId;
  const CustomerDetailScreen({super.key, required this.customerId});
  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  final session = AppSession.instance;
  String get _bizId => session.activeBusiness!.id;

  Customer? _c;
  List<CustomerPackage> _packages = [];
  List<Booking> _bookings = [];
  DateTime? _gdpr;
  bool _loading = true;
  String? _error;
  bool _busy = false;
  bool _dirty = false;

  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _taxId = TextEditingController();
  final _address = TextEditingController();
  final _notes = TextEditingController();
  final _tagCtrl = TextEditingController();
  DateTime? _birthdate;
  List<String> _tags = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _taxId, _address, _notes, _tagCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([
        session.biz.fetchCustomer(widget.customerId),
        session.biz.fetchCustomerPackages(widget.customerId),
        session.biz.fetchCustomerBookings(widget.customerId),
        session.biz.fetchGdprConsent(widget.customerId),
      ]);
      if (!mounted) return;
      final c = r[0] as Customer?;
      setState(() {
        _c = c;
        _packages = r[1] as List<CustomerPackage>;
        _bookings = r[2] as List<Booking>;
        _gdpr = r[3] as DateTime?;
        _loading = false;
        _error = c == null ? 'El cliente no existe.' : null;
        if (c != null && !_dirty) _fill(c);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyError(e);
      });
    }
  }

  void _fill(Customer c) {
    _name.text = c.fullName;
    _email.text = c.email ?? '';
    _phone.text = c.phone ?? '';
    _taxId.text = c.taxId ?? '';
    _address.text = c.address ?? '';
    _notes.text = c.notes ?? '';
    _birthdate = c.birthdate;
    _tags = List.of(c.tags);
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  String? _nn(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      showSnack(context, 'El nombre es obligatorio', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await session.biz.upsertCustomer({
        'id': _c!.id,
        'business_id': _bizId,
        'full_name': _name.text.trim(),
        'email': _nn(_email),
        'phone': _nn(_phone),
        'tax_id': _nn(_taxId)?.toUpperCase(),
        'address': _nn(_address),
        'notes': _nn(_notes),
        'birthdate': _birthdate == null
            ? null
            : '${_birthdate!.year.toString().padLeft(4, '0')}-${_birthdate!.month.toString().padLeft(2, '0')}-${_birthdate!.day.toString().padLeft(2, '0')}',
        'tags': _tags,
      });
      if (!mounted) return;
      setState(() => _dirty = false);
      showSnack(context, 'Ficha guardada');
      await _load();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _patch(Map<String, dynamic> fields, {String? ok}) async {
    setState(() => _busy = true);
    try {
      await session.biz.patchCustomer(_c!.id, fields);
      if (!mounted) return;
      if (ok != null) showSnack(context, ok);
      await _load();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setGdpr(bool grant) async {
    setState(() => _busy = true);
    try {
      await session.biz.setGdprConsent(_c!.id, grant ? DateTime.now() : null);
      if (!mounted) return;
      showSnack(context, grant ? 'Consentimiento registrado' : 'Consentimiento retirado');
      await _load();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _launch(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      showSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _pickBirthdate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _birthdate ?? DateTime(1990),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (d == null || !mounted) return;
    setState(() {
      _birthdate = d;
      _dirty = true;
    });
  }

  Future<void> _sellPackage() async {
    List<Package> pkgs;
    try {
      pkgs = (await session.biz.fetchPackages(_bizId)).where((p) => p.active).toList();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, friendlyError(e), error: true);
      return;
    }
    if (!mounted) return;
    if (pkgs.isEmpty) {
      showSnack(context, 'Crea primero un bono en la sección Bonos', error: true);
      return;
    }
    final chosen = await showDialog<Package>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Vender bono'),
        children: [
          for (final p in pkgs)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, p),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(p.name),
                subtitle: Text([
                  if (p.sessions != null) '${p.sessions} sesiones',
                  if (p.validityDays != null) 'válido ${p.validityDays} días',
                  if (p.type == 'gift_card') 'tarjeta regalo',
                ].join(' · ')),
                trailing: Text(formatEuros(p.priceCents),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      ),
    );
    if (chosen == null || !mounted) return;
    final ok = await confirmDialog(context,
        title: 'Confirmar venta',
        message: 'Vender "${chosen.name}" por ${formatEuros(chosen.priceCents)} a ${_c!.fullName}.',
        confirmLabel: 'Vender');
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await session.biz.sellPackage(
        businessId: _bizId,
        packageId: chosen.id,
        customerId: _c!.id,
        sessionsTotal: chosen.sessions,
        balanceCents: chosen.type == 'gift_card' ? chosen.priceCents : null,
        validUntil: chosen.validityDays == null
            ? null
            : DateTime.now().add(Duration(days: chosen.validityDays!)),
      );
      if (!mounted) return;
      showSnack(context, 'Bono vendido');
      await _load();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_c?.fullName ?? session.customerLabel),
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          if (_dirty)
            TextButton(onPressed: _busy ? null : _save, child: const Text('Guardar')),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: _c == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => showNewBookingSheet(context, customerId: _c!.id, onCreated: _load),
              icon: const Icon(Icons.add),
              label: Text('Nueva ${session.bookingLabel.toLowerCase()}'),
            ),
      body: _loading
          ? const LoadingView()
          : _c == null
              ? ErrorView(_error ?? 'Error', onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: MaxWidth(
                    child: LayoutBuilder(builder: (_, cons) {
                      final wide = cons.maxWidth >= 820;
                      final left = [_header(t), _stats(t), _form(t), _consent(t)];
                      final right = [_packagesSection(t), _historySection(t)];
                      return ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                        children: wide
                            ? [
                                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Expanded(flex: 5, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: left)),
                                  const SizedBox(width: 20),
                                  Expanded(flex: 4, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: right)),
                                ]),
                              ]
                            : [...left, ...right],
                      );
                    }),
                  ),
                ),
    );
  }

  Widget _header(ThemeData t) {
    final c = _c!;
    final digits = (c.phone ?? '').replaceAll(RegExp(r'[^0-9+]'), '');
    final wa = digits.replaceAll('+', '');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Row(children: [
            AvatarCircle(initials: c.initials, radius: 30, color: c.blocked ? Colors.grey : null),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.fullName, style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                Text(
                  [
                    if (c.createdAt != null) 'Desde ${Fmt.date(c.createdAt!)}',
                    'Origen: ${_sourceLabel(c.source)}',
                  ].join(' · '),
                  style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline),
                ),
                if (c.blocked)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text('Bloqueado para reservas online',
                        style: TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w600, fontSize: 12)),
                  ),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
                onPressed: digits.isEmpty ? null : () => _launch('tel:$digits'),
                icon: const Icon(Icons.call_outlined, size: 18),
                label: const Text('Llamar'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
                onPressed: wa.isEmpty ? null : () => _launch('https://wa.me/$wa'),
                icon: const Icon(Icons.chat_outlined, size: 18),
                label: const Text('WhatsApp'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
                onPressed: (c.email ?? '').isEmpty ? null : () => _launch('mailto:${c.email}'),
                icon: const Icon(Icons.mail_outline, size: 18),
                label: const Text('Email'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  String _sourceLabel(String s) {
    switch (s) {
      case 'app':
        return 'App';
      case 'import':
        return 'Importado';
      case 'walk_in':
        return 'Sin cita';
      case 'google':
        return 'Google';
      default:
        return 'Manual';
    }
  }

  Widget _stats(ThemeData t) {
    final c = _c!;
    Widget stat(String label, String value, {Color? color}) => Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              child: Column(children: [
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: color)),
                Text(label,
                    textAlign: TextAlign.center,
                    style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.outline)),
              ]),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(children: [
        stat('Visitas', '${c.totalVisits}'),
        const SizedBox(width: 8),
        stat('Gasto total', formatEuros(c.totalSpentCents)),
        const SizedBox(width: 8),
        stat('No-shows', '${c.noShowCount}', color: c.noShowCount > 0 ? AppTheme.danger : null),
        const SizedBox(width: 8),
        stat('Última visita', c.lastVisitAt == null ? '—' : Fmt.date(c.lastVisitAt!)),
      ]),
    );
  }

  Widget _form(ThemeData t) {
    final c = _c!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle('Datos',
          trailing: _dirty
              ? FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 38)),
                  onPressed: _busy ? null : _save,
                  child: const Text('Guardar'))
              : null),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
                controller: _name,
                onChanged: (_) => _markDirty(),
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nombre completo')),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextField(
                    controller: _phone,
                    onChanged: (_) => _markDirty(),
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Teléfono')),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                    controller: _email,
                    onChanged: (_) => _markDirty(),
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email')),
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextField(
                    controller: _taxId,
                    onChanged: (_) => _markDirty(),
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'NIF')),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: _pickBirthdate,
                  borderRadius: BorderRadius.circular(12),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Fecha de nacimiento',
                      suffixIcon: _birthdate == null
                          ? const Icon(Icons.calendar_today_outlined, size: 18)
                          : IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () => setState(() {
                                _birthdate = null;
                                _dirty = true;
                              })),
                    ),
                    child: Text(_birthdate == null ? '—' : Fmt.date(_birthdate!)),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            TextField(
                controller: _address,
                onChanged: (_) => _markDirty(),
                decoration: const InputDecoration(labelText: 'Dirección')),
            const SizedBox(height: 10),
            TextField(
                controller: _notes,
                onChanged: (_) => _markDirty(),
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                    labelText: 'Notas internas', hintText: 'Alergias, preferencias, avisos…')),
            const SizedBox(height: 12),
            Text('Etiquetas', style: t.textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              for (final tag in _tags)
                InputChip(
                  label: Text(tag),
                  onDeleted: () => setState(() {
                    _tags.remove(tag);
                    _dirty = true;
                  }),
                ),
              SizedBox(
                width: 160,
                child: TextField(
                  controller: _tagCtrl,
                  decoration: const InputDecoration(
                      hintText: 'Añadir etiqueta', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                  onSubmitted: (v) {
                    final tag = v.trim();
                    if (tag.isEmpty || _tags.contains(tag)) return;
                    setState(() {
                      _tags.add(tag);
                      _dirty = true;
                      _tagCtrl.clear();
                    });
                  },
                ),
              ),
            ]),
            const Divider(height: 24),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Bloquear reservas online'),
              subtitle: const Text('No podrá reservar desde la app; tú sí puedes darle cita.'),
              value: c.blocked,
              onChanged: _busy
                  ? null
                  : (v) => _patch({'blocked': v},
                      ok: v ? '${session.customerLabel} bloqueado' : 'Bloqueo retirado'),
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _consent(ThemeData t) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('Consentimiento RGPD'),
      Card(
        child: ListTile(
          leading: Icon(_gdpr == null ? Icons.privacy_tip_outlined : Icons.verified_user_outlined,
              color: _gdpr == null ? AppTheme.warning : AppTheme.accent),
          title: Text(_gdpr == null ? 'Sin consentimiento registrado' : 'Otorgado el ${Fmt.date(_gdpr!)}'),
          subtitle: const Text('Tratamiento de datos y comunicaciones'),
          trailing: _gdpr == null
              ? FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 38)),
                  onPressed: _busy ? null : () => _setGdpr(true),
                  child: const Text('Marcar ahora'))
              : TextButton(
                  onPressed: _busy ? null : () => _setGdpr(false), child: const Text('Retirar')),
        ),
      ),
    ]);
  }

  Widget _packagesSection(ThemeData t) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle('Bonos y membresías',
          trailing: TextButton.icon(
              onPressed: _busy ? null : _sellPackage,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Vender bono'))),
      if (_packages.isEmpty)
        Text('Sin bonos activos.', style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.outline))
      else
        Card(
          child: Column(children: [
            for (var i = 0; i < _packages.length; i++) ...[
              _packageTile(t, _packages[i]),
              if (i < _packages.length - 1) const Divider(indent: 16, endIndent: 16),
            ],
          ]),
        ),
    ]);
  }

  Widget _packageTile(ThemeData t, CustomerPackage p) {
    final active = p.status == 'active';
    final remaining = p.sessionsTotal == null ? null : p.sessionsTotal! - p.sessionsUsed;
    final parts = <String>[
      if (remaining != null) '$remaining de ${p.sessionsTotal} sesiones',
      if (p.balanceCents != null) 'Saldo ${formatEuros(p.balanceCents!)}',
      if (p.validUntil != null) 'hasta ${Fmt.date(p.validUntil!)}',
    ];
    return ListTile(
      leading: Icon(Icons.card_giftcard_outlined, color: active ? t.colorScheme.primary : Colors.grey),
      title: Text(p.packageName ?? 'Bono', style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('${parts.join(' · ')}\nCódigo ${p.code}'),
      isThreeLine: true,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: (active ? AppTheme.accent : Colors.grey).withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(8)),
        child: Text(_pkgStatus(p.status),
            style: TextStyle(
                color: active ? AppTheme.accent : Colors.grey, fontWeight: FontWeight.w700, fontSize: 12)),
      ),
    );
  }

  String _pkgStatus(String s) {
    switch (s) {
      case 'active':
        return 'Activo';
      case 'used':
        return 'Agotado';
      case 'expired':
        return 'Caducado';
      case 'cancelled':
        return 'Cancelado';
      default:
        return s;
    }
  }

  Widget _historySection(ThemeData t) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle('Historial de ${session.bookingLabel.toLowerCase()}s',
          trailing: Text('${_bookings.length}',
              style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline))),
      if (_bookings.isEmpty)
        Text('Todavía no tiene ${session.bookingLabel.toLowerCase()}s.',
            style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.outline))
      else
        Card(
          child: Column(children: [
            for (var i = 0; i < _bookings.length; i++) ...[
              ListTile(
                onTap: () => showBookingSheet(context, _bookings[i].id, onChanged: _load),
                leading: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                        color: hexColor(_bookings[i].memberColor), shape: BoxShape.circle)),
                title: Text(Fmt.dateTime(_bookings[i].startsAt),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                    [
                      _bookings[i].servicesSummary,
                      _bookings[i].memberName,
                      formatEuros(_bookings[i].totalCents),
                    ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                trailing: StatusChip(_bookings[i].status),
              ),
              if (i < _bookings.length - 1) const Divider(indent: 16, endIndent: 16),
            ],
          ]),
        ),
    ]);
  }
}
