import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/models.dart';
import '../../services/admin_extra.dart';
import '../../services/app_session.dart';
import '../../utils/format.dart';
import '../../utils/friendly_errors.dart';
import '../../widgets/admin_widgets.dart';
import '../../widgets/common.dart';

const _types = ['bundle', 'membership', 'gift_card'];

String _typeLabel(String t) {
  switch (t) {
    case 'membership':
      return 'Membresía';
    case 'gift_card':
      return 'Tarjeta regalo';
    default:
      return 'Bono';
  }
}

/// Bonos de sesiones, membresías y tarjetas regalo.
class PackagesScreen extends StatefulWidget {
  const PackagesScreen({super.key});
  @override
  State<PackagesScreen> createState() => _PackagesScreenState();
}

class _PackagesScreenState extends State<PackagesScreen>
    with SingleTickerProviderStateMixin {
  final session = AppSession.instance;
  late final TabController _tabs = TabController(length: 3, vsync: this);
  bool _loading = true;
  String? _error;
  List<Package> _packages = [];
  List<Service> _services = [];

  String get _businessId => session.activeBusiness!.id;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (mounted) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        session.biz.fetchPackages(_businessId),
        session.biz.fetchServices(_businessId, includeInactive: false),
      ]);
      if (!mounted) return;
      setState(() {
        _packages = results[0] as List<Package>;
        _services = results[1] as List<Service>;
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

  Future<void> _edit({Package? package, String? type}) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => _PackageEditScreen(
            package: package,
            type: package?.type ?? type ?? _types[_tabs.index],
            services: _services)));
    if (changed == true) _load();
  }

  Future<void> _toggleActive(Package p) async {
    try {
      await session.biz.upsertPackage({'id': p.id, 'business_id': _businessId, 'active': !p.active});
      if (!mounted) return;
      _load();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _delete(Package p) async {
    final ok = await confirmDialog(context,
        title: 'Eliminar ${_typeLabel(p.type).toLowerCase()}',
        message:
            '¿Eliminar "${p.name}"? Si ya se ha vendido a algún cliente no podrá eliminarse; desactívalo en su lugar.',
        confirmLabel: 'Eliminar',
        destructive: true);
    if (!ok || !mounted) return;
    try {
      await session.biz.deletePackage(p.id);
      if (!mounted) return;
      showSnack(context, 'Eliminado');
      _load();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _sell(Package p) async {
    final customer = await showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CustomerPicker(businessId: _businessId),
    );
    if (customer == null || !mounted) return;
    final ok = await confirmDialog(context,
        title: 'Vender ${_typeLabel(p.type).toLowerCase()}',
        message:
            '¿Vender "${p.name}" (${formatEuros(p.priceCents)}) a ${customer.fullName}?',
        confirmLabel: 'Vender');
    if (!ok || !mounted) return;
    try {
      final today = DateTime.now();
      await session.biz.sellPackage(
        businessId: _businessId,
        packageId: p.id,
        customerId: customer.id,
        sessionsTotal: p.type == 'gift_card'
            ? null
            : (p.type == 'membership' ? p.sessionsPerPeriod : p.sessions),
        balanceCents: p.type == 'gift_card' ? p.priceCents : null,
        validUntil: p.validityDays != null
            ? today.add(Duration(days: p.validityDays!))
            : (p.type == 'membership'
                ? (p.period == 'yearly'
                    ? DateTime(today.year + 1, today.month, today.day)
                    : DateTime(today.year, today.month + 1, today.day))
                : null),
      );
      if (!mounted) return;
      showSnack(context, 'Vendido a ${customer.fullName}');
    } catch (e) {
      if (!mounted) return;
      showSnack(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bonos y membresías'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load, tooltip: 'Actualizar'),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Bonos'),
            Tab(text: 'Membresías'),
            Tab(text: 'Tarjetas regalo'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: Text('Nuevo ${_typeLabel(_types[_tabs.index]).toLowerCase()}'),
      ),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(_error!, onRetry: _load)
              : TabBarView(
                  controller: _tabs,
                  children: [for (final t in _types) _list(t)],
                ),
    );
  }

  Widget _list(String type) {
    final items = _packages.where((p) => p.type == type).toList();
    if (items.isEmpty) {
      return EmptyView(
        icon: type == 'gift_card'
            ? Icons.card_giftcard_outlined
            : type == 'membership'
                ? Icons.loyalty_outlined
                : Icons.confirmation_number_outlined,
        title: 'Sin ${_typeLabel(type).toLowerCase()}s',
        subtitle: type == 'bundle'
            ? 'Vende packs de sesiones con descuento y fideliza a tus clientes.'
            : type == 'membership'
                ? 'Cuotas mensuales o anuales con sesiones incluidas y descuentos.'
                : 'Tarjetas con saldo que el cliente canjea en cualquier servicio.',
        action: FilledButton.icon(
          onPressed: () => _edit(type: type),
          icon: const Icon(Icons.add),
          label: const Text('Crear'),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: MaxWidth(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) => _card(items[i]),
        ),
      ),
    );
  }

  Widget _card(Package p) {
    final t = Theme.of(context);
    final details = <String>[];
    if (p.type == 'bundle') {
      if (p.sessions != null) details.add('${p.sessions} sesiones');
      if (p.validityDays != null) details.add('caduca a los ${p.validityDays} días');
      details.add(p.serviceIds.isEmpty
          ? 'cualquier servicio'
          : '${p.serviceIds.length} ${p.serviceIds.length == 1 ? 'servicio' : 'servicios'}');
    } else if (p.type == 'membership') {
      details.add(p.period == 'yearly' ? 'anual' : 'mensual');
      if (p.sessionsPerPeriod != null) details.add('${p.sessionsPerPeriod} sesiones incluidas');
      if ((p.discountPct ?? 0) > 0) details.add('${p.discountPct} % dto. en el resto');
    } else {
      details.add('saldo ${formatEuros(p.priceCents)}');
      if (p.validityDays != null) details.add('caduca a los ${p.validityDays} días');
    }
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _edit(package: p),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(p.name,
                        style: t.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: p.active ? null : t.colorScheme.outline)),
                  ),
                  if (!p.active)
                    const SmallBadge('Inactivo', color: Colors.grey, icon: Icons.visibility_off_outlined),
                ]),
                const SizedBox(height: 4),
                Text(details.join(' · '), style: t.textTheme.bodySmall),
                if (p.description != null && p.description!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(p.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
                ],
                const SizedBox(height: 8),
                Row(children: [
                  Text(formatEuros(p.priceCents),
                      style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const Spacer(),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 12)),
                    onPressed: p.active ? () => _sell(p) : null,
                    icon: const Icon(Icons.point_of_sale, size: 18),
                    label: const Text('Vender'),
                  ),
                ]),
              ]),
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                switch (v) {
                  case 'edit':
                    _edit(package: p);
                  case 'toggle':
                    _toggleActive(p);
                  case 'delete':
                    _delete(p);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Editar')),
                PopupMenuItem(value: 'toggle', child: Text(p.active ? 'Desactivar' : 'Activar')),
                const PopupMenuItem(
                    value: 'delete',
                    child: Text('Eliminar', style: TextStyle(color: AppTheme.danger))),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}

// ============================================================ Edición

class _PackageEditScreen extends StatefulWidget {
  final Package? package;
  final String type;
  final List<Service> services;
  const _PackageEditScreen({this.package, required this.type, required this.services});
  @override
  State<_PackageEditScreen> createState() => _PackageEditScreenState();
}

class _PackageEditScreenState extends State<_PackageEditScreen> {
  final session = AppSession.instance;
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.package?.name ?? '');
  late final _description = TextEditingController(text: widget.package?.description ?? '');
  late final _price = TextEditingController(text: centsToInput(widget.package?.priceCents ?? 0));
  late final _sessions = TextEditingController(text: '${widget.package?.sessions ?? 10}');
  late final _validity =
      TextEditingController(text: widget.package?.validityDays?.toString() ?? '365');
  late final _sessionsPerPeriod =
      TextEditingController(text: '${widget.package?.sessionsPerPeriod ?? 4}');
  late final _discount = TextEditingController(text: '${widget.package?.discountPct ?? 0}');
  late double _vat = 21;
  late String _period = widget.package?.period ?? 'monthly';
  late bool _active = widget.package?.active ?? true;
  late final Set<String> _serviceIds = {...?widget.package?.serviceIds};
  bool _saving = false;

  String get type => widget.type;

  @override
  void dispose() {
    for (final c in [_name, _description, _price, _sessions, _validity, _sessionsPerPeriod, _discount]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final fields = <String, dynamic>{
        if (widget.package != null) 'id': widget.package!.id,
        'business_id': session.activeBusiness!.id,
        'type': type,
        'name': _name.text.trim(),
        'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
        'price_cents': parseEuros(_price.text),
        'vat_pct': _vat,
        'active': _active,
        'sessions': type == 'bundle' ? int.tryParse(_sessions.text) : null,
        'service_ids': type == 'bundle' ? _serviceIds.toList() : <String>[],
        'validity_days': type == 'membership' ? null : int.tryParse(_validity.text),
        'period': type == 'membership' ? _period : null,
        'sessions_per_period': type == 'membership' ? int.tryParse(_sessionsPerPeriod.text) : null,
        'discount_pct': type == 'membership' ? int.tryParse(_discount.text) : null,
      };
      await session.biz.upsertPackage(fields);
      if (!mounted) return;
      showSnack(context, 'Guardado');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.package == null;
    return Scaffold(
      appBar: AppBar(
        title: Text('${isNew ? 'Nuevo' : 'Editar'} ${_typeLabel(type).toLowerCase()}'),
        actions: [
          TextButton(onPressed: _saving ? null : _save, child: const Text('Guardar')),
          const SizedBox(width: 8),
        ],
      ),
      body: MaxWidth(
        maxWidth: 800,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              FormCard(title: 'Datos', children: [
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                      labelText: 'Nombre *',
                      hintText: type == 'bundle'
                          ? 'Bono 10 sesiones'
                          : type == 'membership'
                              ? 'Cuota mensual ilimitada'
                              : 'Tarjeta regalo 50 €'),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Obligatorio' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _description,
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Descripción'),
                ),
                const SizedBox(height: 12),
                ResponsiveFields(children: [
                  TextFormField(
                    controller: _price,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: euroInputFormatters,
                    decoration: InputDecoration(
                        labelText: type == 'gift_card' ? 'Importe / saldo *' : 'Precio *',
                        suffixText: '€',
                        helperText: 'IVA incluido'),
                    validator: (v) => parseEuros(v ?? '') <= 0 ? 'Indica un importe' : null,
                  ),
                  DropdownButtonFormField<double>(
                    initialValue: _vat,
                    decoration: const InputDecoration(labelText: 'IVA'),
                    items: const [
                      DropdownMenuItem(value: 21, child: Text('21 %')),
                      DropdownMenuItem(value: 10, child: Text('10 %')),
                      DropdownMenuItem(value: 4, child: Text('4 %')),
                      DropdownMenuItem(value: 0, child: Text('0 % (exento)')),
                    ],
                    onChanged: (v) => setState(() => _vat = v ?? 21),
                  ),
                ]),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Activo (a la venta)'),
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                ),
              ]),
              const SizedBox(height: 12),
              if (type == 'bundle') _bundleCard(),
              if (type == 'membership') _membershipCard(),
              if (type == 'gift_card')
                FormCard(title: 'Validez', children: [
                  TextFormField(
                    controller: _validity,
                    keyboardType: TextInputType.number,
                    inputFormatters: intInputFormatters,
                    decoration: const InputDecoration(
                        labelText: 'Caducidad', suffixText: 'días', helperText: 'Vacío = sin caducidad'),
                  ),
                ]),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(isNew ? 'Crear' : 'Guardar cambios'),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bundleCard() {
    return FormCard(title: 'Sesiones y servicios', children: [
      ResponsiveFields(children: [
        TextFormField(
          controller: _sessions,
          keyboardType: TextInputType.number,
          inputFormatters: intInputFormatters,
          decoration: const InputDecoration(labelText: 'Nº de sesiones *'),
          validator: (v) => (int.tryParse(v ?? '') ?? 0) <= 0 ? 'Indica las sesiones' : null,
        ),
        TextFormField(
          controller: _validity,
          keyboardType: TextInputType.number,
          inputFormatters: intInputFormatters,
          decoration: const InputDecoration(
              labelText: 'Validez', suffixText: 'días', helperText: 'Vacío = sin caducidad'),
        ),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: Text('Servicios canjeables',
              style: Theme.of(context).textTheme.labelLarge),
        ),
        TextButton(
          onPressed: () => setState(() => _serviceIds.clear()),
          child: const Text('Cualquiera'),
        ),
      ]),
      Text(
          _serviceIds.isEmpty
              ? 'Sin selección = válido para cualquier servicio.'
              : '${_serviceIds.length} seleccionados',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.outline)),
      for (final s in widget.services)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(s.name),
          subtitle: Text('${Fmt.duration(s.durationMin)} · ${s.priceLabel}'),
          value: _serviceIds.contains(s.id),
          onChanged: (v) => setState(() {
            if (v == true) {
              _serviceIds.add(s.id);
            } else {
              _serviceIds.remove(s.id);
            }
          }),
        ),
    ]);
  }

  Widget _membershipCard() {
    return FormCard(title: 'Condiciones de la membresía', children: [
      ResponsiveFields(children: [
        DropdownButtonFormField<String>(
          initialValue: _period,
          decoration: const InputDecoration(labelText: 'Periodo'),
          items: const [
            DropdownMenuItem(value: 'monthly', child: Text('Mensual')),
            DropdownMenuItem(value: 'yearly', child: Text('Anual')),
          ],
          onChanged: (v) => setState(() => _period = v ?? 'monthly'),
        ),
        TextFormField(
          controller: _sessionsPerPeriod,
          keyboardType: TextInputType.number,
          inputFormatters: intInputFormatters,
          decoration: const InputDecoration(
              labelText: 'Sesiones por periodo', helperText: 'Vacío = ilimitadas'),
        ),
      ]),
      const SizedBox(height: 12),
      ResponsiveFields(children: [
        TextFormField(
          controller: _discount,
          keyboardType: TextInputType.number,
          inputFormatters: intInputFormatters,
          decoration: const InputDecoration(
              labelText: 'Descuento en otros servicios', suffixText: '%'),
        ),
        const SizedBox.shrink(),
      ]),
    ]);
  }
}

// ============================================================ Selector de cliente

class _CustomerPicker extends StatefulWidget {
  final String businessId;
  const _CustomerPicker({required this.businessId});
  @override
  State<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends State<_CustomerPicker> {
  final biz = AppSession.instance.biz;
  final _query = TextEditingController();
  List<Customer> _results = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() => _loading = true);
    try {
      final r = await biz.fetchCustomers(widget.businessId, query: _query.text, limit: 50);
      if (!mounted) return;
      setState(() {
        _results = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showSnack(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = AppSession.instance.customerLabel;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _query,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Buscar ${label.toLowerCase()} por nombre, email o teléfono',
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (_) => _search(),
            ),
          ),
          Expanded(
            child: _loading
                ? const LoadingView()
                : _results.isEmpty
                    ? const EmptyView(icon: Icons.person_search, title: 'Sin resultados')
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (_, i) {
                          final c = _results[i];
                          return ListTile(
                            leading: AvatarCircle(initials: c.initials),
                            title: Text(c.fullName),
                            subtitle: Text([c.phone, c.email].whereType<String>().join(' · ')),
                            onTap: () => Navigator.pop(context, c),
                          );
                        },
                      ),
          ),
        ]),
      ),
    );
  }
}
