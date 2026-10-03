import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/models.dart';
import '../../services/app_session.dart';
import '../../utils/format.dart';
import '../../utils/friendly_errors.dart';
import '../../widgets/admin_widgets.dart';
import '../../widgets/common.dart';

const _roles = <String, String>{
  'owner': 'Propietario',
  'manager': 'Gestor',
  'staff': 'Profesional',
  'reception': 'Recepción',
};

String roleLabel(String role) => _roles[role] ?? role;

Color _roleColor(String role) {
  switch (role) {
    case 'owner':
      return AppTheme.primary;
    case 'manager':
      return const Color(0xFF0EA5E9);
    case 'reception':
      return AppTheme.warning;
    default:
      return AppTheme.accent;
  }
}

/// Equipo del negocio: profesionales, roles, horarios y ausencias.
class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key});
  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  final session = AppSession.instance;
  bool _loading = true;
  String? _error;
  List<Member> _members = [];

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
      final m = await session.biz.fetchMembers(_businessId);
      if (!mounted) return;
      setState(() {
        _members = m;
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

  Future<void> _openEdit([Member? m]) async {
    final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => MemberEditScreen(member: m)));
    if (changed == true) _load();
  }

  void _fabMenu() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.person_add_alt_1_outlined),
            title: Text('Añadir ${session.staffLabel.toLowerCase()}'),
            subtitle: const Text('Sin cuenta de usuario. Solo aparece en la agenda.'),
            onTap: () {
              Navigator.pop(c);
              _openEdit();
            },
          ),
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: const Text('Invitar por email'),
            subtitle: const Text('Recibirá un enlace para unirse con su propia cuenta.'),
            onTap: () {
              Navigator.pop(c);
              _invite();
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _invite() async {
    final emailCtrl = TextEditingController();
    var role = 'staff';
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Invitar por email'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: emailCtrl,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: role,
              decoration: const InputDecoration(labelText: 'Rol'),
              items: [
                for (final e in _roles.entries)
                  if (e.key != 'owner')
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setLocal(() => role = v ?? 'staff'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Invitar')),
          ],
        ),
      ),
    );
    final email = emailCtrl.text.trim();
    if (ok != true || !mounted) return;
    if (!email.contains('@')) {
      showSnack(context, 'Introduce un email válido', error: true);
      return;
    }
    try {
      await session.biz.inviteMember(_businessId, email, role);
      if (!mounted) return;
      showSnack(context, 'Invitación enviada a $email');
    } catch (e) {
      if (!mounted) return;
      showSnack(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(pluralEs(session.staffLabel)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load, tooltip: 'Actualizar'),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _fabMenu,
        icon: const Icon(Icons.add),
        label: const Text('Añadir'),
      ),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(_error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: MaxWidth(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      children: [
                        if (_members.isEmpty)
                          EmptyView(
                              icon: Icons.badge_outlined,
                              title: 'Todavía no hay equipo',
                              subtitle:
                                  'Añade ${pluralEs(session.staffLabel).toLowerCase()} para asignarles servicios y horarios.'),
                        Card(
                          child: Column(children: [
                            for (var i = 0; i < _members.length; i++) ...[
                              if (i > 0) const Divider(indent: 72),
                              _memberTile(_members[i], t),
                            ],
                          ]),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _memberTile(Member m, ThemeData t) {
    final color = hexColor(m.color);
    return ListTile(
      onTap: () => _openEdit(m),
      leading: AvatarCircle(
        url: m.avatarUrl,
        initials: m.displayName.isEmpty ? '?' : m.displayName[0].toUpperCase(),
        color: color,
        radius: 22,
      ),
      title: Text(m.displayName,
          style: TextStyle(
              fontWeight: FontWeight.w600,
              color: m.active ? null : t.colorScheme.outline)),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (m.title != null && m.title!.isNotEmpty) Text(m.title!),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 4, children: [
          SmallBadge(roleLabel(m.role), color: _roleColor(m.role)),
          if (m.bookable)
            const SmallBadge('Reservable', icon: Icons.event_available, color: AppTheme.accent),
          if (!m.active)
            const SmallBadge('Inactivo', icon: Icons.visibility_off_outlined, color: Colors.grey),
          if (m.userId == null)
            const SmallBadge('Sin cuenta', icon: Icons.person_off_outlined, color: Colors.grey),
        ]),
      ]),
      isThreeLine: true,
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

// ============================================================ Edición

class _Range {
  String start;
  String end;
  _Range(this.start, this.end);
}

class _DayPlan {
  bool works;
  List<_Range> ranges;
  _DayPlan({this.works = false, List<_Range>? ranges})
      : ranges = ranges ?? [_Range('09:00', '18:00')];
}

/// Ficha de un miembro del equipo: datos, rol, horario semanal y ausencias.
class MemberEditScreen extends StatefulWidget {
  final Member? member;
  const MemberEditScreen({super.key, this.member});
  @override
  State<MemberEditScreen> createState() => _MemberEditScreenState();
}

class _MemberEditScreenState extends State<MemberEditScreen> {
  final session = AppSession.instance;
  final _formKey = GlobalKey<FormState>();

  late final _name = TextEditingController(text: widget.member?.displayName ?? '');
  late final _title = TextEditingController(text: widget.member?.title ?? '');
  late final _commission =
      TextEditingController(text: '${widget.member?.commissionPct ?? 0}');
  late String _role = widget.member?.role ?? 'staff';
  late String _color = widget.member?.color ?? adminColorPresets[1];
  late bool _bookable = widget.member?.bookable ?? true;
  late bool _active = widget.member?.active ?? true;

  /// Orden Lun..Dom → weekday 1..6,0
  static const _weekOrder = [1, 2, 3, 4, 5, 6, 0];
  final Map<int, _DayPlan> _week = {
    for (final d in [1, 2, 3, 4, 5]) d: _DayPlan(works: true),
    6: _DayPlan(),
    0: _DayPlan(),
  };

  List<Map<String, dynamic>> _overrides = [];
  bool _loading = true;
  bool _saving = false;

  String get _businessId => session.activeBusiness!.id;
  bool get _iAmOwner => session.activeMembership?.role == 'owner';
  bool get _isNew => widget.member == null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _title.dispose();
    _commission.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final m = widget.member;
    if (m == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final biz = session.biz;
      final today = DateTime.now();
      final hours = await biz.fetchWorkingHours(_businessId, memberId: m.id);
      final overrides = await biz.fetchScheduleOverrides(
          _businessId, today, today.add(const Duration(days: 365)));
      if (!mounted) return;
      setState(() {
        if (hours.isNotEmpty) {
          for (final d in _week.keys) {
            _week[d] = _DayPlan(works: false, ranges: []);
          }
          for (final h in hours) {
            final plan = _week[h.weekday]!;
            plan.works = true;
            if (plan.ranges.length < 2) plan.ranges.add(_Range(h.startTime, h.endTime));
          }
          for (final p in _week.values) {
            if (p.ranges.isEmpty) p.ranges.add(_Range('09:00', '18:00'));
          }
        }
        _overrides = overrides.where((o) => o['member_id'] == m.id).toList();
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
      final biz = session.biz;
      final saved = await biz.upsertMember({
        if (widget.member != null) 'id': widget.member!.id,
        'business_id': _businessId,
        if (widget.member?.userId != null) 'user_id': widget.member!.userId,
        'display_name': _name.text.trim(),
        'title': _title.text.trim().isEmpty ? null : _title.text.trim(),
        'role': _role,
        'color': _color,
        'bookable': _bookable,
        'active': _active,
        'commission_pct': (int.tryParse(_commission.text) ?? 0).clamp(0, 100),
      });
      final hours = <WorkingHours>[];
      for (final e in _week.entries) {
        if (!e.value.works) continue;
        for (final r in e.value.ranges) {
          if (_toMinutes(r.end) <= _toMinutes(r.start)) {
            throw Exception(
                'Horario no válido el ${Fmt.weekdaysLong[e.key].toLowerCase()}: la hora de fin debe ser posterior a la de inicio.');
          }
          hours.add(WorkingHours(
              businessId: _businessId,
              memberId: saved.id,
              weekday: e.key,
              startTime: r.start,
              endTime: r.end));
        }
      }
      await biz.replaceWorkingHours(_businessId, saved.id, hours);
      if (!mounted) return;
      showSnack(context, 'Guardado');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSnack(context, friendlyError(e), error: true);
    }
  }

  static int _toMinutes(String hhmm) {
    final p = hhmm.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  static String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickTime(_Range r, bool start) async {
    final cur = start ? r.start : r.end;
    final parts = cur.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
      builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
          child: child!),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        r.start = _fmt(picked);
      } else {
        r.end = _fmt(picked);
      }
    });
  }

  // ---------- Ausencias ----------

  Future<void> _addAbsence() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Periodo de ausencia',
      saveText: 'Siguiente',
    );
    if (range == null || !mounted) return;
    final reasonCtrl = TextEditingController(text: 'Vacaciones');
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Motivo'),
        content: TextField(
          controller: reasonCtrl,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: 'Motivo', hintText: 'Vacaciones, baja, formación…'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Añadir')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      var d = DateTime(range.start.year, range.start.month, range.start.day);
      final end = DateTime(range.end.year, range.end.month, range.end.day);
      var n = 0;
      while (!d.isAfter(end)) {
        await session.biz.addScheduleOverride(
          businessId: _businessId,
          memberId: widget.member!.id,
          date: d,
          isClosed: true,
          reason: reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim(),
        );
        n++;
        d = d.add(const Duration(days: 1));
      }
      if (!mounted) return;
      showSnack(context, 'Ausencia añadida ($n ${n == 1 ? 'día' : 'días'})');
      _load();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _deleteOverride(Map<String, dynamic> o) async {
    try {
      await session.biz.deleteScheduleOverride(o['id'] as String);
      if (!mounted) return;
      setState(() => _overrides.removeWhere((x) => x['id'] == o['id']));
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
        title: Text(_isNew ? 'Nuevo ${session.staffLabel.toLowerCase()}' : widget.member!.displayName),
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
                    _dataCard(),
                    const SizedBox(height: 12),
                    _scheduleCard(),
                    const SizedBox(height: 12),
                    _absencesCard(),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(_isNew ? 'Crear' : 'Guardar cambios'),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _dataCard() {
    final m = widget.member;
    final roleLocked = m?.role == 'owner' && !_iAmOwner;
    return FormCard(title: 'Datos', children: [
      ResponsiveFields(children: [
        TextFormField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Nombre *'),
          validator: (v) => (v ?? '').trim().isEmpty ? 'Obligatorio' : null,
        ),
        TextFormField(
          controller: _title,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
              labelText: 'Cargo / especialidad', hintText: 'Estilista senior, Fisioterapeuta…'),
        ),
      ]),
      const SizedBox(height: 12),
      ResponsiveFields(children: [
        DropdownButtonFormField<String>(
          initialValue: _role,
          decoration: InputDecoration(
              labelText: 'Rol',
              helperText: roleLocked
                  ? 'Solo el propietario puede cambiar este rol'
                  : 'Gestor: todo salvo cerrar el negocio. Recepción: agenda y cobros.'),
          items: [
            for (final e in _roles.entries)
              if (e.key != 'owner' || _iAmOwner || _role == 'owner')
                DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: roleLocked ? null : (v) => setState(() => _role = v ?? 'staff'),
        ),
        TextFormField(
          controller: _commission,
          keyboardType: TextInputType.number,
          inputFormatters: intInputFormatters,
          decoration: const InputDecoration(
              labelText: 'Comisión', suffixText: '%', helperText: 'Sobre los servicios realizados'),
        ),
      ]),
      const SizedBox(height: 16),
      Text('Color en la agenda', style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 8),
      ColorPresetPicker(value: _color, onChanged: (c) => setState(() => _color = c)),
      const SizedBox(height: 8),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Reservable'),
        subtitle: const Text('Aparece como opción al reservar y tiene agenda propia'),
        value: _bookable,
        onChanged: (v) => setState(() => _bookable = v),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Activo'),
        subtitle: const Text('Desactívalo si deja el negocio; se conserva su historial'),
        value: _active,
        onChanged: (v) => setState(() => _active = v),
      ),
    ]);
  }

  Widget _scheduleCard() {
    final t = Theme.of(context);
    return FormCard(title: 'Horario semanal', children: [
      Text('Define los tramos en los que acepta reservas. Puedes añadir un segundo tramo (p. ej. mañana y tarde).',
          style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
      const SizedBox(height: 8),
      for (final d in _weekOrder) _dayRow(d, t),
    ]);
  }

  Widget _dayRow(int weekday, ThemeData t) {
    final plan = _week[weekday]!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Switch(value: plan.works, onChanged: (v) => setState(() => plan.works = v)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(Fmt.weekdaysLong[weekday],
                style: t.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: plan.works ? null : t.colorScheme.outline)),
          ),
          if (plan.works && plan.ranges.length < 2)
            TextButton.icon(
              onPressed: () => setState(() => plan.ranges.add(_Range('16:00', '20:00'))),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Tramo'),
            ),
          if (!plan.works)
            Text('No trabaja', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
        ]),
        if (plan.works)
          Padding(
            padding: const EdgeInsets.only(left: 64),
            child: Column(children: [
              for (var i = 0; i < plan.ranges.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    _timeChip(plan.ranges[i], true),
                    const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8), child: Text('–')),
                    _timeChip(plan.ranges[i], false),
                    if (plan.ranges.length > 1)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() => plan.ranges.removeAt(i)),
                      ),
                  ]),
                ),
            ]),
          ),
      ]),
    );
  }

  Widget _timeChip(_Range r, bool start) => ActionChip(
        avatar: const Icon(Icons.schedule, size: 16),
        label: Text(start ? r.start : r.end),
        onPressed: () => _pickTime(r, start),
      );

  Widget _absencesCard() {
    final t = Theme.of(context);
    if (_isNew) {
      return const FormCard(title: 'Ausencias / vacaciones', children: [
        InlineEmpty('Guarda primero la ficha para poder añadir ausencias.'),
      ]);
    }
    return FormCard(
      title: 'Ausencias / vacaciones',
      trailing: TextButton.icon(
        onPressed: _addAbsence,
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Añadir ausencia'),
      ),
      children: [
        if (_overrides.isEmpty)
          const InlineEmpty('Sin ausencias programadas en los próximos 12 meses.'),
        for (final o in _overrides)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
                (o['is_closed'] as bool? ?? true) ? Icons.event_busy : Icons.schedule,
                color: AppTheme.danger),
            title: Text(Fmt.dayLong(DateTime.parse(o['date'].toString()))),
            subtitle: Text(
                (o['is_closed'] as bool? ?? true)
                    ? (o['reason']?.toString() ?? 'Ausencia')
                    : 'Horario especial ${o['start_time']?.toString().substring(0, 5)} – ${o['end_time']?.toString().substring(0, 5)}',
                style: t.textTheme.bodySmall),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Eliminar',
              onPressed: () => _deleteOverride(o),
            ),
          ),
      ],
    );
  }
}
