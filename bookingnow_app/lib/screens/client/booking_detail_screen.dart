import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_theme.dart';
import '../../models/models.dart';
import '../../services/app_session.dart';
import '../../utils/format.dart';
import '../../utils/friendly_errors.dart';
import '../../widgets/common.dart';
import 'booking_flow_screen.dart';
import 'business_detail_screen.dart';

/// Detalle de una cita del cliente con todas las acciones.
class BookingDetailScreen extends StatefulWidget {
  final String bookingId;
  const BookingDetailScreen({super.key, required this.bookingId});
  @override
  State<BookingDetailScreen> createState() => _BookingDetailScreenState();
}

class _BookingDetailScreenState extends State<BookingDetailScreen> {
  final data = AppSession.instance.data;
  Booking? _booking;
  Business? _business;
  bool _loading = true;
  bool _busy = false;
  String? _error;

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
      final b = await data.fetchBooking(widget.bookingId);
      if (!mounted) return;
      if (b == null) {
        setState(() => _error = 'La reserva no existe.');
        return;
      }
      Business? biz;
      try {
        biz = await data.fetchBusiness(b.businessId);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _booking = b;
        _business = biz;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------- Acciones ----------

  Future<void> _cancel() async {
    final b = _booking!;
    final hours = _business?.cancellationHours ?? 24;
    final feePct = _business?.cancellationFeePct ?? 0;
    final late = b.startsAt.difference(DateTime.now()).inHours < hours;
    final policy = late && feePct > 0
        ? 'Quedan menos de $hours h para la cita: según la política del negocio se puede cobrar el $feePct % del importe.'
        : 'Cancelación gratuita hasta $hours horas antes de la cita.';
    final ok = await confirmDialog(context,
        title: 'Cancelar cita',
        message: '$policy\n\n¿Seguro que quieres cancelar?',
        confirmLabel: 'Sí, cancelar',
        destructive: true);
    if (!ok) return;
    await _run(() async {
      final updated = await data.cancelBooking(b.id, reason: 'Cancelada por el cliente');
      if (!mounted) return;
      showSnack(context, 'Cita cancelada.');
      setState(() => _booking = updated);
      _load();
    });
  }

  Future<void> _reschedule() async {
    final b = _booking!;
    final item = b.items.where((i) => i.serviceId != null).firstOrNull;
    if (item == null) {
      showSnack(context, 'No se puede cambiar la hora de esta reserva.', error: true);
      return;
    }
    Slot? chosen;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, setSheet) => SizedBox(
          height: MediaQuery.sizeOf(c).height * 0.88,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(children: [
                Expanded(
                  child: Text('Elige la nueva hora',
                      style: Theme.of(c).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                ),
                if (chosen != null)
                  Text('${Fmt.dayShort(chosen!.startsAt)} · ${Fmt.time(chosen!.startsAt)}',
                      style: TextStyle(color: Theme.of(c).colorScheme.primary, fontWeight: FontWeight.w700)),
              ]),
            ),
            Expanded(
              child: MaxWidth(
                maxWidth: 760,
                child: SlotPicker(
                  businessId: b.businessId,
                  serviceId: item.serviceId!,
                  variantId: item.variantId,
                  memberId: b.memberId,
                  horizonDays: _business?.bookingHorizonDays ?? 60,
                  initialDay: b.startsAt,
                  selected: chosen,
                  onChanged: (s) => setSheet(() => chosen = s),
                ),
              ),
            ),
            SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: MaxWidth(
                maxWidth: 760,
                child: FilledButton(
                  onPressed: chosen == null ? null : () => Navigator.pop(c, true),
                  child: const Text('Cambiar hora'),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
    if (confirmed != true || chosen == null || !mounted) return;
    final slot = chosen!;
    await _run(() async {
      final updated = await data.rescheduleBooking(b.id, slot.startsAt,
          memberId: b.memberId ?? slot.memberId);
      if (!mounted) return;
      showSnack(context, 'Hora cambiada a ${Fmt.dateTime(updated.startsAt)}.');
      _load();
    });
  }

  Future<void> _review() async {
    final b = _booking!;
    var rating = 5;
    final comment = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Valora tu cita'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var s = 1; s <= 5; s++)
                IconButton(
                  iconSize: 36,
                  onPressed: () => setD(() => rating = s),
                  icon: Icon(s <= rating ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: AppTheme.warning),
                ),
            ]),
            const SizedBox(height: 8),
            TextField(
              controller: comment,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'Comentario (opcional)', alignLabelWithHint: true),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Enviar')),
          ],
        ),
      ),
    );
    final text = comment.text.trim();
    comment.dispose();
    if (ok != true || !mounted) return;
    await _run(() async {
      await data.submitReview(b.id, rating, comment: text.isEmpty ? null : text);
      if (!mounted) return;
      showSnack(context, '¡Gracias por tu valoración!');
      _load();
    });
  }

  Future<void> _openUrl(Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) showSnack(context, 'No se pudo abrir el enlace.', error: true);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  void _addToCalendar() {
    final b = _booking!;
    String z(DateTime d) {
      final u = d.toUtc();
      String p(int n) => n.toString().padLeft(2, '0');
      return '${u.year}${p(u.month)}${p(u.day)}T${p(u.hour)}${p(u.minute)}${p(u.second)}Z';
    }

    final title = Uri.encodeComponent('${b.servicesSummary ?? 'Cita'} · ${b.businessName ?? ''}');
    final details = Uri.encodeComponent('Reserva ${b.code}'
        '${(b.memberName ?? '').isNotEmpty ? ' con ${b.memberName}' : ''}'
        '. Gestionada con BookingNow.');
    final location = Uri.encodeComponent([
      if (_business?.name != null) _business!.name,
      if ((_business?.address ?? '').isNotEmpty) _business!.address!,
      if ((_business?.city ?? '').isNotEmpty) _business!.city!,
    ].join(', '));
    _openUrl(Uri.parse(
        'https://calendar.google.com/calendar/render?action=TEMPLATE&text=$title&dates=${z(b.startsAt)}/${z(b.endsAt)}&details=$details&location=$location'));
  }

  void _share() {
    final b = _booking!;
    SharePlus.instance.share(ShareParams(text: 'Tengo cita en ${b.businessName ?? 'un negocio'} el ${Fmt.dateTime(b.startsAt)}. Código: ${b.code}'));
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    if (_loading && _booking == null) {
      return Scaffold(appBar: AppBar(title: const Text('Cita')), body: const LoadingView());
    }
    if (_error != null && _booking == null) {
      return Scaffold(
          appBar: AppBar(title: const Text('Cita')), body: ErrorView(_error!, onRetry: _load));
    }
    final b = _booking!;
    final t = Theme.of(context);
    final canModify = b.isActive && !b.isPast;
    final paymentLabel = switch (b.paymentStatus) {
      'paid' => 'Pagado',
      'deposit_paid' => 'Señal pagada',
      'refunded' => 'Reembolsado',
      'pending' => 'Pago pendiente',
      _ => null,
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle de la cita'),
        actions: [
          IconButton(icon: const Icon(Icons.share_outlined), onPressed: _share, tooltip: 'Compartir'),
        ],
      ),
      body: MaxWidth(
        maxWidth: 640,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Row(children: [
                StatusChip(b.status),
                const Spacer(),
                Text('Código ${b.code}',
                    style: t.textTheme.labelMedium?.copyWith(color: t.colorScheme.outline)),
              ]),
              const SizedBox(height: 12),
              Card(
                child: Column(children: [
                  ListTile(
                    leading: Icon(Icons.storefront_outlined, color: t.colorScheme.primary),
                    title: Text(b.businessName ?? 'Negocio',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: (_business?.address ?? '').isEmpty ? null : Text(_business!.address!),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => BusinessDetailScreen(businessId: b.businessId))),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(Icons.event_outlined, color: t.colorScheme.primary),
                    title: Text(Fmt.dayLong(b.startsAt),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                        '${Fmt.range(b.startsAt, b.endsAt)} · ${Fmt.duration(b.durationMin > 0 ? b.durationMin : b.endsAt.difference(b.startsAt).inMinutes)}'),
                  ),
                  if ((b.memberName ?? '').isNotEmpty) ...[
                    const Divider(height: 1),
                    ListTile(
                      leading: AvatarCircle(
                          initials: b.memberName![0].toUpperCase(),
                          color: hexColor(b.memberColor),
                          radius: 16),
                      title: Text(b.memberName!),
                    ),
                  ],
                ]),
              ),
              const SectionTitle('Servicios'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(children: [
                    if (b.items.isEmpty)
                      Align(
                          alignment: Alignment.centerLeft,
                          child: Text(b.servicesSummary ?? '—', style: t.textTheme.bodyMedium)),
                    for (final it in b.items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(children: [
                          if (it.addonId != null)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Icon(Icons.add, size: 16, color: t.colorScheme.outline),
                            ),
                          Expanded(
                            child: Text(it.name, style: t.textTheme.bodyMedium),
                          ),
                          if (it.durationMin > 0)
                            Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: Text(Fmt.duration(it.durationMin),
                                  style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
                            ),
                          Text(formatEuros(it.priceCents),
                              style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    const Divider(),
                    Row(children: [
                      Expanded(
                          child: Text('Total',
                              style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                      Text(formatEuros(b.totalCents),
                          style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    ]),
                    if (b.depositCents > 0 || paymentLabel != null) ...[
                      const SizedBox(height: 6),
                      Row(children: [
                        Expanded(
                          child: Text(
                              b.depositCents > 0 ? 'Señal: ${formatEuros(b.depositCents)}' : '',
                              style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
                        ),
                        if (paymentLabel != null)
                          Text(paymentLabel,
                              style: t.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: b.paymentStatus == 'pending'
                                      ? AppTheme.warning
                                      : AppTheme.accent)),
                      ]),
                    ],
                  ]),
                ),
              ),
              if ((b.customerNotes ?? '').isNotEmpty) ...[
                const SectionTitle('Tus notas'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(b.customerNotes!, style: t.textTheme.bodyMedium),
                  ),
                ),
              ],
              if (b.cancelledAt != null && (b.cancelReason ?? '').isNotEmpty) ...[
                const SectionTitle('Motivo de cancelación'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(b.cancelReason!, style: t.textTheme.bodyMedium),
                  ),
                ),
              ],
              if (b.isActive) ...[
                const SectionTitle('Tu código'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            color: Colors.white, borderRadius: BorderRadius.circular(12)),
                        child: QrImageView(data: b.code, size: 160),
                      ),
                      const SizedBox(height: 8),
                      Text(b.code,
                          style: t.textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 2)),
                      Text('Muéstralo al llegar',
                          style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
                    ]),
                  ),
                ),
              ],
              const SectionTitle('Acciones'),
              if (b.canReview)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _review,
                    icon: const Icon(Icons.star_outline),
                    label: const Text('Valorar'),
                  ),
                ),
              if (canModify) ...[
                OutlinedButton.icon(
                  onPressed: _busy ? null : _reschedule,
                  icon: const Icon(Icons.schedule),
                  label: const Text('Cambiar hora'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _addToCalendar,
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: const Text('Añadir al calendario'),
                ),
                const SizedBox(height: 10),
              ],
              if (_business?.allowRecurring ?? true) ...[
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => showRecurringDialog(context, b.id),
                  icon: const Icon(Icons.repeat),
                  label: const Text('Repetir'),
                ),
                const SizedBox(height: 10),
              ],
              OutlinedButton.icon(
                onPressed: _share,
                icon: const Icon(Icons.share_outlined),
                label: const Text('Compartir'),
              ),
              if (canModify) ...[
                const SizedBox(height: 10),
                TextButton.icon(
                  style: TextButton.styleFrom(
                      foregroundColor: AppTheme.danger, minimumSize: const Size.fromHeight(48)),
                  onPressed: _busy ? null : _cancel,
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Cancelar cita'),
                ),
                if (_business != null)
                  Text(
                    'Cancelación gratuita hasta ${_business!.cancellationHours} horas antes.',
                    textAlign: TextAlign.center,
                    style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
