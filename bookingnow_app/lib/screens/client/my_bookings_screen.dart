import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/models.dart';
import '../../services/app_session.dart';
import '../../utils/format.dart';
import '../../utils/friendly_errors.dart';
import '../../widgets/common.dart';
import 'booking_detail_screen.dart';
import 'client_shell.dart';

/// Mis citas: próximas y pasadas, más lista de espera activa.
class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({super.key});
  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen>
    with SingleTickerProviderStateMixin {
  final data = AppSession.instance.data;
  late final TabController _tabs = TabController(length: 2, vsync: this);

  List<Booking>? _upcoming;
  List<Booking>? _past;
  List<WaitlistEntry> _waitlist = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final results = await Future.wait<dynamic>([
        data.fetchMyBookings(upcoming: true),
        data.fetchMyBookings(upcoming: false),
        data.fetchMyWaitlist().catchError((_) => <WaitlistEntry>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _upcoming = results[0] as List<Booking>;
        _past = results[1] as List<Booking>;
        _waitlist = results[2] as List<WaitlistEntry>;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _leaveWaitlist(WaitlistEntry w) async {
    final ok = await confirmDialog(context,
        title: 'Salir de la lista de espera',
        message: '¿Quitar el aviso de "${w.serviceName ?? 'servicio'}"?',
        confirmLabel: 'Quitar',
        destructive: true);
    if (!ok) return;
    try {
      await data.leaveWaitlist(w.id);
      if (!mounted) return;
      setState(() => _waitlist.removeWhere((e) => e.id == w.id));
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _open(Booking b) async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => BookingDetailScreen(bookingId: b.id)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis citas'),
        bottom: TabBar(controller: _tabs, tabs: const [
          Tab(text: 'Próximas'),
          Tab(text: 'Pasadas'),
        ]),
      ),
      body: MaxWidth(
        maxWidth: 760,
        child: TabBarView(controller: _tabs, children: [
          _list(_upcoming, upcoming: true),
          _list(_past, upcoming: false),
        ]),
      ),
    );
  }

  Widget _list(List<Booking>? items, {required bool upcoming}) {
    if (_error != null && items == null) return ErrorView(_error!, onRetry: _load);
    if (items == null) return const LoadingView();
    final showWaitlist = upcoming && _waitlist.isNotEmpty;
    if (items.isEmpty && !showWaitlist) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(children: [
          const SizedBox(height: 60),
          EmptyView(
            icon: upcoming ? Icons.event_available_outlined : Icons.history,
            title: upcoming ? 'No tienes citas próximas' : 'Aún no tienes citas pasadas',
            subtitle: upcoming
                ? 'Encuentra un negocio y reserva en segundos.'
                : 'Aquí verás tu historial de citas.',
            action: FilledButton.icon(
              onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const ClientShell()), (_) => false),
              icon: const Icon(Icons.search),
              label: const Text('Explorar negocios'),
            ),
          ),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (showWaitlist) ...[
            const SectionTitle('En lista de espera'),
            for (final w in _waitlist) _waitlistCard(w),
            if (items.isNotEmpty) const SectionTitle('Próximas citas'),
          ],
          for (final b in items) _BookingCard(b, onTap: () => _open(b)),
        ],
      ),
    );
  }

  Widget _waitlistCard(WaitlistEntry w) {
    final t = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: AppTheme.warning.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.hourglass_empty, color: AppTheme.warning),
        ),
        title: Text(w.serviceName ?? 'Servicio', style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${Fmt.dayShort(w.dateFrom)} – ${Fmt.dayShort(w.dateTo)}'
          '${w.status == 'notified' ? ' · ¡Hay hueco!' : ''}',
          style: t.textTheme.bodySmall,
        ),
        trailing: TextButton(
          onPressed: () => _leaveWaitlist(w),
          child: const Text('Quitar'),
        ),
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  final Booking b;
  final VoidCallback onTap;
  const _BookingCard(this.b, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final color = bookingStatusColor(b.status);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 5, color: color),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(b.businessName ?? 'Negocio',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  StatusChip(b.status),
                ]),
                const SizedBox(height: 4),
                if ((b.servicesSummary ?? '').isNotEmpty)
                  Text(b.servicesSummary!,
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.bodyMedium),
                const SizedBox(height: 8),
                Row(children: [
                  Icon(Icons.schedule, size: 16, color: t.colorScheme.outline),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${Fmt.relativeDay(b.startsAt)} · ${Fmt.range(b.startsAt, b.endsAt)}',
                      style: t.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(formatEuros(b.totalCents),
                      style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
                ]),
                if ((b.memberName ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    Icon(Icons.person_outline, size: 16, color: t.colorScheme.outline),
                    const SizedBox(width: 6),
                    Text(b.memberName!,
                        style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
                  ]),
                ],
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
