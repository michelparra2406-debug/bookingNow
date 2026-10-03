import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_theme.dart';
import '../../models/models.dart';
import '../../services/admin_extra.dart';
import '../../services/app_session.dart';
import '../../utils/friendly_errors.dart';
import '../../widgets/admin_widgets.dart';
import '../../widgets/common.dart';

/// Ajustes del negocio: datos, fiscal, reservas, sedes, avisos y página pública.
class SettingsScreen extends StatefulWidget {
  /// 0 Negocio · 1 Fiscal · 2 Reservas · 3 Sedes · 4 Avisos · 5 Página pública
  final int initialTab;
  const SettingsScreen({super.key, this.initialTab = 0});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  final session = AppSession.instance;
  late final TabController _tabs =
      TabController(length: 6, vsync: this, initialIndex: widget.initialTab.clamp(0, 5));

  @override
  void initState() {
    super.initState();
    session.addListener(_onSession);
  }

  @override
  void dispose() {
    session.removeListener(_onSession);
    _tabs.dispose();
    super.dispose();
  }

  void _onSession() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final b = session.activeBusiness!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajustes'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Negocio'),
            Tab(text: 'Fiscal'),
            Tab(text: 'Reservas'),
            Tab(text: 'Sedes'),
            Tab(text: 'Avisos'),
            Tab(text: 'Página pública'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _BusinessTab(key: ValueKey('biz-${b.id}'), business: b),
          _FiscalTab(key: ValueKey('fiscal-${b.id}'), business: b),
          _BookingTab(key: ValueKey('booking-${b.id}'), business: b),
          _LocationsTab(key: ValueKey('loc-${b.id}'), business: b),
          _NotificationsTab(key: ValueKey('notif-${b.id}'), business: b),
          _PublicPageTab(key: ValueKey('public-${b.id}'), business: b),
        ],
      ),
    );
  }
}

/// Guarda campos del negocio y refresca la sesión. Devuelve true si fue bien.
Future<bool> _saveBusiness(BuildContext context, String id, Map<String, dynamic> fields) async {
  final session = AppSession.instance;
  try {
    await session.biz.updateBusiness(id, fields);
    await session.refreshActiveBusiness();
    if (!context.mounted) return true;
    showSnack(context, 'Ajustes guardados');
    return true;
  } catch (e) {
    if (!context.mounted) return false;
    showSnack(context, friendlyError(e), error: true);
    return false;
  }
}

Widget _saveButton(bool saving, VoidCallback onSave) => FilledButton.icon(
      onPressed: saving ? null : onSave,
      icon: saving
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.save_outlined),
      label: const Text('Guardar'),
    );

Widget _tabBody(List<Widget> children) => MaxWidth(
      maxWidth: 860,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [...children, const SizedBox(height: 32)],
      ),
    );

String? _nullIfEmpty(TextEditingController c) =>
    c.text.trim().isEmpty ? null : c.text.trim();

// ============================================================ Negocio

class _BusinessTab extends StatefulWidget {
  final Business business;
  const _BusinessTab({super.key, required this.business});
  @override
  State<_BusinessTab> createState() => _BusinessTabState();
}

class _BusinessTabState extends State<_BusinessTab> {
  final session = AppSession.instance;
  late final _name = TextEditingController(text: widget.business.name);
  late final _description = TextEditingController(text: widget.business.description ?? '');
  late final _phone = TextEditingController(text: widget.business.phone ?? '');
  late final _email = TextEditingController(text: widget.business.email ?? '');
  late final _website = TextEditingController(text: widget.business.website ?? '');
  late final _instagram = TextEditingController(text: widget.business.instagram ?? '');
  late final _logo = TextEditingController(text: widget.business.logoUrl ?? '');
  late final _cover = TextEditingController(text: widget.business.coverUrl ?? '');
  late String _sectorId = widget.business.sectorId;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _description, _phone, _email, _website, _instagram, _logo, _cover]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      showSnack(context, 'El nombre es obligatorio', error: true);
      return;
    }
    setState(() => _saving = true);
    await _saveBusiness(context, widget.business.id, {
      'name': _name.text.trim(),
      'description': _nullIfEmpty(_description),
      'phone': _nullIfEmpty(_phone),
      'email': _nullIfEmpty(_email),
      'website': _nullIfEmpty(_website),
      'instagram': _nullIfEmpty(_instagram)?.replaceAll('@', ''),
      'logo_url': _nullIfEmpty(_logo),
      'cover_url': _nullIfEmpty(_cover),
      'sector_id': _sectorId,
    });
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final b = widget.business;
    final sectors = session.sectors;
    return _tabBody([
      FormCard(title: 'Datos del negocio', children: [
        ResponsiveFields(children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nombre comercial *'),
          ),
          DropdownButtonFormField<String>(
            initialValue: sectors.any((s) => s.id == _sectorId) ? _sectorId : null,
            decoration: const InputDecoration(labelText: 'Sector'),
            items: [
              for (final s in sectors) DropdownMenuItem(value: s.id, child: Text(s.nameEs)),
            ],
            onChanged: (v) => setState(() => _sectorId = v ?? _sectorId),
          ),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _description,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
              labelText: 'Descripción', hintText: 'Se muestra en tu página pública'),
        ),
        const SizedBox(height: 12),
        ResponsiveFields(children: [
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Teléfono'),
          ),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email de contacto'),
          ),
          TextField(
            controller: _website,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'Web', hintText: 'https://'),
          ),
          TextField(
            controller: _instagram,
            decoration: const InputDecoration(labelText: 'Instagram', prefixText: '@'),
          ),
        ]),
      ]),
      const SizedBox(height: 12),
      FormCard(title: 'Imagen', children: [
        ResponsiveFields(children: [
          TextField(
            controller: _logo,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'URL del logo'),
            onChanged: (_) => setState(() {}),
          ),
          TextField(
            controller: _cover,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'URL de portada'),
            onChanged: (_) => setState(() {}),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          AvatarCircle(
              url: _logo.text.trim().isEmpty ? null : _logo.text.trim(),
              initials: b.name.isEmpty ? '?' : b.name[0],
              radius: 28),
          const SizedBox(width: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                height: 72,
                color: t.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                child: _cover.text.trim().isEmpty
                    ? Center(
                        child: Text('Sin portada',
                            style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)))
                    : Image.network(_cover.text.trim(),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined))),
              ),
            ),
          ),
        ]),
      ]),
      const SizedBox(height: 12),
      Card(
        child: ListTile(
          leading: Icon(Icons.workspace_premium_outlined, color: t.colorScheme.primary),
          title: Text('Plan ${_planLabel(b.plan)}', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(b.plan == 'free'
              ? 'Hasta 2 profesionales y funciones básicas.'
              : b.plan == 'pro'
                  ? 'Recordatorios por WhatsApp/SMS, bonos y marketing.'
                  : 'Multi-sede, API e integraciones avanzadas.'),
          trailing: TextButton(
            onPressed: () => showSnack(context, 'Los planes de pago estarán disponibles próximamente.'),
            child: const Text('Mejorar plan'),
          ),
        ),
      ),
      const SizedBox(height: 20),
      _saveButton(_saving, _save),
    ]);
  }

  static String _planLabel(String p) {
    switch (p) {
      case 'pro':
        return 'Pro';
      case 'business':
        return 'Business';
      default:
        return 'Free';
    }
  }
}

// ============================================================ Fiscal

class _FiscalTab extends StatefulWidget {
  final Business business;
  const _FiscalTab({super.key, required this.business});
  @override
  State<_FiscalTab> createState() => _FiscalTabState();
}

class _FiscalTabState extends State<_FiscalTab> {
  final session = AppSession.instance;
  late final _legalName = TextEditingController(text: widget.business.legalName ?? '');
  late final _taxId = TextEditingController(text: widget.business.taxId ?? '');
  late final _address = TextEditingController(text: widget.business.fiscalAddress ?? '');
  late final _postal = TextEditingController(text: widget.business.fiscalPostalCode ?? '');
  late final _city = TextEditingController(text: widget.business.fiscalCity ?? '');
  late final _province = TextEditingController(text: widget.business.fiscalProvince ?? '');
  String _vatRegime = 'general';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadExtras();
  }

  Future<void> _loadExtras() async {
    try {
      final extras = await session.biz.fetchBusinessExtras(widget.business.id);
      if (!mounted) return;
      setState(() => _vatRegime = extras['vat_regime']?.toString() ?? 'general');
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final c in [_legalName, _taxId, _address, _postal, _city, _province]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await _saveBusiness(context, widget.business.id, {
      'legal_name': _nullIfEmpty(_legalName),
      'tax_id': _nullIfEmpty(_taxId)?.toUpperCase().replaceAll(' ', ''),
      'fiscal_address': _nullIfEmpty(_address),
      'fiscal_postal_code': _nullIfEmpty(_postal),
      'fiscal_city': _nullIfEmpty(_city),
      'fiscal_province': _nullIfEmpty(_province),
      'vat_regime': _vatRegime,
    });
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final complete = _taxId.text.trim().isNotEmpty && _legalName.text.trim().isNotEmpty;
    return _tabBody([
      InfoCard(
        complete
            ? 'Datos fiscales completos. Las facturas se emiten con estos datos y el registro Verifactu.'
            : 'Necesario para emitir facturas. Razón social, NIF y dirección aparecen en cada factura y en el registro Verifactu.',
        icon: complete ? Icons.verified_outlined : Icons.warning_amber_rounded,
        color: complete ? AppTheme.accent : AppTheme.warning,
      ),
      const SizedBox(height: 12),
      FormCard(title: 'Datos fiscales', children: [
        ResponsiveFields(children: [
          TextField(
            controller: _legalName,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
                labelText: 'Razón social / nombre fiscal *', hintText: 'Peluquería Marta S.L.'),
            onChanged: (_) => setState(() {}),
          ),
          TextField(
            controller: _taxId,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'NIF / CIF *', hintText: 'B12345678'),
            onChanged: (_) => setState(() {}),
          ),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _address,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Dirección fiscal'),
        ),
        const SizedBox(height: 12),
        ResponsiveFields(children: [
          TextField(
            controller: _postal,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Código postal'),
          ),
          TextField(
            controller: _city,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Ciudad'),
          ),
          TextField(
            controller: _province,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Provincia'),
          ),
          DropdownButtonFormField<String>(
            key: ValueKey('vat-$_vatRegime'),
            initialValue: _vatRegime,
            decoration: const InputDecoration(labelText: 'Régimen de IVA'),
            items: const [
              DropdownMenuItem(value: 'general', child: Text('General')),
              DropdownMenuItem(value: 'simplified', child: Text('Simplificado (módulos)')),
              DropdownMenuItem(value: 'exempt', child: Text('Exento (art. 20 LIVA: sanidad, formación…)')),
              DropdownMenuItem(value: 'recargo', child: Text('Recargo de equivalencia')),
            ],
            onChanged: (v) => setState(() => _vatRegime = v ?? 'general'),
          ),
        ]),
      ]),
      const SizedBox(height: 20),
      _saveButton(_saving, _save),
    ]);
  }
}

// ============================================================ Reservas

class _BookingTab extends StatefulWidget {
  final Business business;
  const _BookingTab({super.key, required this.business});
  @override
  State<_BookingTab> createState() => _BookingTabState();
}

class _BookingTabState extends State<_BookingTab> {
  late final _lead = TextEditingController(text: '${widget.business.bookingLeadMin}');
  late final _horizon = TextEditingController(text: '${widget.business.bookingHorizonDays}');
  late final _cancelHours = TextEditingController(text: '${widget.business.cancellationHours}');
  late final _cancelFee = TextEditingController(text: '${widget.business.cancellationFeePct}');
  late final _noShowFee = TextEditingController(text: '${widget.business.noShowFeePct}');
  late final _deposit = TextEditingController(text: '${widget.business.depositPct}');
  late bool _requiresConfirmation = widget.business.requiresConfirmation;
  late bool _allowWaitlist = widget.business.allowWaitlist;
  late bool _allowRecurring = widget.business.allowRecurring;
  late bool _online = widget.business.onlineBookingEnabled;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_lead, _horizon, _cancelHours, _cancelFee, _noShowFee, _deposit]) {
      c.dispose();
    }
    super.dispose();
  }

  int _pct(TextEditingController c) => (int.tryParse(c.text) ?? 0).clamp(0, 100);

  Future<void> _save() async {
    setState(() => _saving = true);
    await _saveBusiness(context, widget.business.id, {
      'booking_lead_min': (int.tryParse(_lead.text) ?? 60).clamp(0, 100000),
      'booking_horizon_days': (int.tryParse(_horizon.text) ?? 60).clamp(1, 365),
      'cancellation_hours': (int.tryParse(_cancelHours.text) ?? 24).clamp(0, 720),
      'cancellation_fee_pct': _pct(_cancelFee),
      'no_show_fee_pct': _pct(_noShowFee),
      'deposit_pct': _pct(_deposit),
      'requires_confirmation': _requiresConfirmation,
      'allow_waitlist': _allowWaitlist,
      'allow_recurring': _allowRecurring,
      'online_booking_enabled': _online,
    });
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return _tabBody([
      FormCard(title: 'Reservas online', children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Reservas online activadas'),
          subtitle: const Text('Desactívalo temporalmente si no quieres recibir reservas nuevas'),
          value: _online,
          onChanged: (v) => setState(() => _online = v),
        ),
        ResponsiveFields(children: [
          TextField(
            controller: _lead,
            keyboardType: TextInputType.number,
            inputFormatters: intInputFormatters,
            decoration: const InputDecoration(
                labelText: 'Antelación mínima',
                suffixText: 'min',
                helperText: 'Tiempo mínimo entre la reserva y la cita'),
          ),
          TextField(
            controller: _horizon,
            keyboardType: TextInputType.number,
            inputFormatters: intInputFormatters,
            decoration: const InputDecoration(
                labelText: 'Horizonte de reserva',
                suffixText: 'días',
                helperText: 'Hasta cuántos días vista se puede reservar'),
          ),
        ]),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Confirmación manual'),
          subtitle: const Text('Las reservas quedan pendientes hasta que las aceptes'),
          value: _requiresConfirmation,
          onChanged: (v) => setState(() => _requiresConfirmation = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Lista de espera'),
          subtitle: const Text('Si no hay hueco, el cliente puede apuntarse y le avisamos si se libera'),
          value: _allowWaitlist,
          onChanged: (v) => setState(() => _allowWaitlist = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Citas recurrentes'),
          subtitle: const Text('Permite repetir una cita cada X días (p. ej. cada 4 semanas)'),
          value: _allowRecurring,
          onChanged: (v) => setState(() => _allowRecurring = v),
        ),
      ]),
      const SizedBox(height: 12),
      FormCard(title: 'Protección contra no-shows', children: [
        const InfoCard(
          'Pedir una señal al reservar y cobrar una penalización por cancelación tardía o no presentarse reduce los no-shows hasta un 70 %. Necesitas Stripe o Redsys conectado en Integraciones para cobrarlas automáticamente.',
          icon: Icons.shield_outlined,
        ),
        const SizedBox(height: 12),
        ResponsiveFields(children: [
          TextField(
            controller: _deposit,
            keyboardType: TextInputType.number,
            inputFormatters: intInputFormatters,
            decoration: const InputDecoration(
                labelText: 'Señal al reservar',
                suffixText: '%',
                helperText: '% del precio que se cobra al reservar (0 = sin señal)'),
          ),
          TextField(
            controller: _cancelHours,
            keyboardType: TextInputType.number,
            inputFormatters: intInputFormatters,
            decoration: const InputDecoration(
                labelText: 'Cancelación gratuita hasta',
                suffixText: 'h antes',
                helperText: 'Después se aplica la penalización'),
          ),
          TextField(
            controller: _cancelFee,
            keyboardType: TextInputType.number,
            inputFormatters: intInputFormatters,
            decoration: const InputDecoration(
                labelText: 'Penalización por cancelación tardía',
                suffixText: '%',
                helperText: '% del servicio'),
          ),
          TextField(
            controller: _noShowFee,
            keyboardType: TextInputType.number,
            inputFormatters: intInputFormatters,
            decoration: const InputDecoration(
                labelText: 'Penalización por no presentarse',
                suffixText: '%',
                helperText: '% del servicio (se cobra de la señal)'),
          ),
        ]),
      ]),
      const SizedBox(height: 20),
      _saveButton(_saving, _save),
    ]);
  }
}

// ============================================================ Sedes

class _LocationsTab extends StatefulWidget {
  final Business business;
  const _LocationsTab({super.key, required this.business});
  @override
  State<_LocationsTab> createState() => _LocationsTabState();
}

class _LocationsTabState extends State<_LocationsTab> {
  final session = AppSession.instance;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _locations = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final l = await session.biz.fetchLocationsRaw(widget.business.id);
      if (!mounted) return;
      setState(() {
        _locations = l;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  Future<void> _edit([Map<String, dynamic>? raw]) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _LocationDialog(raw: raw, isFirst: _locations.isEmpty),
    );
    if (result == null || !mounted) return;
    try {
      final makeDefault = result.remove('_make_default') == true;
      if (makeDefault) {
        for (final l in _locations) {
          if (l['is_default'] == true && l['id'] != raw?['id']) {
            await session.biz.upsertLocation({'id': l['id'], 'business_id': widget.business.id, 'is_default': false});
          }
        }
      }
      await session.biz.upsertLocation({
        if (raw != null) 'id': raw['id'],
        'business_id': widget.business.id,
        ...result,
        'is_default': makeDefault || (raw?['is_default'] == true),
      });
      if (!mounted) return;
      showSnack(context, 'Sede guardada');
      _load();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _delete(Map<String, dynamic> l) async {
    if (l['is_default'] == true) {
      showSnack(context, 'No puedes eliminar la sede principal. Marca otra como principal primero.',
          error: true);
      return;
    }
    final ok = await confirmDialog(context,
        title: 'Eliminar sede',
        message: '¿Eliminar "${l['name']}"?',
        confirmLabel: 'Eliminar',
        destructive: true);
    if (!ok || !mounted) return;
    try {
      await session.biz.deleteLocation(l['id'] as String);
      if (!mounted) return;
      _load();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    if (_loading) return const LoadingView();
    if (_error != null) return ErrorView(_error!, onRetry: _load);
    return _tabBody([
      Row(children: [
        Expanded(
          child: Text('Sedes y servicio a domicilio',
              style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        ),
        TextButton.icon(
            onPressed: () => _edit(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Añadir sede')),
      ]),
      const SizedBox(height: 8),
      if (_locations.isEmpty)
        const Card(child: InlineEmpty('Sin sedes. Añade al menos una dirección.')),
      for (final l in _locations)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Card(
            child: ListTile(
              onTap: () => _edit(l),
              leading: Icon(
                  l['is_mobile_service'] == true ? Icons.directions_car_outlined : Icons.store_outlined,
                  color: t.colorScheme.primary),
              title: Row(children: [
                Flexible(
                    child: Text(l['name']?.toString() ?? '',
                        style: const TextStyle(fontWeight: FontWeight.w600))),
                const SizedBox(width: 8),
                if (l['is_default'] == true) const SmallBadge('Principal'),
                if (l['active'] == false) ...[
                  const SizedBox(width: 6),
                  const SmallBadge('Inactiva', color: Colors.grey),
                ],
              ]),
              subtitle: Text([
                [l['address'], l['postal_code'], l['city']]
                    .where((e) => e != null && e.toString().isNotEmpty)
                    .join(', '),
                if (l['is_mobile_service'] == true)
                  'A domicilio${l['travel_radius_km'] != null ? ' · ${l['travel_radius_km']} km' : ''}${(l['travel_fee_cents'] ?? 0) > 0 ? ' · +${formatEuros(l['travel_fee_cents'] as int)}' : ''}',
              ].where((s) => s.isNotEmpty).join('\n')),
              isThreeLine: l['is_mobile_service'] == true,
              trailing: PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'edit') _edit(l);
                  if (v == 'default') {
                    try {
                      await session.biz.setDefaultLocation(widget.business.id, l['id'] as String);
                      if (!context.mounted) return;
                      _load();
                    } catch (e) {
                      if (!context.mounted) return;
                      showSnack(context, friendlyError(e), error: true);
                    }
                  }
                  if (v == 'delete') _delete(l);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Editar')),
                  if (l['is_default'] != true)
                    const PopupMenuItem(value: 'default', child: Text('Marcar como principal')),
                  const PopupMenuItem(
                      value: 'delete',
                      child: Text('Eliminar', style: TextStyle(color: AppTheme.danger))),
                ],
              ),
            ),
          ),
        ),
    ]);
  }
}

class _LocationDialog extends StatefulWidget {
  final Map<String, dynamic>? raw;
  final bool isFirst;
  const _LocationDialog({this.raw, required this.isFirst});
  @override
  State<_LocationDialog> createState() => _LocationDialogState();
}

class _LocationDialogState extends State<_LocationDialog> {
  late final _name = TextEditingController(text: widget.raw?['name']?.toString() ?? '');
  late final _address = TextEditingController(text: widget.raw?['address']?.toString() ?? '');
  late final _postal = TextEditingController(text: widget.raw?['postal_code']?.toString() ?? '');
  late final _city = TextEditingController(text: widget.raw?['city']?.toString() ?? '');
  late final _province = TextEditingController(text: widget.raw?['province']?.toString() ?? '');
  late final _phone = TextEditingController(text: widget.raw?['phone']?.toString() ?? '');
  late final _radius = TextEditingController(text: widget.raw?['travel_radius_km']?.toString() ?? '');
  late final _fee =
      TextEditingController(text: centsToInput((widget.raw?['travel_fee_cents'] as int?) ?? 0));
  late bool _mobile = widget.raw?['is_mobile_service'] == true;
  late bool _default = widget.raw?['is_default'] == true || widget.isFirst;
  late bool _active = widget.raw?['active'] != false;

  @override
  void dispose() {
    for (final c in [_name, _address, _postal, _city, _province, _phone, _radius, _fee]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.raw == null ? 'Nueva sede' : 'Editar sede'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: _name,
              autofocus: widget.raw == null,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nombre *', hintText: 'Centro, Sede norte…'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _address,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Dirección'),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _postal,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'C.P.'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _city,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Ciudad'),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _province,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Provincia'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Teléfono'),
                ),
              ),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Servicio a domicilio'),
              subtitle: const Text('El profesional se desplaza al cliente'),
              value: _mobile,
              onChanged: (v) => setState(() => _mobile = v),
            ),
            if (_mobile)
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _radius,
                    keyboardType: TextInputType.number,
                    inputFormatters: intInputFormatters,
                    decoration: const InputDecoration(labelText: 'Radio', suffixText: 'km'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _fee,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: euroInputFormatters,
                    decoration: const InputDecoration(labelText: 'Suplemento', suffixText: '€'),
                  ),
                ),
              ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Sede principal'),
              value: _default,
              onChanged: (widget.raw?['is_default'] == true || widget.isFirst)
                  ? null
                  : (v) => setState(() => _default = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Activa'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (_name.text.trim().isEmpty) return;
            Navigator.pop(context, {
              'name': _name.text.trim(),
              'address': _nullIfEmpty(_address),
              'postal_code': _nullIfEmpty(_postal),
              'city': _nullIfEmpty(_city),
              'province': _nullIfEmpty(_province),
              'phone': _nullIfEmpty(_phone),
              'is_mobile_service': _mobile,
              'travel_radius_km': _mobile ? int.tryParse(_radius.text) : null,
              'travel_fee_cents': _mobile ? parseEuros(_fee.text) : 0,
              'active': _active,
              '_make_default': _default,
            });
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

// ============================================================ Avisos

class _NotificationsTab extends StatefulWidget {
  final Business business;
  const _NotificationsTab({super.key, required this.business});
  @override
  State<_NotificationsTab> createState() => _NotificationsTabState();
}

class _NotificationsTabState extends State<_NotificationsTab> {
  final session = AppSession.instance;
  static const _hourOptions = [48, 24, 12, 2, 1];
  static const _channelOptions = {
    'push': 'Push (app)',
    'email': 'Email',
    'sms': 'SMS',
    'whatsapp': 'WhatsApp',
  };
  bool _loading = true;
  bool _saving = false;
  Set<int> _hours = {24, 2};
  Set<String> _channels = {'push', 'email'};
  bool _askConfirmation = true;
  final _reviewHours = TextEditingController(text: '2');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reviewHours.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await session.biz.fetchNotificationSettings(widget.business.id);
      if (!mounted) return;
      setState(() {
        if (s != null) {
          _hours = ((s['reminder_hours'] as List?) ?? [24, 2])
              .map((e) => int.tryParse(e.toString()) ?? 0)
              .where((e) => e > 0)
              .toSet();
          _channels = ((s['channels'] as List?) ?? ['push', 'email']).map((e) => e.toString()).toSet();
          _askConfirmation = s['ask_confirmation'] as bool? ?? true;
          _reviewHours.text = '${s['review_request_hours'] ?? 2}';
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final hours = _hours.toList()..sort((a, b) => b.compareTo(a));
      await session.biz.saveNotificationSettings(widget.business.id, {
        'reminder_hours': hours,
        'channels': _channels.toList(),
        'ask_confirmation': _askConfirmation,
        'review_request_hours': (int.tryParse(_reviewHours.text) ?? 2).clamp(0, 720),
      });
      if (!mounted) return;
      showSnack(context, 'Avisos guardados');
    } catch (e) {
      if (!mounted) return;
      showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    if (_loading) return const LoadingView();
    return _tabBody([
      FormCard(title: 'Recordatorios de cita', children: [
        Text('Enviar recordatorio antes de la cita:', style: t.textTheme.bodyMedium),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final h in _hourOptions)
            FilterChip(
              label: Text(h >= 24 ? '${h ~/ 24} ${h == 24 ? 'día' : 'días'} antes' : '$h ${h == 1 ? 'hora' : 'horas'} antes'),
              selected: _hours.contains(h),
              onSelected: (v) => setState(() {
                if (v) {
                  _hours.add(h);
                } else {
                  _hours.remove(h);
                }
              }),
            ),
        ]),
        const SizedBox(height: 16),
        Text('Canales:', style: t.textTheme.bodyMedium),
        for (final e in _channelOptions.entries)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(e.value),
            subtitle: e.key == 'sms' || e.key == 'whatsapp'
                ? const Text('Requiere integración activa (Twilio / WhatsApp Business)')
                : null,
            value: _channels.contains(e.key),
            onChanged: (v) => setState(() {
              if (v == true) {
                _channels.add(e.key);
              } else {
                _channels.remove(e.key);
              }
            }),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Pedir confirmación'),
          subtitle: const Text('El recordatorio incluye "Responde SÍ para confirmar". Las no confirmadas se marcan en la agenda.'),
          value: _askConfirmation,
          onChanged: (v) => setState(() => _askConfirmation = v),
        ),
      ]),
      const SizedBox(height: 12),
      FormCard(title: 'Valoraciones', children: [
        TextField(
          controller: _reviewHours,
          keyboardType: TextInputType.number,
          inputFormatters: intInputFormatters,
          decoration: const InputDecoration(
              labelText: 'Pedir valoración tras completar la cita',
              suffixText: 'horas después',
              helperText: '0 = inmediatamente'),
        ),
      ]),
      const SizedBox(height: 20),
      _saveButton(_saving, _save),
    ]);
  }
}

// ============================================================ Página pública

class _PublicPageTab extends StatefulWidget {
  final Business business;
  const _PublicPageTab({super.key, required this.business});
  @override
  State<_PublicPageTab> createState() => _PublicPageTabState();
}

class _PublicPageTabState extends State<_PublicPageTab> {
  final session = AppSession.instance;
  late bool _published = widget.business.isPublished;
  late final _slug = TextEditingController(text: widget.business.slug);
  bool _saving = false;

  @override
  void dispose() {
    _slug.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await _saveBusiness(context, widget.business.id, {'is_published': _published});
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _preview(String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) showSnack(context, 'No se pudo abrir la página', error: true);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final b = widget.business;
    final url = publicBookingUrl(b.slug);
    return _tabBody([
      FormCard(title: 'Tu página de reservas', children: [
        TextField(
          controller: _slug,
          readOnly: true,
          decoration: InputDecoration(
            labelText: 'Dirección (slug)',
            prefixText: '/b/',
            helperText: 'La dirección no se puede cambiar una vez creada',
            suffixIcon: IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Copiar enlace',
              onPressed: () => copyToClipboard(context, url, message: 'Enlace copiado'),
            ),
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, c) {
          final qr = Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: QrImageView(data: url, size: 140),
          );
          final info = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SelectableText(url,
                style: t.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600, color: t.colorScheme.primary)),
            const SizedBox(height: 6),
            Text('Imprime el QR y ponlo en el mostrador, en tarjetas o en tus redes.',
                style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                onPressed: () => _preview(url),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Vista previa'),
              ),
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                onPressed: () => SharePlus.instance.share(ShareParams(text: 'Reserva en ${b.name}: $url')),
                icon: const Icon(Icons.share_outlined, size: 18),
                label: const Text('Compartir'),
              ),
            ]),
          ]);
          if (c.maxWidth < 480) {
            return Column(children: [qr, const SizedBox(height: 12), info]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            qr,
            const SizedBox(width: 16),
            Expanded(child: info),
          ]);
        }),
      ]),
      const SizedBox(height: 12),
      FormCard(title: 'Visibilidad', children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Publicar en el marketplace'),
          subtitle: const Text(
              'Aparece en las búsquedas de la app de clientes. El enlace directo funciona aunque no esté publicado.'),
          value: _published,
          onChanged: (v) => setState(() => _published = v),
        ),
        if (_published && (b.servicesCount == 0 && b.taxId == null))
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: InfoCard(
              'Para destacar en el marketplace añade servicios con precio, fotos y completa la descripción del negocio.',
              icon: Icons.tips_and_updates_outlined,
              color: AppTheme.warning,
            ),
          ),
      ]),
      const SizedBox(height: 20),
      _saveButton(_saving, _save),
    ]);
  }
}
