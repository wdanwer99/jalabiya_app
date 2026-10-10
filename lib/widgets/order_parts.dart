import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/design.dart';
import '../models/garment_spec.dart';
import '../models/measurements.dart';
import '../models/order.dart';
import '../theme/theme.dart';
import '../util/contact.dart';
import '../util/format.dart';
import 'common.dart';

/// The customer's body, as measured.
class BodySizesPanel extends StatelessWidget {
  const BodySizesPanel({super.key, required this.measurements, required this.unit});

  final Measurements measurements;
  final LengthUnit unit;

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          for (final s in Measurements.specs)
            InfoRow(context.tr('m.${s.key}'), formatLength(measurements.valueOf(s.key), unit), mono: true),
        ],
      ),
    );
  }
}

/// The finished garment with ease: what the tailor actually cuts.
class CuttingListPanel extends StatelessWidget {
  const CuttingListPanel({super.key, required this.measurements, required this.design, required this.unit});

  final Measurements measurements;
  final JalabiyaDesign design;
  final LengthUnit unit;

  @override
  Widget build(BuildContext context) {
    final g = GarmentSpec.compute(measurements, design);
    final fabric = unit == LengthUnit.cm
        ? '${trimNumber(g.fabricMetres)} ${context.tr('unit.m')}'
        : '${trimNumber(g.fabricYards)} ${context.tr('unit.yd')}';
    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(child: Text(context.tr('cut.size'), style: const TextStyle(color: Palette.muted))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: Palette.gold),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(g.sizeLabel, style: displayStyle(17, color: Palette.goldInk)),
                ),
              ],
            ),
          ),
          const Divider(),
          InfoRow(context.tr('cut.length'), formatLength(g.length, unit), mono: true, strong: true),
          InfoRow(context.tr('cut.chest'), formatLength(g.chest, unit), mono: true, strong: true),
          InfoRow(context.tr('cut.hem'), formatLength(g.hem, unit), mono: true),
          InfoRow(context.tr('cut.shoulder'), formatLength(g.shoulderSeam, unit), mono: true),
          InfoRow(context.tr('cut.sleeve'), formatLength(g.sleeve, unit), mono: true),
          InfoRow(context.tr('cut.cuff'), formatLength(g.cuff, unit), mono: true),
          InfoRow(context.tr('cut.neck'), formatLength(g.neckOpening, unit), mono: true),
          InfoRow(context.tr('cut.hemFloor'), formatLength(design.hem, unit), mono: true),
          InfoRow(context.tr('cut.fabric'), '≈ $fabric', mono: true),
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 6),
            child: Text(
              context.tr('cut.easeNote', {
                'chest': trimNumber(GarmentSpec.chestEase),
                'neck': trimNumber(GarmentSpec.neckEase),
              }),
              style: const TextStyle(color: Palette.chalk, fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class DesignPanel extends StatelessWidget {
  const DesignPanel({super.key, required this.design, required this.unit, this.currency = 'SDG'});

  final JalabiyaDesign design;
  final LengthUnit unit;

  /// For the extra a chosen cloth or thread adds to the price.
  final String currency;

  @override
  Widget build(BuildContext context) {
    String named(String kind, Swatch s) {
      final name = swatchName(context, kind, s);
      return s.price > 0 ? '$name · +${formatMoney(context, s.price, currency)}' : name;
    }

    Widget dot(int color) => Container(
          width: 16,
          height: 16,
          margin: const EdgeInsetsDirectional.only(end: 8),
          decoration: BoxDecoration(
            color: Color(0xFF000000 | color),
            shape: BoxShape.circle,
            border: Border.all(color: Palette.line),
          ),
        );
    Widget swatchRow(String label, int color, String name) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              Expanded(flex: 5, child: Text(label, style: const TextStyle(color: Palette.muted, fontSize: 14))),
              Expanded(
                flex: 6,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    dot(color),
                    Flexible(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w500)))
                  ],
                ),
              ),
            ],
          ),
        );
    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          swatchRow(context.tr('d.cloth'), design.cloth.color, named('cloth', design.cloth)),
          InfoRow(context.tr('d.cut'), context.tr('cut.${design.cut}')),
          InfoRow(context.tr('d.collar'), context.tr('collar.${design.collar}')),
          InfoRow(context.tr('d.emb'), context.tr('emb.${design.emb}')),
          if (design.emb != 'none')
            swatchRow(context.tr('d.thread'), design.thread.color, named('thread', design.thread)),
          InfoRow(context.tr('d.cuff'), formatLength(design.cuff, unit), mono: true),
        ],
      ),
    );
  }
}

class DeliveryPanel extends StatelessWidget {
  const DeliveryPanel({super.key, required this.delivery, this.showContact = false});

  final Delivery delivery;
  final bool showContact;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(delivery.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5)),
          const SizedBox(height: 4),
          Text(placeLine(context, delivery.city, delivery.neighbourhood), style: const TextStyle(color: Palette.muted)),
          if ((delivery.addressDetails ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(delivery.addressDetails!, style: const TextStyle(height: 1.5)),
          ],
          const SizedBox(height: 6),
          Text(delivery.phone, style: monoStyle(14), textDirection: TextDirection.ltr),
          if (showContact) ...[
            const SizedBox(height: 12),
            ContactButtons(phone: delivery.phone, whatsapp: delivery.whatsapp),
          ],
        ],
      ),
    );
  }
}

class ContactButtons extends StatelessWidget {
  const ContactButtons({super.key, required this.phone, this.whatsapp, this.message});

  final String phone;
  final String? whatsapp;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final wa = (whatsapp ?? '').trim().isEmpty ? phone : whatsapp!;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(64, 44)),
            onPressed: () async {
              final ok = await callNumber(phone);
              if (!ok && context.mounted) showSnack(context, context.tr('err.cannotOpen'), error: true);
            },
            icon: const Icon(Icons.call_outlined, size: 18),
            label: Text(context.tr('action.call')),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(64, 44)),
            onPressed: () async {
              final ok = await openWhatsApp(wa, text: message);
              if (!ok && context.mounted) showSnack(context, context.tr('err.cannotOpen'), error: true);
            },
            icon: const Icon(Icons.chat_outlined, size: 18),
            label: Text(context.tr('action.whatsapp')),
          ),
        ),
      ],
    );
  }
}

/// Six stops from submitted to delivered, or a single banner if the order
/// ended early.
class OrderProgress extends StatelessWidget {
  const OrderProgress({super.key, required this.status});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    if (status == OrderStatus.declined || status == OrderStatus.cancelled) {
      return NoticeBanner(
        tone: BannerTone.warn,
        text: context.tr('progress.${statusToDb(status)}'),
      );
    }
    final current = progressStep(status);
    final waitingOnCustomer = needsCustomer(status);
    const d = Duration(milliseconds: 320);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < statusPath.length; i++)
          Expanded(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: AnimatedContainer(
                        duration: d,
                        height: 2,
                        color: i == 0 ? Colors.transparent : (i <= current ? Palette.nile : Palette.line),
                      ),
                    ),
                    AnimatedContainer(
                      duration: d,
                      curve: Curves.easeOutCubic,
                      width: i == current ? 26 : 22,
                      height: i == current ? 26 : 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < current
                            ? Palette.nile
                            : i == current
                                ? (waitingOnCustomer ? Palette.henna : Palette.gold)
                                : Palette.card,
                        border: Border.all(color: i <= current ? Colors.transparent : Palette.line, width: 1.5),
                      ),
                      child: i < current ? const Icon(Icons.check_rounded, size: 14, color: Colors.white) : null,
                    ),
                    Expanded(
                      child: AnimatedContainer(
                        duration: d,
                        height: 2,
                        color: i == statusPath.length - 1
                            ? Colors.transparent
                            : (i < current ? Palette.nile : Palette.line),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  context.tr('step.${statusToDb(statusPath[i])}'),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.2,
                    color: i == current ? Palette.ink : Palette.muted,
                    fontWeight: i == current ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Where [s] sits on [statusPath]: an offer waits on the confirmation step,
/// a change request on the first. -1 for an order that ended early.
int progressStep(OrderStatus s) {
  if (s == OrderStatus.declined || s == OrderStatus.cancelled) return -1;
  if (s == OrderStatus.changesRequested) return 0;
  if (s == OrderStatus.priceOffered) return statusPath.indexOf(OrderStatus.confirmed);
  return statusPath.indexOf(s);
}

/// The order's cloth colour with its ready-made size, the picture of an
/// order. [heroTag] lets it fly from the list into the order's page.
class ClothTile extends StatelessWidget {
  const ClothTile({super.key, required this.order, this.width = 50, this.height = 62, this.heroTag});

  final Order order;
  final double width;
  final double height;
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final cloth = order.design.cloth;
    final size = GarmentSpec.sizeFor(order.measurements.chest);
    final dark = isDarkColor(cloth.color);
    final tile = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Color(0xFF000000 | cloth.color),
        borderRadius: BorderRadius.circular(width * 0.24),
        border: Border.all(color: const Color(0x1F101A2B)),
        boxShadow: const [BoxShadow(color: Color(0x14101A2B), blurRadius: 8, offset: Offset(0, 3))],
      ),
      alignment: Alignment.bottomCenter,
      padding: EdgeInsets.only(bottom: height * 0.08),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.checkroom_rounded,
              size: width * 0.42, color: dark ? Palette.damur : Palette.ink.withValues(alpha: 0.55)),
          Text(size, style: monoStyle(width * 0.22, color: dark ? Palette.damur : Palette.ink)),
        ],
      ),
    );
    if (heroTag == null) return tile;
    return Hero(tag: heroTag!, child: Material(type: MaterialType.transparency, child: tile));
  }
}

/// The six steps as a thin segmented bar, for order cards.
class MiniProgress extends StatelessWidget {
  const MiniProgress({super.key, required this.status});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final current = progressStep(status);
    final waiting = needsCustomer(status);
    return Row(
      children: [
        for (var i = 0; i < statusPath.length; i++) ...[
          if (i > 0) const SizedBox(width: 3),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 320),
              height: 4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: current < 0
                    ? Palette.line
                    : i < current
                        ? Palette.nile
                        : i == current
                            ? (waiting ? Palette.henna : Palette.gold)
                            : Palette.line,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class OrderTimeline extends StatelessWidget {
  const OrderTimeline({super.key, required this.events, required this.customerId});

  final List<OrderEvent> events;
  final String customerId;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = events.length - 1; i >= 0; i--)
            _TimelineEntry(
              event: events[i],
              byCustomer: events[i].actorId == customerId,
              last: i == 0,
            ),
        ],
      ),
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry({required this.event, required this.byCustomer, required this.last});

  final OrderEvent event;
  final bool byCustomer;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final title = switch (event.kind) {
      'edited' || 'accepted' || 'rejected' || 'admin' => context.tr('event.${event.kind}'),
      _ => context.tr('event.${statusToDb(event.toStatus)}'),
    };
    final by = event.kind == 'admin' ? 'event.bySupport' : (byCustomer ? 'event.byCustomer' : 'event.byTailor');
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 5),
                decoration: BoxDecoration(color: statusColor(event.toStatus), shape: BoxShape.circle),
              ),
              if (!last) Expanded(child: Container(width: 1.5, color: Palette.line)),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    '${formatDateTime(context, event.createdAt)} · ${context.tr(by)}',
                    style: const TextStyle(color: Palette.muted, fontSize: 12),
                  ),
                  if ((event.note ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('“${event.note}”', style: const TextStyle(height: 1.45)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A row in either side's order list.
class OrderCard extends StatelessWidget {
  const OrderCard({super.key, required this.order, required this.forTailor, required this.onTap});

  final Order order;
  final bool forTailor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cloth = order.design.cloth;
    final who = forTailor ? '${order.delivery.name} · ${order.wearerLabel}' : (order.shop?.shopName ?? '');
    final size = GarmentSpec.sizeFor(order.measurements.chest);
    return Panel(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 58,
            decoration: BoxDecoration(
              color: Color(0xFF000000 | cloth.color),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Palette.line),
            ),
            alignment: Alignment.bottomCenter,
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(size, style: monoStyle(11, color: isDarkColor(cloth.color) ? Palette.damur : Palette.ink)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  forTailor ? order.wearerLabel : context.tr('orders.for', {'name': order.wearerLabel}),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(who, style: const TextStyle(color: Palette.muted, fontSize: 13), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Row(
                  children: [
                    StatusChip(order.status),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        order.dueDate != null && !isClosed(order.status)
                            ? context.tr('orders.due', {'date': formatDate(context, order.dueDate!)})
                            : formatDate(context, order.createdAt),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Palette.muted, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (order.quantity > 1)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 8),
              child: Text('×${order.quantity}', style: monoStyle(14, color: Palette.goldInk)),
            ),
          const Icon(Icons.chevron_right_rounded, color: Palette.chalk),
        ],
      ),
    );
  }
}
