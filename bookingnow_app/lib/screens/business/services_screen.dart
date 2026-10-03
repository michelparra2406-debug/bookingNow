import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/models.dart';
import '../../services/admin_extra.dart';
import '../../services/app_session.dart';
import '../../utils/format.dart';
import '../../utils/friendly_errors.dart';
import '../../widgets/admin_widgets.dart';
import '../../widgets/common.dart';

/// Catálogo de servicios del negocio: categorías, servicios y extras.
class ServicesScreen extends StatefulWidget {
  const ServicesScreen({super.key});
  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  final session = AppSession.instance;
  bool _loading = true;
  String? _error;
  List<ServiceCategory> _categories = [];
  List<Service> _services = [];
  List<ServiceAddon> _addons = [];

  String get _businessId => session.activeBusiness!.id;

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
      final biz = session.biz;
      final results = await Future.wait([
        biz.fetchCategories(_businessId),
        biz.fetchServices(_businessId),
        biz.fetchAddons(_businessId),
      ]);
      if (!mounted) return;
      setState(() {
        _categories = results[0] as List<ServiceCategory>;
        _services = results[1] as List<Service>;
        _addons = results[2] as List<ServiceAddon>;
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

  // ---------- Acciones sobre servicios ----------

  Future<void> _openEdit([Service? s]) async {
    final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => ServiceEditScreen(service: s)));
    if (changed == true) _load();
  }

  Future<void> _duplicate(Service s) async {
    try {
      final fields = s.toInsert()..['name'] = '${s.name} (copia)';
      await session.biz.saveService(
        fields: fields,
        variants: [
          for (final v in s.variants)
            {'name': v.name, 'duration_min': v.durationMin, 'price_cents': v.priceCents}
        ],
        staffIds: s.staffIds,
        addonIds: s.addons.map((a) => a.id).toList(),
      );
      if (!mounted) return;
      showSnack(context, 'Servicio duplicado');
      _load();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _toggleActive(Service s) async {
    try {
      await session.biz.updateServiceFields(s.id, {'active': !s.active});
      if (!mounted) return;
      showSnack(context, s.active ? 'Servicio desactivado' : 'Servicio activado');
      _load();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _delete(Service s) async {
    final ok = await confirmDialog(context,
        title: 'Eliminar servicio',
        message:
            '¿Eliminar "${s.name}"? Las reservas anteriores conservan su importe, pero el servicio dejará de ofrecerse.',
        confirmLabel: 'Eliminar',
        destructive: true);
    if (!ok || !mounted) return;
    try {
      await session.biz.deleteService(s.id);
      if (!mounted) return;
      showSnack(context, 'Servicio eliminado');
      _load();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, friendlyError(e), error: true);
    }
  }

  // ---------- Categorías ----------

  Future<void> _manageCategories() async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => _CategoriesSheet(
        businessId: _businessId,
        categories: _categories,
        onChanged: _load,
      ),
    );
  }

  // ---------- Extras ----------

  Future<void> _editAddon([ServiceAddon? a]) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _AddonDialog(addon: a),
    );
    if (result == null || !mounted) return;
    try {
      await session.biz.upsertAddon({
        if (a != null) 'id': a.id,
        'business_id': _businessId,
        ...result,
      });
      if (!mounted) return;
      showSnack(context, 'Extra guardado');
      _load();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _deleteAddon(ServiceAddon a) async {
    final ok = await confirmDialog(context,
        title: 'Eliminar extra',
        message: '¿Eliminar "${a.name}"?',
        confirmLabel: 'Eliminar',
        destructive: true);
    if (!ok || !mounted) return;
    try {
      await session.biz.deleteAddon(a.id);
      if (!mounted) return;
      _load();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, friendlyError(e), error: true);
    }
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Servicios'),
        actions: [
          IconButton(
            tooltip: 'Categorías',
            icon: const Icon(Icons.category_outlined),
            onPressed: _loading ? null : _manageCategories,
          ),
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEdit(),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo servicio'),
      ),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(_error!, onRetry: _load)
              : RefreshIndicator(onRefresh: _load, child: _buildList()),
    );
  }

  Widget _buildList() {
    final t = Theme.of(context);
    final groups = <String?, List<Service>>{};
    for (final c in _categories) {
      groups[c.id] = [];
    }
    groups[null] = [];
    for (final s in _services) {
      (groups[s.categoryId] ?? groups[null]!).add(s);
    }
    final empty = _services.isEmpty;

    return MaxWidth(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          if (empty)
            EmptyView(
              icon: Icons.design_services_outlined,
              title: 'Aún no tienes servicios',
              subtitle:
                  'Crea tu primer servicio para que tus clientes puedan reservar.',
              action: FilledButton.icon(
                onPressed: () => _openEdit(),
                icon: const Icon(Icons.add),
                label: const Text('Nuevo servicio'),
              ),
            ),
          for (final c in _categories)
            if (groups[c.id]!.isNotEmpty) ...[
              SectionTitle(c.name,
                  trailing: Text('${groups[c.id]!.length}',
                      style: t.textTheme.labelMedium
                          ?.copyWith(color: t.colorScheme.outline))),
              Card(
                child: Column(children: [
                  for (var i = 0; i < groups[c.id]!.length; i++) ...[
                    if (i > 0) const Divider(indent: 56),
                    _serviceTile(groups[c.id]![i]),
                  ],
                ]),
              ),
            ],
          if (groups[null]!.isNotEmpty) ...[
            const SectionTitle('Sin categoría'),
            Card(
              child: Column(children: [
                for (var i = 0; i < groups[null]!.length; i++) ...[
                  if (i > 0) const Divider(indent: 56),
                  _serviceTile(groups[null]![i]),
                ],
              ]),
            ),
          ],
          SectionTitle('Extras',
              trailing: TextButton.icon(
                onPressed: () => _editAddon(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Añadir'),
              )),
          Card(
            child: _addons.isEmpty
                ? const InlineEmpty(
                    'Sin extras. Los extras son complementos que el cliente puede añadir a un servicio (p. ej. "Tratamiento hidratante +10 €").')
                : Column(children: [
                    for (var i = 0; i < _addons.length; i++) ...[
                      if (i > 0) const Divider(indent: 16),
                      ListTile(
                        title: Text(_addons[i].name),
                        subtitle: Text(
                            '${_addons[i].durationMin > 0 ? '+${Fmt.duration(_addons[i].durationMin)} · ' : ''}+${formatEuros(_addons[i].priceCents)}'
                            '${_addons[i].active ? '' : ' · Inactivo'}'),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _editAddon(_addons[i])),
                          IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _deleteAddon(_addons[i])),
                        ]),
                      ),
                    ],
                  ]),
          ),
        ],
      ),
    );
  }

  Widget _serviceTile(Service s) {
    final t = Theme.of(context);
    final color = hexColor(s.color);
    return Dismissible(
      key: ValueKey(s.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        await _openEdit(s);
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: t.colorScheme.primary.withValues(alpha: 0.12),
        child: const Icon(Icons.edit_outlined),
      ),
      child: ListTile(
        onTap: () => _openEdit(s),
        leading: Container(
          width: 12,
          height: 40,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(4)),
        ),
        title: Text(s.name,
            style: TextStyle(
                fontWeight: FontWeight.w600,
                color: s.active ? null : t.colorScheme.outline)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              '${Fmt.duration(s.durationMin)} · ${s.priceLabel} · ${s.staffIds.length} ${s.staffIds.length == 1 ? 'profesional' : 'profesionales'}'
              '${s.variants.isNotEmpty ? ' · ${s.variants.length} variantes' : ''}'),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 4, children: [
            if (s.onlineBookable)
              const SmallBadge('Online', icon: Icons.public, color: AppTheme.primary),
            if (s.requiresDeposit)
              const SmallBadge('Señal', icon: Icons.savings_outlined, color: AppTheme.warning),
            if (s.capacity > 1)
              SmallBadge('Grupal · ${s.capacity}', icon: Icons.groups_outlined, color: AppTheme.accent),
            if (!s.active)
              const SmallBadge('Inactivo', icon: Icons.visibility_off_outlined, color: Colors.grey),
          ]),
        ]),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            switch (v) {
              case 'edit':
                _openEdit(s);
              case 'dup':
                _duplicate(s);
              case 'toggle':
                _toggleActive(s);
              case 'delete':
                _delete(s);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Editar')),
            const PopupMenuItem(value: 'dup', child: Text('Duplicar')),
            PopupMenuItem(
                value: 'toggle', child: Text(s.active ? 'Desactivar' : 'Activar')),
            const PopupMenuItem(
                value: 'delete',
                child: Text('Eliminar', style: TextStyle(color: AppTheme.danger))),
          ],
        ),
      ),
    );
  }
}

// ============================================================ Categorías

class _CategoriesSheet extends StatefulWidget {
  final String businessId;
  final List<ServiceCategory> categories;
  final VoidCallback onChanged;
  const _CategoriesSheet(
      {required this.businessId,
      required this.categories,
      required this.onChanged});
  @override
  State<_CategoriesSheet> createState() => _CategoriesSheetState();
}

class _CategoriesSheetState extends State<_CategoriesSheet> {
  late List<ServiceCategory> _cats = List.of(widget.categories);
  final biz = AppSession.instance.biz;

  Future<void> _edit([ServiceCategory? c]) async {
    final ctrl = TextEditingController(text: c?.name ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(c == null ? 'Nueva categoría' : 'Renombrar categoría'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Nombre'),
          onSubmitted: (v) => Navigator.pop(d, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(d, ctrl.text),
              child: const Text('Guardar')),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    try {
      await biz.upsertCategory({
        if (c != null) 'id': c.id,
        'business_id': widget.businessId,
        'name': name.trim(),
        if (c == null) 'sort_order': (_cats.length + 1) * 10,
      });
      if (!mounted) return;
      _cats = await biz.fetchCategories(widget.businessId);
      if (!mounted) return;
      setState(() {});
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _delete(ServiceCategory c) async {
    final ok = await confirmDialog(context,
        title: 'Eliminar categoría',
        message:
            '¿Eliminar "${c.name}"? Los servicios de esta categoría pasarán a "Sin categoría".',
        confirmLabel: 'Eliminar',
        destructive: true);
    if (!ok || !mounted) return;
    try {
      await biz.deleteCategory(c.id);
      if (!mounted) return;
      setState(() => _cats.removeWhere((x) => x.id == c.id));
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(
                child: Text('Categorías',
                    style: Theme.of(context).textTheme.titleLarge)),
            TextButton.icon(
                onPressed: () => _edit(),
                icon: const Icon(Icons.add),
                label: const Text('Nueva')),
          ]),
          if (_cats.isEmpty) const InlineEmpty('Sin categorías todavía.'),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final c in _cats)
                ListTile(
                  leading: const Icon(Icons.label_outline),
                  title: Text(c.name),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _edit(c)),
                    IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _delete(c)),
                  ]),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ============================================================ Extras

class _AddonDialog extends StatefulWidget {
  final ServiceAddon? addon;
  const _AddonDialog({this.addon});
  @override
  State<_AddonDialog> createState() => _AddonDialogState();
}

class _AddonDialogState extends State<_AddonDialog> {
  late final _name = TextEditingController(text: widget.addon?.name ?? '');
  late final _duration =
      TextEditingController(text: '${widget.addon?.durationMin ?? 0}');
  late final _price =
      TextEditingController(text: centsToInput(widget.addon?.priceCents ?? 0));
  late bool _active = widget.addon?.active ?? true;

  @override
  void dispose() {
    _name.dispose();
    _duration.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.addon == null ? 'Nuevo extra' : 'Editar extra'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Nombre'),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _duration,
                keyboardType: TextInputType.number,
                inputFormatters: intInputFormatters,
                decoration: const InputDecoration(
                    labelText: 'Duración extra', suffixText: 'min'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: euroInputFormatters,
                decoration: const InputDecoration(labelText: 'Precio', suffixText: '€'),
              ),
            ),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Activo'),
            value: _active,
            onChanged: (v) => setState(() => _active = v),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (_name.text.trim().isEmpty) return;
            Navigator.pop(context, {
              'name': _name.text.trim(),
              'duration_min': int.tryParse(_duration.text) ?? 0,
              'price_cents': parseEuros(_price.text),
              'active': _active,
            });
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

// ============================================================ Edición

/// Alta / edición de un servicio con variantes, profesionales y extras.
class ServiceEditScreen extends StatefulWidget {
  final Service? service;
  const ServiceEditScreen({super.key, this.service});
  @override
  State<ServiceEditScreen> createState() => _ServiceEditScreenState();
}

class _VariantDraft {
  final TextEditingController name;
  final TextEditingController duration;
  final TextEditingController price;
  _VariantDraft({String name = '', int duration = 30, int price = 0})
      : name = TextEditingController(text: name),
        duration = TextEditingController(text: '$duration'),
        price = TextEditingController(text: centsToInput(price));
  void dispose() {
    name.dispose();
    duration.dispose();
    price.dispose();
  }
}

class _ServiceEditScreenState extends State<ServiceEditScreen> {
  final session = AppSession.instance;
  final _formKey = GlobalKey<FormState>();

  late final _name = TextEditingController(text: widget.service?.name ?? '');
  late final _description =
      TextEditingController(text: widget.service?.description ?? '');
  late final _duration =
      TextEditingController(text: '${widget.service?.durationMin ?? 30}');
  late final _price =
      TextEditingController(text: centsToInput(widget.service?.priceCents ?? 0));
  late final _bufferBefore =
      TextEditingController(text: '${widget.service?.bufferBeforeMin ?? 0}');
  late final _bufferAfter =
      TextEditingController(text: '${widget.service?.bufferAfterMin ?? 0}');
  late final _capacity =
      TextEditingController(text: '${widget.service?.capacity ?? 1}');
  late final _deposit = TextEditingController(
      text: widget.service?.depositCents == null
          ? ''
          : centsToInput(widget.service!.depositCents!));

  late String? _categoryId = widget.service?.categoryId;
  late String _priceType = widget.service?.priceType ?? 'fixed';
  late double _vat = widget.service?.vatPct ?? 21;
  late bool _online = widget.service?.onlineBookable ?? true;
  late bool _requiresDeposit = widget.service?.requiresDeposit ?? false;
  late String? _color = widget.service?.color ?? adminColorPresets.first;
  late bool _active = widget.service?.active ?? true;
  late final List<_VariantDraft> _variants = [
    for (final v in widget.service?.variants ?? const <ServiceVariant>[])
      _VariantDraft(name: v.name, duration: v.durationMin, price: v.priceCents)
  ];
  late final Set<String> _staffIds = {...?widget.service?.staffIds};
  late final Set<String> _addonIds = {
    for (final a in widget.service?.addons ?? const <ServiceAddon>[]) a.id
  };

  List<ServiceCategory> _categories = [];
  List<Member> _members = [];
  List<ServiceAddon> _addons = [];
  bool _loading = true;
  bool _saving = false;

  String get _businessId => session.activeBusiness!.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _name, _description, _duration, _price, _bufferBefore, _bufferAfter,
      _capacity, _deposit,
    ]) {
      c.dispose();
    }
    for (final v in _variants) {
      v.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final biz = session.biz;
      final results = await Future.wait([
        biz.fetchCategories(_businessId),
        biz.fetchMembers(_businessId, onlyActive: true),
        biz.fetchAddons(_businessId),
      ]);
      if (!mounted) return;
      setState(() {
        _categories = results[0] as List<ServiceCategory>;
        _members = (results[1] as List<Member>).where((m) => m.bookable).toList();
        _addons = results[2] as List<ServiceAddon>;
        if (widget.service == null) {
          _staffIds.addAll(_members.map((m) => m.id));
        }
        if (_categoryId != null && !_categories.any((c) => c.id == _categoryId)) {
          _categoryId = null;
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
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final fields = <String, dynamic>{
        'business_id': _businessId,
        'category_id': _categoryId,
        'name': _name.text.trim(),
        'description':
            _description.text.trim().isEmpty ? null : _description.text.trim(),
        'duration_min': int.tryParse(_duration.text) ?? 30,
        'buffer_before_min': int.tryParse(_bufferBefore.text) ?? 0,
        'buffer_after_min': int.tryParse(_bufferAfter.text) ?? 0,
        'price_cents': _priceType == 'free' ? 0 : parseEuros(_price.text),
        'price_type': _priceType,
        'vat_pct': _vat,
        'capacity': (int.tryParse(_capacity.text) ?? 1).clamp(1, 999),
        'online_bookable': _online,
        'requires_deposit': _requiresDeposit,
        'deposit_cents': _requiresDeposit && _deposit.text.trim().isNotEmpty
            ? parseEuros(_deposit.text)
            : null,
        'color': _color,
        'active': _active,
        if (widget.service != null) 'sort_order': widget.service!.sortOrder,
      };
      await session.biz.saveService(
        id: widget.service?.id,
        fields: fields,
        variants: [
          for (final v in _variants)
            if (v.name.text.trim().isNotEmpty)
              {
                'name': v.name.text.trim(),
                'duration_min': int.tryParse(v.duration.text) ?? 30,
                'price_cents': parseEuros(v.price.text),
              }
        ],
        staffIds: _staffIds.toList(),
        addonIds: _addonIds.toList(),
      );
      if (!mounted) return;
      showSnack(context, 'Servicio guardado');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.service == null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'Nuevo servicio' : 'Editar servicio'),
        actions: [
          TextButton(
            onPressed: _saving || _loading ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Guardar'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const LoadingView()
          : MaxWidth(
              maxWidth: 900,
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _basicsCard(),
                    const SizedBox(height: 12),
                    _pricingCard(),
                    const SizedBox(height: 12),
                    _schedulingCard(),
                    const SizedBox(height: 12),
                    _variantsCard(),
                    const SizedBox(height: 12),
                    _staffCard(),
                    const SizedBox(height: 12),
                    _addonsCard(),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(isNew ? 'Crear servicio' : 'Guardar cambios'),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _basicsCard() {
    return FormCard(title: 'Datos básicos', children: [
      TextFormField(
        controller: _name,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'Nombre del servicio *'),
        validator: (v) => (v ?? '').trim().isEmpty ? 'Obligatorio' : null,
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _description,
        maxLines: 3,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
            labelText: 'Descripción', hintText: 'Se muestra al cliente al reservar'),
      ),
      const SizedBox(height: 12),
      ResponsiveFields(children: [
        DropdownButtonFormField<String?>(
          initialValue: _categoryId,
          decoration: const InputDecoration(labelText: 'Categoría'),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('Sin categoría')),
            for (final c in _categories)
              DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
          ],
          onChanged: (v) => setState(() => _categoryId = v),
        ),
        TextFormField(
          controller: _duration,
          keyboardType: TextInputType.number,
          inputFormatters: intInputFormatters,
          decoration: const InputDecoration(labelText: 'Duración *', suffixText: 'min'),
          validator: (v) =>
              (int.tryParse(v ?? '') ?? 0) <= 0 ? 'Indica una duración' : null,
        ),
      ]),
      const SizedBox(height: 16),
      Text('Color en la agenda', style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 8),
      ColorPresetPicker(value: _color, onChanged: (c) => setState(() => _color = c)),
      const SizedBox(height: 8),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Servicio activo'),
        subtitle: const Text('Los servicios inactivos no se pueden reservar'),
        value: _active,
        onChanged: (v) => setState(() => _active = v),
      ),
    ]);
  }

  Widget _pricingCard() {
    return FormCard(title: 'Precio e IVA', children: [
      ResponsiveFields(children: [
        DropdownButtonFormField<String>(
          initialValue: _priceType,
          decoration: const InputDecoration(labelText: 'Tipo de precio'),
          items: const [
            DropdownMenuItem(value: 'fixed', child: Text('Precio fijo')),
            DropdownMenuItem(value: 'from', child: Text('Desde (precio mínimo)')),
            DropdownMenuItem(value: 'free', child: Text('Gratis')),
            DropdownMenuItem(value: 'variable', child: Text('A consultar')),
          ],
          onChanged: (v) => setState(() => _priceType = v ?? 'fixed'),
        ),
        TextFormField(
          controller: _price,
          enabled: _priceType != 'free',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: euroInputFormatters,
          decoration: InputDecoration(
              labelText: _priceType == 'from' ? 'Precio desde' : 'Precio',
              suffixText: '€',
              helperText: 'IVA incluido'),
        ),
      ]),
      const SizedBox(height: 12),
      ResponsiveFields(children: [
        DropdownButtonFormField<double>(
          initialValue: _vat,
          decoration: const InputDecoration(labelText: 'IVA'),
          items: const [
            DropdownMenuItem(value: 21, child: Text('21 % (general)')),
            DropdownMenuItem(value: 10, child: Text('10 % (reducido)')),
            DropdownMenuItem(value: 4, child: Text('4 % (superreducido)')),
            DropdownMenuItem(value: 0, child: Text('0 % (exento)')),
          ],
          onChanged: (v) => setState(() => _vat = v ?? 21),
        ),
        const SizedBox.shrink(),
      ]),
      const SizedBox(height: 8),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Requiere señal al reservar'),
        subtitle: const Text(
            'Protege contra no-shows. Si no indicas importe se aplica el % de señal del negocio.'),
        value: _requiresDeposit,
        onChanged: (v) => setState(() => _requiresDeposit = v),
      ),
      if (_requiresDeposit)
        TextFormField(
          controller: _deposit,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: euroInputFormatters,
          decoration: const InputDecoration(
              labelText: 'Señal fija (opcional)', suffixText: '€'),
        ),
    ]);
  }

  Widget _schedulingCard() {
    return FormCard(title: 'Agenda y reservas', children: [
      ResponsiveFields(children: [
        TextFormField(
          controller: _bufferBefore,
          keyboardType: TextInputType.number,
          inputFormatters: intInputFormatters,
          decoration: const InputDecoration(
              labelText: 'Margen antes',
              suffixText: 'min',
              helperText: 'Preparación previa'),
        ),
        TextFormField(
          controller: _bufferAfter,
          keyboardType: TextInputType.number,
          inputFormatters: intInputFormatters,
          decoration: const InputDecoration(
              labelText: 'Margen después',
              suffixText: 'min',
              helperText: 'Limpieza / descanso'),
        ),
      ]),
      const SizedBox(height: 12),
      ResponsiveFields(children: [
        TextFormField(
          controller: _capacity,
          keyboardType: TextInputType.number,
          inputFormatters: intInputFormatters,
          decoration: const InputDecoration(
              labelText: 'Plazas por sesión',
              helperText: 'Más de 1 = sesión grupal / clase'),
        ),
        const SizedBox.shrink(),
      ]),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Reservable online'),
        subtitle: const Text('Visible en la página pública y en la app de clientes'),
        value: _online,
        onChanged: (v) => setState(() => _online = v),
      ),
    ]);
  }

  Widget _variantsCard() {
    return FormCard(
      title: 'Variantes',
      trailing: TextButton.icon(
        onPressed: () => setState(() => _variants.add(_VariantDraft(
            duration: int.tryParse(_duration.text) ?? 30,
            price: parseEuros(_price.text)))),
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Añadir'),
      ),
      children: [
        if (_variants.isEmpty)
          const InlineEmpty(
              'Opcional. Ej.: "Pelo corto · 30 min" / "Pelo largo · 45 min". Cada variante tiene su duración y precio.'),
        for (var i = 0; i < _variants.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: LayoutBuilder(builder: (context, c) {
              final narrow = c.maxWidth < 520;
              final nameField = TextFormField(
                controller: _variants[i].name,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Nombre'),
              );
              final durField = TextFormField(
                controller: _variants[i].duration,
                keyboardType: TextInputType.number,
                inputFormatters: intInputFormatters,
                decoration: const InputDecoration(labelText: 'Min'),
              );
              final priceField = TextFormField(
                controller: _variants[i].price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: euroInputFormatters,
                decoration: const InputDecoration(labelText: '€'),
              );
              final remove = IconButton(
                icon: const Icon(Icons.remove_circle_outline, color: AppTheme.danger),
                onPressed: () => setState(() => _variants.removeAt(i).dispose()),
              );
              if (narrow) {
                return Column(children: [
                  Row(children: [Expanded(child: nameField), remove]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: durField),
                    const SizedBox(width: 8),
                    Expanded(child: priceField),
                  ]),
                ]);
              }
              return Row(children: [
                Expanded(flex: 3, child: nameField),
                const SizedBox(width: 8),
                Expanded(child: durField),
                const SizedBox(width: 8),
                Expanded(child: priceField),
                remove,
              ]);
            }),
          ),
      ],
    );
  }

  Widget _staffCard() {
    final label = pluralEs(session.staffLabel);
    return FormCard(
      title: '$label que lo realizan',
      trailing: TextButton(
        onPressed: () => setState(() {
          if (_staffIds.length == _members.length) {
            _staffIds.clear();
          } else {
            _staffIds.addAll(_members.map((m) => m.id));
          }
        }),
        child: Text(_staffIds.length == _members.length ? 'Ninguno' : 'Todos'),
      ),
      children: [
        if (_members.isEmpty)
          const InlineEmpty('No hay profesionales reservables. Añádelos en Equipo.'),
        for (final m in _members)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            secondary: AvatarCircle(
                url: m.avatarUrl,
                initials: m.displayName.isEmpty ? '?' : m.displayName[0],
                color: hexColor(m.color),
                radius: 16),
            title: Text(m.displayName),
            subtitle: m.title == null ? null : Text(m.title!),
            value: _staffIds.contains(m.id),
            onChanged: (v) => setState(() {
              if (v == true) {
                _staffIds.add(m.id);
              } else {
                _staffIds.remove(m.id);
              }
            }),
          ),
      ],
    );
  }

  Widget _addonsCard() {
    return FormCard(title: 'Extras disponibles', children: [
      if (_addons.isEmpty)
        const InlineEmpty('Sin extras. Créalos desde la pantalla de Servicios.'),
      for (final a in _addons.where((a) => a.active || _addonIds.contains(a.id)))
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(a.name),
          subtitle: Text(
              '${a.durationMin > 0 ? '+${Fmt.duration(a.durationMin)} · ' : ''}+${formatEuros(a.priceCents)}'),
          value: _addonIds.contains(a.id),
          onChanged: (v) => setState(() {
            if (v == true) {
              _addonIds.add(a.id);
            } else {
              _addonIds.remove(a.id);
            }
          }),
        ),
    ]);
  }
}
