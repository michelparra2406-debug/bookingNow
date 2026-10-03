import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_theme.dart';
import '../../models/models.dart';
import '../../services/app_session.dart';
import '../../utils/format.dart';
import '../../utils/friendly_errors.dart';
import '../../widgets/admin_widgets.dart';
import '../../widgets/common.dart';
import 'settings_screen.dart';

String _providerName(String? id) {
  if (id == null) return '';
  for (final p in integrationProviders) {
    if (p.id == id) return p.name;
  }
  return id;
}

String _invoiceStatus(String s) {
  switch (s) {
    case 'draft':
      return 'Borrador';
    case 'issued':
      return 'Emitida';
    case 'sent':
      return 'Enviada';
    case 'paid':
      return 'Pagada';
    case 'cancelled':
      return 'Anulada';
    case 'rectified':
      return 'Rectificada';
    default:
      return s;
  }
}

Color _invoiceStatusColor(String s) {
  switch (s) {
    case 'paid':
      return AppTheme.accent;
    case 'issued':
    case 'sent':
      return AppTheme.primary;
    case 'cancelled':
    case 'rectified':
      return AppTheme.danger;
    default:
      return Colors.grey;
  }
}

enum _SyncFilter { all, pending, errors }

/// Facturas emitidas, por mes, con estado de sincronización externa.
class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({super.key});
  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  final session = AppSession.instance;
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _loading = true;
  String? _error;
  List<Invoice> _invoices = [];
  _SyncFilter _filter = _SyncFilter.all;

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
      final from = _month;
      final to = DateTime(_month.year, _month.month + 1, 0);
      final list = await session.biz
          .fetchInvoices(_businessId, from: from, to: to, limit: 500);
      if (!mounted) return;
      setState(() {
        _invoices = list;
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

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    _load();
  }

  List<Invoice> get _filtered {
    switch (_filter) {
      case _SyncFilter.pending:
        return _invoices
            .where((i) => i.externalSyncedAt == null && i.externalError == null)
            .toList();
      case _SyncFilter.errors:
        return _invoices.where((i) => i.externalError != null).toList();
      case _SyncFilter.all:
        return _invoices;
    }
  }

  Future<void> _openDetail(Invoice inv) async {
    final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => InvoiceDetailScreen(invoice: inv)));
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final b = session.activeBusiness!;
    final noFiscal = b.taxId == null || b.taxId!.trim().isEmpty;
    final list = _filtered;
    final base = _invoices.fold<int>(0, (a, i) => a + i.subtotalCents);
    final vat = _invoices.fold<int>(0, (a, i) => a + i.vatCents);
    final total = _invoices.fold<int>(0, (a, i) => a + i.totalCents);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Facturas'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load, tooltip: 'Actualizar'),
        ],
      ),
      body: MaxWidth(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(children: [
              if (noFiscal)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InfoCard(
                    'Para emitir facturas válidas necesitas completar los datos fiscales del negocio (razón social, NIF y dirección).',
                    icon: Icons.warning_amber_rounded,
                    color: AppTheme.warning,
                    action: TextButton(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const SettingsScreen(initialTab: 2))),
                      child: const Text('Ir a Ajustes → Datos fiscales'),
                    ),
                  ),
                ),
              Row(children: [
                IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => _shiftMonth(-1)),
                Expanded(
                  child: Text(Fmt.month(_month),
                      textAlign: TextAlign.center,
                      style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                ),
                IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => _shiftMonth(1)),
              ]),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: Row(children: [
                    _total(t, 'Facturas', '${_invoices.length}'),
                    _total(t, 'Base', formatEuros(base)),
                    _total(t, 'IVA', formatEuros(vat)),
                    _total(t, 'Total', formatEuros(total), bold: true),
                  ]),
                ),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _filterChip('Todas', _SyncFilter.all),
                  const SizedBox(width: 8),
                  _filterChip('Pendientes de sincronizar', _SyncFilter.pending),
                  const SizedBox(width: 8),
                  _filterChip('Con errores', _SyncFilter.errors),
                ]),
              ),
            ]),
          ),
          Expanded(
            child: _loading
                ? const LoadingView()
                : _error != null
                    ? ErrorView(_error!, onRetry: _load)
                    : list.isEmpty
                        ? const EmptyView(
                            icon: Icons.receipt_long_outlined,
                            title: 'Sin facturas',
                            subtitle:
                                'Las facturas se emiten desde cada cita completada en la agenda.')
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              itemCount: list.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (_, i) => _invoiceCard(list[i], t),
                            ),
                          ),
          ),
        ]),
      ),
    );
  }

  Widget _total(ThemeData t, String label, String value, {bool bold = false}) => Expanded(
        child: Column(children: [
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.textTheme.titleSmall
                  ?.copyWith(fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
          Text(label, style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.outline)),
        ]),
      );

  Widget _filterChip(String label, _SyncFilter f) => ChoiceChip(
        label: Text(label),
        selected: _filter == f,
        onSelected: (_) => setState(() => _filter = f),
      );

  Widget _invoiceCard(Invoice inv, ThemeData t) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openDetail(inv),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(inv.fullNumber,
                      style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  Text(Fmt.date(inv.issueDate),
                      style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
                ]),
                const SizedBox(height: 4),
                Text(inv.recipientName, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  SmallBadge(_invoiceStatus(inv.status), color: _invoiceStatusColor(inv.status)),
                  SmallBadge(Fmt.paymentMethod(inv.paymentMethod),
                      icon: Icons.payments_outlined, color: Colors.blueGrey),
                  if (inv.type != 'F1') SmallBadge(inv.type, color: Colors.deepOrange),
                  _syncBadge(inv),
                ]),
              ]),
            ),
            const SizedBox(width: 10),
            Text(formatEuros(inv.totalCents),
                style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const Icon(Icons.chevron_right),
          ]),
        ),
      ),
    );
  }

  Widget _syncBadge(Invoice inv) {
    if (inv.externalProvider == null) return const SizedBox.shrink();
    if (inv.externalSyncedAt != null) {
      return SmallBadge(_providerName(inv.externalProvider),
          icon: Icons.check_circle, color: AppTheme.accent);
    }
    if (inv.externalError != null) {
      return SmallBadge('Error ${_providerName(inv.externalProvider)}',
          icon: Icons.warning_amber_rounded, color: AppTheme.danger);
    }
    return SmallBadge('Pendiente ${_providerName(inv.externalProvider)}',
        icon: Icons.sync, color: AppTheme.warning);
  }
}

// ============================================================ Detalle

/// Ficha completa de una factura con bloque Verifactu y sincronización.
class InvoiceDetailScreen extends StatefulWidget {
  final Invoice invoice;
  const InvoiceDetailScreen({super.key, required this.invoice});
  @override
  State<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends State<InvoiceDetailScreen> {
  final session = AppSession.instance;
  late Invoice _inv = widget.invoice;
  bool _resyncing = false;
  bool _changed = false;

  Future<void> _reload() async {
    try {
      final i = await session.biz.fetchInvoice(_inv.id);
      if (!mounted || i == null) return;
      setState(() => _inv = i);
    } catch (_) {}
  }

  Future<void> _resync() async {
    setState(() => _resyncing = true);
    try {
      final integrations = await session.biz.fetchIntegrations(_inv.businessId);
      final invoicing =
          integrations.where((i) => i.category == 'invoicing' && i.enabled).toList();
      if (invoicing.isEmpty) {
        if (!mounted) return;
        showSnack(context, 'No hay ningún software de facturación conectado. Ve a Integraciones.',
            error: true);
        return;
      }
      for (final i in invoicing) {
        await session.biz.resyncInvoice(_inv.businessId, _inv.id, i.provider);
      }
      _changed = true;
      if (!mounted) return;
      showSnack(context,
          'Sincronización encolada (${invoicing.map((i) => _providerName(i.provider)).join(', ')})');
      await _reload();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _resyncing = false);
    }
  }

  String _summaryText() {
    final b = session.activeBusiness!;
    final sb = StringBuffer()
      ..writeln('Factura ${_inv.fullNumber} · ${Fmt.date(_inv.issueDate)}')
      ..writeln('Emisor: ${b.legalName ?? b.name}${b.taxId != null ? ' · ${b.taxId}' : ''}')
      ..writeln('Cliente: ${_inv.recipientName}${_inv.recipientTaxId != null ? ' · ${_inv.recipientTaxId}' : ''}')
      ..writeln('');
    for (final l in _inv.lines) {
      sb.writeln('- ${l.description} × ${_qty(l.quantity)}: ${formatEuros(l.totalCents)}');
    }
    sb
      ..writeln('')
      ..writeln('Base: ${formatEuros(_inv.subtotalCents)}')
      ..writeln('IVA: ${formatEuros(_inv.vatCents)}')
      ..writeln('Total: ${formatEuros(_inv.totalCents)}')
      ..writeln('Pago: ${Fmt.paymentMethod(_inv.paymentMethod)}');
    if (_inv.verifactuQrUrl != null) sb.writeln('Verifactu: ${_inv.verifactuQrUrl}');
    if (_inv.pdfUrl != null) sb.writeln('PDF: ${_inv.pdfUrl}');
    return sb.toString();
  }

  static String _qty(double q) => q == q.roundToDouble() ? '${q.toInt()}' : q.toStringAsFixed(2);

  Future<void> _share() async {
    try {
      await SharePlus.instance.share(ShareParams(text: _summaryText(), subject: 'Factura ${_inv.fullNumber}'));
    } catch (e) {
      if (!mounted) return;
      showSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _openPdf() async {
    final url = _inv.pdfUrl;
    if (url == null) return;
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) showSnack(context, 'No se pudo abrir el PDF', error: true);
  }

  void _rectifyInfo() {
    showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Factura rectificativa'),
        content: const Text(
            'Una factura emitida no puede modificarse ni borrarse (Verifactu exige registros inalterables). '
            'Para corregirla se emite una factura rectificativa (tipo R1) que la referencia.\n\n'
            'En esta versión las rectificativas se emiten desde tu software de facturación conectado '
            '(Holded, Quipu, Contasimple…), que ya tiene la factura sincronizada.'),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(d), child: const Text('Entendido')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final b = session.activeBusiness!;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_inv.fullNumber),
          actions: [
            IconButton(icon: const Icon(Icons.share_outlined), tooltip: 'Compartir', onPressed: _share),
            if (_inv.pdfUrl != null)
              IconButton(
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  tooltip: 'Abrir PDF',
                  onPressed: _openPdf),
          ],
        ),
        body: MaxWidth(
          maxWidth: 900,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _headerCard(t, b),
              const SizedBox(height: 12),
              _linesCard(t),
              const SizedBox(height: 12),
              _verifactuCard(t),
              const SizedBox(height: 12),
              _syncCard(t),
              const SizedBox(height: 16),
              Wrap(spacing: 10, runSpacing: 10, children: [
                OutlinedButton.icon(
                    onPressed: _share,
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('Compartir')),
                if (_inv.pdfUrl != null)
                  OutlinedButton.icon(
                      onPressed: _openPdf,
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('Abrir PDF')),
                OutlinedButton.icon(
                    onPressed: _rectifyInfo,
                    icon: const Icon(Icons.undo),
                    label: const Text('Rectificar')),
              ]),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerCard(ThemeData t, Business b) {
    final issuer = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('EMISOR', style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.outline)),
      const SizedBox(height: 4),
      Text(b.legalName ?? b.name, style: const TextStyle(fontWeight: FontWeight.w700)),
      if (b.taxId != null) Text('NIF ${b.taxId}'),
      if (b.fiscalAddress != null) Text(b.fiscalAddress!),
      if (b.fiscalPostalCode != null || b.fiscalCity != null)
        Text('${b.fiscalPostalCode ?? ''} ${b.fiscalCity ?? ''}${b.fiscalProvince != null ? ' (${b.fiscalProvince})' : ''}'
            .trim()),
    ]);
    final recipient = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('CLIENTE', style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.outline)),
      const SizedBox(height: 4),
      Text(_inv.recipientName, style: const TextStyle(fontWeight: FontWeight.w700)),
      if (_inv.recipientTaxId != null) Text('NIF ${_inv.recipientTaxId}'),
      if (_inv.recipientAddress != null) Text(_inv.recipientAddress!),
    ]);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('Factura ${_inv.fullNumber}',
                  style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            ),
            SmallBadge(_invoiceStatus(_inv.status), color: _invoiceStatusColor(_inv.status)),
          ]),
          const SizedBox(height: 4),
          Text('Fecha: ${Fmt.date(_inv.issueDate)} · Tipo ${_inv.type} · Pago: ${Fmt.paymentMethod(_inv.paymentMethod)}',
              style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
          const Divider(height: 24),
          LayoutBuilder(builder: (context, c) {
            if (c.maxWidth < 520) {
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                issuer,
                const SizedBox(height: 16),
                recipient,
              ]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: issuer),
              const SizedBox(width: 24),
              Expanded(child: recipient),
            ]);
          }),
        ]),
      ),
    );
  }

  Widget _linesCard(ThemeData t) {
    final head = t.textTheme.labelSmall?.copyWith(color: t.colorScheme.outline);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(flex: 5, child: Text('Concepto', style: head)),
            Expanded(child: Text('Cant.', textAlign: TextAlign.right, style: head)),
            Expanded(flex: 2, child: Text('Precio', textAlign: TextAlign.right, style: head)),
            Expanded(child: Text('IVA', textAlign: TextAlign.right, style: head)),
            Expanded(flex: 2, child: Text('Importe', textAlign: TextAlign.right, style: head)),
          ]),
          const Divider(height: 16),
          if (_inv.lines.isEmpty) const InlineEmpty('Sin líneas'),
          for (final l in _inv.lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Expanded(flex: 5, child: Text(l.description)),
                Expanded(child: Text(_qty(l.quantity), textAlign: TextAlign.right)),
                Expanded(flex: 2, child: Text(formatEuros(l.unitPriceCents), textAlign: TextAlign.right)),
                Expanded(child: Text('${l.vatPct.toStringAsFixed(0)} %', textAlign: TextAlign.right)),
                Expanded(flex: 2, child: Text(formatEuros(l.totalCents), textAlign: TextAlign.right)),
              ]),
            ),
          const Divider(height: 20),
          Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 260,
              child: Column(children: [
                _totalRow(t, 'Base imponible', formatEuros(_inv.subtotalCents)),
                _totalRow(t, 'IVA', formatEuros(_inv.vatCents)),
                _totalRow(t, 'TOTAL', formatEuros(_inv.totalCents), bold: true),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _totalRow(ThemeData t, String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: bold ? t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800) : null),
          Text(value,
              style: bold
                  ? t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)
                  : t.textTheme.bodyMedium),
        ]),
      );

  Widget _verifactuCard(ThemeData t) {
    final hash = _inv.verifactuHash;
    final qr = _inv.verifactuQrUrl;
    final sent = _inv.verifactuSentAt;
    final qrWidget = qr == null || qr.isEmpty
        ? Container(
            width: 140,
            height: 140,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                border: Border.all(color: t.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(12)),
            child: Text('QR no disponible',
                textAlign: TextAlign.center,
                style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.outline)),
          )
        : Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: QrImageView(data: qr, size: 128),
          );
    final info = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(sent != null ? Icons.verified : Icons.schedule,
            size: 18, color: sent != null ? AppTheme.accent : AppTheme.warning),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
              sent != null ? 'Enviada a la AEAT el ${Fmt.dateTime(sent)}' : 'Pendiente de envío a la AEAT',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: sent != null ? AppTheme.accent : AppTheme.warning)),
        ),
      ]),
      const SizedBox(height: 10),
      Text('Huella (SHA-256)', style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.outline)),
      const SizedBox(height: 4),
      if (hash == null)
        Text('Sin huella generada', style: t.textTheme.bodySmall)
      else
        InkWell(
          onTap: () => copyToClipboard(context, hash, message: 'Huella copiada'),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: t.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              Expanded(
                child: Text(hash,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.copy, size: 16),
            ]),
          ),
        ),
      if (qr != null && qr.isNotEmpty) ...[
        const SizedBox(height: 8),
        TextButton.icon(
          style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
          onPressed: () => copyToClipboard(context, qr, message: 'URL del QR copiada'),
          icon: const Icon(Icons.link, size: 16),
          label: const Text('Copiar URL de verificación'),
        ),
      ],
    ]);
    return FormCard(title: 'Verifactu', children: [
      LayoutBuilder(builder: (context, c) {
        if (c.maxWidth < 480) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: qrWidget),
            const SizedBox(height: 12),
            info,
          ]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          qrWidget,
          const SizedBox(width: 16),
          Expanded(child: info),
        ]);
      }),
    ]);
  }

  Widget _syncCard(ThemeData t) {
    final p = _inv.externalProvider;
    return FormCard(title: 'Sincronización con software de facturación', children: [
      if (p == null)
        Text('Esta factura no se ha enviado a ningún software externo.',
            style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.outline))
      else ...[
        DetailRow('Proveedor', _providerName(p)),
        DetailRow('ID externo', _inv.externalId ?? '—'),
        DetailRow('Sincronizada',
            _inv.externalSyncedAt != null ? Fmt.dateTime(_inv.externalSyncedAt!) : 'Pendiente'),
        if (_inv.externalError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: InfoCard(_inv.externalError!,
                icon: Icons.error_outline, color: AppTheme.danger),
          ),
      ],
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _resyncing ? null : _resync,
        icon: _resyncing
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.sync),
        label: const Text('Reintentar sincronización'),
      ),
    ]);
  }
}
