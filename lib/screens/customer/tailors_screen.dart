import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/repository.dart';
import '../../l10n/strings.dart';
import '../../models/design.dart';
import '../../models/tailor_shop.dart';
import '../../state/session.dart';
import '../../theme/theme.dart';
import '../../util/contact.dart';
import '../../util/format.dart';
import '../../widgets/common.dart';
import '../../widgets/motion.dart';
import 'order_composer_screen.dart';

enum _Sort { near, price, fast }

/// Browse the approved tailors taking orders, and pick one to make the
/// jalabiya. Tailors in the customer's city come first.
class TailorsScreen extends StatefulWidget {
  const TailorsScreen({super.key});

  @override
  State<TailorsScreen> createState() => _TailorsScreenState();
}

class _TailorsScreenState extends State<TailorsScreen> {
  final _search = TextEditingController();
  List<TailorShop>? _shops;
  Object? _error;
  bool _myCityOnly = false;
  _Sort _sort = _Sort.near;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final shops = await context.read<Repository>().listOpenShops();
      if (mounted) {
        setState(() {
          _shops = shops;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  List<TailorShop> _visible(String? myCity) {
    final q = _search.text.trim().toLowerCase();
    final list = (_shops ?? const <TailorShop>[]).where((s) {
      if (_myCityOnly && myCity != null && s.city != myCity) return false;
      if (q.isEmpty) return true;
      return s.shopName.toLowerCase().contains(q) ||
          s.city.toLowerCase().contains(q) ||
          cityLabel(context, s.city).toLowerCase().contains(q) ||
          s.neighbourhood.toLowerCase().contains(q);
    }).toList();
    int near(TailorShop a, TailorShop b) {
      final ac = a.city == myCity ? 0 : 1;
      final bc = b.city == myCity ? 0 : 1;
      if (ac != bc) return ac - bc;
      return a.shopName.compareTo(b.shopName);
    }

    list.sort(switch (_sort) {
      _Sort.near => near,
      _Sort.price => (a, b) {
          final c = a.basePrice.compareTo(b.basePrice);
          return c != 0 ? c : near(a, b);
        },
      _Sort.fast => (a, b) {
          final c = a.leadTimeDays.compareTo(b.leadTimeDays);
          return c != 0 ? c : near(a, b);
        },
    });
    return list;
  }

  void _orderFrom(TailorShop shop) {
    Haptics.tap();
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => OrderComposerScreen(tailor: shop)),
    );
  }

  void _showDetails(TailorShop shop) {
    Haptics.tap();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Palette.paper,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (ctx) => _TailorSheet(
        shop: shop,
        nearby: shop.city == context.read<Session>().profile?.city,
        onOrder: () {
          Navigator.of(ctx).pop();
          _orderFrom(shop);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final myCity = context.watch<Session>().profile?.city;
    final hasCity = (myCity ?? '').trim().isNotEmpty;
    final header = _Header(
      search: _search,
      onChanged: () => setState(() {}),
    );

    final List<Widget> slivers;
    if (_shops == null && _error != null) {
      slivers = [
        SliverFillRemaining(
          hasScrollBody: false,
          child: ErrorView(error: _error!, onRetry: _load),
        ),
      ];
    } else if (_shops == null) {
      slivers = [
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList.list(children: [for (var i = 0; i < 3; i++) const _TailorSkeleton()]),
        ),
      ];
    } else if (_shops!.isEmpty) {
      slivers = [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: Icons.content_cut_rounded,
            title: context.tr('compose.noTailors'),
            body: context.tr('compose.noTailorsBody'),
          ),
        ),
      ];
    } else {
      final shops = _visible(myCity);
      slivers = [
        SliverToBoxAdapter(
          child: _Filters(
            cityLabel: hasCity ? cityLabel(context, myCity) : null,
            myCityOnly: _myCityOnly,
            sort: _sort,
            onCity: (v) {
              Haptics.select();
              setState(() => _myCityOnly = v);
            },
            onSort: (v) {
              Haptics.select();
              setState(() => _sort = v);
            },
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
            child: AnimatedSwitcher(
              duration: Motion.quick,
              child: Text(
                context.tr('tailors.count', {'n': '${shops.length}'}),
                key: ValueKey(shops.length),
                style: const TextStyle(color: Palette.muted, fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ),
        if (shops.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 24),
              child: EmptyState(icon: Icons.search_off_rounded, title: context.tr('tailors.noMatch')),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
            sliver: SliverList.builder(
              itemCount: shops.length,
              itemBuilder: (context, i) {
                final s = shops[i];
                return Padding(
                  key: ValueKey(s.tailorId),
                  padding: const EdgeInsets.only(bottom: 14),
                  child: EntranceFade(
                    index: i,
                    child: _TailorCard(
                      shop: s,
                      nearby: hasCity && s.city == myCity,
                      onTap: () => _showDetails(s),
                      onOrder: () => _orderFrom(s),
                    ),
                  ),
                );
              },
            ),
          ),
      ];
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: RefreshIndicator(
          color: Palette.nile,
          edgeOffset: 160,
          onRefresh: _load,
          child: CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [SliverToBoxAdapter(child: header), ...slivers],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.search, required this.onChanged});

  final TextEditingController search;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return InkHeader(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 20),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const BackButton(color: Palette.damur),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.tr('tailors.title'), style: displayStyle(26, color: Palette.damur)),
                  const SizedBox(height: 4),
                  Text(context.tr('tailors.intro'), style: const TextStyle(color: Palette.onInkMuted, height: 1.45)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: search,
                    onChanged: (_) => onChanged(),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: context.tr('tailors.search'),
                      hintStyle: const TextStyle(color: Palette.chalk),
                      filled: true,
                      fillColor: Palette.card,
                      prefixIcon: const Icon(Icons.search_rounded, color: Palette.muted),
                      suffixIcon: search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: context.tr('action.cancel'),
                              icon: const Icon(Icons.close_rounded, color: Palette.muted),
                              onPressed: () {
                                search.clear();
                                onChanged();
                              },
                            ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Palette.gold, width: 1.6),
                      ),
                    ),
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

class _Filters extends StatelessWidget {
  const _Filters({
    required this.cityLabel,
    required this.myCityOnly,
    required this.sort,
    required this.onCity,
    required this.onSort,
  });

  final String? cityLabel;
  final bool myCityOnly;
  final _Sort sort;
  final ValueChanged<bool> onCity;
  final ValueChanged<_Sort> onSort;

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, bool selected, VoidCallback onTap, {IconData? icon}) => Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: FilterChip(
            avatar: icon == null ? null : Icon(icon, size: 16, color: selected ? Palette.damur : Palette.muted),
            label: Text(label),
            selected: selected,
            showCheckmark: false,
            onSelected: (_) => onTap(),
            selectedColor: Palette.ink,
            backgroundColor: Palette.card,
            shape: const StadiumBorder(),
            side: BorderSide(color: selected ? Palette.ink : Palette.line),
            labelStyle: TextStyle(
              color: selected ? Palette.damur : Palette.ink,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        );
    return SizedBox(
      height: 64,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        children: [
          if (cityLabel != null)
            chip(context.tr('tailors.inCity', {'city': cityLabel!}), myCityOnly, () => onCity(!myCityOnly),
                icon: Icons.place_outlined),
          chip(context.tr('tailors.sort.near'), sort == _Sort.near, () => onSort(_Sort.near),
              icon: Icons.near_me_outlined),
          chip(context.tr('tailors.sort.price'), sort == _Sort.price, () => onSort(_Sort.price),
              icon: Icons.payments_outlined),
          chip(context.tr('tailors.sort.fast'), sort == _Sort.fast, () => onSort(_Sort.fast), icon: Icons.bolt_rounded),
        ],
      ),
    );
  }
}

class _TailorCard extends StatelessWidget {
  const _TailorCard({required this.shop, required this.nearby, required this.onTap, required this.onOrder});

  final TailorShop shop;
  final bool nearby;
  final VoidCallback onTap;
  final VoidCallback onOrder;

  @override
  Widget build(BuildContext context) {
    final cloths = shop.offeredCloths;
    return Pressable(
      child: Panel(
        onTap: onTap,
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // the shop's cloths as a ribbon across the top of the card
            SizedBox(
              height: 6,
              child: Row(
                children: [
                  for (final c in cloths.take(8)) Expanded(child: ColoredBox(color: Color(0xFF000000 | c.color))),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ShopBadge(name: shop.shopName),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(shop.shopName, style: displayStyle(17)),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(Icons.place_outlined, size: 15, color: Palette.muted),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    placeLine(context, shop.city, shop.neighbourhood),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Palette.muted, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (nearby)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: Palette.nileSoft, borderRadius: BorderRadius.circular(20)),
                          child: Text(
                            context.tr('tailors.nearby'),
                            style: const TextStyle(color: Palette.nile, fontSize: 11.5, fontWeight: FontWeight.w600),
                          ),
                        ),
                    ],
                  ),
                  if ((shop.bio ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      shop.bio!.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(height: 1.5, fontSize: 14),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _Pill(Icons.payments_outlined,
                          context.tr('shop.from', {'price': formatMoney(context, shop.basePrice, shop.currency)})),
                      _Pill(Icons.schedule_rounded, context.tr('shop.ready', {'days': '${shop.leadTimeDays}'})),
                      _Pill(Icons.palette_outlined, context.tr('tailors.colours', {'n': '${cloths.length}'})),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(minimumSize: const Size(64, 46)),
                          onPressed: onTap,
                          child: Text(context.tr('tailors.details')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(minimumSize: const Size(64, 46)),
                          onPressed: onOrder,
                          icon: const Icon(Icons.checkroom_rounded, size: 20),
                          label: Text(context.tr('tailors.orderHere')),
                        ),
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

class _TailorSkeleton extends StatelessWidget {
  const _TailorSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Panel(
        child: Shimmer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  SkeletonBox(height: 46, circle: true),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FractionallySizedBox(widthFactor: 0.55, child: SkeletonBox(height: 16)),
                        SizedBox(height: 8),
                        FractionallySizedBox(widthFactor: 0.4, child: SkeletonBox(height: 11)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: const [
                  SkeletonBox(width: 90, height: 28, radius: 14),
                  SizedBox(width: 8),
                  SkeletonBox(width: 90, height: 28, radius: 14),
                ],
              ),
              const SizedBox(height: 14),
              const SkeletonBox(height: 46, radius: 12),
            ],
          ),
        ),
      ),
    );
  }
}

/// The full shop: about, colours, price, time, place, and ways to reach the tailor.
class _TailorSheet extends StatelessWidget {
  const _TailorSheet({required this.shop, required this.nearby, required this.onOrder});

  final TailorShop shop;
  final bool nearby;
  final VoidCallback onOrder;

  @override
  Widget build(BuildContext context) {
    final phone = (shop.ownerPhone ?? '').trim();
    final whatsapp = (shop.ownerWhatsapp ?? '').trim().isNotEmpty ? shop.ownerWhatsapp!.trim() : phone;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(
        children: [
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 16),
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: Palette.line, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    _ShopBadge(name: shop.shopName, size: 60),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(shop.shopName, style: displayStyle(22)),
                          if ((shop.ownerName ?? '').trim().isNotEmpty)
                            Text(shop.ownerName!.trim(), style: const TextStyle(color: Palette.muted)),
                          if (nearby)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(context.tr('tailors.nearby'),
                                  style: const TextStyle(
                                      color: Palette.nile, fontWeight: FontWeight.w600, fontSize: 12.5)),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                if ((shop.bio ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(shop.bio!.trim(), style: const TextStyle(height: 1.6, fontSize: 15)),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    _FactTile(
                      icon: Icons.payments_outlined,
                      label: context.tr('shop.price'),
                      value: formatMoney(context, shop.basePrice, shop.currency),
                    ),
                    const SizedBox(width: 10),
                    _FactTile(
                      icon: Icons.schedule_rounded,
                      label: context.tr('shop.lead'),
                      value: context.tr('shop.days', {'days': '${shop.leadTimeDays}'}),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Panel(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Column(
                    children: [
                      InfoRow(context.tr('profile.place'), placeLine(context, shop.city, shop.neighbourhood)),
                      if (shop.addressDetails.trim().isNotEmpty)
                        InfoRow(context.tr('profile.addressDetails'), shop.addressDetails.trim()),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(context.tr('compose.priceNote'), style: const TextStyle(color: Palette.chalk, fontSize: 12.5)),
                for (final kind in const ['cloth', 'thread']) ...[
                  const SizedBox(height: 20),
                  Text(context.tr('options.$kind'), style: displayStyle(16)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in kind == 'cloth' ? shop.offeredCloths : shop.offeredThreads)
                        _ColourChip(kind: kind, swatch: s, currency: shop.currency),
                    ],
                  ),
                ],
                if (phone.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => callNumber(phone),
                          icon: const Icon(Icons.call_outlined),
                          label: Text(context.tr('action.call')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => openWhatsApp(whatsapp),
                          icon: const Icon(Icons.chat_outlined),
                          label: Text(context.tr('action.whatsapp')),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          // the main action stays in reach however far the sheet scrolls
          BottomActions(children: [
            FilledButton.icon(
              onPressed: onOrder,
              icon: const Icon(Icons.checkroom_rounded),
              label: Text(context.tr('tailors.orderHere')),
            ),
          ]),
        ],
      ),
    );
  }
}

class _ColourChip extends StatelessWidget {
  const _ColourChip({required this.kind, required this.swatch, required this.currency});

  final String kind;
  final Swatch swatch;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(6, 6, 12, 6),
      decoration: BoxDecoration(
        color: Palette.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Palette.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Color(0xFF000000 | swatch.color),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0x22101A2B)),
            ),
          ),
          const SizedBox(width: 8),
          Text(swatchName(context, kind, swatch), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          if (swatch.price > 0) ...[
            const SizedBox(width: 6),
            Text('+${formatMoney(context, swatch.price, currency)}',
                style: const TextStyle(fontSize: 12, color: Palette.goldInk, fontWeight: FontWeight.w600)),
          ],
        ],
      ),
    );
  }
}

class _FactTile extends StatelessWidget {
  const _FactTile({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Panel(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Palette.goldInk, size: 22),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(color: Palette.muted, fontSize: 12)),
            const SizedBox(height: 2),
            Text(value, style: displayStyle(16)),
          ],
        ),
      ),
    );
  }
}

/// The shop's initial on a gold disc, standing in for a logo.
class _ShopBadge extends StatelessWidget {
  const _ShopBadge({required this.name, this.size = 46});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = name.trim();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Palette.goldSoft, Color(0xFFEBD9AE)],
        ),
      ),
      child: Text(t.isEmpty ? '?' : t.characters.first, style: displayStyle(size * 0.42, color: Palette.goldInk)),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: Palette.goldSoft, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Palette.goldInk),
          const SizedBox(width: 5),
          Text(text, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Palette.ink)),
        ],
      ),
    );
  }
}
