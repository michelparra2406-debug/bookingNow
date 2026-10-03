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

/// Ficha pública de un negocio: servicios, equipo, bonos y opiniones.
class BusinessDetailScreen extends StatefulWidget {
  final String businessId;
  const BusinessDetailScreen({super.key, required this.businessId});
  @override
  State<BusinessDetailScreen> createState() => _BusinessDetailScreenState();
}

class _BusinessDetailScreenState extends State<BusinessDetailScreen>
    with SingleTickerProviderStateMixin {
  final data = AppSession.instance.data;
  late final TabController _tabs = TabController(length: 4, vsync: this);

  Business? _biz;
  List<Location> _locations = [];
  List<ServiceCategory> _categories = [];
  List<Service> _services = [];
  List<Member> _members = [];
  List<Review> _reviews = [];
  List<Package> _packages = [];
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
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------- Acciones ----------

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

  Future<void> _openUrl(Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) showSnack(context, 'No se pudo abrir el enlace.', error: true);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  void _directions() {
    final q = Uri.encodeComponent('${_biz!.name}, ${_address ?? ''}');
    _openUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=$q'));
  }

  void _call() {
    final phone = _biz!.phone ?? (_locations.isEmpty ? null : _locations.first.phone);
    if (phone == null || phone.isEmpty) return;
    _openUrl(Uri(scheme: 'tel', path: phone.replaceAll(' ', '')));
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
    final hasPhone = (b.phone ?? '').isNotEmpty ||
        (_locations.isNotEmpty && (_locations.first.phone ?? '').isNotEmpty);

    return Scaffold(
      body: MaxWidth(
        child: NestedScrollView(
          headerSliverBuilder: (_, __) => [
            SliverAppBar(
              expandedHeight: 220,
              pinned: true,
              flexibleSpace: FlexibleSpaceBar(background: _cover(b)),
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
                        if (b.sectorName != null)
                          Text(b.sectorName!,
                              style: t.textTheme.bodyMedium
                                  ?.copyWith(color: t.colorScheme.outline)),
                        const SizedBox(height: 4),
                        Row(children: [
                          const Icon(Icons.star_rounded, size: 18, color: AppTheme.warning),
                          const SizedBox(width: 4),
                          Text(
                            b.ratingCount == 0
                                ? 'Sin valoraciones todavía'
                                : '${b.ratingAvg.toStringAsFixed(1)} · ${b.ratingCount} opiniones',
                            style: t.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ]),
                      ]),
                    ),
                  ]),
                  if (_address != null) ...[
                    const SizedBox(height: 12),
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
                    if (hasPhone)
                      ActionChip(
                        avatar: const Icon(Icons.call_outlined, size: 18),
                        label: const Text('Llamar'),
                        onPressed: _call,
                      ),
                    if ((b.website ?? '').isNotEmpty)
                      ActionChip(
                        avatar: const Icon(Icons.language, size: 18),
                        label: const Text('Web'),
                        onPressed: () => _openUrl(Uri.parse(
                            b.website!.startsWith('http') ? b.website! : 'https://${b.website}')),
                      ),
                    if ((b.instagram ?? '').isNotEmpty)
                      ActionChip(
                        avatar: const Icon(Icons.camera_alt_outlined, size: 18),
                        label: const Text('Instagram'),
                        onPressed: () => _openUrl(Uri.parse(
                            'https://instagram.com/${b.instagram!.replaceAll('@', '')}')),
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

  Widget _cover(Business b) {
    final url = b.coverUrl;
    if (url != null && url.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => _gradient(b),
      );
    }
    return _gradient(b);
  }

  Widget _gradient(Business b) {
    final seed = b.name.hashCode;
    final c1 = HSLColor.fromAHSL(1, (seed % 360).toDouble(), 0.55, 0.5).toColor();
    final c2 = HSLColor.fromAHSL(1, ((seed + 40) % 360).toDouble(), 0.6, 0.35).toColor();
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

  Widget _teamTab(ThemeData t) {
    if (_members.isEmpty) {
      return const EmptyView(icon: Icons.badge_outlined, title: 'Equipo no publicado');
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _members.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final m = _members[i];
        return Card(
          child: ListTile(
            leading: AvatarCircle(
              url: m.avatarUrl,
              initials: m.displayName.isEmpty ? '?' : m.displayName[0].toUpperCase(),
              color: hexColor(m.color),
            ),
            title: Text(m.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: (m.title ?? '').isEmpty ? null : Text(m.title!),
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
}

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
