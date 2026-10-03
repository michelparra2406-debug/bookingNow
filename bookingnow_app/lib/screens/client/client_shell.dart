import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../services/app_session.dart';
import '../business/business_shell.dart';
import '../business/onboarding_screen.dart';
import 'explore_screen.dart';
import 'my_bookings_screen.dart';
import 'profile_screen.dart';

/// Modo CLIENTE: explorar negocios, mis citas y perfil.
class ClientShell extends StatefulWidget {
  final int initialIndex;
  const ClientShell({super.key, this.initialIndex = 0});
  @override
  State<ClientShell> createState() => _ClientShellState();
}

class _ClientShellState extends State<ClientShell> {
  late int _index = widget.initialIndex;
  final session = AppSession.instance;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    const pages = [ExploreScreen(), MyBookingsScreen(), ProfileScreen()];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.search_outlined), selectedIcon: const Icon(Icons.search), label: l.tabExplore),
          NavigationDestination(icon: const Icon(Icons.event_outlined), selectedIcon: const Icon(Icons.event), label: l.tabBookings),
          NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person), label: l.tabProfile),
        ],
      ),
    );
  }
}

/// Cambia al modo negocio (o lanza el alta de negocio si no tiene ninguno).
Future<void> goToBusinessMode(BuildContext context) async {
  final session = AppSession.instance;
  if (!session.hasBusinesses) {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OnboardingScreen()));
    return;
  }
  if (session.memberships.length == 1) {
    await session.switchToBusiness(session.memberships.first.businessId);
  } else {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const ListTile(title: Text('Elige el negocio', style: TextStyle(fontWeight: FontWeight.w700))),
          for (final m in session.memberships)
            FutureBuilder(
              future: session.biz.fetchBusiness(m.businessId),
              builder: (_, snap) => ListTile(
                leading: const Icon(Icons.storefront),
                title: Text(snap.data?.name ?? '…'),
                subtitle: Text(m.role),
                onTap: () => Navigator.pop(c, m.businessId),
              ),
            ),
        ]),
      ),
    );
    if (chosen == null) return;
    await session.switchToBusiness(chosen);
  }
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const BusinessShell()), (_) => false);
}
