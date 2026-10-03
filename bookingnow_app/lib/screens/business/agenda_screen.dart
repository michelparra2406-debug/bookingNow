import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../config.dart';
import '../../models/models.dart';
import '../../services/app_session.dart';
import '../../utils/format.dart';
import '../../utils/friendly_errors.dart';
import '../../widgets/common.dart';
import 'booking_sheet.dart';
import 'new_booking_sheet.dart';

const _startHour = 7;
const _endHour = 22;
const _pxPerHour = 60.0;
const _pxPerMin = _pxPerHour / 60;
const _gutter = 48.0;
const _gridHeight = (_endHour - _startHour) * _pxPerHour;

/// Columna del calendario diario (un profesional, o "sin asignar").
class _Col {
  final String? id;
  final String name;
  final Color color;
  const _Col(this.id, this.name, this.color);
}

/// Agenda del negocio: vista de día (rejilla por profesional) y de semana.
class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key});
  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  final session = AppSession.instance;
  String get _bizId => session.activeBusiness!.id;

  late DateTime _day = _dateOnly(DateTime.now());
  bool _week = false;
  String? _memberFilter;
  List<Member> _members = [];
  List<Booking> _bookings = [];
  List<Map<String, dynamic>> _blocks = [];
  bool _loading = true;
  String? _error;
  final _vScroll = ScrollController();
  bool _scrolledOnce = false;
  Timer? _clock;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _weekStart(DateTime d) =>
      _dateOnly(d).subtract(Duration(days: d.weekday - 1));

  @override
  void initState() {
    super.initState();
    _init();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _vScroll.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final m = await session.biz.fetchMembers(_bizId, onlyActive: true);
      if (!mounted) return;
      setState(() => _members = m.where((x) => x.bookable).toList());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyError(e);
      });
      return;
    }
    await _load();
  }

  Future<void> _load() async {
    final from = _week ? _weekStart(_day) : _day;
    final to = from.add(Duration(days: _week ? 7 : 1));
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await Future.wait([
        session.biz.fetchBookings(_bizId, from: from, to: to),
        session.biz.fetchTimeBlocks(_bizId, from, to),
      ]);
      if (!mounted) return;
      setState(() {
        _bookings = r[0] as List<Booking>;
        _blocks = r[1] as List<Map<String, dynamic>>;
        _loading = false;
      });
      if (!_scrolledOnce) {
        _scrolledOnce = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToStart());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyError(e);
      });
    }
  }

  void _scrollToStart() {
    if (!_vScroll.hasClients) return;
    final now = DateTime.now();
    final target = _dateOnly(now) == _day
        ? ((now.hour * 60 + now.minute - _startHour * 60) * _pxPerMin - 120)
        : 2 * _pxPerHour;
    _vScroll.jumpTo(target.clamp(0, _vScroll.position.maxScrollExtent).toDouble());
  }

  void _setDay(DateTime d, {bool reload = true}) {
    final nd = _dateOnly(d);
    final needsReload = !_week || _weekStart(nd) != _weekStart(_day);
    setState(() => _day = nd);
    if (reload && needsReload) _load();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (d != null) _setDay(d);
  }

  void _openBooking(String id) => showBookingSheet(context, id, onChanged: _load);

  void _newBooking({DateTime? at, String? memberId}) => showNewBookingSheet(context,
      initialDate: at ?? _day.add(const Duration(hours: 10)),
      memberId: memberId ?? _memberFilter,
      onCreated: _load);

  Future<void> _newBlock() async {
    final ok = await showTimeBlockDialog(context,
        initialStart: _day.add(const Duration(hours: 13)), memberId: _memberFilter);
    if (ok) _load();
  }

  Future<void> _deleteBlock(Map<String, dynamic> bl) async {
    final ok = await confirmDialog(context,
        title: 'Eliminar bloqueo',
        message: '¿Quitar "${bl['title'] ?? 'Bloqueo'}" de la agenda?',
        confirmLabel: 'Eliminar',
        destructive: true);
    if (!ok) return;
    try {
      await session.biz.deleteTimeBlock(bl['id'] as String);
      if (!mounted) return;
      _load();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, friendlyError(e), error: true);
    }
  }

  // ---------- Datos filtrados ----------

  List<Booking> get _visibleBookings => _bookings
      .where((b) =>
          b.status != 'cancelled' && (_memberFilter == null || b.memberId == _memberFilter))
      .toList();

  List<Map<String, dynamic>> get _visibleBlocks => _blocks
      .where((bl) =>
          _memberFilter == null || bl['member_id'] == null || bl['member_id'] == _memberFilter)
      .toList();

  static DateTime _blockStart(Map<String, dynamic> bl) =>
      DateTime.parse(bl['starts_at'].toString()).toLocal();
  static DateTime _blockEnd(Map<String, dynamic> bl) =>
      DateTime.parse(bl['ends_at'].toString()).toLocal();

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= AppConfig.desktopBreakpoint;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agenda'),
        actions: [
          TextButton(onPressed: () => _setDay(DateTime.now()), child: const Text('Hoy')),
          const SizedBox(width: 4),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(value: false, label: Text('Día')),
              ButtonSegment(value: true, label: Text('Semana')),
            ],
            selected: {_week},
            onSelectionChanged: (s) {
              setState(() => _week = s.first);
              _load();
            },
          ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'Actualizar'),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(children: [
        _dateBar(),
        _weekStrip(),
        if (_members.isNotEmpty) _staffFilter(),
        const Divider(),
        Expanded(
          child: _loading && _bookings.isEmpty
              ? const LoadingView()
              : _error != null
                  ? ErrorView(_error!, onRetry: _load)
                  : _week
                      ? _weekView()
                      : _dayView(wide),
        ),
      ]),
      floatingActionButton: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        FloatingActionButton.small(
          heroTag: 'agenda_block',
          tooltip: 'Bloquear tiempo',
          onPressed: _newBlock,
          child: const Icon(Icons.block),
        ),
        const SizedBox(height: 10),
        FloatingActionButton.extended(
          heroTag: 'agenda_new',
          onPressed: () => _newBooking(),
          icon: const Icon(Icons.add),
          label: Text('Nueva ${session.bookingLabel.toLowerCase()}'),
        ),
      ]),
    );
  }

  Widget _dateBar() {
    final t = Theme.of(context);
    final step = Duration(days: _week ? 7 : 1);
    final label = _week
        ? '${Fmt.dayShort(_weekStart(_day))} – ${Fmt.dayShort(_weekStart(_day).add(const Duration(days: 6)))}'
        : Fmt.dayLong(_day);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(children: [
        IconButton(
            onPressed: () => _setDay(_day.subtract(step)), icon: const Icon(Icons.chevron_left)),
        Expanded(
          child: InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Flexible(
                  child: Text(label,
                      overflow: TextOverflow.ellipsis,
                      style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 6),
                Icon(Icons.arrow_drop_down, color: t.colorScheme.outline),
              ]),
            ),
          ),
        ),
        IconButton(onPressed: () => _setDay(_day.add(step)), icon: const Icon(Icons.chevron_right)),
      ]),
    );
  }

  Widget _weekStrip() {
    final t = Theme.of(context);
    final start = _weekStart(_day);
    final today = _dateOnly(DateTime.now());
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(children: [
        for (var i = 0; i < 7; i++)
          Builder(builder: (_) {
            final d = start.add(Duration(days: i));
            final sel = d == _day;
            final isToday = d == today;
            return Expanded(
              child: InkWell(
                onTap: () => _setDay(d),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: sel ? t.colorScheme.primary : null,
                    borderRadius: BorderRadius.circular(10),
                    border: isToday && !sel ? Border.all(color: t.colorScheme.primary) : null,
                  ),
                  child: Column(children: [
                    Text(Fmt.weekdaysShort[d.weekday % 7],
                        style: t.textTheme.labelSmall?.copyWith(
                            color: sel ? t.colorScheme.onPrimary : t.colorScheme.outline)),
                    Text('${d.day}',
                        style: t.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: sel ? t.colorScheme.onPrimary : null)),
                  ]),
                ),
              ),
            );
          }),
      ]),
    );
  }

  Widget _staffFilter() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('Todos'),
              selected: _memberFilter == null,
              onSelected: (_) => setState(() => _memberFilter = null),
            ),
          ),
          for (final m in _members)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: CircleAvatar(backgroundColor: hexColor(m.color), radius: 6),
                label: Text(m.displayName),
                selected: _memberFilter == m.id,
                onSelected: (_) => setState(() => _memberFilter = m.id),
              ),
            ),
        ],
      ),
    );
  }

  // ---------- Vista de día ----------

  Widget _dayView(bool wide) {
    final bookings = _visibleBookings;
    final blocks = _visibleBlocks;
    if (!wide && _memberFilter == null) return _dayList(bookings, blocks);

    final cols = <_Col>[];
    if (_memberFilter != null) {
      final m = _members.where((x) => x.id == _memberFilter).firstOrNull;
      cols.add(_Col(_memberFilter, m?.displayName ?? session.staffLabel, hexColor(m?.color)));
    } else {
      for (final m in _members) {
        cols.add(_Col(m.id, m.displayName, hexColor(m.color)));
      }
      final unassigned = bookings.where((b) => !cols.any((c) => c.id == b.memberId));
      if (cols.isEmpty || unassigned.isNotEmpty) {
        cols.add(const _Col(null, 'Sin asignar', Colors.grey));
      }
    }
    return _dayGrid(cols, bookings, blocks);
  }

  Widget _dayGrid(List<_Col> cols, List<Booking> bookings, List<Map<String, dynamic>> blocks) {
    final t = Theme.of(context);
    final isToday = _day == _dateOnly(DateTime.now());
    final now = DateTime.now();
    return LayoutBuilder(builder: (ctx, c) {
      final colW = math.max(170.0, (c.maxWidth - _gutter) / cols.length);
      final totalW = _gutter + colW * cols.length;
      double top(DateTime d) =>
          ((d.hour * 60 + d.minute - _startHour * 60) * _pxPerMin).clamp(0, _gridHeight);
      double height(DateTime a, DateTime b) =>
          math.max(18, (top(b) - top(a)).clamp(0, _gridHeight - top(a)));
      int colIndex(String? memberId) {
        final i = cols.indexWhere((x) => x.id == memberId);
        return i >= 0 ? i : cols.length - 1;
      }

      final children = <Widget>[
        // Líneas de hora y cuartos
        for (var h = _startHour; h <= _endHour; h++)
          Positioned(
            top: (h - _startHour) * _pxPerHour,
            left: 0,
            width: totalW,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: _gutter,
                child: Transform.translate(
                  offset: const Offset(0, -7),
                  child: Text('${h.toString().padLeft(2, '0')}:00',
                      textAlign: TextAlign.center,
                      style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.outline)),
                ),
              ),
              Expanded(child: Divider(color: t.colorScheme.outlineVariant.withValues(alpha: 0.8))),
            ]),
          ),
        for (var h = _startHour; h < _endHour; h++)
          for (final q in const [15, 30, 45])
            Positioned(
              top: (h - _startHour) * _pxPerHour + q * _pxPerMin,
              left: _gutter,
              width: totalW - _gutter,
              child: Divider(color: t.colorScheme.outlineVariant.withValues(alpha: 0.3)),
            ),
        // Áreas de toque por columna + separadores
        for (var i = 0; i < cols.length; i++)
          Positioned(
            left: _gutter + i * colW,
            top: 0,
            width: colW,
            height: _gridHeight,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapDown: (d) {
                final mins = ((d.localPosition.dy / _pxPerMin) ~/ 15) * 15 + _startHour * 60;
                _newBooking(
                    at: _day.add(Duration(minutes: mins)), memberId: cols[i].id);
              },
              child: Container(
                decoration: BoxDecoration(
                    border: Border(
                        left: BorderSide(
                            color: t.colorScheme.outlineVariant.withValues(alpha: 0.6)))),
              ),
            ),
          ),
        // Bloqueos
        for (final bl in blocks)
          for (var i = 0; i < cols.length; i++)
            if (bl['member_id'] == null || bl['member_id'] == cols[i].id)
              Positioned(
                left: _gutter + i * colW + 1,
                top: top(_blockStart(bl)),
                width: colW - 2,
                height: height(_blockStart(bl), _blockEnd(bl)),
                child: GestureDetector(
                  onTap: () => _deleteBlock(bl),
                  child: _HatchedBlock(title: bl['title']?.toString()),
                ),
              ),
        // Reservas
        for (final b in bookings)
          Positioned(
            left: _gutter + colIndex(b.memberId) * colW + 3,
            top: top(b.startsAt),
            width: colW - 6,
            height: height(b.startsAt, b.endsAt),
            child: _BookingBlock(booking: b, onTap: () => _openBooking(b.id)),
          ),
        // Línea de "ahora"
        if (isToday && now.hour >= _startHour && now.hour < _endHour)
          Positioned(
            top: top(now),
            left: _gutter - 6,
            width: totalW - _gutter + 6,
            child: IgnorePointer(
              child: Row(children: [
                Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(color: AppTheme.danger, shape: BoxShape.circle)),
                const Expanded(child: SizedBox(height: 2, child: ColoredBox(color: AppTheme.danger))),
              ]),
            ),
          ),
      ];

      return SingleChildScrollView(
        controller: _vScroll,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: totalW,
            child: Column(children: [
              Row(children: [
                const SizedBox(width: _gutter),
                for (final col in cols)
                  SizedBox(
                    width: colW,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(color: col.color, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(col.name,
                              overflow: TextOverflow.ellipsis,
                              style: t.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                        ),
                      ]),
                    ),
                  ),
              ]),
              SizedBox(
                height: _gridHeight + 20,
                child: Stack(clipBehavior: Clip.none, children: children),
              ),
              const SizedBox(height: 90),
            ]),
          ),
        ),
      );
    });
  }

  /// Vista de día en móvil con "Todos": lista cronológica fusionada.
  Widget _dayList(List<Booking> bookings, List<Map<String, dynamic>> blocks) {
    final t = Theme.of(context);
    final rows = <(DateTime, Widget)>[
      for (final b in bookings)
        (
          b.startsAt,
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _openBooking(b.id),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  SizedBox(
                    width: 48,
                    child: Column(children: [
                      Text(Fmt.time(b.startsAt),
                          style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                      Text(Fmt.time(b.endsAt),
                          style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.outline)),
                    ]),
                  ),
                  Container(
                      width: 4,
                      height: 40,
                      margin: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                          color: hexColor(b.memberColor), borderRadius: BorderRadius.circular(2))),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(b.customerName ?? session.customerLabel,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(b.servicesSummary ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
                      if (b.memberName != null)
                        Text(b.memberName!,
                            style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.outline)),
                    ]),
                  ),
                  StatusChip(b.status),
                ]),
              ),
            ),
          ),
        ),
      for (final bl in blocks)
        (
          _blockStart(bl),
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            color: t.colorScheme.surfaceContainerHighest,
            child: ListTile(
              leading: const Icon(Icons.block),
              title: Text(bl['title']?.toString() ?? 'Bloqueo'),
              subtitle: Text(Fmt.range(_blockStart(bl), _blockEnd(bl))),
              trailing: IconButton(
                  onPressed: () => _deleteBlock(bl), icon: const Icon(Icons.delete_outline)),
            ),
          ),
        ),
    ]..sort((a, b) => a.$1.compareTo(b.$1));

    return RefreshIndicator(
      onRefresh: _load,
      child: rows.isEmpty
          ? ListView(children: [
              const SizedBox(height: 40),
              EmptyView(
                icon: Icons.event_available_outlined,
                title: 'Sin ${session.bookingLabel.toLowerCase()}s este día',
                subtitle: 'Toca "Nueva ${session.bookingLabel.toLowerCase()}" para añadir una.',
              ),
            ])
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              children: [for (final r in rows) r.$2],
            ),
    );
  }

  // ---------- Vista de semana ----------

  Widget _weekView() {
    final t = Theme.of(context);
    final start = _weekStart(_day);
    final today = _dateOnly(DateTime.now());
    final bookings = _visibleBookings;
    final blocks = _visibleBlocks;
    return LayoutBuilder(builder: (ctx, c) {
      final colW = math.max(130.0, c.maxWidth / 7);
      return SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < 7; i++)
              Builder(builder: (_) {
                final d = start.add(Duration(days: i));
                final dayBookings = bookings.where((b) => _dateOnly(b.startsAt) == d).toList();
                final dayBlocks = blocks.where((bl) => _dateOnly(_blockStart(bl)) == d).toList();
                final isToday = d == today;
                return Container(
                  width: colW,
                  decoration: BoxDecoration(
                    border: Border(
                        left: BorderSide(color: t.colorScheme.outlineVariant.withValues(alpha: 0.6))),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    InkWell(
                      onTap: () {
                        setState(() {
                          _day = d;
                          _week = false;
                        });
                        _load();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        color: isToday ? t.colorScheme.primary.withValues(alpha: 0.08) : null,
                        child: Column(children: [
                          Text(Fmt.weekdaysShort[d.weekday % 7],
                              style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.outline)),
                          Text('${d.day}',
                              style: t.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: isToday ? t.colorScheme.primary : null)),
                          Text('${dayBookings.length} cita${dayBookings.length == 1 ? '' : 's'}',
                              style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.outline)),
                        ]),
                      ),
                    ),
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 4, 4, 100),
                      child: Column(children: [
                        for (final bl in dayBlocks)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: InkWell(
                              onTap: () => _deleteBlock(bl),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                decoration: BoxDecoration(
                                    color: t.colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(6)),
                                child: Text(
                                    '${Fmt.time(_blockStart(bl))} ${bl['title'] ?? 'Bloqueo'}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: t.textTheme.labelSmall),
                              ),
                            ),
                          ),
                        for (final b in dayBookings)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: InkWell(
                              onTap: () => _openBooking(b.id),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                decoration: BoxDecoration(
                                  color: hexColor(b.memberColor).withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border(
                                      left: BorderSide(
                                          color: bookingStatusColor(b.status), width: 3)),
                                ),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('${Fmt.time(b.startsAt)} ${b.customerName ?? ''}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: t.textTheme.labelSmall
                                          ?.copyWith(fontWeight: FontWeight.w700)),
                                  if (b.servicesSummary != null)
                                    Text(b.servicesSummary!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: t.textTheme.labelSmall
                                            ?.copyWith(color: t.colorScheme.outline)),
                                ]),
                              ),
                            ),
                          ),
                      ]),
                    ),
                  ]),
                );
              }),
          ]),
        ),
      );
    });
  }
}

// ---------------------------------------------------------------- Widgets

class _BookingBlock extends StatelessWidget {
  final Booking booking;
  final VoidCallback onTap;
  const _BookingBlock({required this.booking, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final t = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: LayoutBuilder(builder: (_, c) {
        final tall = c.maxHeight >= 38;
        return Container(
          padding: const EdgeInsets.fromLTRB(6, 2, 4, 2),
          decoration: BoxDecoration(
            color: hexColor(b.memberColor).withValues(alpha: b.status == 'completed' ? 0.10 : 0.20),
            borderRadius: BorderRadius.circular(6),
            border: Border(left: BorderSide(color: bookingStatusColor(b.status), width: 3)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              '${Fmt.time(b.startsAt)} · ${b.customerName ?? ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, height: 1.1),
            ),
            if (tall && b.servicesSummary != null)
              Text(b.servicesSummary!,
                  maxLines: c.maxHeight >= 56 ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.outline, height: 1.1)),
          ]),
        );
      }),
    );
  }
}

class _HatchedBlock extends StatelessWidget {
  final String? title;
  const _HatchedBlock({this.title});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: CustomPaint(
        painter: _HatchPainter(t.colorScheme.outline.withValues(alpha: 0.35)),
        child: Container(
          color: t.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          alignment: Alignment.topLeft,
          child: Text(title ?? 'Bloqueado',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

class _HatchPainter extends CustomPainter {
  final Color color;
  _HatchPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    const step = 8.0;
    for (double x = -size.height; x < size.width; x += step) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
    }
  }

  @override
  bool shouldRepaint(_HatchPainter old) => old.color != color;
}

// ---------------------------------------------------------------- Bloqueos

/// Diálogo para bloquear un tramo de tiempo (vacaciones, comida, reunión…).
/// Devuelve true si se creó el bloqueo.
Future<bool> showTimeBlockDialog(BuildContext context,
    {DateTime? initialStart, String? memberId}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (_) => _TimeBlockDialog(initialStart: initialStart, memberId: memberId),
  );
  return r ?? false;
}

class _TimeBlockDialog extends StatefulWidget {
  final DateTime? initialStart;
  final String? memberId;
  const _TimeBlockDialog({this.initialStart, this.memberId});
  @override
  State<_TimeBlockDialog> createState() => _TimeBlockDialogState();
}

class _TimeBlockDialogState extends State<_TimeBlockDialog> {
  final session = AppSession.instance;
  List<Member> _members = [];
  String? _memberId;
  late DateTime _date;
  late TimeOfDay _start;
  late TimeOfDay _end;
  final _title = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final s = widget.initialStart ?? DateTime.now();
    _date = DateTime(s.year, s.month, s.day);
    _start = TimeOfDay(hour: s.hour, minute: (s.minute ~/ 15) * 15);
    _end = TimeOfDay(hour: math.min(23, s.hour + 1), minute: _start.minute);
    _memberId = widget.memberId;
    session.biz.fetchMembers(session.activeBusiness!.id, onlyActive: true).then((m) {
      if (mounted) setState(() => _members = m);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final starts = DateTime(_date.year, _date.month, _date.day, _start.hour, _start.minute);
    final ends = DateTime(_date.year, _date.month, _date.day, _end.hour, _end.minute);
    if (!ends.isAfter(starts)) {
      showSnack(context, 'La hora de fin debe ser posterior a la de inicio', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await session.biz.addTimeBlock(
        businessId: session.activeBusiness!.id,
        memberId: _memberId,
        startsAt: starts,
        endsAt: ends,
        title: _title.text.trim().isEmpty ? null : _title.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showSnack(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Bloquear tiempo'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            DropdownButtonFormField<String?>(
              key: ValueKey('${_memberId}_${_members.length}'),
              initialValue: _memberId,
              decoration: InputDecoration(labelText: session.staffLabel),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Todo el equipo')),
                for (final m in _members)
                  DropdownMenuItem<String?>(value: m.id, child: Text(m.displayName)),
              ],
              onChanged: (v) => setState(() => _memberId = v),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final d = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 730)));
                if (d != null && mounted) setState(() => _date = DateTime(d.year, d.month, d.day));
              },
              icon: const Icon(Icons.calendar_today_outlined, size: 18),
              label: Text(Fmt.dayLong(_date)),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final v = await showTimePicker(context: context, initialTime: _start);
                    if (v != null && mounted) setState(() => _start = v);
                  },
                  child: Text('Inicio ${_start.format(context)}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final v = await showTimePicker(context: context, initialTime: _end);
                    if (v != null && mounted) setState(() => _end = v);
                  },
                  child: Text('Fin ${_end.format(context)}'),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Motivo (comida, reunión, vacaciones…)'),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Bloquear')),
      ],
    );
  }
}
