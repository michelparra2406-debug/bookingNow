import 'dart:async';
import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../app_theme.dart';
import '../../models/models.dart';
import '../../services/app_session.dart';
import '../../utils/format.dart';
import '../../utils/friendly_errors.dart';
import '../../widgets/common.dart';
import 'customer_detail_screen.dart';

/// Diálogo de alta/edición rápida de cliente. Devuelve el cliente guardado.
Future<Customer?> showCustomerFormDialog(BuildContext context, {Customer? existing}) {
  return showDialog<Customer>(
    context: context,
    builder: (_) => _CustomerFormDialog(existing: existing),
  );
}

/// Listado de clientes (CRM) con búsqueda, alta, importación y exportación.
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});
  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final session = AppSession.instance;
  String get _bizId => session.activeBusiness!.id;

  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<Customer> _customers = [];
  bool _loading = true;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final c = await session.biz.fetchCustomers(_bizId, query: _searchCtrl.text);
      if (!mounted) return;
      setState(() {
        _customers = c;
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

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  Future<void> _openDetail(Customer c) async {
    await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CustomerDetailScreen(customerId: c.id)));
    if (mounted) _load();
  }

  Future<void> _newCustomer() async {
    final c = await showCustomerFormDialog(context);
    if (c == null || !mounted) return;
    showSnack(context, '${session.customerLabel} creado');
    _load();
  }

  void _openMenu() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 480),
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(
            leading: const Icon(Icons.person_add_alt_1_outlined),
            title: Text('Nuevo ${session.customerLabel.toLowerCase()}'),
            onTap: () {
              Navigator.pop(c);
              _newCustomer();
            },
          ),
          ListTile(
            leading: const Icon(Icons.upload_file_outlined),
            title: const Text('Importar CSV'),
            subtitle: const Text('Columnas: nombre, email, teléfono, NIF, notas'),
            onTap: () {
              Navigator.pop(c);
              _importCsv();
            },
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Exportar CSV'),
            subtitle: const Text('Tus datos son tuyos: descárgalos cuando quieras'),
            onTap: () {
              Navigator.pop(c);
              _exportCsv();
            },
          ),
        ]),
      ),
    );
  }

  // ---------- Importar ----------

  static const _headerMap = <String, String>{
    'nombre': 'full_name',
    'name': 'full_name',
    'full_name': 'full_name',
    'nombre completo': 'full_name',
    'cliente': 'full_name',
    'email': 'email',
    'correo': 'email',
    'e-mail': 'email',
    'telefono': 'phone',
    'teléfono': 'phone',
    'phone': 'phone',
    'movil': 'phone',
    'móvil': 'phone',
    'nif': 'tax_id',
    'dni': 'tax_id',
    'tax_id': 'tax_id',
    'cif': 'tax_id',
    'notas': 'notes',
    'notes': 'notes',
  };

  Future<void> _importCsv() async {
    try {
      final files = await FilePicker.pickFiles(
          type: FileType.custom, allowedExtensions: ['csv']);
      if (files.isEmpty) return;
      final bytes = await files.first.readAsBytes();
      String text;
      try {
        text = utf8.decode(bytes);
      } catch (_) {
        text = latin1.decode(bytes);
      }
      text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
      if (text.startsWith('﻿')) text = text.substring(1);
      final firstLine = text.split('\n').first;
      final delim = ';'.allMatches(firstLine).length > ','.allMatches(firstLine).length ? ';' : ',';
      final table = CsvToListConverter(shouldParseNumbers: false, fieldDelimiter: delim, eol: '\n')
          .convert(text);
      if (table.length < 2) {
        if (mounted) showSnack(context, 'El archivo no tiene filas de datos', error: true);
        return;
      }
      final headers = table.first.map((h) => h.toString().trim().toLowerCase()).toList();
      final keys = headers.map((h) => _headerMap[h]).toList();
      if (!keys.contains('full_name')) {
        if (mounted) {
          showSnack(context, 'No se encontró la columna "nombre". Cabeceras: ${headers.join(', ')}',
              error: true);
        }
        return;
      }
      final rows = <Map<String, dynamic>>[];
      for (final r in table.skip(1)) {
        final m = <String, dynamic>{};
        for (var i = 0; i < r.length && i < keys.length; i++) {
          final k = keys[i];
          if (k == null) continue;
          final v = r[i].toString().trim();
          if (v.isNotEmpty) m[k] = v;
        }
        if ((m['full_name'] ?? '').toString().isNotEmpty) rows.add(m);
      }
      if (rows.isEmpty) {
        if (mounted) showSnack(context, 'No hay filas con nombre', error: true);
        return;
      }
      if (!mounted) return;
      final ok = await confirmDialog(context,
          title: 'Importar ${session.customerLabel.toLowerCase()}s',
          message:
              'Se importarán ${rows.length} registros del archivo "${files.first.name}". '
              'Ejemplo: ${rows.first['full_name']}${rows.first['phone'] != null ? ' · ${rows.first['phone']}' : ''}.',
          confirmLabel: 'Importar');
      if (!ok) return;
      setState(() => _busy = true);
      final n = await session.biz.importCustomers(_bizId, rows);
      if (!mounted) return;
      showSnack(context, '$n ${session.customerLabel.toLowerCase()}s importados');
      await _load();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------- Exportar ----------

  Future<void> _exportCsv() async {
    setState(() => _busy = true);
    try {
      final all = await session.biz.fetchCustomers(_bizId, limit: 10000);
      final rows = <List<dynamic>>[
        ['nombre', 'email', 'telefono', 'nif', 'direccion', 'fecha_nacimiento', 'etiquetas', 'visitas', 'gasto_total_eur', 'no_shows', 'bloqueado', 'origen', 'notas'],
        for (final c in all)
          [
            c.fullName,
            c.email ?? '',
            c.phone ?? '',
            c.taxId ?? '',
            c.address ?? '',
            c.birthdate == null ? '' : Fmt.date(c.birthdate!),
            c.tags.join('|'),
            c.totalVisits,
            (c.totalSpentCents / 100).toStringAsFixed(2),
            c.noShowCount,
            c.blocked ? 'si' : 'no',
            c.source,
            c.notes ?? '',
          ],
      ];
      final csv = const ListToCsvConverter(fieldDelimiter: ';').convert(rows);
      await SharePlus.instance.share(ShareParams(text: csv, subject: 'clientes_${session.activeBusiness!.slug}.csv'));
    } catch (e) {
      if (!mounted) return;
      showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final label = session.customerLabel;
    return Scaffold(
      appBar: AppBar(
        title: Text('${label}s'),
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          IconButton(onPressed: _exportCsv, icon: const Icon(Icons.download_outlined), tooltip: 'Exportar CSV'),
          IconButton(onPressed: _importCsv, icon: const Icon(Icons.upload_file_outlined), tooltip: 'Importar CSV'),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openMenu,
        icon: const Icon(Icons.add),
        label: Text('Nuevo ${label.toLowerCase()}'),
      ),
      body: MaxWidth(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearch,
              decoration: InputDecoration(
                hintText: 'Buscar por nombre, teléfono o email',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          _load();
                        }),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const LoadingView()
                : _error != null
                    ? ErrorView(_error!, onRetry: _load)
                    : _customers.isEmpty
                        ? EmptyView(
                            icon: Icons.people_outline,
                            title: _searchCtrl.text.isEmpty
                                ? 'Todavía no tienes ${label.toLowerCase()}s'
                                : 'Sin resultados',
                            subtitle: _searchCtrl.text.isEmpty
                                ? 'Añádelos a mano o importa tu listado en CSV.'
                                : null,
                            action: _searchCtrl.text.isEmpty
                                ? OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                                    onPressed: _importCsv,
                                    icon: const Icon(Icons.upload_file_outlined),
                                    label: const Text('Importar CSV'))
                                : null,
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                              itemCount: _customers.length,
                              separatorBuilder: (_, __) => const Divider(),
                              itemBuilder: (_, i) => _tile(t, _customers[i]),
                            ),
                          ),
          ),
        ]),
      ),
    );
  }

  Widget _tile(ThemeData t, Customer c) {
    final contact = [c.phone, c.email].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: AvatarCircle(initials: c.initials, color: c.blocked ? Colors.grey : null),
      title: Text(c.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(contact.isEmpty ? 'Sin datos de contacto' : contact,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        if (c.totalVisits > 0) _badge('${c.totalVisits} visita${c.totalVisits == 1 ? '' : 's'}', t.colorScheme.primary),
        if (c.noShowCount > 0) _badge('⚠ ${c.noShowCount} no-show${c.noShowCount == 1 ? '' : 's'}', AppTheme.danger),
        if (c.blocked) _badge('Bloqueado', Colors.grey),
        const Icon(Icons.chevron_right),
      ]),
      onTap: () => _openDetail(c),
    );
  }

  Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      );
}

// ---------------------------------------------------------------- Formulario

class _CustomerFormDialog extends StatefulWidget {
  final Customer? existing;
  const _CustomerFormDialog({this.existing});
  @override
  State<_CustomerFormDialog> createState() => _CustomerFormDialogState();
}

class _CustomerFormDialogState extends State<_CustomerFormDialog> {
  final session = AppSession.instance;
  late final _name = TextEditingController(text: widget.existing?.fullName ?? '');
  late final _email = TextEditingController(text: widget.existing?.email ?? '');
  late final _phone = TextEditingController(text: widget.existing?.phone ?? '');
  late final _taxId = TextEditingController(text: widget.existing?.taxId ?? '');
  late final _notes = TextEditingController(text: widget.existing?.notes ?? '');
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _taxId.dispose();
    _notes.dispose();
    super.dispose();
  }

  String? _nn(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      showSnack(context, 'El nombre es obligatorio', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final c = await session.biz.upsertCustomer({
        if (widget.existing != null) 'id': widget.existing!.id,
        'business_id': session.activeBusiness!.id,
        'full_name': _name.text.trim(),
        'email': _nn(_email),
        'phone': _nn(_phone),
        'tax_id': _nn(_taxId)?.toUpperCase(),
        'notes': _nn(_notes),
        if (widget.existing == null) 'source': 'manual',
      });
      if (!mounted) return;
      Navigator.pop(context, c);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showSnack(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = session.customerLabel.toLowerCase();
    return AlertDialog(
      title: Text(widget.existing == null ? 'Nuevo $label' : 'Editar $label'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nombre completo *')),
            const SizedBox(height: 12),
            TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Teléfono')),
            const SizedBox(height: 12),
            TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email')),
            const SizedBox(height: 12),
            TextField(
                controller: _taxId,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'NIF (para facturar)')),
            const SizedBox(height: 12),
            TextField(
                controller: _notes,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Notas internas')),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Guardar')),
      ],
    );
  }
}
