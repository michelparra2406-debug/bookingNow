import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/models.dart';
import '../../services/app_session.dart';
import '../../utils/format.dart';
import '../../utils/friendly_errors.dart';
import '../../widgets/admin_widgets.dart';
import '../../widgets/common.dart';

const _categoryOrder = ['invoicing', 'payments', 'messaging', 'calendar', 'marketplace'];

String _categoryTitle(String c) {
  switch (c) {
    case 'invoicing':
      return 'Facturación (Verifactu)';
    case 'payments':
      return 'Pagos online y señales';
    case 'messaging':
      return 'Mensajería (recordatorios)';
    case 'calendar':
      return 'Calendario';
    case 'marketplace':
      return 'Marketplace';
    default:
      return c;
  }
}

IconData _categoryIcon(String c) {
  switch (c) {
    case 'invoicing':
      return Icons.receipt_long_outlined;
    case 'payments':
      return Icons.credit_card;
    case 'messaging':
      return Icons.chat_bubble_outline;
    case 'calendar':
      return Icons.calendar_month_outlined;
    case 'marketplace':
      return Icons.storefront_outlined;
    default:
      return Icons.extension_outlined;
  }
}

/// Integraciones con software de facturación, pagos, mensajería, etc.
class IntegrationsScreen extends StatefulWidget {
  const IntegrationsScreen({super.key});
  @override
  State<IntegrationsScreen> createState() => _IntegrationsScreenState();
}

class _IntegrationsScreenState extends State<IntegrationsScreen> {
  final session = AppSession.instance;
  bool _loading = true;
  String? _error;
  List<Integration> _integrations = [];
  List<Map<String, dynamic>> _jobs = [];
  bool _historyOpen = false;
  final Set<String> _busy = {};

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
      final results = await Future.wait([
        session.biz.fetchIntegrations(_businessId),
        session.biz.fetchSyncJobs(_businessId),
      ]);
      if (!mounted) return;
      setState(() {
        _integrations = results[0] as List<Integration>;
        _jobs = results[1] as List<Map<String, dynamic>>;
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

  Integration? _of(IntegrationProvider p) =>
      _integrations.where((i) => i.provider == p.id).firstOrNull;

  Future<void> _connect(IntegrationProvider p, Integration? existing) async {
    final creds = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _CredentialsDialog(provider: p, existing: existing),
    );
    if (creds == null || !mounted) return;
    setState(() => _busy.add(p.id));
    try {
      await session.biz.saveIntegration(
        businessId: _businessId,
        provider: p.id,
        category: p.category,
        credentials: creds,
        settings: existing?.settings ?? const {},
        enabled: existing?.enabled ?? true,
      );
      if (!mounted) return;
      showSnack(context, '${p.name} conectado. Credenciales guardadas de forma segura.');
      await _load();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(p.id));
    }
  }

  Future<void> _toggle(Integration i, bool enabled) async {
    try {
      await session.biz.setIntegrationEnabled(i.id, enabled);
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _test(IntegrationProvider p) async {
    setState(() => _busy.add(p.id));
    try {
      final r = await session.biz.testIntegration(_businessId, p.id);
      if (!mounted) return;
      final ok = r['ok'] == true;
      final msg = r['message']?.toString() ?? r['error']?.toString();
      showSnack(
          context,
          ok
              ? 'Conexión correcta con ${p.name}${msg != null ? ': $msg' : ''}'
              : 'Error de conexión${msg != null ? ': $msg' : ''}',
          error: !ok);
      await _load();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(p.id));
    }
  }

  Future<void> _disconnect(IntegrationProvider p, Integration i) async {
    final ok = await confirmDialog(context,
        title: 'Desconectar ${p.name}',
        message:
            'Se eliminarán las credenciales guardadas. Las facturas ya sincronizadas no se ven afectadas.',
        confirmLabel: 'Desconectar',
        destructive: true);
    if (!ok || !mounted) return;
    try {
      await session.biz.deleteIntegration(i.id);
      if (!mounted) return;
      showSnack(context, '${p.name} desconectado');
      await _load();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Integraciones'),
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
                        const InfoCard(
                          'Las facturas emitidas en BookingNow se envían automáticamente al software conectado. '
                          'Verifactu es obligatorio en España desde 2027 (sociedades: 1 enero 2027; autónomos: 1 julio 2027): '
                          'BookingNow genera el registro con huella encadenada y QR; el envío a la AEAT lo hace tu software '
                          'de facturación o la integración directa.',
                          icon: Icons.verified_outlined,
                        ),
                        for (final cat in _categoryOrder) ...[
                          SectionTitle(_categoryTitle(cat),
                              trailing: Icon(_categoryIcon(cat),
                                  size: 20, color: Theme.of(context).colorScheme.outline)),
                          LayoutBuilder(builder: (context, c) {
                            final providers =
                                integrationProviders.where((p) => p.category == cat).toList();
                            final two = c.maxWidth >= 760;
                            if (!two) {
                              return Column(children: [
                                for (final p in providers)
                                  Padding(
                                      padding: const EdgeInsets.only(bottom: 10),
                                      child: _providerCard(p)),
                              ]);
                            }
                            final w = (c.maxWidth - 10) / 2;
                            return Wrap(spacing: 10, runSpacing: 10, children: [
                              for (final p in providers) SizedBox(width: w, child: _providerCard(p)),
                            ]);
                          }),
                        ],
                        const SizedBox(height: 8),
                        _historyCard(),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _providerCard(IntegrationProvider p) {
    final t = Theme.of(context);
    final i = _of(p);
    final busy = _busy.contains(p.id);
    final connected = i != null;
    Widget status;
    if (!connected) {
      status = const SmallBadge('No conectado', color: Colors.grey, icon: Icons.link_off);
    } else if (i.lastError != null) {
      status = const SmallBadge('Error', color: AppTheme.danger, icon: Icons.warning_amber_rounded);
    } else {
      status = const SmallBadge('Conectado', color: AppTheme.accent, icon: Icons.check_circle);
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.name, style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(p.description,
                    style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
              ]),
            ),
            if (connected)
              Switch(
                value: i.enabled,
                onChanged: busy ? null : (v) => _toggle(i, v),
              ),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            status,
            if (connected && i.lastSyncAt != null)
              Text('Última sincronización: ${Fmt.dateTime(i.lastSyncAt!)}',
                  style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.outline)),
            if (connected && !i.enabled)
              Text('Pausado', style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.outline)),
          ]),
          if (connected && i.lastError != null) ...[
            const SizedBox(height: 8),
            InfoCard(i.lastError!, icon: Icons.error_outline, color: AppTheme.danger),
          ],
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, children: [
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 12)),
              onPressed: busy ? null : () => _connect(p, i),
              icon: Icon(connected ? Icons.edit_outlined : Icons.link, size: 18),
              label: Text(connected ? 'Editar' : 'Conectar'),
            ),
            if (connected)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 12)),
                onPressed: busy ? null : () => _test(p),
                icon: busy
                    ? const SizedBox(
                        width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.network_check, size: 18),
                label: const Text('Probar conexión'),
              ),
            if (connected)
              TextButton.icon(
                style: TextButton.styleFrom(
                    minimumSize: const Size(0, 38),
                    foregroundColor: AppTheme.danger,
                    padding: const EdgeInsets.symmetric(horizontal: 12)),
                onPressed: busy ? null : () => _disconnect(p, i),
                icon: const Icon(Icons.link_off, size: 18),
                label: const Text('Desconectar'),
              ),
          ]),
        ]),
      ),
    );
  }

  Widget _historyCard() {
    final t = Theme.of(context);
    return Card(
      child: Column(children: [
        ListTile(
          leading: const Icon(Icons.history),
          title: const Text('Historial de sincronización',
              style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('${_jobs.length} ${_jobs.length == 1 ? 'tarea' : 'tareas'} recientes'),
          trailing: Icon(_historyOpen ? Icons.expand_less : Icons.expand_more),
          onTap: () => setState(() => _historyOpen = !_historyOpen),
        ),
        if (_historyOpen) ...[
          const Divider(),
          if (_jobs.isEmpty) const InlineEmpty('Todavía no hay tareas de sincronización.'),
          for (final j in _jobs)
            ListTile(
              dense: true,
              leading: Icon(_jobIcon(j['status']?.toString()), color: _jobColor(j['status']?.toString())),
              title: Text(
                  '${_providerLabel(j['provider']?.toString())} · ${_entityLabel(j['entity']?.toString())}'),
              subtitle: Text(
                [
                  _jobStatus(j['status']?.toString()),
                  if (j['attempts'] != null && (j['attempts'] as num) > 1) '${j['attempts']} intentos',
                  if (j['error'] != null) j['error'].toString(),
                ].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: t.textTheme.bodySmall?.copyWith(
                    color: j['error'] != null ? AppTheme.danger : t.colorScheme.outline),
              ),
              trailing: Text(
                j['created_at'] != null
                    ? Fmt.dateTime(DateTime.parse(j['created_at'].toString()).toLocal())
                    : '',
                style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.outline),
              ),
            ),
        ],
      ]),
    );
  }

  static String _providerLabel(String? id) {
    for (final p in integrationProviders) {
      if (p.id == id) return p.name;
    }
    return id ?? '';
  }

  static String _entityLabel(String? e) {
    switch (e) {
      case 'invoice':
        return 'Factura';
      case 'customer':
        return 'Cliente';
      default:
        return e ?? '';
    }
  }

  static String _jobStatus(String? s) {
    switch (s) {
      case 'queued':
        return 'En cola';
      case 'running':
        return 'En curso';
      case 'done':
        return 'Completada';
      case 'error':
        return 'Error';
      default:
        return s ?? '';
    }
  }

  static IconData _jobIcon(String? s) {
    switch (s) {
      case 'done':
        return Icons.check_circle_outline;
      case 'error':
        return Icons.error_outline;
      case 'running':
        return Icons.sync;
      default:
        return Icons.schedule;
    }
  }

  static Color _jobColor(String? s) {
    switch (s) {
      case 'done':
        return AppTheme.accent;
      case 'error':
        return AppTheme.danger;
      case 'running':
        return AppTheme.primary;
      default:
        return Colors.grey;
    }
  }
}

// ============================================================ Credenciales

class _CredentialsDialog extends StatefulWidget {
  final IntegrationProvider provider;
  final Integration? existing;
  const _CredentialsDialog({required this.provider, this.existing});
  @override
  State<_CredentialsDialog> createState() => _CredentialsDialogState();
}

class _CredentialsDialogState extends State<_CredentialsDialog> {
  late final Map<String, TextEditingController> _ctrls = {
    for (final f in widget.provider.fields) f.key: TextEditingController(),
  };
  final Set<String> _visible = {};

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = widget.provider;
    final editing = widget.existing != null;
    return AlertDialog(
      title: Text(editing ? 'Editar ${p.name}' : 'Conectar ${p.name}'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(p.description, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
            const SizedBox(height: 12),
            if (editing)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: InfoCard(
                  'Por seguridad no se muestran las credenciales guardadas. Introduce todos los campos de nuevo para sustituirlas.',
                  icon: Icons.lock_outline,
                ),
              ),
            for (final f in p.fields)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: _ctrls[f.key],
                  obscureText: f.secret && !_visible.contains(f.key),
                  maxLines: f.secret && f.key.endsWith('_pem') && _visible.contains(f.key) ? 4 : 1,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: f.label,
                    hintText: f.hint,
                    suffixIcon: f.secret
                        ? IconButton(
                            icon: Icon(_visible.contains(f.key)
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined),
                            onPressed: () => setState(() {
                              if (!_visible.remove(f.key)) _visible.add(f.key);
                            }),
                          )
                        : null,
                  ),
                ),
              ),
            Row(children: [
              Icon(Icons.lock_outline, size: 14, color: t.colorScheme.outline),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                    'Las credenciales se guardan cifradas y solo las usan los procesos de sincronización del servidor. Nunca se muestran de nuevo.',
                    style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.outline)),
              ),
            ]),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            final creds = <String, dynamic>{};
            for (final f in p.fields) {
              final v = _ctrls[f.key]!.text.trim();
              if (v.isEmpty) {
                showSnack(context, 'Falta el campo "${f.label}"', error: true);
                return;
              }
              creds[f.key] = v;
            }
            Navigator.pop(context, creds);
          },
          child: Text(editing ? 'Guardar' : 'Conectar'),
        ),
      ],
    );
  }
}
