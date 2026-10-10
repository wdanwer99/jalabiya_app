import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/repository.dart';
import '../../l10n/strings.dart';
import '../../models/order.dart';
import '../../state/session.dart';
import '../../theme/theme.dart';
import '../../util/format.dart';
import '../../widgets/common.dart';
import '../../widgets/fitting_room.dart';
import '../../widgets/live.dart';
import '../../widgets/motion.dart';
import '../../widgets/order_parts.dart';
import 'order_composer_screen.dart';

/// The customer's view of one order, live: it updates the moment the tailor
/// confirms, asks for a change, offers a new price, or moves it along.
class OrderDetailScreen extends StatelessWidget {
  const OrderDetailScreen({super.key, required this.orderId, this.justSent = false});

  final String orderId;
  final bool justSent;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<Repository>();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: LiveData<OrderBundle>(
          load: () => repo.fetchOrder(orderId),
          changes: () => repo.orderChanges(column: 'id', value: orderId),
          skeleton: const _DetailSkeleton(),
          frame: (child) => Column(
            children: [
              const _PlainHeader(),
              Expanded(child: child),
            ],
          ),
          builder: (context, bundle, refresh) =>
              _CustomerOrderBody(bundle: bundle, justSent: justSent, refresh: refresh),
        ),
      ),
    );
  }
}

class _CustomerOrderBody extends StatefulWidget {
  const _CustomerOrderBody({required this.bundle, required this.justSent, required this.refresh});

  final OrderBundle bundle;
  final bool justSent;
  final Future<void> Function() refresh;

  @override
  State<_CustomerOrderBody> createState() => _CustomerOrderBodyState();
}

class _CustomerOrderBodyState extends State<_CustomerOrderBody> {
  final _room = FittingRoomController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _room.setUnit(context.read<Session>().unit);
    _room.show(widget.bundle.order.measurements, widget.bundle.order.design);
    if (widget.justSent) Haptics.success();
  }

  @override
  void didUpdateWidget(_CustomerOrderBody old) {
    super.didUpdateWidget(old);
    _room.show(widget.bundle.order.measurements, widget.bundle.order.design);
  }

  @override
  void dispose() {
    _room.dispose();
    super.dispose();
  }

  Future<void> _cancel(Order o) async {
    final ok = await confirmAction(
      context,
      title: context.tr('order.cancelTitle'),
      body: context.tr('order.cancelBody'),
      confirmLabel: context.tr('order.cancel'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _run(() => context.read<Repository>().advanceOrder(o.id, OrderStatus.cancelled));
  }

  Future<void> _accept(Order o) async {
    final ok = await confirmAction(
      context,
      title: context.tr('offer.acceptTitle'),
      body: context.tr('offer.acceptBody', {
        'price': formatMoney(context, o.price ?? 0, o.currency),
        'date': o.dueDate == null ? '—' : formatDate(context, o.dueDate!),
      }),
      confirmLabel: context.tr('offer.accept'),
    );
    if (!ok || !mounted) return;
    final done = await _run(() => context.read<Repository>().advanceOrder(o.id, OrderStatus.confirmed));
    if (done && mounted) await showSuccess(context, context.tr('offer.accepted'));
  }

  Future<void> _reject(Order o) async {
    final reason = await askForText(
      context,
      title: context.tr('offer.rejectTitle'),
      hint: context.tr('offer.rejectHint'),
      confirmLabel: context.tr('offer.rejectConfirm'),
      required: false,
    );
    if (reason == null || !mounted) return;
    final done = await _run(
      () => context.read<Repository>().advanceOrder(o.id, OrderStatus.cancelled, note: reason),
    );
    if (done && mounted) showSnack(context, context.tr('offer.rejected'));
  }

  /// Runs a server call with the buttons locked; true when it went through.
  Future<bool> _run(Future<void> Function() action) async {
    Haptics.tap();
    setState(() => _busy = true);
    try {
      if (!await requireOnline(context) || !mounted) return false;
      await action();
      await widget.refresh();
      return true;
    } catch (e) {
      if (mounted) showError(context, e, onRetry: () => _run(action));
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(Order o) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => OrderComposerScreen(editing: o)),
    );
    await widget.refresh();
  }

  void _reorder(Order o) {
    Haptics.tap();
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => OrderComposerScreen(reorderFrom: o)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.bundle.order;
    final unit = context.watch<Session>().unit;
    final shop = o.shop;
    final editable = customerCanEdit(o.status);

    // the page's sections, in order; each fades in a beat after the last
    final sections = <Widget>[
      if (widget.justSent && o.status == OrderStatus.submitted) _SentCard(shopName: shop?.shopName ?? ''),
      _ProgressCard(order: o),
      if (o.status == OrderStatus.changesRequested)
        NoticeBanner(
          tone: BannerTone.warn,
          title: context.tr('order.changesTitle'),
          text: o.tailorNote ?? '',
          action: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Palette.henna, minimumSize: const Size(64, 44)),
            onPressed: () => _edit(o),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: Text(context.tr('order.fix')),
          ),
        ),
      if (o.status == OrderStatus.priceOffered) _OfferCard(order: o) else if (o.price != null) _PriceCard(order: o),
      ClipRRect(
        borderRadius: BorderRadius.circular(Panel.radius),
        child: SizedBox(height: 320, child: FittingRoomView(controller: _room)),
      ),
      if (shop != null)
        _Section(
          title: context.tr('order.yourTailor'),
          child: Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(color: Palette.goldSoft, shape: BoxShape.circle),
                      child: Text(
                        shop.shopName.trim().isEmpty ? '?' : shop.shopName.trim().characters.first,
                        style: displayStyle(18, color: Palette.goldInk),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(shop.shopName, style: displayStyle(17)),
                          Text(placeLine(context, shop.city, shop.neighbourhood),
                              style: const TextStyle(color: Palette.muted, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
                if (shop.addressDetails.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(shop.addressDetails, style: const TextStyle(height: 1.5)),
                ],
                if ((shop.ownerPhone ?? '').isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ContactButtons(
                    phone: shop.ownerPhone!,
                    whatsapp: shop.ownerWhatsapp,
                    message: context.tr('order.waToTailor', {'id': o.shortId}),
                  ),
                ],
              ],
            ),
          ),
        ),
      _Section(
        title: context.tr('order.design'),
        child: DesignPanel(design: o.design, unit: unit, currency: o.currency),
      ),
      _Section(
        title: context.tr('order.cutting'),
        subtitle: context.tr('order.cuttingHint'),
        collapsible: true,
        child: CuttingListPanel(measurements: o.measurements, design: o.design, unit: unit),
      ),
      _Section(
        title: context.tr('order.body'),
        collapsible: true,
        child: BodySizesPanel(measurements: o.measurements, unit: unit),
      ),
      _Section(title: context.tr('order.delivery'), child: DeliveryPanel(delivery: o.delivery)),
      if ((o.customerNotes ?? '').isNotEmpty)
        _Section(
          title: context.tr('order.notes'),
          child: Panel(child: Text(o.customerNotes!, style: const TextStyle(height: 1.5))),
        ),
      _Section(
        title: context.tr('order.history'),
        child: OrderTimeline(events: widget.bundle.events, customerId: o.customerId),
      ),
    ];

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            color: Palette.nile,
            onRefresh: widget.refresh,
            edgeOffset: 120,
            child: CustomScrollView(
              // keep the 3D stage mounted while scrolling, so the page never reloads
              cacheExtent: 4000,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                _OrderHeader(order: o),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  sliver: SliverList.list(
                    children: [
                      for (var i = 0; i < sections.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: EntranceFade(index: i, child: sections[i]),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        BottomActions(
          children: o.status == OrderStatus.priceOffered
              ? [
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: Palette.henna),
                    onPressed: _busy ? null : () => _reject(o),
                    child: Text(context.tr('offer.reject')),
                  ),
                  BusyButton(
                    label: context.tr('offer.accept'),
                    icon: Icons.check_rounded,
                    busy: _busy,
                    onPressed: () => _accept(o),
                  ),
                ]
              : editable
                  ? [
                      OutlinedButton(
                        onPressed: _busy ? null : () => _cancel(o),
                        child: Text(context.tr('order.cancel')),
                      ),
                      FilledButton(
                        onPressed: _busy ? null : () => _edit(o),
                        child: Text(context.tr('order.edit')),
                      ),
                    ]
                  : [
                      FilledButton.icon(
                        onPressed: () => _reorder(o),
                        icon: const Icon(Icons.replay_rounded),
                        label: Text(context.tr('order.again')),
                      ),
                    ],
        ),
      ],
    );
  }
}

/// Navy header that shrinks to a bar as the page scrolls. The cloth tile is
/// the same one tapped in the list, so it flies here.
class _OrderHeader extends StatelessWidget {
  const _OrderHeader({required this.order});

  final Order order;

  static const _expanded = 200.0;

  @override
  Widget build(BuildContext context) {
    final o = order;
    final title = context.tr('orders.for', {'name': o.wearerLabel});
    return SliverAppBar(
      pinned: true,
      stretch: true,
      expandedHeight: _expanded,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: Palette.damur,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      flexibleSpace: LayoutBuilder(
        builder: (context, box) {
          final top = MediaQuery.paddingOf(context).top;
          final min = top + kToolbarHeight;
          final t = ((box.maxHeight - min) / (_expanded + top - min)).clamp(0.0, 1.0);
          return InkHeader(
            radius: 24,
            padding: EdgeInsets.zero,
            child: SizedBox.expand(
              child: Stack(
                children: [
                  // collapsed: just the title next to the back button
                  PositionedDirectional(
                    top: top,
                    start: 56,
                    end: 16,
                    height: kToolbarHeight,
                    child: Opacity(
                      opacity: (1 - t * 2).clamp(0.0, 1.0),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: displayStyle(18, color: Palette.damur)),
                      ),
                    ),
                  ),
                  // expanded: the cloth, the title, and where it stands
                  PositionedDirectional(
                    start: 20,
                    end: 20,
                    bottom: 22,
                    child: Opacity(
                      opacity: ((t - 0.35) / 0.65).clamp(0.0, 1.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          ClothTile(order: o, width: 64, height: 80, heroTag: 'cloth-${o.id}'),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: displayStyle(22, color: Palette.damur)),
                                const SizedBox(height: 4),
                                Text(
                                  '#${o.shortId} · ${formatDate(context, o.createdAt)}',
                                  style: monoStyle(12, color: Palette.onInkMuted),
                                ),
                                const SizedBox(height: 10),
                                AnimatedSwitcher(
                                  duration: Motion.quick,
                                  child: StatusChip(o.status, key: ValueKey(o.status)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The header shape for the error view, with a way back.
class _PlainHeader extends StatelessWidget {
  const _PlainHeader();

  @override
  Widget build(BuildContext context) {
    return InkHeader(
      radius: 24,
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: SafeArea(
        bottom: false,
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: BackButton(color: Palette.damur),
        ),
      ),
    );
  }
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkHeader(
          radius: 24,
          padding: const EdgeInsets.fromLTRB(4, 0, 20, 22),
          child: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BackButton(color: Palette.damur),
                const SizedBox(height: 40),
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 16),
                  child: Shimmer(
                    child: Row(
                      children: const [
                        SkeletonBox(width: 64, height: 80, radius: 15),
                        SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              FractionallySizedBox(widthFactor: 0.7, child: SkeletonBox(height: 20)),
                              SizedBox(height: 10),
                              FractionallySizedBox(widthFactor: 0.45, child: SkeletonBox(height: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const Expanded(child: SkeletonList(count: 3)),
      ],
    );
  }
}

/// A titled block; [collapsible] ones fold away to keep the page short.
class _Section extends StatefulWidget {
  const _Section({required this.title, required this.child, this.subtitle, this.collapsible = false});

  final String title;
  final String? subtitle;
  final Widget child;
  final bool collapsible;

  @override
  State<_Section> createState() => _SectionState();
}

class _SectionState extends State<_Section> {
  late bool _open = !widget.collapsible;

  @override
  Widget build(BuildContext context) {
    final head = Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.title, style: displayStyle(17)),
                if (widget.subtitle != null)
                  Text(widget.subtitle!, style: const TextStyle(color: Palette.muted, fontSize: 12.5)),
              ],
            ),
          ),
          if (widget.collapsible)
            AnimatedRotation(
              turns: _open ? 0.5 : 0,
              duration: Motion.quick,
              child: const Icon(Icons.expand_more_rounded, color: Palette.muted),
            ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.collapsible)
          Semantics(
            button: true,
            expanded: _open,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                Haptics.select();
                setState(() => _open = !_open);
              },
              child: head,
            ),
          )
        else
          head,
        AnimatedSize(
          duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 240),
          curve: Motion.curve,
          alignment: Alignment.topCenter,
          child: _open ? widget.child : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// Shown once, right after sending: a check that draws itself.
class _SentCard extends StatelessWidget {
  const _SentCard({required this.shopName});

  final String shopName;

  @override
  Widget build(BuildContext context) {
    return Panel(
      color: Palette.nileSoft,
      borderColor: Palette.nileSoft,
      child: Row(
        children: [
          const SuccessCheck(size: 48),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr('order.sentTitle'), style: displayStyle(17)),
                const SizedBox(height: 2),
                Text(context.tr('order.sentBody', {'shop': shopName}), style: const TextStyle(height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The six steps, with a sentence on what is happening now.
class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final s = order.status;
    final ended = s == OrderStatus.declined || s == OrderStatus.cancelled;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!ended) ...[
            OrderProgress(status: s),
            const SizedBox(height: 14),
            const Divider(),
            const SizedBox(height: 12),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_icon(s), color: statusColor(s), size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: AnimatedSwitcher(
                  duration: Motion.quick,
                  child: Text(
                    context.tr('detail.now.${statusToDb(s)}'),
                    key: ValueKey(s),
                    style: const TextStyle(height: 1.5),
                  ),
                ),
              ),
            ],
          ),
          if (ended && order.tailorNote != null && order.tailorNote!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('“${order.tailorNote}”', style: const TextStyle(color: Palette.muted, height: 1.45)),
          ],
        ],
      ),
    );
  }

  static IconData _icon(OrderStatus s) => switch (s) {
        OrderStatus.submitted => Icons.hourglass_top_rounded,
        OrderStatus.changesRequested => Icons.edit_note_rounded,
        OrderStatus.priceOffered => Icons.price_change_outlined,
        OrderStatus.confirmed => Icons.verified_outlined,
        OrderStatus.cutting => Icons.content_cut_rounded,
        OrderStatus.sewing => Icons.design_services_outlined,
        OrderStatus.ready => Icons.inventory_2_outlined,
        OrderStatus.delivered => Icons.home_rounded,
        OrderStatus.declined || OrderStatus.cancelled => Icons.block_rounded,
      };
}

class _PriceCard extends StatelessWidget {
  const _PriceCard({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final o = order;
    return Panel(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                  child: _Figure(label: context.tr('order.price'), value: formatMoney(context, o.price!, o.currency))),
              if (o.dueDate != null)
                Expanded(child: _Figure(label: context.tr('order.due'), value: formatDate(context, o.dueDate!))),
            ],
          ),
          if ((o.tailorNote ?? '').isNotEmpty && o.status != OrderStatus.changesRequested) ...[
            const SizedBox(height: 12),
            const Divider(),
            InfoRow(context.tr('order.tailorNote'), o.tailorNote!),
          ],
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Palette.muted, fontSize: 12.5)),
        const SizedBox(height: 2),
        Text(value, style: displayStyle(19, color: color ?? Palette.ink)),
      ],
    );
  }
}

/// The tailor's offer against what the customer was quoted, so the
/// difference is plain before they accept or reject.
class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final o = order;
    final estimate = o.estimate;
    final price = o.price ?? 0;
    final changed = estimate != null && (price * 100).round() != (estimate * 100).round();
    final diff = estimate == null ? 0.0 : price - estimate;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Panel.radius),
        border: Border.all(color: Palette.henna.withValues(alpha: 0.35)),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Palette.hennaSoft, Palette.card],
        ),
        boxShadow: Panel.shadow,
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(color: Palette.henna, shape: BoxShape.circle),
                child: const Icon(Icons.price_change_outlined, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(context.tr('offer.title'), style: displayStyle(17))),
            ],
          ),
          const SizedBox(height: 8),
          Text(context.tr('offer.body'), style: const TextStyle(height: 1.5, fontSize: 13.5)),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (estimate != null && changed) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr('offer.estimate'), style: const TextStyle(color: Palette.muted, fontSize: 12)),
                    Text(
                      formatMoney(context, estimate, o.currency),
                      style: monoStyle(14, color: Palette.muted).copyWith(decoration: TextDecoration.lineThrough),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  child: Icon(Icons.arrow_forward_rounded, size: 18, color: Palette.muted),
                ),
              ],
              Expanded(
                child: _Figure(
                  label: context.tr('offer.price'),
                  value: formatMoney(context, price, o.currency),
                  color: Palette.henna,
                ),
              ),
            ],
          ),
          if (changed) ...[
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: diff > 0 ? Palette.hennaSoft : Palette.nileSoft,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${context.tr(diff > 0 ? 'offer.more' : 'offer.less')} ${formatMoney(context, diff.abs(), o.currency)}',
                  style: TextStyle(
                    color: diff > 0 ? Palette.henna : Palette.nile,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Divider(),
          if (o.dueDate != null) InfoRow(context.tr('order.due'), formatDate(context, o.dueDate!), strong: true),
          if ((o.tailorNote ?? '').isNotEmpty) InfoRow(context.tr('order.tailorNote'), o.tailorNote!),
        ],
      ),
    );
  }
}
