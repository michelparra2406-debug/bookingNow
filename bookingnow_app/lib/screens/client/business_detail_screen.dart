import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_theme.dart';
import '../../models/models.dart';
import '../../services/app_session.dart';
import '../../utils/format.dart';
import '../../utils/friendly_errors.dart';
import '../../widgets/common.dart';
import 'booking_flow_screen.dart';

/// Ficha pública de un negocio: galería, servicios, equipo, bonos, opiniones
/// e información práctica (horario, comodidades, pago, redes, ubicación).
class BusinessDetailScreen extends StatefulWidget {
  final String businessId;
  const BusinessDetailScreen({super.key, required this.businessId});
  @override
  State<BusinessDetailScreen> createState() => _BusinessDetailScreenState();
}

class _BusinessDetailScreenState extends State<BusinessDetailScreen>
    with SingleTickerProviderStateMixin {
  final data = AppSession.instance.data;
  late final TabController _tabs = TabController(length: 5, vsync: this);

  Business? _biz;
  List<Location> _locations = [];
  List<ServiceCategory> _categories = [];
  List<Service> _services = [];
  List<Member> _members = [];
  List<Review> _reviews = [];
  List<Package> _packages = [];
  List<BusinessPhoto> _photos = [];
  List<PublicHours> _hours = [];
  bool _loading = true;
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

  /// Galería y horario dependen de la migración 002: si aún no está aplicada
  /// (tabla o RPC inexistente) devolvemos listas vacías sin romper la ficha.
  static Future<List<T>> _tolerant<T>(Future<List<T>> f) async {
    try {
      return await f;
    } catch (_) {
      return <T>[];
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final id = widget.businessId;
      final results = await Future.wait<dynamic>([
        data.fetchBusiness(id),
        data.fetchLocations(id),
        data.fetchCategories(id),
        data.fetchServices(id),
        data.fetchBookableMembers(id),
        data.fetchReviews(id),
        data.fetchPackages(id),
        _tolerant(data.fetchPhotos(id)),
        _tolerant(data.fetchPublicHours(id)),
      ]);
      if (!mounted) return;
      final biz = results[0] as Business?;
      if (biz == null) {
        setState(() => _error = 'El negocio no existe.');
        return;
      }
      setState(() {
        _biz = biz;
        _locations = results[1] as List<Location>;
        _categories = results[2] as List<ServiceCategory>;
        _services = results[3] as List<Service>;
        _members = results[4] as List<Member>;
        _reviews = results[5] as List<Review>;
        _packages = results[6] as List<Package>;
        _photos = results[7] as List<BusinessPhoto>;
        _hours = results[8] as List<PublicHours>;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------- Derivados ----------

  String? get _address {
    final loc = _locations.isEmpty ? null : _locations.first;
    final parts = <String>[
      if (loc?.address != null && loc!.address!.isNotEmpty) loc.address!,
      if (loc?.postalCode != null && loc!.postalCode!.isNotEmpty) loc.postalCode!,
      if (loc?.city != null && loc!.city!.isNotEmpty) loc.city!,
    ];
    if (parts.isNotEmpty) return parts.join(', ');
    final b = _biz!;
    final alt = [
      if (b.address != null && b.address!.isNotEmpty) b.address!,
      if (b.city != null && b.city!.isNotEmpty) b.city!,
    ];
    return alt.isEmpty ? null : alt.join(', ');
  }

  String? get _phone {
    final b = _biz!;
    final p = (b.phone ?? '').isNotEmpty
        ? b.phone
        : (_locations.isEmpty ? null : _locations.first.phone);
    return (p ?? '').isEmpty ? null : p;
  }

  /// Portada + fotos de la galería, sin repetir la portada si coincide con
  /// la primera foto.
  List<_GalleryItem> get _gallery {
    final b = _biz!;
    final cover = b.coverUrl;
    final items = <_GalleryItem>[
      for (final p in _photos)
        if (p.url.isNotEmpty) _GalleryItem(p.url, p.caption),
    ];
    if (cover != null && cover.isNotEmpty && (items.isEmpty || items.first.url != cover)) {
      items.insert(0, _GalleryItem(cover, null));
    }
    return items;
  }

  // ---------- Acciones ----------

  Future<void> _openUrl(Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) showSnack(context, 'No se pudo abrir el enlace.', error: true);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  void _directions() {
    final b = _biz!;
    final q = b.lat != null && b.lng != null
        ? '${b.lat},${b.lng}'
        : Uri.encodeComponent('${b.name}, ${_address ?? ''}');
    _openUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=$q'));
  }

  void _call() {
    final phone = _phone;
    if (phone == null) return;
    _openUrl(Uri(scheme: 'tel', path: phone.replaceAll(' ', '')));
  }

  void _openWeb(String site) =>
      _openUrl(Uri.parse(site.startsWith('http') ? site : 'https://$site'));

  void _openHandle(String base, String handle) {
    final h = handle.trim().replaceAll('@', '');
    _openUrl(Uri.parse(h.startsWith('http') ? h : '$base$h'));
  }

  void _whatsapp(String number) {
    final digits = number.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return;
    _openUrl(Uri.parse('https://wa.me/$digits'));
  }

  void _openViewer(int index) {
    final items = _gallery;
    if (items.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _PhotoViewer(items: items, initialIndex: index),
    ));
  }

  void _book({Service? initial}) {
    final b = _biz!;
    if (!b.onlineBookingEnabled) {
      showSnack(context, 'Este negocio no admite reservas online ahora mismo.', error: true);
      return;
    }
    if (_services.isEmpty) {
      showSnack(context, 'Este negocio aún no tiene servicios reservables.', error: true);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BookingFlowScreen(
        business: b,
        services: _services,
        members: _members,
        initialService: initial,
      ),
    ));
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    if (_loading && _biz == null) {
      return Scaffold(appBar: AppBar(), body: const LoadingView());
    }
    if (_error != null && _biz == null) {
      return Scaffold(appBar: AppBar(), body: ErrorView(_error!, onRetry: _load));
    }
    final b = _biz!;
    final t = Theme.of(context);
    final gallery = _gallery;
    final status = _OpenStatus.compute(_hours);

    return Scaffold(
      body: MaxWidth(
        child: NestedScrollView(
          headerSliverBuilder: (_, __) => [
            SliverAppBar(
              expandedHeight: gallery.isEmpty ? 200 : 260,
              pinned: true,
              flexibleSpace: FlexibleSpaceBar(
                background: gallery.isEmpty
                    ? _gradient(b)
                    : _Gallery(items: gallery, onTap: _openViewer),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    AvatarCircle(
                        url: b.logoUrl,
                        initials: b.name.isEmpty ? '?' : b.name[0].toUpperCase(),
                        radius: 26),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(b.name,
                            style: t.textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        if ((b.tagline ?? '').isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(b.tagline!,
                                style: t.textTheme.bodyMedium?.copyWith(
                                    fontStyle: FontStyle.italic,
                                    color: t.colorScheme.outline)),
                          ),
                        const SizedBox(height: 4),
                        Row(children: [
                          const Icon(Icons.star_rounded, size: 18, color: AppTheme.warning),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              b.ratingCount == 0
                                  ? 'Sin valoraciones todavía'
                                  : '${b.ratingAvg.toStringAsFixed(1)} · ${b.ratingCount} opiniones',
                              style: t.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ]),
                        if (b.sectorName != null)
                          Text(b.sectorName!,
                              style: t.textTheme.bodySmall
                                  ?.copyWith(color: t.colorScheme.outline)),
                      ]),
                    ),
                  ]),
                  if (status != null) ...[
                    const SizedBox(height: 10),
                    Row(children: [
                      Icon(Icons.schedule,
                          size: 18, color: status.open ? AppTheme.success : AppTheme.danger),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(status.label,
                            style: t.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: status.open ? AppTheme.success : AppTheme.danger)),
                      ),
                    ]),
                  ],
                  if (_address != null) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      Icon(Icons.place_outlined, size: 18, color: t.colorScheme.outline),
                      const SizedBox(width: 6),
                      Expanded(child: Text(_address!, style: t.textTheme.bodyMedium)),
                    ]),
                  ],
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    if (_address != null)
                      ActionChip(
                        avatar: const Icon(Icons.directions_outlined, size: 18),
                        label: const Text('Cómo llegar'),
                        onPressed: _directions,
                      ),
                    if (_phone != null)
                      ActionChip(
                        avatar: const Icon(Icons.call_outlined, size: 18),
                        label: const Text('Llamar'),
                        onPressed: _call,
                      ),
                    if ((b.whatsapp ?? '').isNotEmpty)
                      ActionChip(
                        avatar: const Icon(Icons.chat_outlined, size: 18),
                        label: const Text('WhatsApp'),
                        onPressed: () => _whatsapp(b.whatsapp!),
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.info_outline, size: 18),
                      label: const Text('Más info'),
                      onPressed: () => _tabs.animateTo(4),
                    ),
                  ]),
                  if ((b.description ?? '').isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(b.description!, style: t.textTheme.bodyMedium),
                  ],
                ]),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabBarDelegate(
                TabBar(
                  controller: _tabs,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    Tab(text: 'Servicios (${_services.length})'),
                    Tab(text: 'Equipo (${_members.length})'),
                    Tab(text: 'Bonos (${_packages.length})'),
                    Tab(text: 'Opiniones (${_reviews.length})'),
                    const Tab(text: 'Info'),
                  ],
                ),
                t.scaffoldBackgroundColor,
              ),
            ),
          ],
          body: TabBarView(controller: _tabs, children: [
            _servicesTab(t),
            _teamTab(t),
            _packagesTab(t),
            _reviewsTab(t),
            _infoTab(t, status),
          ]),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: MaxWidth(
          maxWidth: 600,
          child: FilledButton.icon(
            onPressed: _book,
            icon: const Icon(Icons.event_available),
            label: const Text('Reservar cita'),
          ),
        ),
      ),
    );
  }

  Widget _gradient(Business b) {
    final seed = b.name.hashCode;
    // Variaciones dentro de la familia de la marca (teal → azul petróleo)
    final hue = 165.0 + (seed.abs() % 45);
    final c1 = HSLColor.fromAHSL(1, hue, 0.6, 0.42).toColor();
    final c2 = HSLColor.fromAHSL(1, hue + 15, 0.55, 0.22).toColor();
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [c1, c2], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
    );
  }

  // ---------- Servicios ----------

  Widget _servicesTab(ThemeData t) {
    if (_services.isEmpty) {
      return const EmptyView(
          icon: Icons.design_services_outlined,
          title: 'Sin servicios reservables online');
    }
    final byCat = <String?, List<Service>>{};
    for (final s in _services) {
      byCat.putIfAbsent(s.categoryId, () => []).add(s);
    }
    final orderedKeys = <String?>[
      for (final c in _categories)
        if (byCat.containsKey(c.id)) c.id,
      for (final k in byCat.keys)
        if (!_categories.any((c) => c.id == k)) k,
    ];
    String catName(String? id) {
      if (id == null) return 'Otros';
      return _categories.where((c) => c.id == id).firstOrNull?.name ?? 'Otros';
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        for (final k in orderedKeys) ...[
          if (orderedKeys.length > 1 || k != null) SectionTitle(catName(k)),
          for (final s in byCat[k]!) _serviceCard(t, s),
        ],
      ],
    );
  }

  Widget _serviceCard(ThemeData t, Service s) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.name,
                    style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  s.variants.isEmpty
                      ? '${Fmt.duration(s.durationMin)} · ${s.priceLabel}'
                      : '${s.variants.length} opciones',
                  style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline),
                ),
                if ((s.description ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(s.description!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: t.textTheme.bodySmall),
                ],
              ]),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 36,
              child: FilledButton.tonal(
                style: FilledButton.styleFrom(
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(horizontal: 14)),
                onPressed: () => _book(initial: s),
                child: const Text('Reservar'),
              ),
            ),
          ]),
          if (s.variants.isNotEmpty) ...[
            const Divider(height: 16),
            for (final v in s.variants)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Icon(Icons.subdirectory_arrow_right, size: 16, color: t.colorScheme.outline),
                  const SizedBox(width: 6),
                  Expanded(child: Text(v.name, style: t.textTheme.bodyMedium)),
                  Text('${Fmt.duration(v.durationMin)} · ${formatEuros(v.priceCents)}',
                      style: t.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                ]),
              ),
          ],
        ]),
      ),
    );
  }

  // ---------- Equipo ----------

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  Widget _teamTab(ThemeData t) {
    if (_members.isEmpty) {
      return const EmptyView(icon: Icons.badge_outlined, title: 'Equipo no publicado');
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: 150,
      ),
      itemCount: _members.length,
      itemBuilder: (_, i) {
        final m = _members[i];
        return Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              AvatarCircle(
                url: m.avatarUrl,
                initials: _initials(m.displayName),
                color: hexColor(m.color),
                radius: 28,
              ),
              const SizedBox(height: 10),
              Text(m.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              if ((m.title ?? '').isNotEmpty)
                Text(m.title!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
            ]),
          ),
        );
      },
    );
  }

  // ---------- Bonos ----------

  Widget _packagesTab(ThemeData t) {
    if (_packages.isEmpty) {
      return const EmptyView(
          icon: Icons.card_giftcard_outlined,
          title: 'Este negocio no ofrece bonos',
          subtitle: 'Pregunta en el propio negocio por bonos o tarjetas regalo.');
    }
    String typeLabel(String type) {
      switch (type) {
        case 'membership':
          return 'Suscripción';
        case 'gift_card':
          return 'Tarjeta regalo';
        default:
          return 'Bono';
      }
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _packages.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final p = _packages[i];
        final details = <String>[
          if (p.sessions != null) '${p.sessions} sesiones',
          if (p.sessionsPerPeriod != null && p.period != null)
            '${p.sessionsPerPeriod} sesiones/${p.period}',
          if (p.discountPct != null && p.discountPct! > 0) '${p.discountPct}% dto.',
          if (p.validityDays != null) 'válido ${p.validityDays} días',
        ];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: t.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(
                    p.type == 'gift_card'
                        ? Icons.card_giftcard
                        : p.type == 'membership'
                            ? Icons.autorenew
                            : Icons.confirmation_num_outlined,
                    color: t.colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.name,
                      style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  Text(
                    [typeLabel(p.type), ...details].join(' · '),
                    style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline),
                  ),
                  if ((p.description ?? '').isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(p.description!, style: t.textTheme.bodySmall),
                  ],
                ]),
              ),
              const SizedBox(width: 10),
              Text(formatEuros(p.priceCents),
                  style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            ]),
          ),
        );
      },
    );
  }

  // ---------- Opiniones ----------

  Widget _reviewsTab(ThemeData t) {
    if (_reviews.isEmpty) {
      return const EmptyView(
          icon: Icons.reviews_outlined,
          title: 'Todavía no hay opiniones',
          subtitle: 'Sé el primero en valorar tras tu cita.');
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _reviews.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final r = _reviews[i];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(r.customerName ?? 'Cliente',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                Text(Fmt.date(r.createdAt),
                    style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                for (var s = 1; s <= 5; s++)
                  Icon(s <= r.rating ? Icons.star_rounded : Icons.star_outline_rounded,
                      size: 18, color: AppTheme.warning),
              ]),
              if ((r.comment ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(r.comment!, style: t.textTheme.bodyMedium),
              ],
              if ((r.reply ?? '').isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: t.colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Respuesta del negocio',
                        style: t.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700, color: t.colorScheme.primary)),
                    const SizedBox(height: 2),
                    Text(r.reply!, style: t.textTheme.bodySmall),
                  ]),
                ),
              ],
            ]),
          ),
        );
      },
    );
  }

  // ---------- Información ----------

  Widget _infoTab(ThemeData t, _OpenStatus? status) {
    final b = _biz!;
    final amenities = [
      for (final id in b.amenities)
        for (final a in amenityCatalog)
          if (a.id == id) a,
    ];
    final payments = [
      for (final id in b.paymentMethods)
        if (paymentMethodLabels.containsKey(id)) paymentMethodLabels[id]!,
    ];
    final contact = <Widget>[
      if ((b.instagram ?? '').isNotEmpty)
        _contactChip(Icons.camera_alt_outlined, 'Instagram',
            () => _openHandle('https://instagram.com/', b.instagram!)),
      if ((b.facebook ?? '').isNotEmpty)
        _contactChip(Icons.facebook, 'Facebook',
            () => _openHandle('https://facebook.com/', b.facebook!)),
      if ((b.tiktok ?? '').isNotEmpty)
        _contactChip(Icons.music_note_outlined, 'TikTok',
            () => _openHandle('https://tiktok.com/@', b.tiktok!)),
      if ((b.whatsapp ?? '').isNotEmpty)
        _contactChip(Icons.chat_outlined, 'WhatsApp', () => _whatsapp(b.whatsapp!)),
      if ((b.website ?? '').isNotEmpty)
        _contactChip(Icons.language, 'Web', () => _openWeb(b.website!)),
      if (_phone != null) _contactChip(Icons.call_outlined, 'Llamar', _call),
      if ((b.email ?? '').isNotEmpty)
        _contactChip(Icons.mail_outline, 'Email',
            () => _openUrl(Uri(scheme: 'mailto', path: b.email!))),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _infoCard(t, Icons.schedule, 'Horario', _hoursTable(t, status)),
        if (amenities.isNotEmpty) ...[
          const SizedBox(height: 12),
          _infoCard(
            t,
            Icons.spa_outlined,
            'Comodidades',
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final a in amenities)
                Chip(
                  avatar: Icon(_amenityIcon(a.id), size: 18, color: t.colorScheme.primary),
                  label: Text(a.label),
                ),
            ]),
          ),
        ],
        if (payments.isNotEmpty) ...[
          const SizedBox(height: 12),
          _infoCard(
            t,
            Icons.payments_outlined,
            'Formas de pago',
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final p in payments) Chip(label: Text(p)),
            ]),
          ),
        ],
        if (contact.isNotEmpty) ...[
          const SizedBox(height: 12),
          _infoCard(t, Icons.alternate_email, 'Redes y contacto',
              Wrap(spacing: 8, runSpacing: 8, children: contact)),
        ],
        if (_address != null) ...[
          const SizedBox(height: 12),
          _infoCard(t, Icons.place_outlined, 'Ubicación', _locationBlock(t, b)),
        ],
      ],
    );
  }

  Widget _contactChip(IconData icon, String label, VoidCallback onTap) =>
      ActionChip(avatar: Icon(icon, size: 18), label: Text(label), onPressed: onTap);

  Widget _infoCard(ThemeData t, IconData icon, String title, Widget child) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(icon, size: 20, color: t.colorScheme.primary),
            const SizedBox(width: 8),
            Text(title, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 12),
          child,
        ]),
      ),
    );
  }

  Widget _hoursTable(ThemeData t, _OpenStatus? status) {
    if (_hours.isEmpty) {
      return Text('Horario no publicado. Consulta disponibilidad al reservar.',
          style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.outline));
    }
    final today = DateTime.now().weekday % 7; // 0 = domingo
    final byDay = {for (final h in _hours) h.weekday: h};
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (status != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(status.label,
              style: t.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: status.open ? AppTheme.success : AppTheme.danger)),
        ),
      for (final d in const [1, 2, 3, 4, 5, 6, 0])
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: d == today ? t.colorScheme.primary.withValues(alpha: 0.10) : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            Expanded(
              child: Text(Fmt.weekdaysLong[d],
                  style: t.textTheme.bodyMedium?.copyWith(
                      fontWeight: d == today ? FontWeight.w700 : FontWeight.w500)),
            ),
            Text(
              byDay[d] == null ? 'Cerrado' : '${byDay[d]!.opens} – ${byDay[d]!.closes}',
              style: t.textTheme.bodyMedium?.copyWith(
                  fontWeight: d == today ? FontWeight.w700 : FontWeight.w500,
                  color: byDay[d] == null ? t.colorScheme.outline : null),
            ),
          ]),
        ),
    ]);
  }

  Widget _locationBlock(ThemeData t, Business b) {
    final hasCoords = b.lat != null && b.lng != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (hasCoords)
        Container(
          height: 120,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              colors: [
                t.colorScheme.primary.withValues(alpha: 0.18),
                t.colorScheme.primary.withValues(alpha: 0.06),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Stack(alignment: Alignment.center, children: [
            Icon(Icons.map_outlined, size: 56, color: t.colorScheme.primary.withValues(alpha: 0.35)),
            Icon(Icons.place, size: 32, color: t.colorScheme.primary),
          ]),
        ),
      Text(_address!, style: t.textTheme.bodyMedium),
      const SizedBox(height: 10),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.tonalIcon(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
          onPressed: _directions,
          icon: const Icon(Icons.directions_outlined, size: 18),
          label: const Text('Cómo llegar'),
        ),
      ),
    ]);
  }
}

/// Iconos de comodidades como constantes `Icons.*` (el tree-shaking de
/// iconos exige code points constantes; `amenityCatalog` solo guarda el int).
const _amenityIcons = <String, IconData>{
  'wifi': Icons.wifi,
  'parking': Icons.local_parking,
  'accessible': Icons.accessible,
  'card': Icons.credit_card,
  'online_payment': Icons.credit_card,
  'kids': Icons.child_care,
  'pets': Icons.pets,
  'air_conditioning': Icons.ac_unit,
  'home_service': Icons.home,
  'late_hours': Icons.schedule,
};

IconData _amenityIcon(String id) => _amenityIcons[id] ?? Icons.check_circle_outline;

// ============================================================ Horario

/// Estado "abierto/cerrado ahora" calculado con la hora local.
class _OpenStatus {
  final bool open;
  final String label;
  const _OpenStatus(this.open, this.label);

  static int? _minutes(String hhmm) {
    final p = hhmm.split(':');
    if (p.length < 2) return null;
    final h = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  static _OpenStatus? compute(List<PublicHours> hours) {
    if (hours.isEmpty) return null;
    final now = DateTime.now();
    final today = now.weekday % 7;
    final nowMin = now.hour * 60 + now.minute;
    final h = hours.where((e) => e.weekday == today).firstOrNull;
    if (h == null) return const _OpenStatus(false, 'Cerrado hoy');
    final opens = _minutes(h.opens);
    final closes = _minutes(h.closes);
    if (opens == null || closes == null) return null;
    if (nowMin >= opens && nowMin < closes) {
      return _OpenStatus(true, 'Abierto ahora · cierra a las ${h.closes}');
    }
    if (nowMin < opens) return _OpenStatus(false, 'Cerrado ahora · abre a las ${h.opens}');
    return const _OpenStatus(false, 'Cerrado ahora');
  }
}

// ============================================================ Galería

class _GalleryItem {
  final String url;
  final String? caption;
  const _GalleryItem(this.url, this.caption);
}

/// Carrusel de portada: PageView con degradado inferior, indicador de
/// página, contador "1/5" y flechas (útiles con ratón en escritorio).
class _Gallery extends StatefulWidget {
  final List<_GalleryItem> items;
  final ValueChanged<int> onTap;
  const _Gallery({required this.items, required this.onTap});
  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final target = (_index + delta).clamp(0, widget.items.length - 1);
    _controller.animateToPage(target,
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final many = items.length > 1;
    return Stack(fit: StackFit.expand, children: [
      PageView.builder(
        controller: _controller,
        itemCount: items.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) => GestureDetector(
          onTap: () => widget.onTap(i),
          child: CachedNetworkImage(
            imageUrl: items[i].url,
            fit: BoxFit.cover,
            placeholder: (_, __) => const ColoredBox(color: AppTheme.primaryDeep),
            errorWidget: (_, __, ___) => const DecoratedBox(
              decoration: BoxDecoration(gradient: AppTheme.heroGradient),
              child: Center(child: Icon(Icons.broken_image_outlined, color: Colors.white54)),
            ),
          ),
        ),
      ),
      // Degradado inferior para la legibilidad de indicadores y del AppBar
      IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.black.withValues(alpha: 0.35),
                Colors.transparent,
                Colors.transparent,
                Colors.black.withValues(alpha: 0.55),
              ],
              stops: const [0, 0.3, 0.6, 1],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ),
      if (many) ...[
        Positioned(
          left: 4,
          top: 0,
          bottom: 0,
          child: Center(
            child: _arrow(Icons.chevron_left, _index > 0 ? () => _go(-1) : null),
          ),
        ),
        Positioned(
          right: 4,
          top: 0,
          bottom: 0,
          child: Center(
            child: _arrow(Icons.chevron_right,
                _index < items.length - 1 ? () => _go(1) : null),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 12,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < items.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _index ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: i == _index ? 1 : 0.55),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ]),
        ),
      ],
      Positioned(
        right: 12,
        bottom: 10,
        child: IgnorePointer(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.photo_library_outlined, size: 14, color: Colors.white),
              const SizedBox(width: 5),
              Text('${_index + 1}/${items.length}',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ),
    ]);
  }

  Widget _arrow(IconData icon, VoidCallback? onTap) => AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: onTap == null ? 0 : 1,
        child: Material(
          color: Colors.black.withValues(alpha: 0.35),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
          ),
        ),
      );
}

/// Visor a pantalla completa: fondo negro, zoom, pie de foto y cierre.
class _PhotoViewer extends StatefulWidget {
  final List<_GalleryItem> items;
  final int initialIndex;
  const _PhotoViewer({required this.items, required this.initialIndex});
  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _controller = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final target = (_index + delta).clamp(0, widget.items.length - 1);
    _controller.animateToPage(target,
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final caption = items[_index].caption;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(children: [
          PageView.builder(
            controller: _controller,
            itemCount: items.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) => InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Center(
                child: CachedNetworkImage(
                  imageUrl: items[i].url,
                  fit: BoxFit.contain,
                  placeholder: (_, __) =>
                      const Center(child: CircularProgressIndicator(color: Colors.white)),
                  errorWidget: (_, __, ___) =>
                      const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
                ),
              ),
            ),
          ),
          Positioned(
            top: 8,
            left: 8,
            child: IconButton.filledTonal(
              style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close),
              tooltip: 'Cerrar',
            ),
          ),
          Positioned(
            top: 16,
            right: 16,
            child: Text('${_index + 1} / ${items.length}',
                style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
          ),
          if (items.length > 1) ...[
            Positioned(
              left: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: IconButton(
                  onPressed: _index > 0 ? () => _go(-1) : null,
                  icon: const Icon(Icons.chevron_left, color: Colors.white, size: 32),
                ),
              ),
            ),
            Positioned(
              right: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: IconButton(
                  onPressed: _index < items.length - 1 ? () => _go(1) : null,
                  icon: const Icon(Icons.chevron_right, color: Colors.white, size: 32),
                ),
              ),
            ),
          ],
          if ((caption ?? '').isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.75)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Text(caption!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 15)),
              ),
            ),
        ]),
      ),
    );
  }
}

// ============================================================ TabBar fija

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final Color background;
  _TabBarDelegate(this.tabBar, this.background);

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      Container(color: background, child: tabBar);

  @override
  bool shouldRebuild(_TabBarDelegate old) =>
      old.tabBar != tabBar || old.background != background;
}
