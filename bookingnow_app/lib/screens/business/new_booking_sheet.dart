import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/app_session.dart';
import '../../utils/format.dart';
import '../../utils/friendly_errors.dart';
import '../../widgets/common.dart';

/// Abre el formulario de alta manual de cita en una hoja modal.
Future<void> showNewBookingSheet(
  BuildContext context, {
  DateTime? initialDate,
  String? memberId,
  String? customerId,
  VoidCallback? onCreated,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (_) => NewBookingSheet(
        initialDate: initialDate,
        memberId: memberId,
        customerId: customerId,
        onCreated: onCreated),
  );
}

class _Selection {
  final Service service;
  ServiceVariant? variant;
  _Selection(this.service, this.variant);
  int get durationMin => variant?.durationMin ?? service.durationMin;
  int get priceCents => variant?.priceCents ?? service.priceCents;
}

/// Alta manual de una reserva (walk-in, teléfono) desde la agenda.
class NewBookingSheet extends StatefulWidget {
  final DateTime? initialDate;
  final String? memberId;
  final String? customerId;
  final VoidCallback? onCreated;
  const NewBookingSheet(
      {super.key, this.initialDate, this.memberId, this.customerId, this.onCreated});

  @override
  State<NewBookingSheet> createState() => _NewBookingSheetState();
}

class _NewBookingSheetState extends State<NewBookingSheet> {
  final session = AppSession.instance;
  String get _bizId => session.activeBusiness!.id;

  bool _loading = true;
  String? _error;
  bool _busy = false;

  // Cliente
  Customer? _customer;
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<Customer> _results = [];
  bool _searching = false;
  bool _creatingNew = false;
  final _newName = TextEditingController();
  final _newPhone = TextEditingController();

  // Servicios
  List<Service> _services = [];
  final List<_Selection> _selected = [];

  // Profesional
  List<Member> _members = [];
  String? _memberId;

  // Fecha / hora
  late DateTime _date;
  TimeOfDay? _time;
  bool _manualTime = false;
  List<Slot> _slots = [];
  bool _loadingSlots = false;

  final _notesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final d = widget.initialDate ?? DateTime.now();
    _date = DateTime(d.year, d.month, d.day);
    if (widget.initialDate != null) {
      _time = TimeOfDay.fromDateTime(widget.initialDate!);
      _manualTime = true;
    }
    _memberId = widget.memberId;
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _newName.dispose();
    _newPhone.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        session.biz.fetchServices(_bizId, includeInactive: false),
        session.biz.fetchMembers(_bizId, onlyActive: true),
        if (widget.customerId != null) session.biz.fetchCustomer(widget.customerId!),
      ]);
      if (!mounted) return;
      setState(() {
        _services = results[0] as List<Service>;
        _members = (results[1] as List<Member>).where((m) => m.bookable).toList();
        if (results.length > 2) _customer = results[2] as Customer?;
        if (_memberId != null && !_members.any((m) => m.id == _memberId)) _memberId = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyError(e);
      });
    }
  }

  // ---------- Cliente ----------

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(q));
  }

  Future<void> _search(String q) async {
    if (q.trim().length < 2) {
      setState(() => _results = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final r = await session.biz.fetchCustomers(_bizId, query: q, limit: 20);
      if (!mounted) return;
      setState(() => _results = r);
    } catch (e) {
      if (!mounted) return;
      showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _createCustomer() async {
    final name = _newName.text.trim();
    if (name.isEmpty) {
      showSnack(context, 'Indica el nombre', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final c = await session.biz.upsertCustomer({
        'business_id': _bizId,
        'full_name': name,
        'phone': _newPhone.text.trim().isEmpty ? null : _newPhone.text.trim(),
        'source': 'manual',
      });
      if (!mounted) return;
      setState(() {
        _customer = c;
        _creatingNew = false;
      });
    } catch (e) {
      if (!mounted) return;
      showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------- Servicios ----------

  void _toggleService(Service s) {
    setState(() {
      final i = _selected.indexWhere((x) => x.service.id == s.id);
      if (i >= 0) {
        _selected.removeAt(i);
      } else {
        _selected.add(_Selection(s, s.variants.isEmpty ? null : s.variants.first));
      }
    });
    _reloadSlots();
  }

  int get _totalMin => _selected.fold(0, (a, s) => a + s.durationMin);
  int get _totalCents => _selected.fold(0, (a, s) => a + s.priceCents);

  // ---------- Huecos ----------

  Future<void> _reloadSlots() async {
    if (_selected.isEmpty) {
      setState(() => _slots = []);
      return;
    }
    setState(() => _loadingSlots = true);
    try {
      final slots = await session.biz.fetchSlots(
        businessId: _bizId,
        serviceId: _selected.first.service.id,
        date: _date,
        memberId: _memberId,
      );
      if (!mounted) return;
      setState(() => _slots = slots);
    } catch (e) {
      if (!mounted) return;
      setState(() => _slots = []);
      showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _loadingSlots = false);
    }
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d == null || !mounted) return;
    setState(() {
      _date = DateTime(d.year, d.month, d.day);
      if (!_manualTime) _time = null;
    });
    _reloadSlots();
  }

  Future<void> _pickManualTime() async {
    final t = await showTimePicker(
        context: context, initialTime: _time ?? const TimeOfDay(hour: 10, minute: 0));
    if (t == null || !mounted) return;
    setState(() {
      _time = t;
      _manualTime = true;
    });
  }

  // ---------- Crear ----------

  Future<void> _create() async {
    if (_customer == null) {
      showSnack(context, 'Selecciona un ${session.customerLabel.toLowerCase()}', error: true);
      return;
    }
    if (_selected.isEmpty) {
      showSnack(context, 'Añade al menos un servicio', error: true);
      return;
    }
    if (_time == null) {
      showSnack(context, 'Elige una hora', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final starts = DateTime(_date.year, _date.month, _date.day, _time!.hour, _time!.minute);
      await session.biz.createBooking(
        businessId: _bizId,
        customerId: _customer!.id,
        memberId: _memberId,
        startsAt: starts,
        items: [
          for (final s in _selected)
            {'service_id': s.service.id, if (s.variant != null) 'variant_id': s.variant!.id},
        ],
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );
      if (!mounted) return;
      widget.onCreated?.call();
      Navigator.of(context).pop();
      showSnack(context, '${session.bookingLabel} creada');
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
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    if (_loading) return const SizedBox(height: 240, child: LoadingView());
    if (_error != null) {
      return SizedBox(height: 240, child: ErrorView(_error!, onRetry: _load));
    }
    final t = Theme.of(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Nueva ${session.bookingLabel.toLowerCase()}',
            style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        SectionTitle(session.customerLabel),
        _customerSection(t),
        const SectionTitle('Servicios'),
        _servicesSection(t),
        SectionTitle(session.staffLabel),
        DropdownButtonFormField<String?>(
          key: ValueKey(_memberId),
          initialValue: _memberId,
          decoration: const InputDecoration(),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('Cualquiera disponible')),
            for (final m in _members)
              DropdownMenuItem<String?>(
                value: m.id,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                      width: 10,
                      height: 10,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(color: hexColor(m.color), shape: BoxShape.circle)),
                  Text(m.displayName),
                ]),
              ),
          ],
          onChanged: (v) {
            setState(() => _memberId = v);
            _reloadSlots();
          },
        ),
        const SectionTitle('Fecha y hora'),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today_outlined, size: 18),
              label: Text(Fmt.dayShort(_date)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _pickManualTime,
              icon: const Icon(Icons.access_time, size: 18),
              label: Text(_time == null ? 'Hora manual' : _time!.format(context)),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        _slotsSection(t),
        const SectionTitle('Notas internas'),
        TextField(
          controller: _notesCtrl,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Opcional'),
        ),
        const SizedBox(height: 20),
        if (_selected.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Text('Total: ${formatEuros(_totalCents)}',
                  style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const Spacer(),
              Text(Fmt.duration(_totalMin), style: t.textTheme.bodyMedium),
            ]),
          ),
        FilledButton.icon(
          onPressed: _busy ? null : _create,
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.check),
          label: Text('Crear ${session.bookingLabel.toLowerCase()}'),
        ),
      ]),
    );
  }

  Widget _customerSection(ThemeData t) {
    if (_customer != null) {
      final c = _customer!;
      return Card(
        child: ListTile(
          leading: AvatarCircle(initials: c.initials),
          title: Text(c.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text([c.phone, c.email].whereType<String>().join(' · ')),
          trailing: widget.customerId == null
              ? IconButton(
                  tooltip: 'Cambiar',
                  onPressed: () => setState(() => _customer = null),
                  icon: const Icon(Icons.close))
              : null,
        ),
      );
    }
    if (_creatingNew) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
                controller: _newName,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nombre completo')),
            const SizedBox(height: 10),
            TextField(
                controller: _newPhone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Teléfono (opcional)')),
            const SizedBox(height: 10),
            Row(children: [
              TextButton(
                  onPressed: () => setState(() => _creatingNew = false),
                  child: const Text('Cancelar')),
              const Spacer(),
              FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(120, 44)),
                  onPressed: _busy ? null : _createCustomer,
                  child: const Text('Crear')),
            ]),
          ]),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _searchCtrl,
        onChanged: _onSearchChanged,
        decoration: InputDecoration(
          hintText: 'Buscar por nombre, teléfono o email',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searching
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
              : null,
        ),
      ),
      if (_results.isNotEmpty)
        Card(
          margin: const EdgeInsets.only(top: 8),
          child: Column(children: [
            for (final c in _results.take(8))
              ListTile(
                dense: true,
                leading: AvatarCircle(initials: c.initials, radius: 16),
                title: Text(c.fullName),
                subtitle: Text([c.phone, c.email].whereType<String>().join(' · ')),
                onTap: () => setState(() {
                  _customer = c;
                  _results = [];
                  _searchCtrl.clear();
                }),
              ),
          ]),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() {
            _creatingNew = true;
            _newName.text = _searchCtrl.text;
          }),
          icon: const Icon(Icons.person_add_alt_1_outlined),
          label: Text('Crear nuevo ${session.customerLabel.toLowerCase()}'),
        ),
      ),
    ]);
  }

  Widget _servicesSection(ThemeData t) {
    if (_services.isEmpty) {
      return Text('No hay servicios activos. Créalos en la sección Servicios.',
          style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.outline));
    }
    return Card(
      child: Column(children: [
        for (final s in _services) ...[
          CheckboxListTile(
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            value: _selected.any((x) => x.service.id == s.id),
            title: Text(s.name),
            subtitle: Text('${Fmt.duration(s.durationMin)} · ${s.priceLabel}'),
            onChanged: (_) => _toggleService(s),
          ),
          if (s.variants.isNotEmpty && _selected.any((x) => x.service.id == s.id))
            Padding(
              padding: const EdgeInsets.only(left: 48, right: 8, bottom: 6),
              child: RadioGroup<String>(
                groupValue: _selected.firstWhere((x) => x.service.id == s.id).variant?.id,
                onChanged: (id) {
                  if (id == null) return;
                  setState(() => _selected.firstWhere((x) => x.service.id == s.id).variant =
                      s.variants.firstWhere((v) => v.id == id));
                  _reloadSlots();
                },
                child: Column(children: [
                  for (final v in s.variants)
                    RadioListTile<String>(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      contentPadding: EdgeInsets.zero,
                      value: v.id,
                      title: Text(v.name),
                      subtitle: Text('${Fmt.duration(v.durationMin)} · ${formatEuros(v.priceCents)}'),
                    ),
                ]),
              ),
            ),
        ],
      ]),
    );
  }

  Widget _slotsSection(ThemeData t) {
    if (_selected.isEmpty) {
      return Text('Elige un servicio para ver los huecos disponibles.',
          style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline));
    }
    if (_loadingSlots) {
      return const Padding(
          padding: EdgeInsets.all(12),
          child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))));
    }
    // Agrupar por hora de inicio (si no se ha elegido profesional, puede haber
    // varios huecos a la misma hora con distinto profesional).
    final byTime = <String, Slot>{};
    for (final s in _slots) {
      byTime.putIfAbsent(Fmt.time(s.startsAt), () => s);
    }
    if (byTime.isEmpty) {
      return Text('Sin huecos libres ese día. Puedes fijar una hora manual.',
          style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Huecos disponibles', style: t.textTheme.labelLarge),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final e in byTime.entries)
          ChoiceChip(
            label: Text(e.key),
            selected: !_manualTime &&
                _time != null &&
                _time!.hour == e.value.startsAt.hour &&
                _time!.minute == e.value.startsAt.minute,
            onSelected: (_) => setState(() {
              _time = TimeOfDay.fromDateTime(e.value.startsAt);
              _manualTime = false;
              _memberId ??= e.value.memberId;
            }),
          ),
      ]),
    ]);
  }
}
