import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/models.dart';
import '../../services/app_session.dart';
import '../../utils/friendly_errors.dart';
import '../../widgets/common.dart';
import 'business_detail_screen.dart';

/// Marketplace: buscar negocios por texto y sector.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});
  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final session = AppSession.instance;
  final _search = TextEditingController();
  Timer? _debounce;
  List<Sector> _sectors = [];
  String? _sectorId;
  List<Business>? _results;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _sectors = session.sectors;
    _init();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    if (_sectors.isEmpty) {
      try {
        _sectors = await session.data.fetchSectors();
      } catch (_) {}
    }
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await session.data
          .searchBusinesses(query: _search.text, sectorId: _sectorId);
      if (!mounted) return;
      setState(() => _results = r);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _load);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Explorar')),
      body: MaxWidth(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                hintText: 'Buscar negocio, ciudad, servicio…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _search.clear();
                          _load();
                        },
                      ),
              ),
            ),
          ),
          if (_sectors.isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _chip('Todos', null),
                  for (final s in _sectors) _chip(s.nameEs, s.id),
                ],
              ),
            ),
          const SizedBox(height: 4),
          Expanded(child: _body(t)),
        ]),
      ),
    );
  }

  Widget _chip(String label, String? id) {
    final selected = _sectorId == id;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          setState(() => _sectorId = id);
          _load();
        },
      ),
    );
  }

  Widget _body(ThemeData t) {
    if (_loading && _results == null) return const LoadingView();
    if (_error != null && _results == null) {
      return ErrorView(_error!, onRetry: _load);
    }
    final list = _results ?? const <Business>[];
    if (list.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(children: const [
          SizedBox(height: 80),
          EmptyView(
            icon: Icons.storefront_outlined,
            title: 'No hay negocios que coincidan',
            subtitle: 'Prueba con otra búsqueda o cambia de sector.',
          ),
        ]),
      );
    }
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 1000 ? 3 : (width >= 640 ? 2 : 1);
    return RefreshIndicator(
      onRefresh: _load,
      child: columns == 1
          ? ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _BusinessCard(list[i], onTap: () => _open(list[i])),
            )
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                mainAxisExtent: 280,
              ),
              itemCount: list.length,
              itemBuilder: (_, i) => _BusinessCard(list[i], onTap: () => _open(list[i])),
            ),
    );
  }

  void _open(Business b) => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => BusinessDetailScreen(businessId: b.id)));
}

class _BusinessCard extends StatelessWidget {
  final Business b;
  final VoidCallback onTap;
  const _BusinessCard(this.b, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final subtitle = [
      if (b.sectorName != null && b.sectorName!.isNotEmpty) b.sectorName!,
      if (b.city != null && b.city!.isNotEmpty) b.city!,
    ].join(' · ');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            height: 150,
            child: Stack(fit: StackFit.expand, children: [
              _cover(),
              if (b.photosCount > 1)
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.photo_library_outlined, size: 13, color: Colors.white),
                      const SizedBox(width: 4),
                      Text('${b.photosCount}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(b.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              if ((b.tagline ?? '').isNotEmpty)
                Text(b.tagline!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
              ],
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.star_rounded, size: 18, color: AppTheme.warning),
                const SizedBox(width: 4),
                Text(
                  b.ratingCount == 0 ? 'Sin valoraciones' : b.ratingAvg.toStringAsFixed(1),
                  style: t.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (b.ratingCount > 0)
                  Text(' (${b.ratingCount})',
                      style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
                const Spacer(),
                if (b.minPriceCents != null)
                  Text('Desde ${formatEuros(b.minPriceCents!)}',
                      style: t.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700, color: t.colorScheme.primary)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _cover() {
    final url = b.coverUrl ?? b.logoUrl;
    if (url != null && url.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        placeholder: (_, __) => _placeholder(),
        errorWidget: (_, __, ___) => _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
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
      alignment: Alignment.center,
      child: Text(
        b.name.isEmpty ? '?' : b.name[0].toUpperCase(),
        style: const TextStyle(
            color: Colors.white, fontSize: 56, fontWeight: FontWeight.w800),
      ),
    );
  }
}
