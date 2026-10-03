import 'package:flutter/material.dart';

import '../../config.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../services/app_session.dart';
import '../../widgets/common.dart';
import '../client/client_shell.dart';
import 'agenda_screen.dart';
import 'customers_screen.dart';
import 'dashboard_screen.dart';
import 'integrations_screen.dart';
import 'invoices_screen.dart';
import 'marketing_screen.dart';
import 'packages_screen.dart';
import 'reports_screen.dart';
import 'services_screen.dart';
import 'settings_screen.dart';
import 'team_screen.dart';
import 'waitlist_screen.dart';

/// Modo NEGOCIO. Adaptativo:
///  - móvil: barra inferior con 5 destinos + menú "Más".
///  - web/escritorio (≥ 900 px): NavigationRail lateral con todas las secciones
///    → es el panel de administración web.
class BusinessShell extends StatefulWidget {
  const BusinessShell({super.key});
  @override
  State<BusinessShell> createState() => _BusinessShellState();
}

class _NavItem {
  final String label;
  final IconData icon;
  final Widget page;
  final bool managerOnly;
  const _NavItem(this.label, this.icon, this.page, {this.managerOnly = false});
}

class _BusinessShellState extends State<BusinessShell> {
  int _index = 0;
  final session = AppSession.instance;

  @override
  void initState() {
    super.initState();
    session.addListener(_onSession);
  }

  @override
  void dispose() {
    session.removeListener(_onSession);
    super.dispose();
  }

  void _onSession() {
    if (mounted) setState(() {});
  }

  List<_NavItem> _items(AppLocalizations l) => [
        _NavItem(l.navDashboard, Icons.dashboard_outlined, const DashboardScreen()),
        _NavItem(l.navAgenda, Icons.calendar_month_outlined, const AgendaScreen()),
        _NavItem(l.navCustomers, Icons.people_outline, const CustomersScreen()),
        _NavItem(l.navServices, Icons.design_services_outlined, const ServicesScreen(), managerOnly: true),
        _NavItem(l.navTeam, Icons.badge_outlined, const TeamScreen(), managerOnly: true),
        _NavItem(l.navWaitlist, Icons.hourglass_empty, const WaitlistScreen()),
        _NavItem(l.navInvoices, Icons.receipt_long_outlined, const InvoicesScreen()),
        _NavItem(l.navPackages, Icons.card_giftcard_outlined, const PackagesScreen(), managerOnly: true),
        _NavItem(l.navMarketing, Icons.campaign_outlined, const MarketingScreen(), managerOnly: true),
        _NavItem(l.navReports, Icons.bar_chart_outlined, const ReportsScreen(), managerOnly: true),
        _NavItem(l.navIntegrations, Icons.extension_outlined, const IntegrationsScreen(), managerOnly: true),
        _NavItem(l.navSettings, Icons.settings_outlined, const SettingsScreen(), managerOnly: true),
      ];

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final canManage = session.activeMembership?.canManage ?? false;
    final items = _items(l).where((i) => !i.managerOnly || canManage).toList();
    if (_index >= items.length) _index = 0;
    final wide = MediaQuery.sizeOf(context).width >= AppConfig.desktopBreakpoint;

    if (session.activeBusiness == null) {
      return const Scaffold(body: LoadingView());
    }

    if (wide) return _buildWide(context, items, l);
    return _buildMobile(context, items, l);
  }

  // ---------- Escritorio / web ----------
  Widget _buildWide(BuildContext context, List<_NavItem> items, AppLocalizations l) {
    final t = Theme.of(context);
    final b = session.activeBusiness!;
    return Scaffold(
      body: Row(children: [
        Container(
          width: 240,
          color: t.colorScheme.surface,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
              child: Row(children: [
                AvatarCircle(url: b.logoUrl, initials: b.name.isEmpty ? '?' : b.name[0], radius: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(b.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    Text(session.activeMembership?.role ?? '',
                        style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.outline)),
                  ]),
                ),
              ]),
            ),
            const Divider(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                children: [
                  for (var i = 0; i < items.length; i++)
                    ListTile(
                      dense: true,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      selected: i == _index,
                      selectedTileColor: t.colorScheme.primary.withValues(alpha: 0.12),
                      leading: Icon(items[i].icon, size: 20),
                      title: Text(items[i].label),
                      onTap: () => setState(() => _index = i),
                    ),
                ],
              ),
            ),
            const Divider(),
            ListTile(
              dense: true,
              leading: const Icon(Icons.swap_horiz, size: 20),
              title: Text(l.switchToClient),
              onTap: () => _toClient(context),
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.logout, size: 20),
              title: Text(l.signOut),
              onTap: () => _signOut(context),
            ),
            const SizedBox(height: 8),
          ]),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: items[_index].page),
      ]),
    );
  }

  // ---------- Móvil ----------
  Widget _buildMobile(BuildContext context, List<_NavItem> items, AppLocalizations l) {
    const primaryCount = 4; // Inicio, Agenda, Clientes, Servicios/Facturas…
    final primary = items.take(primaryCount).toList();
    final more = items.skip(primaryCount).toList();
    final showingMore = _index >= primaryCount;
    return Scaffold(
      body: items[_index].page,
      bottomNavigationBar: NavigationBar(
        selectedIndex: showingMore ? primaryCount : _index,
        onDestinationSelected: (i) {
          if (i == primaryCount) {
            _openMore(context, more, l);
          } else {
            setState(() => _index = i);
          }
        },
        destinations: [
          for (final it in primary) NavigationDestination(icon: Icon(it.icon), label: it.label),
          const NavigationDestination(icon: Icon(Icons.menu), label: 'Más'),
        ],
      ),
    );
  }

  void _openMore(BuildContext context, List<_NavItem> more, AppLocalizations l) {
    const primaryCount = 4;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          for (var i = 0; i < more.length; i++)
            ListTile(
              leading: Icon(more[i].icon),
              title: Text(more[i].label),
              onTap: () {
                Navigator.pop(c);
                setState(() => _index = primaryCount + i);
              },
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: Text(l.switchToClient),
            onTap: () { Navigator.pop(c); _toClient(context); },
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: Text(l.signOut),
            onTap: () { Navigator.pop(c); _signOut(context); },
          ),
        ]),
      ),
    );
  }

  Future<void> _toClient(BuildContext context) async {
    await session.switchToClientMode();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ClientShell()), (_) => false);
  }

  Future<void> _signOut(BuildContext context) async {
    await session.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
  }
}
