import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repository.dart';
import '../../l10n/strings.dart';
import '../../models/order.dart';
import '../../state/order_alerts.dart';
import '../../state/session.dart';
import '../../theme/theme.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common.dart';
import '../../widgets/live.dart';
import '../../widgets/motion.dart';
import '../../widgets/nav_bar.dart';
import '../../widgets/order_parts.dart';
import '../profile/account_tab.dart';
import 'tailor_order_screen.dart';

class TailorHome extends StatefulWidget {
  const TailorHome({super.key});

  @override
  State<TailorHome> createState() => _TailorHomeState();
}

class _TailorHomeState extends State<TailorHome> {
  int _tab = 0;

  void _setTab(int i) {
    if (i != _tab) Haptics.select();
    setState(() => _tab = i);
  }

  @override
  Widget build(BuildContext context) {
    final awaiting = context.watch<OrderAlerts>().awaiting;
    return Scaffold(
      drawer: AppDrawer(
        selected: const ['work', 'shop'][_tab],
        entries: [
          DrawerEntry(
            id: 'work',
            icon: Icons.content_cut_outlined,
            selectedIcon: Icons.content_cut_rounded,
            label: context.tr('tab.work'),
            badge: awaiting,
            onTap: () => _setTab(0),
          ),
          DrawerEntry(
            id: 'shop',
            icon: Icons.storefront_outlined,
            selectedIcon: Icons.storefront_rounded,
            label: context.tr('tab.shop'),
            onTap: () => _setTab(1),
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: reduceMotion(context) ? Duration.zero : Motion.quick,
        child: KeyedSubtree(
          key: ValueKey(_tab),
          child: [const _TailorOrders(), const AccountTab()][_tab],
        ),
      ),
      bottomNavigationBar: AnimatedNavBar(
        selectedIndex: _tab,
        onSelected: _setTab,
        items: [
          NavItem(
            icon: Icons.content_cut_outlined,
            selectedIcon: Icons.content_cut_rounded,
            label: context.tr('tab.work'),
            badge: awaiting,
          ),
          NavItem(
            icon: Icons.storefront_outlined,
            selectedIcon: Icons.storefront_rounded,
            label: context.tr('tab.shop'),
          ),
        ],
      ),
    );
  }
}

class _TailorOrders extends StatelessWidget {
  const _TailorOrders();

  @override
  Widget build(BuildContext context) {
    final repo = context.read<Repository>();
    final session = context.watch<Session>();
    final uid = session.user?.id;
    // Signed out: the gate is fading this screen away, so draw nothing.
    if (uid == null) return const SizedBox.shrink();
    final shop = session.shop;
    return LiveData<List<Order>>(
      load: () => repo.fetchTailorOrders(uid),
      changes: () => repo.orderChanges(column: 'tailor_id', value: uid),
      builder: (context, orders, refresh) {
        final fresh = orders.where((o) => needsTailor(o.status)).toList();
        final work = orders.where((o) => !needsTailor(o.status) && !isClosed(o.status)).toList()
          ..sort((a, b) {
            final ad = a.dueDate ?? DateTime(2100);
            final bd = b.dueDate ?? DateTime(2100);
            return ad.compareTo(bd);
          });
        final closed = orders.where((o) => isClosed(o.status)).toList();
        return DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              leading: const DrawerMenuButton(),
              title: Text(shop?.shopName ?? context.tr('tab.work')),
              bottom: TabBar(
                labelColor: Palette.ink,
                unselectedLabelColor: Palette.muted,
                indicatorColor: Palette.gold,
                indicatorWeight: 3,
                tabs: [
                  Tab(text: '${context.tr('tailor.tabNew')} (${fresh.length})'),
                  Tab(text: '${context.tr('tailor.tabWork')} (${work.length})'),
                  Tab(text: context.tr('tailor.tabClosed')),
                ],
              ),
            ),
            body: Column(
              children: [
                if (shop != null && ShopStatusBanner.applies(shop))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: ShopStatusBanner(shop: shop),
                  ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _list(context, fresh, refresh, 'tailor.emptyNew'),
                      _list(context, work, refresh, 'tailor.emptyWork'),
                      _list(context, closed, refresh, 'tailor.emptyClosed'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _list(BuildContext context, List<Order> orders, Future<void> Function() refresh, String emptyKey) {
    if (orders.isEmpty) {
      return RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.1),
            EmptyState(icon: Icons.inbox_outlined, title: context.tr(emptyKey)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        itemCount: orders.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) => OrderCard(
          order: orders[i],
          forTailor: true,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => TailorOrderScreen(orderId: orders[i].id)),
          ),
        ),
      ),
    );
  }
}
