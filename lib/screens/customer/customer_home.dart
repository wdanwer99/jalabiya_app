import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/repository.dart';
import '../../l10n/strings.dart';
import '../../models/order.dart';
import '../../state/session.dart';
import '../../theme/theme.dart';
import '../../util/contact.dart';
import '../../util/format.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common.dart';
import '../../widgets/live.dart';
import '../../widgets/motion.dart';
import '../../widgets/nav_bar.dart';
import '../../widgets/order_parts.dart';
import '../profile/account_tab.dart';
import 'family_tab.dart';
import 'order_composer_screen.dart';
import 'order_detail_screen.dart';
import 'tailors_screen.dart';

class CustomerHome extends StatefulWidget {
  const CustomerHome({super.key});

  @override
  State<CustomerHome> createState() => _CustomerHomeState();
}

class _CustomerHomeState extends State<CustomerHome> {
  int _tab = 0;

  void _newOrder() {
    Haptics.tap();
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const OrderComposerScreen()),
    );
  }

  void _browseTailors() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const TailorsScreen()),
    );
  }

  void _setTab(int i) {
    if (i != _tab) Haptics.select();
    setState(() => _tab = i);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: AppDrawer(
        selected: const ['orders', 'sizes', 'account'][_tab],
        entries: [
          DrawerEntry(
            id: 'new',
            icon: Icons.add_rounded,
            label: context.tr('orders.new'),
            onTap: _newOrder,
            highlight: true,
          ),
          DrawerEntry(
            id: 'orders',
            icon: Icons.receipt_long_outlined,
            selectedIcon: Icons.receipt_long_rounded,
            label: context.tr('tab.orders'),
            onTap: () => _setTab(0),
          ),
          DrawerEntry(
            id: 'tailors',
            icon: Icons.content_cut_outlined,
            label: context.tr('tailors.title'),
            onTap: _browseTailors,
          ),
          DrawerEntry(
            id: 'sizes',
            icon: Icons.straighten_outlined,
            selectedIcon: Icons.straighten_rounded,
            label: context.tr('tab.family'),
            onTap: () => _setTab(1),
          ),
          DrawerEntry(
            id: 'account',
            icon: Icons.person_outline_rounded,
            selectedIcon: Icons.person_rounded,
            label: context.tr('tab.account'),
            onTap: () => _setTab(2),
          ),
        ],
      ),
      // Each tab is rebuilt when opened, so sizes saved during an order show
      // up in Family straight away.
      body: AnimatedSwitcher(
        duration: reduceMotion(context) ? Duration.zero : Motion.quick,
        child: KeyedSubtree(
          key: ValueKey(_tab),
          child: [
            _OrdersTab(
              onNewOrder: _newOrder,
              onBrowseTailors: _browseTailors,
              onOpenFamily: () => _setTab(1),
            ),
            const FamilyTab(),
            const AccountTab(),
          ][_tab],
        ),
      ),
      bottomNavigationBar: AnimatedNavBar(
        selectedIndex: _tab,
        onSelected: _setTab,
        items: [
          NavItem(
            icon: Icons.receipt_long_outlined,
            selectedIcon: Icons.receipt_long_rounded,
            label: context.tr('tab.orders'),
          ),
          NavItem(
            icon: Icons.straighten_outlined,
            selectedIcon: Icons.straighten_rounded,
            label: context.tr('tab.family'),
          ),
          NavItem(
            icon: Icons.person_outline_rounded,
            selectedIcon: Icons.person_rounded,
            label: context.tr('tab.account'),
          ),
        ],
      ),
    );
  }
}

enum _Filter { all, active, answer, past }

bool _matches(_Filter f, Order o) => switch (f) {
      _Filter.all => true,
      _Filter.active => !isClosed(o.status),
      _Filter.answer => needsCustomer(o.status),
      _Filter.past => isClosed(o.status),
    };

/// The customer's start screen: a greeting with counts on the navy stage,
/// quick ways to start, and their orders as cards that can be filtered and
/// swiped for shortcuts.
class _OrdersTab extends StatefulWidget {
  const _OrdersTab({required this.onNewOrder, required this.onBrowseTailors, required this.onOpenFamily});

  final VoidCallback onNewOrder;
  final VoidCallback onBrowseTailors;
  final VoidCallback onOpenFamily;

  @override
  State<_OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<_OrdersTab> {
  _Filter _filter = _Filter.all;
  bool _fabWide = true;

  void _setFilter(_Filter f) {
    Haptics.select();
    // tapping the active filter again shows everything
    setState(() => _filter = f == _filter ? _Filter.all : f);
  }

  bool _onScroll(UserScrollNotification n) {
    final wide = n.direction != ScrollDirection.reverse;
    if (n.direction != ScrollDirection.idle && wide != _fabWide) setState(() => _fabWide = wide);
    return false;
  }

  void _open(Order o) {
    Haptics.tap();
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => OrderDetailScreen(orderId: o.id)),
    );
  }

  void _reorder(Order o) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => OrderComposerScreen(reorderFrom: o)),
    );
  }

  Future<void> _contact(Order o) async {
    final shop = o.shop;
    final phone = (shop?.ownerWhatsapp ?? '').trim().isNotEmpty ? shop!.ownerWhatsapp! : (shop?.ownerPhone ?? '');
    final ok = await openWhatsApp(phone, text: context.tr('order.waToTailor', {'id': o.shortId}));
    if (!ok && mounted) showSnack(context, context.tr('err.cannotOpen'), error: true);
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<Repository>();
    final session = context.watch<Session>();
    final uid = session.user!.id;
    final firstName = session.profile!.fullName.trim().split(' ').first;

    Widget header(List<Order>? orders) => _HomeHeader(
          name: firstName,
          orders: orders,
          filter: _filter,
          onFilter: _setFilter,
        );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: Palette.nile,
          foregroundColor: Colors.white,
          onPressed: widget.onNewOrder,
          isExtended: _fabWide,
          icon: const Icon(Icons.add_rounded),
          label: Text(context.tr('orders.new')),
        ),
        body: LiveData<List<Order>>(
          load: () => repo.fetchCustomerOrders(uid),
          changes: () => repo.orderChanges(column: 'customer_id', value: uid),
          skeleton: Column(
            children: [
              header(null),
              const Expanded(child: SkeletonList(count: 3)),
            ],
          ),
          frame: (child) => Column(children: [header(null), Expanded(child: child)]),
          builder: (context, orders, refresh) {
            final visible = orders.where((o) => _matches(_filter, o)).toList();
            final attention = orders.where((o) => needsCustomer(o.status)).length;
            return NotificationListener<UserScrollNotification>(
              onNotification: _onScroll,
              child: RefreshIndicator(
                color: Palette.nile,
                backgroundColor: Palette.card,
                onRefresh: () {
                  Haptics.tap();
                  return refresh();
                },
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(child: header(orders)),
                    SliverToBoxAdapter(
                      child: _QuickActions(
                        onNewOrder: widget.onNewOrder,
                        onTailors: widget.onBrowseTailors,
                        onFamily: widget.onOpenFamily,
                      ),
                    ),
                    if (orders.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _EmptyOrders(onNewOrder: widget.onNewOrder, onTailors: widget.onBrowseTailors),
                      )
                    else ...[
                      if (attention > 0 && _filter != _Filter.answer)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                            child: EntranceFade(
                              child: NoticeBanner(
                                tone: BannerTone.warn,
                                text: context.tr('orders.attention', {'n': '$attention'}),
                                action: TextButton(
                                  style: TextButton.styleFrom(foregroundColor: Palette.henna),
                                  onPressed: () => _setFilter(_Filter.answer),
                                  child: Text(context.tr('home.showThem')),
                                ),
                              ),
                            ),
                          ),
                        ),
                      SliverToBoxAdapter(
                        child: _FilterChips(orders: orders, selected: _filter, onSelected: _setFilter),
                      ),
                      if (visible.isEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 36),
                            child: EmptyState(icon: Icons.filter_alt_off_outlined, title: context.tr('home.noneHere')),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                          sliver: SliverList.builder(
                            itemCount: visible.length,
                            itemBuilder: (context, i) {
                              final o = visible[i];
                              return Padding(
                                key: ValueKey(o.id),
                                padding: const EdgeInsets.only(bottom: 12),
                                child: EntranceFade(
                                  index: i,
                                  child: _SwipeActions(
                                    order: o,
                                    onReorder: () => _reorder(o),
                                    onContact: _canContact(o) ? () => _contact(o) : null,
                                    child: _HomeOrderCard(order: o, onTap: () => _open(o)),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.swipe_rounded, size: 16, color: Palette.chalk),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(context.tr('home.swipeHint'),
                                    style: const TextStyle(color: Palette.chalk, fontSize: 12)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SliverToBoxAdapter(child: SizedBox(height: 110)),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  bool _canContact(Order o) =>
      (o.shop?.ownerPhone ?? '').trim().isNotEmpty || (o.shop?.ownerWhatsapp ?? '').trim().isNotEmpty;
}

/// Navy stage with the greeting and three counts that double as filters.
class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.name, required this.orders, required this.filter, required this.onFilter});

  final String name;
  final List<Order>? orders;
  final _Filter filter;
  final ValueChanged<_Filter> onFilter;

  @override
  Widget build(BuildContext context) {
    final list = orders;
    int count(bool Function(Order) test) => list == null ? 0 : list.where(test).length;
    return InkHeader(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 22),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: IconTheme(data: IconThemeData(color: Palette.damur), child: DrawerMenuButton()),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.tr('orders.hello', {'name': name}), style: displayStyle(26, color: Palette.damur)),
                  const SizedBox(height: 4),
                  Text(context.tr('home.subtitle'), style: const TextStyle(color: Palette.onInkMuted, height: 1.45)),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      _StatTile(
                        label: context.tr('home.stat.active'),
                        value: list == null ? null : count((o) => !isClosed(o.status)),
                        icon: Icons.local_shipping_outlined,
                        selected: filter == _Filter.active,
                        onTap: () => onFilter(_Filter.active),
                      ),
                      const SizedBox(width: 10),
                      _StatTile(
                        label: context.tr('home.stat.answer'),
                        value: list == null ? null : count((o) => needsCustomer(o.status)),
                        icon: Icons.notifications_active_outlined,
                        alert: true,
                        selected: filter == _Filter.answer,
                        onTap: () => onFilter(_Filter.answer),
                      ),
                      const SizedBox(width: 10),
                      _StatTile(
                        label: context.tr('home.stat.past'),
                        value: list == null ? null : count((o) => isClosed(o.status)),
                        icon: Icons.inventory_2_outlined,
                        selected: filter == _Filter.past,
                        onTap: () => onFilter(_Filter.past),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.alert = false,
  });

  final String label;
  final int? value;
  final IconData icon;
  final bool selected;
  final bool alert;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hot = alert && (value ?? 0) > 0;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: '$label ${value ?? ''}',
        child: Pressable(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: value == null ? null : onTap,
              child: AnimatedContainer(
                duration: Motion.quick,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                decoration: BoxDecoration(
                  color: selected ? Palette.damur : const Color(0x14F2EDE1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: selected ? Palette.gold : const Color(0x26F2EDE1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(icon,
                            size: 18, color: selected ? Palette.goldInk : (hot ? Palette.gold : Palette.onInkMuted)),
                        const Spacer(),
                        if (hot && !selected)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(color: Palette.gold, shape: BoxShape.circle),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    value == null
                        ? const Shimmer(child: SkeletonBox(width: 28, height: 24))
                        : AnimatedCount(
                            value: value!,
                            style: displayStyle(24, color: selected ? Palette.ink : Palette.damur),
                          ),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: selected ? Palette.muted : Palette.onInkMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onNewOrder, required this.onTailors, required this.onFamily});

  final VoidCallback onNewOrder;
  final VoidCallback onTailors;
  final VoidCallback onFamily;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          _QuickAction(
            icon: Icons.add_rounded,
            label: context.tr('home.quick.new'),
            primary: true,
            onTap: onNewOrder,
          ),
          const SizedBox(width: 10),
          _QuickAction(icon: Icons.content_cut_rounded, label: context.tr('home.quick.tailors'), onTap: onTailors),
          const SizedBox(width: 10),
          _QuickAction(icon: Icons.straighten_rounded, label: context.tr('home.quick.family'), onTap: onFamily),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.onTap, this.primary = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Pressable(
        child: Panel(
          color: primary ? Palette.nile : null,
          borderColor: primary ? Palette.nile : null,
          flat: false,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
          onTap: () {
            Haptics.tap();
            onTap();
          },
          child: Column(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: primary ? const Color(0x26FFFFFF) : Palette.nileSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: primary ? Colors.white : Palette.nile, size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: primary ? Colors.white : Palette.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.orders, required this.selected, required this.onSelected});

  final List<Order> orders;
  final _Filter selected;
  final ValueChanged<_Filter> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        children: [
          for (final f in _Filter.values) ...[
            ChoiceChip(
              label: Text('${context.tr('home.filter.${f.name}')}  ${orders.where((o) => _matches(f, o)).length}'),
              selected: f == selected,
              showCheckmark: false,
              onSelected: (_) => onSelected(f),
              selectedColor: Palette.ink,
              backgroundColor: Palette.card,
              shape: const StadiumBorder(),
              side: BorderSide(color: f == selected ? Palette.ink : Palette.line),
              labelStyle: TextStyle(
                color: f == selected ? Palette.damur : Palette.ink,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

/// Swipe from the start edge to order the same again; from the end edge to
/// message the tailor. The card springs back: nothing is removed.
class _SwipeActions extends StatelessWidget {
  const _SwipeActions({required this.order, required this.child, required this.onReorder, this.onContact});

  final Order order;
  final Widget child;
  final VoidCallback onReorder;
  final VoidCallback? onContact;

  @override
  Widget build(BuildContext context) {
    Widget bg(Color color, IconData icon, String label, AlignmentGeometry align) => Container(
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(Panel.radius)),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          alignment: align,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12.5)),
            ],
          ),
        );
    return Dismissible(
      key: ValueKey('swipe-${order.id}'),
      direction: onContact == null ? DismissDirection.startToEnd : DismissDirection.horizontal,
      dismissThresholds: const {DismissDirection.startToEnd: 0.3, DismissDirection.endToStart: 0.3},
      confirmDismiss: (dir) async {
        Haptics.success();
        if (dir == DismissDirection.startToEnd) {
          onReorder();
        } else {
          onContact?.call();
        }
        return false;
      },
      background:
          bg(Palette.goldInk, Icons.replay_rounded, context.tr('order.again'), AlignmentDirectional.centerStart),
      secondaryBackground:
          bg(Palette.nile, Icons.chat_outlined, context.tr('home.swipeContact'), AlignmentDirectional.centerEnd),
      child: child,
    );
  }
}

class _HomeOrderCard extends StatelessWidget {
  const _HomeOrderCard({required this.order, required this.onTap});

  final Order order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final o = order;
    final price = o.price ?? o.estimate;
    final when = o.dueDate != null && !isClosed(o.status)
        ? context.tr('orders.due', {'date': formatDate(context, o.dueDate!)})
        : formatDate(context, o.createdAt);
    return Pressable(
      child: Panel(
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ClothTile(order: o, heroTag: 'cloth-${o.id}'),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              context.tr('orders.for', {'name': o.wearerLabel}),
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (o.quantity > 1)
                            Container(
                              margin: const EdgeInsetsDirectional.only(start: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: Palette.goldSoft,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('×${o.quantity}', style: monoStyle(12, color: Palette.goldInk)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        o.shop?.shopName ?? '',
                        style: const TextStyle(color: Palette.muted, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          StatusChip(o.status),
                          const Spacer(),
                          if (price != null)
                            Text(formatMoney(context, price, o.currency),
                                style: monoStyle(13, weight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            MiniProgress(status: o.status),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  o.dueDate != null && !isClosed(o.status) ? Icons.event_outlined : Icons.schedule_rounded,
                  size: 14,
                  color: Palette.muted,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(when,
                      overflow: TextOverflow.ellipsis, style: const TextStyle(color: Palette.muted, fontSize: 12)),
                ),
                Text('#${o.shortId}', style: monoStyle(11, color: Palette.chalk)),
                const Icon(Icons.chevron_right_rounded, color: Palette.chalk, size: 20),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyOrders extends StatelessWidget {
  const _EmptyOrders({required this.onNewOrder, required this.onTailors});

  final VoidCallback onNewOrder;
  final VoidCallback onTailors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 32, 32, 24),
      child: EntranceFade(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Palette.goldSoft, Color(0xFFEBD9AE)],
                ),
              ),
              child: const Icon(Icons.checkroom_rounded, size: 46, color: Palette.goldInk),
            ),
            const SizedBox(height: 18),
            Text(context.tr('orders.emptyTitle'), textAlign: TextAlign.center, style: displayStyle(20)),
            const SizedBox(height: 6),
            Text(
              context.tr('orders.emptyBody'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Palette.muted, height: 1.5),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onNewOrder,
              icon: const Icon(Icons.add_rounded),
              label: Text(context.tr('orders.new')),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onTailors,
              icon: const Icon(Icons.content_cut_rounded, size: 18),
              label: Text(context.tr('tailors.title')),
            ),
          ],
        ),
      ),
    );
  }
}
