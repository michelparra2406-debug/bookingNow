import 'dart:async';

import 'package:flutter/material.dart';

import '../../config.dart';
import '../../models/models.dart';
import '../../services/app_session.dart';
import '../../utils/friendly_errors.dart';
import '../../widgets/common.dart';
import 'business_shell.dart';

/// Icono Material para el nombre de icono guardado en `sectors.icon`.
IconData sectorIcon(String name) {
  switch (name) {
    case 'content_cut':
      return Icons.content_cut;
    case 'face':
      return Icons.face;
    case 'spa':
      return Icons.spa;
    case 'medical_services':
      return Icons.medical_services;
    case 'healing':
      return Icons.healing;
    case 'dentistry':
      return Icons.medical_information;
    case 'psychology':
      return Icons.psychology;
    case 'fitness_center':
      return Icons.fitness_center;
    case 'car_repair':
      return Icons.car_repair;
    case 'home_repair_service':
      return Icons.home_repair_service;
    case 'pets':
      return Icons.pets;
    case 'gavel':
      return Icons.gavel;
    case 'school':
      return Icons.school;
    case 'brush':
      return Icons.brush;
    case 'photo_camera':
      return Icons.photo_camera;
    case 'storefront':
    default:
      return Icons.storefront;
  }
}

/// Genera un slug a partir del nombre: minúsculas, sin acentos, [a-z0-9-].
String slugify(String input) {
  const from = 'áàäâãåéèëêíìïîóòöôõúùüûñçÁÀÄÂÃÅÉÈËÊÍÌÏÎÓÒÖÔÕÚÙÜÛÑÇ';
  const to = 'aaaaaaeeeeiiiiooooouuuuncAAAAAAEEEEIIIIOOOOOUUUUNC';
  final sb = StringBuffer();
  for (final ch in input.characters) {
    final i = from.indexOf(ch);
    sb.write(i >= 0 ? to[i] : ch);
  }
  return sb
      .toString()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

/// Alta de un negocio en 3 pasos: sector → datos → confirmación.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final session = AppSession.instance;
  int _step = 0;

  List<Sector> _sectors = [];
  bool _loadingSectors = true;
  String? _sectorsError;
  Sector? _sector;

  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _city = TextEditingController();
  final _slug = TextEditingController();
  bool _slugEdited = false;
  bool? _slugTaken; // null = sin comprobar / comprobando
  bool _checkingSlug = false;
  Timer? _slugDebounce;

  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _loadSectors();
  }

  @override
  void dispose() {
    _slugDebounce?.cancel();
    _name.dispose();
    _phone.dispose();
    _city.dispose();
    _slug.dispose();
    super.dispose();
  }

  Future<void> _loadSectors() async {
    setState(() {
      _loadingSectors = true;
      _sectorsError = null;
    });
    try {
      final s = await session.biz.fetchSectors();
      if (!mounted) return;
      setState(() {
        _sectors = s;
        _loadingSectors = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingSectors = false;
        _sectorsError = friendlyError(e);
      });
    }
  }

  void _onNameChanged(String v) {
    if (!_slugEdited) {
      _slug.text = slugify(v);
      _scheduleSlugCheck();
    }
    setState(() {});
  }

  void _onSlugChanged(String v) {
    _slugEdited = true;
    final clean = slugify(v);
    if (clean != v) {
      _slug.value = TextEditingValue(
          text: clean, selection: TextSelection.collapsed(offset: clean.length));
    }
    _scheduleSlugCheck();
    setState(() {});
  }

  void _scheduleSlugCheck() {
    _slugDebounce?.cancel();
    setState(() {
      _slugTaken = null;
      _checkingSlug = _slug.text.isNotEmpty;
    });
    if (_slug.text.isEmpty) return;
    _slugDebounce = Timer(const Duration(milliseconds: 400), _checkSlug);
  }

  Future<void> _checkSlug() async {
    final s = _slug.text;
    if (s.isEmpty) return;
    try {
      final taken = await session.biz.isSlugTaken(s);
      if (!mounted || _slug.text != s) return;
      setState(() {
        _slugTaken = taken;
        _checkingSlug = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _checkingSlug = false);
    }
  }

  bool get _step2Valid =>
      _name.text.trim().length >= 2 && _slug.text.length >= 3 && _slugTaken == false;

  Future<void> _create() async {
    if (_sector == null || !_step2Valid) return;
    setState(() => _creating = true);
    try {
      final id = await session.biz.createBusiness(
        name: _name.text.trim(),
        sectorId: _sector!.id,
        slug: _slug.text,
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        city: _city.text.trim().isEmpty ? null : _city.text.trim(),
      );
      await session.load();
      await session.switchToBusiness(id);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const BusinessShell()), (_) => false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      showSnack(context, friendlyError(e), error: true);
    }
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crear negocio'),
        leading: _step > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _creating ? null : () => setState(() => _step--))
            : null,
      ),
      body: MaxWidth(
        maxWidth: 760,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Row(children: [
              for (var i = 0; i < 3; i++) ...[
                Expanded(
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                        color: i <= _step
                            ? t.colorScheme.primary
                            : t.colorScheme.outlineVariant.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(3)),
                  ),
                ),
                if (i < 2) const SizedBox(width: 6),
              ],
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Paso ${_step + 1} de 3',
                  style: t.textTheme.labelMedium?.copyWith(color: t.colorScheme.outline)),
            ),
          ),
          Expanded(
            child: switch (_step) {
              0 => _stepSector(t),
              1 => _stepDetails(t),
              _ => _stepSummary(t),
            },
          ),
        ]),
      ),
    );
  }

  Widget _stepSector(ThemeData t) {
    if (_loadingSectors) return const LoadingView();
    if (_sectorsError != null) return ErrorView(_sectorsError!, onRetry: _loadSectors);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('¿A qué se dedica tu negocio?',
              style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Adaptamos el vocabulario y creamos servicios de ejemplo según el sector.',
              style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.outline)),
        ]),
      ),
      Expanded(
        child: LayoutBuilder(builder: (_, c) {
          final cols = c.maxWidth >= 640 ? 4 : (c.maxWidth >= 420 ? 3 : 2);
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.15),
            itemCount: _sectors.length,
            itemBuilder: (_, i) {
              final s = _sectors[i];
              final sel = _sector?.id == s.id;
              return Card(
                color: sel ? t.colorScheme.primary.withValues(alpha: 0.10) : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                      color: sel ? t.colorScheme.primary : t.colorScheme.outlineVariant.withValues(alpha: 0.5),
                      width: sel ? 2 : 1),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => setState(() {
                    _sector = s;
                    _step = 1;
                  }),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(sectorIcon(s.icon), size: 32, color: t.colorScheme.primary),
                      const SizedBox(height: 10),
                      Text(s.nameEs,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
              );
            },
          );
        }),
      ),
    ]);
  }

  Widget _stepDetails(ThemeData t) {
    final previewUrl = '${AppConfig.publicBookingHost}/b/${_slug.text.isEmpty ? 'tu-negocio' : _slug.text}';
    Widget slugSuffix;
    if (_checkingSlug) {
      slugSuffix = const Padding(
          padding: EdgeInsets.all(12),
          child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)));
    } else if (_slugTaken == true) {
      slugSuffix = const Icon(Icons.error_outline, color: Colors.red);
    } else if (_slugTaken == false) {
      slugSuffix = const Icon(Icons.check_circle_outline, color: Colors.green);
    } else {
      slugSuffix = const SizedBox.shrink();
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Datos del negocio', style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Row(children: [
          Icon(sectorIcon(_sector?.icon ?? 'storefront'), size: 18, color: t.colorScheme.outline),
          const SizedBox(width: 6),
          Text(_sector?.nameEs ?? '', style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.outline)),
          TextButton(onPressed: () => setState(() => _step = 0), child: const Text('Cambiar')),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _name,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          onChanged: _onNameChanged,
          decoration: const InputDecoration(labelText: 'Nombre del negocio *'),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Teléfono'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _city,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Ciudad'),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _slug,
          onChanged: _onSlugChanged,
          decoration: InputDecoration(
            labelText: 'Dirección web *',
            helperText: _slugTaken == true
                ? 'Esa dirección ya está en uso. Elige otra.'
                : 'Solo letras, números y guiones. Mínimo 3 caracteres.',
            helperStyle: _slugTaken == true ? const TextStyle(color: Colors.red) : null,
            suffixIcon: slugSuffix,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
              color: t.colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            Icon(Icons.link, size: 18, color: t.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(previewUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
        const SizedBox(height: 6),
        Text('Tus clientes reservarán en esta página. Podrás compartirla y ponerla en Instagram o Google.',
            style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _step2Valid ? () => setState(() => _step = 2) : null,
          child: const Text('Continuar'),
        ),
      ]),
    );
  }

  Widget _stepSummary(ThemeData t) {
    final s = _sector!;
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
                width: 120,
                child: Text(label, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.outline))),
            Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
          ]),
        );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Todo listo', style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('Revisa los datos antes de crear tu negocio.',
            style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.outline)),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              row('Sector', s.nameEs),
              row('Nombre', _name.text.trim()),
              if (_phone.text.trim().isNotEmpty) row('Teléfono', _phone.text.trim()),
              if (_city.text.trim().isNotEmpty) row('Ciudad', _city.text.trim()),
              row('Página de reservas', '${AppConfig.publicBookingHost}/b/${_slug.text}'),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          color: t.colorScheme.primary.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.auto_awesome, color: t.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Crearemos automáticamente servicios de ejemplo típicos de "${s.nameEs}" '
                  '(con sus categorías, duraciones y precios), un horario de lunes a viernes de 9:00 a 18:00 '
                  'y tu serie de facturación. Podrás editar o borrar todo desde el panel.',
                  style: t.textTheme.bodyMedium,
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'En este sector tus clientes se llaman "${s.labelCustomer}s", tu equipo "${s.labelStaff}es" '
          'y las reservas "${s.labelBooking}s". Lo verás así en toda la app.',
          style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _creating ? null : _create,
          icon: _creating
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.rocket_launch_outlined),
          label: Text(_creating ? 'Creando…' : 'Crear negocio'),
        ),
      ]),
    );
  }
}
