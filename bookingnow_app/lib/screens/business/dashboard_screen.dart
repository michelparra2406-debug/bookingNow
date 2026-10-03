import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/models.dart';
import '../../services/app_session.dart';
import '../../utils/format.dart';
import '../../utils/friendly_errors.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/common.dart';
import 'agenda_screen.dart';
import 'booking_sheet.dart';
import 'customers_screen.dart';
import 'new_booking_sheet.dart';

/// Inicio del modo negocio: KPIs, pendientes de confirmar y agenda de hoy.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final session = AppSession.instance;
  String get _bizId => session.activeBusiness!.id;

  BusinessKpis _kpis = BusinessKpis();
  List<Booking> _today = [];
  List<Booking> _pending = [];
  bool _loading = true;
  String? _error;
  bool _publishing = false;
  final Set<String> _acting = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    try {
      final r = await Future.wait([
        session.biz.fetchKpis(_bizId),
        session.biz.fetchBookings(_bizId, from: start, to: start.add(const Duration(days: 1))),
        session.biz.fetchPendingBookings(_bizId),
      ]);
      if (!mounted) return;
      setState(() {
        _kpis = r[0] as BusinessKpis;
        _today = r[1] as List<Booking>;
        _pending = r[2] as List<Booking>;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyError(e);
      });
    }
  }

  Future<void> _decide(Booking b, bool accept) async {
    setState(() => _acting.add(b.id));
    try {
      if (accept) {
        await session.biz.setStatus(b.id, 'confirmed');
      } else {
        final ok = await confirmDialog(context,
            title: 'Rechazar ${session.bookingLabel.toLowerCase()}',
            message: 'Se cancelará la reserva de ${b.customerName ?? 'este cliente'} y se le avisará.',
            confirmLabel: 'Rechazar',
            destructive: true);
        if (!ok) return;
        await session.biz.cancel(b.id, reason: 'Rechazada por el negocio');
      }
      if (!mounted) return;
      showSnack(context, accept ? 'Cita confirmada' : 'Cita rechazada');
      await _load();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _acting.remove(b.id));
    }
  }

  Future<void> _publish() async {
    setState(() => _publishing = true);
    try {
      await session.biz.updateBusiness(_bizId, {'is_published': true});
      await session.refreshActiveBusiness();
      if (!mounted) return;
      showSnack(context, 'Tu negocio ya es visible en el marketplace');
    } catch (e) {
      if (!mounted) return;
      showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  void _newBooking() => showNewBookingSheet(context, onCreated: _load);

  Future<void> _newBlock() async {
    final ok = await showTimeBlockDialog(context);
    if (ok && mounted) showSnack(context, 'Tiempo bloqueado');
  }

  Future<void> _newCustomer() async {
    final c = await showCustomerFormDialog(context);
    if (c != null && mounted) showSnack(context, '${session.customerLabel} creado');
  }

  @override
  Widget build(BuildContext context) {
    final b = session.activeBusiness!;
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(b.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text('Hoy, ${Fmt.dayLong(DateTime.now())}',
              style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
        ]),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'Actualizar'),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const LoadingView()
          : _error != null && _today.isEmpty
              ? ErrorView(_error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: MaxWidth(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      children: [
                        _welcomeHeader(t, b),
                        const SizedBox(height: 16),
                        if (!b.isPublished) _publishBanner(t),
                        _quickActions(t),
                        const SizedBox(height: 16),
                        _kpiGrid(),
                        if (_pending.isNotEmpty) ...[
                          SectionTitle('Pendientes de confirmar (${_pending.length})'),
                          for (final p in _pending.take(10)) _pendingTile(t, p),
                        ],
                        SectionTitle('Agenda de hoy',
                            trailing: Text('${_today.length} ${session.bookingLabel.toLowerCase()}s',
                                style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline))),
                        if (_today.isEmpty)
                          EmptyView(
                            icon: Icons.event_available_outlined,
                            title: 'Hoy no hay ${session.bookingLabel.toLowerCase()}s',
                            subtitle: 'Las reservas online y manuales aparecerán aquí.',
                            action: FilledButton.icon(
                              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                              onPressed: _newBooking,
                              icon: const Icon(Icons.add),
                              label: Text('Nueva ${session.bookingLabel.toLowerCase()}'),
                            ),
                          )
                        else
                          Card(
                            child: Column(children: [
                              for (var i = 0; i < _today.length; i++) ...[
                                _todayTile(t, _today[i]),
                                if (i < _today.length - 1) const Divider(indent: 16, endIndent: 16),
                              ],
                            ]),
                          ),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _publishBanner(ThemeData t) {
    return Card(
      color: AppTheme.warning.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          const Icon(Icons.visibility_off_outlined, color: AppTheme.warning),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Tu negocio aún no es visible en el marketplace',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          TextButton(
              onPressed: _publishing ? null : _publish,
              child: Text(_publishing ? 'Publicando…' : 'Publicar')),
        ]),
      ),
    );
  }

  Widget _quickActions(ThemeData t) {
    Widget action(String label, IconData icon, VoidCallback fn) => Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
            onPressed: fn,
            icon: Icon(icon, size: 18),
            label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(children: [
        action('Nueva ${session.bookingLabel.toLowerCase()}', Icons.add, _newBooking),
        const SizedBox(width: 8),
        action('Bloquear', Icons.block, _newBlock),
        const SizedBox(width: 8),
        action('Nuevo ${session.customerLabel.toLowerCase()}', Icons.person_add_alt_1_outlined, _newCustomer),
      ]),
    );
  }

  Widget _kpiGrid() {
    final k = _kpis;
    final cards = <Widget>[
      KpiCard(label: '${session.bookingLabel}s hoy', value: '${k.bookingsToday}', icon: Icons.today_outlined),
      KpiCard(
          label: 'Pendientes de confirmar',
          value: '${k.pendingConfirmation}',
          icon: Icons.hourglass_top_outlined,
          color: AppTheme.warning),
      KpiCard(
          label: 'Ingresos del mes',
          value: formatEuros(k.revenueMonthCents),
          icon: Icons.euro_outlined,
          color: AppTheme.accent),
      KpiCard(label: 'Completadas este mes', value: '${k.completedMonth}', icon: Icons.task_alt_outlined, color: AppTheme.accent),
      KpiCard(
          label: 'Tasa de no-show (30 días)',
          value: '${(k.noShowRate * 100).toStringAsFixed(k.noShowRate * 100 >= 10 ? 0 : 1)} %',
          icon: Icons.person_off_outlined,
          color: AppTheme.danger,
          hint: '${k.noShows30d} de ${k.finished30d}'),
      KpiCard(
          label: '${session.customerLabel}s nuevos este mes',
          value: '${k.customersNewMonth}',
          icon: Icons.person_add_alt_outlined,
          hint: '${k.customersTotal} en total'),
      KpiCard(label: 'Lista de espera', value: '${k.waitlistWaiting}', icon: Icons.hourglass_empty, color: const Color(0xFF0EA5E9)),
    ];
    return LayoutBuilder(builder: (_, c) {
      final cols = c.maxWidth >= 900 ? 4 : (c.maxWidth >= 560 ? 3 : 2);
      const gap = 10.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final k in cards) SizedBox(width: w, child: k)],
      );
    });
  }

  Widget _pendingTile(ThemeData t, Booking p) {
    final busy = _acting.contains(p.id);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => showBookingSheet(context, p.id, onChanged: _load),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: LayoutBuilder(builder: (_, c) {
            final info = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.customerName ?? session.customerLabel,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('${Fmt.dateTime(p.startsAt)} · ${p.servicesSummary ?? ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
              if (p.memberName != null)
                Text(p.memberName!, style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.outline)),
            ]);
            final buttons = Row(mainAxisSize: MainAxisSize.min, children: [
              TextButton(
                  style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
                  onPressed: busy ? null : () => _decide(p, false),
                  child: const Text('Rechazar')),
              const SizedBox(width: 4),
              FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                  onPressed: busy ? null : () => _decide(p, true),
                  child: const Text('Confirmar')),
            ]);
            if (c.maxWidth < 480) {
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                info,
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerRight, child: buttons),
              ]);
            }
            return Row(children: [Expanded(child: info), buttons]);
          }),
        ),
      ),
    );
  }

  Widget _todayTile(ThemeData t, Booking b) {
    final past = b.endsAt.isBefore(DateTime.now());
    return InkWell(
      onTap: () => showBookingSheet(context, b.id, onChanged: _load),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          SizedBox(
            width: 50,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(Fmt.time(b.startsAt),
                  style: t.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: past ? t.colorScheme.outline : null)),
              Text(Fmt.time(b.endsAt),
                  style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.outline)),
            ]),
          ),
          Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(color: hexColor(b.memberColor), shape: BoxShape.circle)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(b.customerName ?? session.customerLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                  [b.servicesSummary, b.memberName].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
            ]),
          ),
          const SizedBox(width: 8),
          StatusChip(b.status),
        ]),
      ),
    );
  }
}

/// Cabecera de bienvenida con degradado de marca y resumen del día.
extension _DashboardHeader on _DashboardScreenState {
  Widget _welcomeHeader(ThemeData t, Business b) {
    final today = _today.where((x) => x.status != 'cancelled').length;
    final next = _today.where((x) => x.isActive && x.endsAt.isAfter(DateTime.now())).toList();
    return BrandHeader(
      borderRadius: BorderRadius.circular(24),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Hola, ${session.activeMembership?.displayName.split(' ').first ?? ''}',
            style: t.textTheme.titleMedium?.copyWith(color: Colors.white70)),
        const SizedBox(height: 4),
        Text(
          today == 0
              ? 'Hoy no tienes ${session.bookingLabel.toLowerCase()}s'
              : 'Hoy tienes $today ${session.bookingLabel.toLowerCase()}${today == 1 ? '' : 's'}',
          style: t.textTheme.headlineSmall?.copyWith(color: Colors.white),
        ),
        if (next.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.schedule, color: AppTheme.accent, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Siguiente: ${Fmt.time(next.first.startsAt)} · ${next.first.customerName ?? ''}'
                  '${next.first.servicesSummary != null ? ' · ${next.first.servicesSummary}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.textTheme.bodyMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ]),
          ),
        ],
      ]),
    );
  }
}
