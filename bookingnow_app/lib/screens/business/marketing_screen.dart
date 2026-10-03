import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../app_theme.dart';
import '../../models/models.dart';
import '../../services/admin_extra.dart';
import '../../services/app_session.dart';
import '../../utils/format.dart';
import '../../utils/friendly_errors.dart';
import '../../widgets/admin_widgets.dart';
import '../../widgets/common.dart';
import 'integrations_screen.dart';

enum _Segment { all, inactive60, noShows }

/// Marketing: códigos promocionales, campañas y página pública.
class MarketingScreen extends StatefulWidget {
  const MarketingScreen({super.key});
  @override
  State<MarketingScreen> createState() => _MarketingScreenState();
}

class _MarketingScreenState extends State<MarketingScreen> {
  final session = AppSession.instance;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _promos = [];
  List<Customer> _customers = [];

  // Campaña
  String _channel = 'push';
  _Segment _segment = _Segment.all;
  final _title = TextEditingController();
  final _message = TextEditingController();
  bool _sending = false;

  String get _businessId => session.activeBusiness!.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        session.biz.fetchPromoCodes(_businessId),
        session.biz.fetchCustomers(_businessId, limit: 2000),
      ]);
      if (!mounted) return;
      setState(() {
        _promos = results[0] as List<Map<String, dynamic>>;
        _customers = results[1] as List<Customer>;
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

  // ---------- Promociones ----------

  Future<void> _editPromo([Map<String, dynamic>? p]) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _PromoDialog(promo: p),
    );
    if (result == null || !mounted) return;
    try {
      await session.biz.upsertPromoCode({
        if (p != null) 'id': p['id'],
        'business_id': _businessId,
        ...result,
      });
      if (!mounted) return;
      showSnack(context, 'Código guardado');
      _load();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _deletePromo(Map<String, dynamic> p) async {
    final ok = await confirmDialog(context,
        title: 'Eliminar código',
        message: '¿Eliminar el código ${p['code']}?',
        confirmLabel: 'Eliminar',
        destructive: true);
    if (!ok || !mounted) return;
    try {
      await session.biz.deletePromoCode(p['id'] as String);
      if (!mounted) return;
      _load();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, friendlyError(e), error: true);
    }
  }

  // ---------- Campañas ----------

  List<Customer> get _segmentCustomers {
    final now = DateTime.now();
    switch (_segment) {
      case _Segment.all:
        return _customers.where((c) => !c.blocked).toList();
      case _Segment.inactive60:
        return _customers
            .where((c) =>
                !c.blocked &&
                (c.lastVisitAt == null || now.difference(c.lastVisitAt!).inDays >= 60))
            .toList();
      case _Segment.noShows:
        return _customers.where((c) => !c.blocked && c.noShowCount > 0).toList();
    }
  }

  Future<void> _send() async {
    final targets = _segmentCustomers;
    if (_title.text.trim().isEmpty || _message.text.trim().isEmpty) {
      showSnack(context, 'Escribe un título y un mensaje', error: true);
      return;
    }
    if (targets.isEmpty) {
      showSnack(context, 'No hay clientes en ese segmento', error: true);
      return;
    }
    final ok = await confirmDialog(context,
        title: 'Enviar campaña',
        message:
            'Se enviará por ${_channelLabel(_channel)} a ${targets.length} ${targets.length == 1 ? 'cliente' : 'clientes'}. ¿Continuar?',
        confirmLabel: 'Enviar');
    if (!ok || !mounted) return;
    setState(() => _sending = true);
    try {
      final n = await session.biz.sendCampaign(
        businessId: _businessId,
        channel: _channel,
        title: _title.text.trim(),
        body: _message.text.trim(),
        customerIds: _segment == _Segment.all ? null : targets.map((c) => c.id).toList(),
      );
      if (!mounted) return;
      showSnack(context, 'Campaña encolada: $n ${n == 1 ? 'envío' : 'envíos'}');
      _title.clear();
      _message.clear();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  static String _channelLabel(String c) {
    switch (c) {
      case 'email':
        return 'email';
      case 'sms':
        return 'SMS';
      case 'whatsapp':
        return 'WhatsApp';
      default:
        return 'notificación push';
    }
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Marketing'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load, tooltip: 'Actualizar'),
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
                        _publicPageCard(),
                        SectionTitle('Códigos promocionales',
                            trailing: TextButton.icon(
                              onPressed: () => _editPromo(),
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Nuevo código'),
                            )),
                        _promosCard(),
                        const SectionTitle('Campañas'),
                        _campaignCard(),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _publicPageCard() {
    final t = Theme.of(context);
    final b = session.activeBusiness!;
    final url = publicBookingUrl(b.slug);
    return FormCard(title: 'Página pública de reservas', children: [
      LayoutBuilder(builder: (context, c) {
        final qr = Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: QrImageView(data: url, size: 120),
        );
        final info = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SelectableText(url,
              style: t.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600, color: t.colorScheme.primary)),
          const SizedBox(height: 4),
          Text(
              b.isPublished
                  ? 'Publicada en el marketplace.'
                  : 'Aún no publicada en el marketplace (actívalo en Ajustes → Página pública). El enlace directo funciona igualmente.',
              style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              onPressed: () => copyToClipboard(context, url, message: 'Enlace copiado'),
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copiar'),
            ),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              onPressed: () => SharePlus.instance.share(ShareParams(text: 'Reserva tu ${session.bookingLabel.toLowerCase()} en ${b.name}: $url')),
              icon: const Icon(Icons.share_outlined, size: 18),
              label: const Text('Compartir'),
            ),
          ]),
          const SizedBox(height: 10),
          InkWell(
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const IntegrationsScreen())),
            child: Row(children: [
              const Icon(Icons.tips_and_updates_outlined, size: 16, color: AppTheme.warning),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                    'Consigue reservas desde Google Maps (Reserve with Google) e Instagram: conéctalo en Integraciones.',
                    style: t.textTheme.bodySmall?.copyWith(
                        color: t.colorScheme.primary, decoration: TextDecoration.underline)),
              ),
            ]),
          ),
        ]);
        if (c.maxWidth < 480) {
          return Column(children: [qr, const SizedBox(height: 12), info]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          qr,
          const SizedBox(width: 16),
          Expanded(child: info),
        ]);
      }),
    ]);
  }

  Widget _promosCard() {
    final t = Theme.of(context);
    if (_promos.isEmpty) {
      return const Card(
        child: InlineEmpty(
            'Sin códigos. Crea descuentos por porcentaje o importe fijo, con fechas y límite de usos.'),
      );
    }
    return Card(
      child: Column(children: [
        for (var i = 0; i < _promos.length; i++) ...[
          if (i > 0) const Divider(indent: 16),
          _promoTile(_promos[i], t),
        ],
      ]),
    );
  }

  Widget _promoTile(Map<String, dynamic> p, ThemeData t) {
    final pct = p['discount_pct'];
    final cents = p['discount_cents'];
    final discount = pct != null ? '-$pct %' : (cents != null ? '-${formatEuros(cents as int)}' : '');
    final active = p['active'] as bool? ?? true;
    final from = p['valid_from'] != null ? DateTime.tryParse(p['valid_from'].toString()) : null;
    final until = p['valid_until'] != null ? DateTime.tryParse(p['valid_until'].toString()) : null;
    final uses = p['uses'] ?? 0;
    final maxUses = p['max_uses'];
    final expired = until != null && until.isBefore(DateTime.now());
    final parts = <String>[
      if (from != null || until != null)
        '${from != null ? Fmt.date(from) : '…'} → ${until != null ? Fmt.date(until) : '…'}',
      'usos: $uses${maxUses != null ? '/$maxUses' : ''}',
      if (p['first_visit_only'] == true) 'solo 1ª visita',
    ];
    return ListTile(
      onTap: () => _editPromo(p),
      leading: CircleAvatar(
        backgroundColor: AppTheme.accent.withValues(alpha: 0.15),
        child: const Icon(Icons.local_offer_outlined, color: AppTheme.accent, size: 20),
      ),
      title: Row(children: [
        Text(p['code'].toString(),
            style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
        const SizedBox(width: 8),
        Text(discount, style: TextStyle(color: t.colorScheme.primary, fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        if (!active)
          const SmallBadge('Inactivo', color: Colors.grey)
        else if (expired)
          const SmallBadge('Caducado', color: AppTheme.danger),
      ]),
      subtitle: Text(parts.join(' · ')),
      trailing: PopupMenuButton<String>(
        onSelected: (v) async {
          if (v == 'edit') _editPromo(p);
          if (v == 'toggle') {
            try {
              await session.biz.upsertPromoCode({
                'id': p['id'],
                'business_id': _businessId,
                'code': p['code'],
                'active': !active,
              });
              if (!mounted) return;
              _load();
            } catch (e) {
              if (!mounted) return;
              showSnack(context, friendlyError(e), error: true);
            }
          }
          if (v == 'delete') _deletePromo(p);
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'edit', child: Text('Editar')),
          PopupMenuItem(value: 'toggle', child: Text(active ? 'Desactivar' : 'Activar')),
          const PopupMenuItem(
              value: 'delete',
              child: Text('Eliminar', style: TextStyle(color: AppTheme.danger))),
        ],
      ),
    );
  }

  Widget _campaignCard() {
    final t = Theme.of(context);
    final count = _segmentCustomers.length;
    return FormCard(children: [
      ResponsiveFields(children: [
        DropdownButtonFormField<String>(
          initialValue: _channel,
          decoration: const InputDecoration(labelText: 'Canal'),
          items: const [
            DropdownMenuItem(value: 'push', child: Text('Notificación push (app)')),
            DropdownMenuItem(value: 'email', child: Text('Email')),
            DropdownMenuItem(value: 'sms', child: Text('SMS')),
            DropdownMenuItem(value: 'whatsapp', child: Text('WhatsApp')),
          ],
          onChanged: (v) => setState(() => _channel = v ?? 'push'),
        ),
        DropdownButtonFormField<_Segment>(
          initialValue: _segment,
          decoration: const InputDecoration(labelText: 'Segmento'),
          items: const [
            DropdownMenuItem(value: _Segment.all, child: Text('Todos los clientes')),
            DropdownMenuItem(value: _Segment.inactive60, child: Text('Sin visita en 60 días')),
            DropdownMenuItem(value: _Segment.noShows, child: Text('Con no-shows')),
          ],
          onChanged: (v) => setState(() => _segment = v ?? _Segment.all),
        ),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Icon(Icons.people_outline, size: 16, color: t.colorScheme.outline),
        const SizedBox(width: 6),
        Text('$count ${count == 1 ? 'destinatario' : 'destinatarios'}',
            style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
      ]),
      const SizedBox(height: 12),
      TextField(
        controller: _title,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'Título', hintText: '¡Te echamos de menos!'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _message,
        maxLines: 4,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
            labelText: 'Mensaje',
            hintText: 'Reserva esta semana y llévate un 10 % de descuento con el código VUELVE10.'),
      ),
      if (_channel == 'sms' || _channel == 'whatsapp') ...[
        const SizedBox(height: 10),
        InfoCard(
            'Los envíos por ${_channel == 'sms' ? 'SMS (Twilio)' : 'WhatsApp (Meta)'} requieren la integración activa y pueden tener coste por mensaje.',
            icon: Icons.info_outline),
      ],
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: _sending ? null : _send,
        icon: _sending
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.send_outlined),
        label: const Text('Enviar campaña'),
      ),
    ]);
  }
}

// ============================================================ Diálogo promo

class _PromoDialog extends StatefulWidget {
  final Map<String, dynamic>? promo;
  const _PromoDialog({this.promo});
  @override
  State<_PromoDialog> createState() => _PromoDialogState();
}

class _PromoDialogState extends State<_PromoDialog> {
  late final _code = TextEditingController(text: widget.promo?['code']?.toString() ?? '');
  late bool _isPct = widget.promo == null || widget.promo!['discount_pct'] != null;
  late final _value = TextEditingController(
      text: widget.promo == null
          ? '10'
          : widget.promo!['discount_pct'] != null
              ? '${widget.promo!['discount_pct']}'
              : centsToInput((widget.promo!['discount_cents'] as int?) ?? 0));
  late final _maxUses =
      TextEditingController(text: widget.promo?['max_uses']?.toString() ?? '');
  late DateTime? _from = widget.promo?['valid_from'] != null
      ? DateTime.tryParse(widget.promo!['valid_from'].toString())
      : null;
  late DateTime? _until = widget.promo?['valid_until'] != null
      ? DateTime.tryParse(widget.promo!['valid_until'].toString())
      : null;
  late bool _firstVisit = widget.promo?['first_visit_only'] as bool? ?? false;
  late bool _active = widget.promo?['active'] as bool? ?? true;

  @override
  void dispose() {
    _code.dispose();
    _value.dispose();
    _maxUses.dispose();
    super.dispose();
  }

  static String _d(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pick(bool from) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: (from ? _from : _until) ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (d == null) return;
    setState(() {
      if (from) {
        _from = d;
      } else {
        _until = d;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.promo == null ? 'Nuevo código' : 'Editar código'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: _code,
              autofocus: widget.promo == null,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Código', hintText: 'VERANO10'),
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Porcentaje'), icon: Icon(Icons.percent)),
                ButtonSegment(value: false, label: Text('Importe fijo'), icon: Icon(Icons.euro)),
              ],
              selected: {_isPct},
              onSelectionChanged: (s) => setState(() => _isPct = s.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _value,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: _isPct ? intInputFormatters : euroInputFormatters,
              decoration: InputDecoration(
                  labelText: 'Descuento', suffixText: _isPct ? '%' : '€'),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: () => _pick(true),
                  icon: const Icon(Icons.event, size: 16),
                  label: Text(_from == null ? 'Desde' : Fmt.date(_from!)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: () => _pick(false),
                  icon: const Icon(Icons.event, size: 16),
                  label: Text(_until == null ? 'Hasta' : Fmt.date(_until!)),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _maxUses,
              keyboardType: TextInputType.number,
              inputFormatters: intInputFormatters,
              decoration: const InputDecoration(
                  labelText: 'Máximo de usos', hintText: 'Vacío = ilimitado'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Solo primera visita'),
              value: _firstVisit,
              onChanged: (v) => setState(() => _firstVisit = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Activo'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            final code = _code.text.trim().toUpperCase();
            if (code.isEmpty) return;
            Navigator.pop(context, {
              'code': code,
              'discount_pct': _isPct ? (int.tryParse(_value.text) ?? 0).clamp(0, 100) : null,
              'discount_cents': _isPct ? null : parseEuros(_value.text),
              'valid_from': _from == null ? null : _d(_from!),
              'valid_until': _until == null ? null : _d(_until!),
              'max_uses': int.tryParse(_maxUses.text),
              'first_visit_only': _firstVisit,
              'active': _active,
            });
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
