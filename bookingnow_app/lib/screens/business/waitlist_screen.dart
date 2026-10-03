import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/models.dart';
import '../../services/app_session.dart';
import '../../utils/format.dart';
import '../../utils/friendly_errors.dart';
import '../../widgets/common.dart';
import 'new_booking_sheet.dart';

/// Lista de espera: clientes que quieren un hueco cuando se libere.
class WaitlistScreen extends StatefulWidget {
  const WaitlistScreen({super.key});
  @override
  State<WaitlistScreen> createState() => _WaitlistScreenState();
}

class _WaitlistScreenState extends State<WaitlistScreen> {
  final session = AppSession.instance;
  List<WaitlistEntry> _entries = [];
  bool _loading = true;
  String? _error;
  final Set<String> _acting = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final e = await session.biz.fetchWaitlist(session.activeBusiness!.id);
      if (!mounted) return;
      setState(() {
        _entries = e;
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

  Future<void> _setStatus(WaitlistEntry e, String status, {String? ok}) async {
    setState(() => _acting.add(e.id));
    try {
      await session.biz.updateWaitlistStatus(e.id, status);
      if (!mounted) return;
      if (ok != null) showSnack(context, ok);
      await _load();
    } catch (err) {
      if (!mounted) return;
      showSnack(context, friendlyError(err), error: true);
    } finally {
      if (mounted) setState(() => _acting.remove(e.id));
    }
  }

  Future<void> _book(WaitlistEntry e) async {
    var created = false;
    await showNewBookingSheet(context,
        customerId: e.customerId,
        memberId: e.memberId,
        initialDate: e.dateFrom.isAfter(DateTime.now()) ? e.dateFrom.add(const Duration(hours: 10)) : null,
        onCreated: () => created = true);
    if (!mounted || !created) return;
    await _setStatus(e, 'booked', ok: 'Cita reservada y entrada atendida');
  }

  Future<void> _remove(WaitlistEntry e) async {
    final ok = await confirmDialog(context,
        title: 'Quitar de la lista de espera',
        message: '¿Quitar a ${e.customerName ?? 'este cliente'} de la lista?',
        confirmLabel: 'Quitar',
        destructive: true);
    if (!ok) return;
    await _setStatus(e, 'cancelled', ok: 'Entrada eliminada');
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lista de espera'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'Actualizar'),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(_error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: MaxWidth(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      children: [
                        Card(
                          color: t.colorScheme.primary.withValues(alpha: 0.08),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(children: [
                              Icon(Icons.notifications_active_outlined, color: t.colorScheme.primary),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                    'Cuando se cancela una cita, avisamos automáticamente a los clientes en espera.'),
                              ),
                            ]),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_entries.isEmpty)
                          const EmptyView(
                            icon: Icons.hourglass_empty,
                            title: 'Nadie en espera',
                            subtitle:
                                'Los clientes pueden apuntarse desde la app cuando no hay huecos disponibles.',
                          )
                        else
                          for (final e in _entries) _tile(t, e),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _tile(ThemeData t, WaitlistEntry e) {
    final busy = _acting.contains(e.id);
    final name = e.customerName ?? session.customerLabel;
    final parts = name.trim().split(RegExp(r'\s+'));
    final initials = parts.length >= 2
        ? (parts.first[0] + parts.last[0]).toUpperCase()
        : (name.isEmpty ? '?' : name[0].toUpperCase());
    final notified = e.status == 'notified';
    final sameDay = e.dateFrom.year == e.dateTo.year &&
        e.dateFrom.month == e.dateTo.month &&
        e.dateFrom.day == e.dateTo.day;
    final range = sameDay ? Fmt.dayShort(e.dateFrom) : '${Fmt.dayShort(e.dateFrom)} – ${Fmt.dayShort(e.dateTo)}';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
        child: LayoutBuilder(builder: (_, c) {
          final info = Row(children: [
            AvatarCircle(initials: initials, radius: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(e.serviceName ?? 'Servicio',
                    style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
                Text(range, style: t.textTheme.bodySmall),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: (notified ? AppTheme.accent : AppTheme.warning).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(notified ? 'Avisado' : 'En espera',
                  style: TextStyle(
                      color: notified ? AppTheme.accent : AppTheme.warning,
                      fontWeight: FontWeight.w700,
                      fontSize: 12)),
            ),
          ]);
          final buttons = Row(mainAxisSize: MainAxisSize.min, children: [
            TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
                onPressed: busy ? null : () => _remove(e),
                icon: const Icon(Icons.remove_circle_outline, size: 18),
                label: const Text('Quitar')),
            const SizedBox(width: 4),
            FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                onPressed: busy ? null : () => _book(e),
                icon: const Icon(Icons.event_available, size: 18),
                label: const Text('Reservar')),
          ]);
          if (c.maxWidth < 560) {
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              info,
              const SizedBox(height: 6),
              Align(alignment: Alignment.centerRight, child: buttons),
            ]);
          }
          return Row(children: [Expanded(child: info), const SizedBox(width: 12), buttons]);
        }),
      ),
    );
  }
}
