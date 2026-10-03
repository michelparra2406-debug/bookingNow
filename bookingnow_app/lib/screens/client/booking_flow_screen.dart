import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../app_theme.dart';
import '../../models/models.dart';
import '../../services/app_session.dart';
import '../../utils/format.dart';
import '../../utils/friendly_errors.dart';
import '../../widgets/common.dart';
import 'client_shell.dart';

/// Selección de un servicio dentro del asistente de reserva.
class _Selection {
  final Service service;
  ServiceVariant? variant;
  final Set<String> addonIds = {};
  _Selection(this.service);

  int get durationMin =>
      (variant?.durationMin ?? service.durationMin) +
      service.addons
          .where((a) => addonIds.contains(a.id))
          .fold(0, (acc, a) => acc + a.durationMin);

  int get priceCents =>
      (variant?.priceCents ?? (service.priceType == 'free' ? 0 : service.priceCents)) +
      service.addons
          .where((a) => addonIds.contains(a.id))
          .fold(0, (acc, a) => acc + a.priceCents);

  bool get needsVariant => service.variants.isNotEmpty && variant == null;

  Map<String, dynamic> toItem() => {
        'service_id': service.id,
        'variant_id': variant?.id,
        'addon_ids': addonIds.toList(),
      };
}

/// Asistente de reserva en 4 pasos.
class BookingFlowScreen extends StatefulWidget {
  final Business business;
  final List<Service> services;
  final List<Member> members;
  final Service? initialService;
  const BookingFlowScreen({
    super.key,
    required this.business,
    required this.services,
    required this.members,
    this.initialService,
  });
  @override
  State<BookingFlowScreen> createState() => _BookingFlowScreenState();
}

class _BookingFlowScreenState extends State<BookingFlowScreen> {
  final data = AppSession.instance.data;
  final _slotPicker = GlobalKey<SlotPickerState>();
  final _notes = TextEditingController();
  final _promo = TextEditingController();

  int _step = 0;
  final Map<String, _Selection> _selected = {};
  String? _memberId; // null = cualquier profesional
  Slot? _slot;
  bool _submitting = false;
  Booking? _result;

  Business get biz => widget.business;

  @override
  void initState() {
    super.initState();
    final s = widget.initialService;
    if (s != null) _selected[s.id] = _Selection(s);
  }

  @override
  void dispose() {
    _notes.dispose();
    _promo.dispose();
    super.dispose();
  }

  // ---------- Derivados ----------

  List<_Selection> get _selections => _selected.values.toList();
  int get _totalMin => _selections.fold(0, (a, s) => a + s.durationMin);
  int get _totalCents => _selections.fold(0, (a, s) => a + s.priceCents);
  bool get _priceIsApprox =>
      _selections.any((s) => s.variant == null && (s.service.priceType == 'from' || s.service.priceType == 'variable'));

  int get _depositCents {
    var d = 0;
    for (final s in _selections) {
      if (s.service.requiresDeposit) {
        d += s.service.depositCents ?? (s.priceCents * biz.depositPct ~/ 100);
      } else if (biz.depositPct > 0) {
        d += s.priceCents * biz.depositPct ~/ 100;
      }
    }
    return d;
  }

  List<Member> get _eligibleMembers {
    if (_selections.isEmpty) return widget.members;
    final ids = _selections.first.service.staffIds;
    if (ids.isEmpty) return widget.members;
    return widget.members.where((m) => ids.contains(m.id)).toList();
  }

  Member? get _member =>
      widget.members.where((m) => m.id == (_memberId ?? _slot?.memberId)).firstOrNull;

  // ---------- Navegación entre pasos ----------

  void _next() {
    if (_step == 0) {
      if (_selected.isEmpty) {
        showSnack(context, 'Elige al menos un servicio.', error: true);
        return;
      }
      final missing = _selections.where((s) => s.needsVariant).firstOrNull;
      if (missing != null) {
        showSnack(context, 'Elige una opción para "${missing.service.name}".', error: true);
        return;
      }
      // Si el profesional elegido ya no es válido para el servicio, se resetea.
      if (_memberId != null && !_eligibleMembers.any((m) => m.id == _memberId)) {
        _memberId = null;
      }
    }
    if (_step == 2 && _slot == null) {
      showSnack(context, 'Elige una fecha y hora.', error: true);
      return;
    }
    setState(() => _step++);
  }

  void _back() {
    if (_step == 0) {
      Navigator.of(context).pop();
    } else {
      setState(() => _step--);
    }
  }

  Future<void> _confirm() async {
    final slot = _slot;
    if (slot == null) return;
    setState(() => _submitting = true);
    try {
      final b = await data.createBooking(
        businessId: biz.id,
        memberId: _memberId ?? slot.memberId,
        startsAt: slot.startsAt,
        items: _selections.map((s) => s.toItem()).toList(),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        promoCode: _promo.text.trim().isEmpty ? null : _promo.text.trim().toUpperCase(),
      );
      if (!mounted) return;
      setState(() => _result = b);
    } catch (e) {
      if (!mounted) return;
      showSnack(context, friendlyError(e), error: true);
      if (e.toString().contains('slot_unavailable') || e.toString().contains('too_soon')) {
        setState(() {
          _slot = null;
          _step = 2;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _slotPicker.currentState?.reload());
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    if (_result != null) return _SuccessView(booking: _result!, business: biz);
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(biz.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _back),
      ),
      body: MaxWidth(
        maxWidth: 760,
        child: Column(children: [
          _StepHeader(step: _step),
          const Divider(),
          Expanded(
            child: switch (_step) {
              0 => _servicesStep(t),
              1 => _memberStep(t),
              2 => _dateStep(t),
              _ => _confirmStep(t),
            },
          ),
        ]),
      ),
      bottomNavigationBar: _bottomBar(t),
    );
  }

  Widget _bottomBar(ThemeData t) {
    final last = _step == 3;
    return Container(
      decoration: BoxDecoration(
        color: t.colorScheme.surface,
        border: Border(top: BorderSide(color: t.colorScheme.outlineVariant.withValues(alpha: 0.5))),
      ),
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: MaxWidth(
          maxWidth: 760,
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(
                  _selected.isEmpty
                      ? 'Ningún servicio'
                      : '${_selected.length} servicio${_selected.length == 1 ? '' : 's'} · ${Fmt.duration(_totalMin)}',
                  style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline),
                ),
                Text(
                  '${_priceIsApprox ? 'Desde ' : ''}${formatEuros(_totalCents)}',
                  style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
              ]),
            ),
            SizedBox(
              width: 180,
              child: FilledButton(
                onPressed: _submitting ? null : (last ? _confirm : _next),
                child: _submitting
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(last ? 'Confirmar reserva' : 'Continuar'),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ---------- Paso 1: servicios ----------

  Widget _servicesStep(ThemeData t) {
    if (widget.services.isEmpty) {
      return const EmptyView(icon: Icons.design_services_outlined, title: 'Sin servicios disponibles');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text('¿Qué quieres reservar?', style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('Puedes elegir varios servicios para la misma cita.',
            style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
        const SizedBox(height: 12),
        for (final s in widget.services) _serviceTile(t, s),
      ],
    );
  }

  Widget _serviceTile(ThemeData t, Service s) {
    final sel = _selected[s.id];
    final checked = sel != null;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(children: [
        CheckboxListTile(
          value: checked,
          controlAffinity: ListTileControlAffinity.leading,
          onChanged: (v) => setState(() {
            if (v == true) {
              _selected[s.id] = _Selection(s);
            } else {
              _selected.remove(s.id);
            }
          }),
          title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(s.variants.isEmpty
              ? '${Fmt.duration(s.durationMin)} · ${s.priceLabel}'
              : '${s.variants.length} opciones · desde ${formatEuros(s.variants.map((v) => v.priceCents).reduce((a, b) => a < b ? a : b))}'),
        ),
        if (checked && s.variants.isNotEmpty) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Elige una opción',
                  style: t.textTheme.labelMedium?.copyWith(color: t.colorScheme.primary, fontWeight: FontWeight.w700)),
            ),
          ),
          RadioGroup<String>(
            groupValue: sel.variant?.id,
            onChanged: (id) => setState(
                () => sel.variant = s.variants.where((v) => v.id == id).firstOrNull),
            child: Column(children: [
              for (final v in s.variants)
                RadioListTile<String>(
                  dense: true,
                  value: v.id,
                  title: Text(v.name),
                  subtitle: Text('${Fmt.duration(v.durationMin)} · ${formatEuros(v.priceCents)}'),
                ),
            ]),
          ),
        ],
        if (checked && s.addons.isNotEmpty) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Extras opcionales',
                  style: t.textTheme.labelMedium?.copyWith(color: t.colorScheme.outline, fontWeight: FontWeight.w700)),
            ),
          ),
          for (final a in s.addons.where((a) => a.active))
            CheckboxListTile(
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              value: sel.addonIds.contains(a.id),
              onChanged: (v) => setState(() {
                if (v == true) {
                  sel.addonIds.add(a.id);
                } else {
                  sel.addonIds.remove(a.id);
                }
              }),
              title: Text(a.name),
              subtitle: Text([
                if (a.durationMin > 0) '+${Fmt.duration(a.durationMin)}',
                '+${formatEuros(a.priceCents)}',
              ].join(' · ')),
            ),
          const SizedBox(height: 6),
        ],
      ]),
    );
  }

  // ---------- Paso 2: profesional ----------

  Widget _memberStep(ThemeData t) {
    final members = _eligibleMembers;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text('¿Con quién?', style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        _memberCard(
          t,
          selected: _memberId == null,
          leading: CircleAvatar(
            backgroundColor: t.colorScheme.primary.withValues(alpha: 0.15),
            child: Icon(Icons.groups_outlined, color: t.colorScheme.primary),
          ),
          title: 'Cualquier profesional disponible',
          subtitle: 'Más huecos libres',
          onTap: () => setState(() => _memberId = null),
        ),
        for (final m in members)
          _memberCard(
            t,
            selected: _memberId == m.id,
            leading: AvatarCircle(
              url: m.avatarUrl,
              initials: m.displayName.isEmpty ? '?' : m.displayName[0].toUpperCase(),
              color: hexColor(m.color),
            ),
            title: m.displayName,
            subtitle: m.title,
            onTap: () => setState(() => _memberId = m.id),
          ),
        if (members.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('El negocio asignará al profesional disponible.',
                style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
          ),
      ],
    );
  }

  Widget _memberCard(ThemeData t,
      {required bool selected,
      required Widget leading,
      required String title,
      String? subtitle,
      required VoidCallback onTap}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
            color: selected ? t.colorScheme.primary : t.colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: selected ? 2 : 1),
      ),
      child: ListTile(
        leading: leading,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: (subtitle ?? '').isEmpty ? null : Text(subtitle!),
        trailing: selected ? Icon(Icons.check_circle, color: t.colorScheme.primary) : null,
        onTap: onTap,
      ),
    );
  }

  // ---------- Paso 3: fecha y hora ----------

  Widget _dateStep(ThemeData t) {
    final first = _selections.first;
    return SlotPicker(
      key: _slotPicker,
      businessId: biz.id,
      serviceId: first.service.id,
      variantId: first.variant?.id,
      memberId: _memberId,
      horizonDays: biz.bookingHorizonDays,
      selected: _slot,
      onChanged: (s) => setState(() => _slot = s),
      emptyBuilder: biz.allowWaitlist ? (day) => _waitlistCard(t, day, first.service) : null,
    );
  }

  Widget _waitlistCard(ThemeData t, DateTime day, Service service) {
    return Card(
      color: t.colorScheme.primary.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.notifications_active_outlined, color: t.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text('¿Te avisamos si se libera un hueco?',
                  style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            'Te apuntamos a la lista de espera entre el ${Fmt.dayShort(day)} y el ${Fmt.dayShort(day.add(const Duration(days: 7)))}.',
            style: t.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _joinWaitlist(day, service),
            icon: const Icon(Icons.hourglass_empty),
            label: const Text('Apuntarme a la lista de espera'),
          ),
        ]),
      ),
    );
  }

  Future<void> _joinWaitlist(DateTime day, Service service) async {
    try {
      await data.joinWaitlist(
        businessId: biz.id,
        serviceId: service.id,
        from: day,
        to: day.add(const Duration(days: 7)),
        memberId: _memberId,
      );
      if (mounted) showSnack(context, 'Apuntado. Te avisaremos si se libera un hueco.');
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  // ---------- Paso 4: confirmar ----------

  Widget _confirmStep(ThemeData t) {
    final slot = _slot!;
    final member = _member;
    final deposit = _depositCents;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text('Revisa tu reserva', style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _summaryRow(t, Icons.storefront_outlined, biz.name),
              const SizedBox(height: 10),
              _summaryRow(t, Icons.event_outlined,
                  '${Fmt.dayLong(slot.startsAt)} · ${Fmt.time(slot.startsAt)}',
                  sub: 'Duración aprox. ${Fmt.duration(_totalMin)}'),
              const SizedBox(height: 10),
              _summaryRow(t, Icons.person_outline,
                  member?.displayName ?? 'Profesional disponible',
                  sub: member?.title),
              const Divider(height: 24),
              for (final s in _selections) ...[
                Row(children: [
                  Expanded(
                    child: Text(
                      s.variant == null ? s.service.name : '${s.service.name} · ${s.variant!.name}',
                      style: t.textTheme.bodyMedium,
                    ),
                  ),
                  Text(
                    s.variant == null && (s.service.priceType == 'from' || s.service.priceType == 'variable' || s.service.priceType == 'free')
                        ? s.service.priceLabel
                        : formatEuros(s.variant?.priceCents ?? s.service.priceCents),
                    style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ]),
                for (final a in s.service.addons.where((a) => s.addonIds.contains(a.id)))
                  Padding(
                    padding: const EdgeInsets.only(left: 12, top: 2),
                    child: Row(children: [
                      Expanded(child: Text('+ ${a.name}', style: t.textTheme.bodySmall)),
                      Text(formatEuros(a.priceCents), style: t.textTheme.bodySmall),
                    ]),
                  ),
                const SizedBox(height: 6),
              ],
              const Divider(height: 16),
              Row(children: [
                Expanded(child: Text('Total', style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                Text('${_priceIsApprox ? 'Desde ' : ''}${formatEuros(_totalCents)}',
                    style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              ]),
              if (deposit > 0) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: AppTheme.warning.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    const Icon(Icons.payments_outlined, size: 18, color: AppTheme.warning),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Se requiere una señal de ${formatEuros(deposit)}',
                          style: t.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ),
              ],
            ]),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _notes,
          maxLines: 3,
          minLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
              labelText: 'Notas para el negocio (opcional)',
              hintText: 'Alergias, preferencias, cómo llegar…',
              alignLabelWithHint: true),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _promo,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
              labelText: 'Código promocional (opcional)', prefixIcon: Icon(Icons.local_offer_outlined)),
        ),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline, size: 18, color: t.colorScheme.outline),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Cancelación gratuita hasta ${biz.cancellationHours} horas antes.'
              '${biz.cancellationFeePct > 0 ? ' Después se podrá cobrar el ${biz.cancellationFeePct} % del importe.' : ''}'
              '${biz.requiresConfirmation ? ' El negocio confirmará tu cita en breve.' : ''}',
              style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _summaryRow(ThemeData t, IconData icon, String text, {String? sub}) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 20, color: t.colorScheme.primary),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(text, style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          if ((sub ?? '').isNotEmpty)
            Text(sub!, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
        ]),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- Cabecera

class _StepHeader extends StatelessWidget {
  final int step;
  const _StepHeader({required this.step});
  static const _labels = ['Servicios', 'Profesional', 'Fecha y hora', 'Confirmar'];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 520;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(children: [
        for (var i = 0; i < _labels.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                color: i <= step ? t.colorScheme.primary : t.colorScheme.outlineVariant,
              ),
            ),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i <= step ? t.colorScheme.primary : t.colorScheme.surfaceContainerHighest,
              ),
              child: i < step
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : Text('${i + 1}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: i <= step ? Colors.white : t.colorScheme.outline)),
            ),
            if (wide || i == step) ...[
              const SizedBox(width: 6),
              Text(_labels[i],
                  style: t.textTheme.labelMedium?.copyWith(
                      fontWeight: i == step ? FontWeight.w700 : FontWeight.w500,
                      color: i == step ? t.colorScheme.primary : t.colorScheme.outline)),
            ],
          ]),
        ],
      ]),
    );
  }
}

// ---------------------------------------------------------------- SlotPicker

/// Calendario + huecos de un servicio. Reutilizable (reserva y cambio de hora).
class SlotPicker extends StatefulWidget {
  final String businessId;
  final String serviceId;
  final String? variantId;
  final String? memberId; // null = cualquier profesional
  final int horizonDays;
  final Slot? selected;
  final ValueChanged<Slot?> onChanged;
  final Widget Function(DateTime day)? emptyBuilder;
  final DateTime? initialDay;
  const SlotPicker({
    super.key,
    required this.businessId,
    required this.serviceId,
    this.variantId,
    this.memberId,
    this.horizonDays = 60,
    this.selected,
    required this.onChanged,
    this.emptyBuilder,
    this.initialDay,
  });
  @override
  State<SlotPicker> createState() => SlotPickerState();
}

class SlotPickerState extends State<SlotPicker> {
  final data = AppSession.instance.data;
  late DateTime _today = _dateOnly(DateTime.now());
  late DateTime _day = widget.initialDay == null ? _today : _dateOnly(widget.initialDay!);
  CalendarFormat _format = CalendarFormat.week;
  List<Slot> _slots = [];
  bool _loading = true;
  String? _error;
  int _requestId = 0;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  void initState() {
    super.initState();
    _today = _dateOnly(DateTime.now());
    if (_day.isBefore(_today)) _day = _today;
    reload();
  }

  @override
  void didUpdateWidget(SlotPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.serviceId != widget.serviceId ||
        oldWidget.variantId != widget.variantId ||
        oldWidget.memberId != widget.memberId) {
      reload();
    }
  }

  /// Vuelve a cargar los huecos del día seleccionado.
  Future<void> reload() async {
    final id = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await data.fetchSlots(
        businessId: widget.businessId,
        serviceId: widget.serviceId,
        date: _day,
        memberId: widget.memberId,
        variantId: widget.variantId,
      );
      if (!mounted || id != _requestId) return;
      // Con "cualquier profesional" llegan varios huecos a la misma hora:
      // agrupamos por hora y nos quedamos con el primer profesional.
      final byTime = <int, Slot>{};
      for (final s in raw) {
        byTime.putIfAbsent(s.startsAt.millisecondsSinceEpoch, () => s);
      }
      final slots = byTime.values.toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));
      setState(() => _slots = slots);
      // Si el hueco elegido ya no existe, se deselecciona.
      final sel = widget.selected;
      if (sel != null && !slots.any((s) => s.startsAt == sel.startsAt && s.memberId == sel.memberId)) {
        widget.onChanged(null);
      }
    } catch (e) {
      if (!mounted || id != _requestId) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted && id == _requestId) setState(() => _loading = false);
    }
  }

  void _selectDay(DateTime day, DateTime focused) {
    final d = _dateOnly(day);
    if (d == _day) return;
    setState(() {
      _day = d;
      _slots = [];
    });
    widget.onChanged(null);
    reload();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final lastDay = _today.add(Duration(days: widget.horizonDays));
    final morning = _slots.where((s) => s.startsAt.hour < 14).toList();
    final afternoon = _slots.where((s) => s.startsAt.hour >= 14).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: TableCalendar(
              locale: 'es',
              firstDay: _today,
              lastDay: lastDay,
              focusedDay: _day.isAfter(lastDay) ? lastDay : _day,
              currentDay: _today,
              selectedDayPredicate: (d) => isSameDay(d, _day),
              onDaySelected: _selectDay,
              calendarFormat: _format,
              onFormatChanged: (f) => setState(() => _format = f),
              onPageChanged: (f) {},
              availableCalendarFormats: const {
                CalendarFormat.month: 'Mes',
                CalendarFormat.week: 'Semana',
              },
              startingDayOfWeek: StartingDayOfWeek.monday,
              headerStyle: HeaderStyle(
                titleCentered: true,
                formatButtonShowsNext: false,
                formatButtonDecoration: BoxDecoration(
                  border: Border.all(color: t.colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                titleTextStyle: t.textTheme.titleSmall!.copyWith(fontWeight: FontWeight.w700),
              ),
              calendarStyle: CalendarStyle(
                selectedDecoration: BoxDecoration(color: t.colorScheme.primary, shape: BoxShape.circle),
                todayDecoration: BoxDecoration(
                    color: t.colorScheme.primary.withValues(alpha: 0.2), shape: BoxShape.circle),
                todayTextStyle: TextStyle(color: t.colorScheme.primary, fontWeight: FontWeight.w700),
                outsideDaysVisible: false,
                disabledTextStyle: TextStyle(color: t.colorScheme.outlineVariant),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(Fmt.dayLong(_day),
              style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 8),
        if (_loading)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
        else if (_error != null)
          ErrorView(_error!, onRetry: reload)
        else if (_slots.isEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
            child: Row(children: [
              Icon(Icons.event_busy_outlined, color: t.colorScheme.outline),
              const SizedBox(width: 8),
              Expanded(
                child: Text('No quedan huecos este día. Prueba otro día.',
                    style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.outline)),
              ),
            ]),
          ),
          if (widget.emptyBuilder != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: widget.emptyBuilder!(_day),
            ),
        ] else ...[
          if (morning.isNotEmpty) _group(t, 'Mañana', morning),
          if (afternoon.isNotEmpty) _group(t, 'Tarde', afternoon),
        ],
      ],
    );
  }

  Widget _group(ThemeData t, String label, List<Slot> slots) {
    final sel = widget.selected;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: t.textTheme.labelLarge?.copyWith(color: t.colorScheme.outline)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in slots)
              ChoiceChip(
                label: Text(Fmt.time(s.startsAt)),
                selected: sel != null && sel.startsAt == s.startsAt,
                onSelected: (_) => widget.onChanged(s),
              ),
          ],
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- Éxito

class _SuccessView extends StatelessWidget {
  final Booking booking;
  final Business business;
  const _SuccessView({required this.booking, required this.business});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final pending = booking.status == 'pending';
    return Scaffold(
      body: SafeArea(
        child: MaxWidth(
          maxWidth: 520,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 24),
              Center(
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.15), shape: BoxShape.circle),
                  child: const Icon(Icons.check_rounded, size: 56, color: AppTheme.accent),
                ),
              ),
              const SizedBox(height: 20),
              Text(pending ? '¡Solicitud enviada!' : '¡Reserva confirmada!',
                  textAlign: TextAlign.center,
                  style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                pending
                    ? 'El negocio confirmará tu cita en breve. Te avisaremos.'
                    : 'Te esperamos. Te enviaremos un recordatorio antes de la cita.',
                textAlign: TextAlign.center,
                style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.outline),
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    Text(business.name,
                        style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(Fmt.dateTime(booking.startsAt), style: t.textTheme.bodyLarge),
                    const SizedBox(height: 12),
                    Text('Código de reserva',
                        style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.outline)),
                    Text(booking.code,
                        style: t.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 2)),
                  ]),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const ClientShell(initialIndex: 1)),
                    (_) => false),
                icon: const Icon(Icons.event_outlined),
                label: const Text('Ver mis citas'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => SharePlus.instance.share(ShareParams(text: 'Tengo cita en ${business.name} el ${Fmt.dateTime(booking.startsAt)}. Código: ${booking.code}')),
                icon: const Icon(Icons.share_outlined),
                label: const Text('Compartir'),
              ),
              if (business.allowRecurring) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => showRecurringDialog(context, booking.id),
                  icon: const Icon(Icons.repeat),
                  label: const Text('Repetir esta cita'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Recurrencia

/// Diálogo para repetir una reserva cada semana / 2 semanas / mes × N veces.
Future<void> showRecurringDialog(BuildContext context, String bookingId) async {
  var everyDays = 7;
  var count = 4;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setD) => AlertDialog(
        title: const Text('Repetir la cita'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<int>(
            initialValue: everyDays,
            decoration: const InputDecoration(labelText: 'Frecuencia'),
            items: const [
              DropdownMenuItem(value: 7, child: Text('Cada semana')),
              DropdownMenuItem(value: 14, child: Text('Cada 2 semanas')),
              DropdownMenuItem(value: 30, child: Text('Cada mes')),
            ],
            onChanged: (v) => setD(() => everyDays = v ?? 7),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: count,
            decoration: const InputDecoration(labelText: 'Número de repeticiones'),
            items: [
              for (var n = 1; n <= 12; n++)
                DropdownMenuItem(value: n, child: Text('× $n')),
            ],
            onChanged: (v) => setD(() => count = v ?? 4),
          ),
          const SizedBox(height: 8),
          const Text(
            'Se crearán citas a la misma hora con el mismo profesional. Las que no tengan hueco se omitirán.',
            style: TextStyle(fontSize: 12),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Repetir')),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    final n = await AppSession.instance.data
        .makeRecurring(bookingId, everyDays: everyDays, count: count);
    if (!context.mounted) return;
    showSnack(context, n == 0 ? 'No había huecos libres para repetir la cita.' : 'Se han creado $n citas más.');
  } catch (e) {
    if (context.mounted) showSnack(context, friendlyError(e), error: true);
  }
}
