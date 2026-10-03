import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../app_theme.dart';
import '../../models/models.dart';
import '../../services/app_session.dart';
import '../../utils/format.dart';
import '../../utils/friendly_errors.dart';
import '../../widgets/admin_widgets.dart';
import '../../widgets/common.dart';

enum _Preset { thisMonth, lastMonth, last30, custom }

class _Agg {
  int count = 0;
  int revenue = 0;
}

/// Informes: ingresos, actividad, no-shows y rendimiento por profesional,
/// servicio, día y hora.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final session = AppSession.instance;
  _Preset _preset = _Preset.thisMonth;
  late DateTime _from;
  late DateTime _to; // exclusivo
  bool _loading = true;
  String? _error;
  List<Booking> _bookings = [];

  String get _businessId => session.activeBusiness!.id;

  @override
  void initState() {
    super.initState();
    _applyPreset(_Preset.thisMonth);
  }

  void _applyPreset(_Preset p, {DateTimeRange? custom}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (p) {
      case _Preset.thisMonth:
        _from = DateTime(now.year, now.month);
        _to = DateTime(now.year, now.month + 1);
      case _Preset.lastMonth:
        _from = DateTime(now.year, now.month - 1);
        _to = DateTime(now.year, now.month);
      case _Preset.last30:
        _from = today.subtract(const Duration(days: 29));
        _to = today.add(const Duration(days: 1));
      case _Preset.custom:
        if (custom != null) {
          _from = DateTime(custom.start.year, custom.start.month, custom.start.day);
          _to = DateTime(custom.end.year, custom.end.month, custom.end.day + 1);
        }
    }
    _preset = p;
    _load();
  }

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now.add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _from, end: _to.subtract(const Duration(days: 1))),
    );
    if (r == null) return;
    _applyPreset(_Preset.custom, custom: r);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await session.biz.fetchCompletedBookings(_businessId, _from, _to);
      if (!mounted) return;
      setState(() {
        _bookings = list;
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

  Future<void> _exportCsv() async {
    final rows = <List<dynamic>>[
      ['Código', 'Fecha', 'Hora', 'Cliente', 'Profesional', 'Servicios', 'Estado', 'Importe (€)', 'Pago'],
      for (final b in _bookings)
        [
          b.code,
          Fmt.date(b.startsAt),
          Fmt.time(b.startsAt),
          b.customerName ?? '',
          b.memberName ?? '',
          b.servicesSummary ?? '',
          Fmt.bookingStatus(b.status),
          (b.totalCents / 100).toStringAsFixed(2).replaceAll('.', ','),
          Fmt.paymentMethod(b.paymentStatus == 'none' ? null : b.paymentProvider),
        ],
    ];
    final csv = const ListToCsvConverter(fieldDelimiter: ';').convert(rows);
    try {
      await SharePlus.instance.share(ShareParams(text: csv, subject: 'Reservas ${Fmt.date(_from)} - ${Fmt.date(_to.subtract(const Duration(days: 1)))}.csv'));
    } catch (e) {
      if (!mounted) return;
      showSnack(context, friendlyError(e), error: true);
    }
  }

  // ---------- Cálculos ----------

  List<Booking> get _completed => _bookings.where((b) => b.status == 'completed').toList();

  Map<String, _Agg> _byMember() {
    final m = <String, _Agg>{};
    for (final b in _completed) {
      final k = b.memberName ?? 'Sin asignar';
      final a = m.putIfAbsent(k, () => _Agg());
      a.count++;
      a.revenue += b.totalCents;
    }
    return m;
  }

  Map<String, _Agg> _byService() {
    final m = <String, _Agg>{};
    for (final b in _completed) {
      final names = (b.servicesSummary ?? 'Sin detalle')
          .split(' + ')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (names.isEmpty) names.add('Sin detalle');
      final share = b.totalCents ~/ names.length;
      for (final n in names) {
        final a = m.putIfAbsent(n, () => _Agg());
        a.count++;
        a.revenue += share;
      }
    }
    return m;
  }

  List<int> _byWeekday() {
    final c = List<int>.filled(7, 0);
    for (final b in _completed) {
      c[b.startsAt.weekday % 7]++;
    }
    return c;
  }

  Map<int, int> _byHour() {
    final c = <int, int>{};
    for (final b in _completed) {
      c[b.startsAt.hour] = (c[b.startsAt.hour] ?? 0) + 1;
    }
    return c;
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Informes'),
        actions: [
          IconButton(
              icon: const Icon(Icons.download_outlined),
              tooltip: 'Exportar CSV',
              onPressed: _bookings.isEmpty ? null : _exportCsv),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load, tooltip: 'Actualizar'),
        ],
      ),
      body: MaxWidth(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _chip('Este mes', _Preset.thisMonth),
                const SizedBox(width: 8),
                _chip('Mes anterior', _Preset.lastMonth),
                const SizedBox(width: 8),
                _chip('Últimos 30 días', _Preset.last30),
                const SizedBox(width: 8),
                ChoiceChip(
                  avatar: const Icon(Icons.date_range, size: 16),
                  label: Text(_preset == _Preset.custom
                      ? '${Fmt.date(_from)} – ${Fmt.date(_to.subtract(const Duration(days: 1)))}'
                      : 'Personalizado'),
                  selected: _preset == _Preset.custom,
                  onSelected: (_) => _pickCustom(),
                ),
              ]),
            ),
          ),
          Expanded(
            child: _loading
                ? const LoadingView()
                : _error != null
                    ? ErrorView(_error!, onRetry: _load)
                    : _bookings.isEmpty
                        ? const EmptyView(
                            icon: Icons.bar_chart_outlined,
                            title: 'Sin datos en este periodo',
                            subtitle: 'Las citas completadas, canceladas y no presentadas aparecerán aquí.')
                        : _content(),
          ),
        ]),
      ),
    );
  }

  Widget _chip(String label, _Preset p) => ChoiceChip(
        label: Text(label),
        selected: _preset == p,
        onSelected: (_) => _applyPreset(p),
      );

  Widget _content() {
    final t = Theme.of(context);
    final completed = _completed;
    final cancelled = _bookings.where((b) => b.status == 'cancelled').length;
    final noShows = _bookings.where((b) => b.status == 'no_show').length;
    final finished = completed.length + noShows;
    final revenue = completed.fold<int>(0, (a, b) => a + b.totalCents);
    final avgTicket = completed.isEmpty ? 0 : revenue ~/ completed.length;
    final noShowRate = finished == 0 ? 0.0 : noShows / finished;

    final byMember = _byMember().entries.toList()
      ..sort((a, b) => b.value.revenue.compareTo(a.value.revenue));
    final byService = _byService().entries.toList()
      ..sort((a, b) => b.value.count.compareTo(a.value.count));
    final byWeekday = _byWeekday();
    final byHour = _byHour();
    final maxMember = byMember.isEmpty ? 1 : byMember.first.value.revenue.clamp(1, 1 << 40);
    final maxService = byService.isEmpty ? 1 : byService.first.value.count.clamp(1, 1 << 40);
    final maxWeekday = byWeekday.fold<int>(1, (a, b) => b > a ? b : a);
    final maxHour = byHour.values.fold<int>(1, (a, b) => b > a ? b : a);
    final hours = byHour.keys.toList()..sort();
    final staff = pluralEs(session.staffLabel);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth >= 900 ? 4 : (c.maxWidth >= 520 ? 3 : 2);
          final w = (c.maxWidth - 10 * (cols - 1)) / cols;
          return Wrap(spacing: 10, runSpacing: 10, children: [
            for (final k in [
              KpiCard(
                  label: 'Ingresos',
                  value: formatEuros(revenue),
                  icon: Icons.euro,
                  color: AppTheme.accent),
              KpiCard(
                  label: 'Completadas',
                  value: '${completed.length}',
                  icon: Icons.check_circle_outline),
              KpiCard(
                  label: 'Ticket medio',
                  value: formatEuros(avgTicket),
                  icon: Icons.receipt_long_outlined),
              KpiCard(
                  label: 'Canceladas',
                  value: '$cancelled',
                  icon: Icons.event_busy_outlined,
                  color: Colors.grey),
              KpiCard(
                  label: 'No-shows',
                  value: '$noShows',
                  icon: Icons.person_off_outlined,
                  color: AppTheme.danger),
              KpiCard(
                  label: 'Tasa no-show',
                  value: '${(noShowRate * 100).toStringAsFixed(1)} %',
                  icon: Icons.percent,
                  color: noShowRate > 0.1 ? AppTheme.danger : AppTheme.warning,
                  hint: 'sobre $finished finalizadas'),
            ])
              SizedBox(width: w, child: k),
          ]);
        }),
        if (noShowRate > 0.1)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: InfoCard(
              'Tu tasa de no-show supera el 10 %. Activa la señal al reservar y los recordatorios por WhatsApp/SMS en Ajustes para reducirla.',
              icon: Icons.lightbulb_outline,
              color: AppTheme.warning,
            ),
          ),
        SectionTitle('Por ${staff.toLowerCase()}'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: byMember.isEmpty
                ? const InlineEmpty('Sin citas completadas')
                : Column(children: [
                    for (final e in byMember)
                      HBar(
                        label: e.key,
                        fraction: e.value.revenue / maxMember,
                        value: '${formatEuros(e.value.revenue)} · ${e.value.count}',
                      ),
                  ]),
          ),
        ),
        const SectionTitle('Por servicio'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: byService.isEmpty
                ? const InlineEmpty('Sin citas completadas')
                : Column(children: [
                    for (final e in byService.take(12))
                      HBar(
                        label: e.key,
                        fraction: e.value.count / maxService,
                        value: '${e.value.count} · ${formatEuros(e.value.revenue)}',
                        color: AppTheme.accent,
                      ),
                    if (byService.length > 12)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('y ${byService.length - 12} más…',
                            style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
                      ),
                  ]),
          ),
        ),
        const SectionTitle('Por día de la semana'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              for (final d in [1, 2, 3, 4, 5, 6, 0])
                HBar(
                  label: Fmt.weekdaysLong[d],
                  fraction: byWeekday[d] / maxWeekday,
                  value: '${byWeekday[d]}',
                  color: const Color(0xFF0EA5E9),
                ),
            ]),
          ),
        ),
        const SectionTitle('Ocupación por hora'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: hours.isEmpty
                ? const InlineEmpty('Sin datos')
                : Column(children: [
                    for (final h in hours)
                      HBar(
                        label: '${h.toString().padLeft(2, '0')}:00 – ${(h + 1).toString().padLeft(2, '0')}:00',
                        fraction: byHour[h]! / maxHour,
                        value: '${byHour[h]}',
                        color: Color.lerp(AppTheme.warning, AppTheme.danger, byHour[h]! / maxHour),
                      ),
                  ]),
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _exportCsv,
          icon: const Icon(Icons.download_outlined),
          label: Text('Exportar CSV (${_bookings.length} reservas)'),
        ),
      ],
    );
  }
}
