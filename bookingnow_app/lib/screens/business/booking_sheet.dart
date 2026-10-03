import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_theme.dart';
import '../../models/models.dart';
import '../../services/app_session.dart';
import '../../utils/format.dart';
import '../../utils/friendly_errors.dart';
import '../../widgets/common.dart';

/// Abre el detalle de una reserva en una hoja modal (centrada y con ancho
/// limitado en escritorio).
Future<void> showBookingSheet(BuildContext context, String bookingId,
    {VoidCallback? onChanged}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (_) => BookingSheet(bookingId: bookingId, onChanged: onChanged),
  );
}

/// Detalle y acciones de una reserva (contenido de bottom sheet).
class BookingSheet extends StatefulWidget {
  final String bookingId;
  final VoidCallback? onChanged;
  const BookingSheet({super.key, required this.bookingId, this.onChanged});

  @override
  State<BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends State<BookingSheet> {
  final session = AppSession.instance;
  Booking? _b;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  final _notesCtrl = TextEditingController();
  bool _notesDirty = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final b = await session.biz.fetchBooking(widget.bookingId);
      if (!mounted) return;
      setState(() {
        _b = b;
        _loading = false;
        if (b == null) _error = 'La reserva no existe.';
        _notesCtrl.text = b?.internalNotes ?? '';
        _notesDirty = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyError(e);
      });
    }
  }

  /// Ejecuta una mutación, recarga y avisa al padre.
  Future<void> _run(Future<void> Function() fn, {String? ok}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await fn();
      if (!mounted) return;
      if (ok != null) showSnack(context, ok);
      widget.onChanged?.call();
      await _load();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------- Acciones ----------

  Future<void> _confirm() =>
      _run(() => session.biz.setStatus(_b!.id, 'confirmed'), ok: 'Cita confirmada');

  Future<void> _reject() async {
    final ok = await confirmDialog(context,
        title: 'Rechazar ${session.bookingLabel.toLowerCase()}',
        message: 'Se cancelará la reserva y se avisará al cliente.',
        confirmLabel: 'Rechazar',
        destructive: true);
    if (!ok) return;
    await _run(() => session.biz.cancel(_b!.id, reason: 'Rechazada por el negocio'),
        ok: 'Reserva rechazada');
  }

  Future<void> _checkIn() =>
      _run(() => session.biz.setStatus(_b!.id, 'checked_in'), ok: 'Check-in realizado');

  Future<void> _complete() =>
      _run(() => session.biz.setStatus(_b!.id, 'completed'), ok: 'Cita completada');

  Future<void> _noShow() async {
    final ok = await confirmDialog(context,
        title: 'Marcar como no presentado',
        message:
            'Se registrará un no-show en la ficha del ${session.customerLabel.toLowerCase()}.',
        confirmLabel: 'Marcar',
        destructive: true);
    if (!ok) return;
    await _run(() => session.biz.setStatus(_b!.id, 'no_show'), ok: 'Marcada como no presentado');
  }

  Future<void> _cancel() async {
    final ok = await confirmDialog(context,
        title: 'Cancelar ${session.bookingLabel.toLowerCase()}',
        message: 'Se avisará al cliente y, si hay lista de espera, a quien corresponda.',
        confirmLabel: 'Cancelar cita',
        destructive: true);
    if (!ok) return;
    await _run(() => session.biz.cancel(_b!.id), ok: 'Reserva cancelada');
  }

  Future<void> _reschedule() async {
    final b = _b!;
    final date = await showDatePicker(
      context: context,
      initialDate: b.startsAt,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(b.startsAt));
    if (time == null || !mounted) return;
    final starts = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    await _run(() => session.biz.reschedule(b.id, starts), ok: 'Hora cambiada');
  }

  Future<void> _saveNotes() => _run(
      () => session.biz.updateBookingNotes(_b!.id, _notesCtrl.text.trim()),
      ok: 'Notas guardadas');

  Future<void> _issueInvoice() async {
    final b = _b!;
    final r = await showDialog<_InvoiceInput>(
        context: context, builder: (_) => _InvoiceDialog(booking: b));
    if (r == null) return;
    await _run(() async {
      final inv = await session.biz.issueInvoice(
        bookingId: b.id,
        paymentMethod: r.method,
        recipientName: r.name,
        recipientTaxId: r.taxId,
        recipientAddress: r.address,
      );
      if (!mounted) return;
      showSnack(context, 'Factura ${inv.fullNumber} emitida');
    });
  }

  Future<void> _repeat() async {
    final b = _b!;
    final r = await showDialog<(int, int)>(
        context: context, builder: (_) => const _RecurringDialog());
    if (r == null) return;
    await _run(() async {
      final n = await session.biz.makeRecurring(b.id, everyDays: r.$1, count: r.$2);
      if (!mounted) return;
      showSnack(context, '$n citas creadas');
    });
  }

  Future<void> _launch(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      showSnack(context, friendlyError(e), error: true);
    }
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    if (_loading) {
      return const SizedBox(height: 240, child: LoadingView());
    }
    if (_error != null || _b == null) {
      return SizedBox(height: 240, child: ErrorView(_error ?? 'Error', onRetry: _load));
    }
    final b = _b!;
    final t = Theme.of(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          StatusChip(b.status),
          const SizedBox(width: 10),
          Text(b.code,
              style: t.textTheme.labelLarge?.copyWith(
                  color: t.colorScheme.outline, fontFeatures: const [FontFeature.tabularFigures()])),
          const Spacer(),
          if (b.invoiced)
            const Chip(
                avatar: Icon(Icons.receipt_long, size: 16),
                label: Text('Facturada'),
                visualDensity: VisualDensity.compact),
          if (_busy)
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
        const SizedBox(height: 14),
        Text(Fmt.dayLong(b.startsAt), style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Row(children: [
          const Icon(Icons.schedule, size: 18),
          const SizedBox(width: 6),
          Text('${Fmt.range(b.startsAt, b.endsAt)} · ${Fmt.duration(b.durationMin)}',
              style: t.textTheme.bodyLarge),
        ]),
        if (b.memberName != null) ...[
          const SizedBox(height: 6),
          Row(children: [
            Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: hexColor(b.memberColor), shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text('${session.staffLabel}: ${b.memberName}', style: t.textTheme.bodyMedium),
          ]),
        ],
        const SizedBox(height: 16),
        _customerCard(t, b),
        const SectionTitle('Servicios'),
        Card(
          child: Column(children: [
            for (final it in b.items)
              ListTile(
                dense: true,
                title: Text(it.name),
                subtitle: Text(Fmt.duration(it.durationMin)),
                trailing: Text(formatEuros(it.priceCents),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            if (b.items.isEmpty)
              ListTile(dense: true, title: Text(b.servicesSummary ?? 'Sin servicios')),
            const Divider(),
            ListTile(
              dense: true,
              title: const Text('Total', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(_paymentLabel(b)),
              trailing: Text(formatEuros(b.totalCents),
                  style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
        if (b.customerNotes != null && b.customerNotes!.trim().isNotEmpty) ...[
          SectionTitle('Notas del ${session.customerLabel.toLowerCase()}'),
          Card(
            child: Padding(padding: const EdgeInsets.all(14), child: Text(b.customerNotes!)),
          ),
        ],
        if (b.cancelReason != null && b.cancelReason!.isNotEmpty) ...[
          const SectionTitle('Motivo de cancelación'),
          Text(b.cancelReason!, style: t.textTheme.bodyMedium),
        ],
        SectionTitle('Notas internas',
            trailing: _notesDirty
                ? TextButton(onPressed: _busy ? null : _saveNotes, child: const Text('Guardar'))
                : null),
        TextField(
          controller: _notesCtrl,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(hintText: 'Solo visibles para el equipo'),
          onChanged: (_) {
            if (!_notesDirty) setState(() => _notesDirty = true);
          },
        ),
        const SizedBox(height: 20),
        ..._actions(b),
      ]),
    );
  }

  String _paymentLabel(Booking b) {
    switch (b.paymentStatus) {
      case 'paid':
        return 'Pagado${b.paymentProvider != null ? ' · ${Fmt.paymentMethod(b.paymentProvider)}' : ''}';
      case 'deposit_paid':
        return 'Señal pagada: ${formatEuros(b.depositCents)}';
      case 'refunded':
        return 'Reembolsado';
      case 'pending':
        return 'Pago pendiente';
      default:
        return 'Sin pago registrado';
    }
  }

  Widget _customerCard(ThemeData t, Booking b) {
    final name = b.customerName ?? session.customerLabel;
    final parts = name.trim().split(RegExp(r'\s+'));
    final initials = parts.length >= 2
        ? (parts.first[0] + parts.last[0]).toUpperCase()
        : (name.isEmpty ? '?' : name[0].toUpperCase());
    final phoneDigits = (b.customerPhone ?? '').replaceAll(RegExp(r'[^0-9+]'), '');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            AvatarCircle(initials: initials, radius: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                if (b.customerPhone != null) Text(b.customerPhone!, style: t.textTheme.bodySmall),
                if (b.customerEmail != null) Text(b.customerEmail!, style: t.textTheme.bodySmall),
              ]),
            ),
            if (phoneDigits.isNotEmpty)
              IconButton(
                  tooltip: 'Llamar',
                  onPressed: () => _launch('tel:$phoneDigits'),
                  icon: const Icon(Icons.call_outlined)),
            if (b.customerEmail != null)
              IconButton(
                  tooltip: 'Email',
                  onPressed: () => _launch('mailto:${b.customerEmail}'),
                  icon: const Icon(Icons.mail_outline)),
          ]),
          if (b.customerNoShows > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                  color: AppTheme.danger.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.warning_amber_rounded, size: 16, color: AppTheme.danger),
                const SizedBox(width: 6),
                Text('${b.customerNoShows} no-show${b.customerNoShows == 1 ? '' : 's'} anteriores',
                    style: const TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w600)),
              ]),
            ),
          ],
        ]),
      ),
    );
  }

  List<Widget> _actions(Booking b) {
    final canInvoice = session.activeMembership?.canInvoice ?? false;
    final primary = <Widget>[];
    final secondary = <Widget>[];
    void p(String label, IconData icon, VoidCallback fn, {Color? color}) =>
        primary.add(FilledButton.icon(
            style: color == null ? null : FilledButton.styleFrom(backgroundColor: color),
            onPressed: _busy ? null : fn,
            icon: Icon(icon),
            label: Text(label)));
    void s(String label, IconData icon, VoidCallback fn, {Color? color}) =>
        secondary.add(OutlinedButton.icon(
            style: color == null ? null : OutlinedButton.styleFrom(foregroundColor: color),
            onPressed: _busy ? null : fn,
            icon: Icon(icon),
            label: Text(label)));

    switch (b.status) {
      case 'pending':
        p('Confirmar', Icons.check, _confirm);
        s('Rechazar', Icons.close, _reject, color: AppTheme.danger);
        s('Cambiar hora', Icons.edit_calendar_outlined, _reschedule);
      case 'confirmed':
        p('Check-in', Icons.login, _checkIn);
        p('Completar', Icons.task_alt, _complete, color: AppTheme.accent);
        s('Cambiar hora', Icons.edit_calendar_outlined, _reschedule);
        s('No se presentó', Icons.person_off_outlined, _noShow, color: AppTheme.danger);
        s('Cancelar', Icons.cancel_outlined, _cancel, color: AppTheme.danger);
      case 'checked_in':
        p('Completar', Icons.task_alt, _complete, color: AppTheme.accent);
        s('Cancelar', Icons.cancel_outlined, _cancel, color: AppTheme.danger);
      case 'completed':
        if (!b.invoiced && canInvoice) {
          p('Emitir factura', Icons.receipt_long_outlined, _issueInvoice);
        }
    }
    if (b.status != 'cancelled' && b.status != 'no_show' && (session.activeBusiness?.allowRecurring ?? true)) {
      s('Repetir cita', Icons.repeat, _repeat);
    }
    return [
      for (final w in primary) ...[w, const SizedBox(height: 8)],
      if (secondary.isNotEmpty)
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final w in secondary)
            SizedBox(
                width: 200,
                child: Theme(
                    data: Theme.of(context).copyWith(
                        outlinedButtonTheme: OutlinedButtonThemeData(
                            style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(44),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12))))),
                    child: w)),
        ]),
    ];
  }
}

// ---------------------------------------------------------------- Diálogos

class _InvoiceInput {
  final String method;
  final String name;
  final String? taxId;
  final String? address;
  const _InvoiceInput(this.method, this.name, this.taxId, this.address);
}

class _InvoiceDialog extends StatefulWidget {
  final Booking booking;
  const _InvoiceDialog({required this.booking});
  @override
  State<_InvoiceDialog> createState() => _InvoiceDialogState();
}

class _InvoiceDialogState extends State<_InvoiceDialog> {
  String _method = 'cash';
  late final _name = TextEditingController(text: widget.booking.customerName ?? '');
  final _taxId = TextEditingController();
  final _address = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _taxId.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Emitir factura'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Importe: ${formatEuros(widget.booking.totalCents)}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _method,
              decoration: const InputDecoration(labelText: 'Método de pago'),
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('Efectivo')),
                DropdownMenuItem(value: 'card', child: Text('Tarjeta')),
                DropdownMenuItem(value: 'bizum', child: Text('Bizum')),
                DropdownMenuItem(value: 'transfer', child: Text('Transferencia')),
              ],
              onChanged: (v) => setState(() => _method = v ?? 'cash'),
            ),
            const SizedBox(height: 12),
            TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Nombre del destinatario')),
            const SizedBox(height: 12),
            TextField(
                controller: _taxId,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'NIF (opcional)')),
            const SizedBox(height: 12),
            TextField(
                controller: _address,
                decoration: const InputDecoration(labelText: 'Dirección (opcional)')),
            const SizedBox(height: 8),
            Text('La numeración es correlativa y la factura queda registrada (Verifactu).',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline)),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(
                context,
                _InvoiceInput(
                    _method,
                    name,
                    _taxId.text.trim().isEmpty ? null : _taxId.text.trim().toUpperCase(),
                    _address.text.trim().isEmpty ? null : _address.text.trim()));
          },
          child: const Text('Emitir'),
        ),
      ],
    );
  }
}

class _RecurringDialog extends StatefulWidget {
  const _RecurringDialog();
  @override
  State<_RecurringDialog> createState() => _RecurringDialogState();
}

class _RecurringDialogState extends State<_RecurringDialog> {
  int _every = 7;
  int _count = 4;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Repetir cita'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<int>(
          initialValue: _every,
          decoration: const InputDecoration(labelText: 'Frecuencia'),
          items: const [
            DropdownMenuItem(value: 7, child: Text('Cada semana')),
            DropdownMenuItem(value: 14, child: Text('Cada 2 semanas')),
            DropdownMenuItem(value: 30, child: Text('Cada 30 días')),
          ],
          onChanged: (v) => setState(() => _every = v ?? 7),
        ),
        const SizedBox(height: 12),
        Row(children: [
          const Expanded(child: Text('Número de repeticiones')),
          IconButton(
              onPressed: _count > 1 ? () => setState(() => _count--) : null,
              icon: const Icon(Icons.remove_circle_outline)),
          Text('$_count', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          IconButton(
              onPressed: _count < 52 ? () => setState(() => _count++) : null,
              icon: const Icon(Icons.add_circle_outline)),
        ]),
        const SizedBox(height: 4),
        Text('Se crearán $_count citas con el mismo servicio, profesional y hora.',
            style: Theme.of(context).textTheme.bodySmall),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
            onPressed: () => Navigator.pop(context, (_every, _count)),
            child: const Text('Crear')),
      ],
    );
  }
}
