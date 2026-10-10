import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repository.dart';
import '../../l10n/strings.dart';
import '../../models/order.dart';
import '../../models/profile.dart';
import '../../state/session.dart';
import '../../theme/theme.dart';
import '../../util/format.dart';
import '../../widgets/common.dart';
import '../../widgets/fitting_room.dart';
import '../../widgets/live.dart';
import '../../widgets/order_parts.dart';

/// Everything a tailor needs to accept and sew one order: who the customer
/// is and how to reach them, the figure in 3D, and the cutting list.
class TailorOrderScreen extends StatelessWidget {
  const TailorOrderScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<Repository>();
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('order.title'))),
      body: LiveData<OrderBundle>(
        load: () => repo.fetchOrder(orderId),
        changes: () => repo.orderChanges(column: 'id', value: orderId),
        builder: (context, bundle, refresh) => _TailorOrderBody(bundle: bundle, refresh: refresh),
      ),
    );
  }
}

class _TailorOrderBody extends StatefulWidget {
  const _TailorOrderBody({required this.bundle, required this.refresh});

  final OrderBundle bundle;
  final Future<void> Function() refresh;

  @override
  State<_TailorOrderBody> createState() => _TailorOrderBodyState();
}

class _TailorOrderBodyState extends State<_TailorOrderBody> {
  final _room = FittingRoomController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _room.setUnit(context.read<Session>().unit);
    _room.show(widget.bundle.order.measurements, widget.bundle.order.design);
  }

  @override
  void didUpdateWidget(_TailorOrderBody old) {
    super.didUpdateWidget(old);
    _room.show(widget.bundle.order.measurements, widget.bundle.order.design);
  }

  @override
  void dispose() {
    _room.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, String doneKey) async {
    setState(() => _busy = true);
    try {
      if (!await requireOnline(context) || !mounted) return;
      await action();
      await widget.refresh();
      if (mounted) showSnack(context, context.tr(doneKey));
    } catch (e) {
      if (mounted) showError(context, e, onRetry: () => _run(action, doneKey));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm(Order o) async {
    final shop = context.read<Session>().shop;
    final result = await showModalBottomSheet<_ConfirmResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Palette.paper,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ConfirmSheet(
        // the estimate the customer saw; older orders fall back to today's prices
        suggestedPrice: o.estimate ?? ((shop?.basePrice ?? 0) + o.design.extrasPrice) * o.quantity,
        estimate: o.estimate,
        leadDays: shop?.leadTimeDays ?? 7,
        suggestedDue: DateTime.now().add(Duration(days: shop?.leadTimeDays ?? 7)),
        currency: shop?.currency ?? 'SDG',
      ),
    );
    if (result == null || !mounted) return;
    final offer = offerNeedsApproval(
      estimate: o.estimate,
      price: result.price,
      due: result.due,
      leadDays: shop?.leadTimeDays ?? 7,
    );
    final repo = context.read<Repository>();
    await _run(
      () => repo.advanceOrder(o.id, OrderStatus.confirmed,
          price: result.price, dueDate: result.due, note: result.note),
      offer ? 'tailor.offered' : 'tailor.confirmed',
    );
  }

  Future<void> _askChanges(Order o) async {
    final note = await askForText(
      context,
      title: context.tr('tailor.askTitle'),
      hint: context.tr('tailor.askHint'),
      confirmLabel: context.tr('tailor.askSend'),
    );
    if (note == null || !mounted) return;
    final repo = context.read<Repository>();
    await _run(() => repo.advanceOrder(o.id, OrderStatus.changesRequested, note: note), 'tailor.asked');
  }

  Future<void> _decline(Order o) async {
    final note = await askForText(
      context,
      title: context.tr('tailor.declineTitle'),
      hint: context.tr('tailor.declineHint'),
      confirmLabel: context.tr('tailor.decline'),
    );
    if (note == null || !mounted) return;
    final repo = context.read<Repository>();
    await _run(() => repo.advanceOrder(o.id, OrderStatus.declined, note: note), 'tailor.declined');
  }

  Future<void> _advance(Order o, OrderStatus next) async {
    final repo = context.read<Repository>();
    await _run(() => repo.advanceOrder(o.id, next), 'tailor.moved');
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.bundle.order;
    final events = widget.bundle.events;
    final unit = context.watch<Session>().unit;
    final customer = o.customer;
    final lastEdited = events.isNotEmpty && events.last.kind == 'edited';
    final next = nextTailorStep(o.status);

    final List<Widget> actions;
    if (o.status == OrderStatus.submitted) {
      actions = [
        OutlinedButton(onPressed: _busy ? null : () => _askChanges(o), child: Text(context.tr('tailor.ask'))),
        BusyButton(label: context.tr('tailor.confirm'), busy: _busy, onPressed: () => _confirm(o)),
      ];
    } else if (next != null) {
      actions = [
        BusyButton(
          label: context.tr('tailor.next.${statusToDb(next)}'),
          icon: Icons.arrow_forward_rounded,
          busy: _busy,
          onPressed: () => _advance(o, next),
        ),
      ];
    } else {
      actions = const [];
    }

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: widget.refresh,
            child: ListView(
              cacheExtent: 4000,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                Row(
                  children: [
                    Expanded(child: Text(o.wearerLabel, style: displayStyle(22))),
                    StatusChip(o.status),
                  ],
                ),
                const SizedBox(height: 4),
                Text('#${o.shortId} · ${context.tr('tailor.received', {'date': formatDateTime(context, o.createdAt)})}',
                    style: monoStyle(12.5, color: Palette.muted)),
                if (o.quantity > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: NoticeBanner(tone: BannerTone.gold, text: context.tr('tailor.quantity', {'n': '${o.quantity}'})),
                  ),
                if (o.status == OrderStatus.submitted && lastEdited)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: NoticeBanner(tone: BannerTone.info, text: context.tr('tailor.edited')),
                  ),
                if (o.status == OrderStatus.priceOffered)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: NoticeBanner(
                      tone: BannerTone.gold,
                      title: context.tr('tailor.offerWaiting'),
                      text: context.tr('tailor.offerWaitingBody'),
                    ),
                  ),
                if (o.status == OrderStatus.changesRequested)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: NoticeBanner(
                      tone: BannerTone.warn,
                      title: context.tr('tailor.waiting'),
                      text: o.tailorNote ?? '',
                    ),
                  ),
                const SizedBox(height: 16),
                OrderProgress(status: o.status),
                if (o.price != null) ...[
                  const SizedBox(height: 16),
                  Panel(
                    color: Palette.nileSoft,
                    borderColor: Palette.nileSoft,
                    child: Column(
                      children: [
                        if (o.status == OrderStatus.priceOffered && o.estimate != null)
                          InfoRow(context.tr('offer.estimate'), formatMoney(context, o.estimate!, o.currency)),
                        InfoRow(
                          context.tr(o.status == OrderStatus.priceOffered ? 'offer.yourPrice' : 'order.price'),
                          formatMoney(context, o.price!, o.currency),
                          strong: true,
                        ),
                        if (o.dueDate != null)
                          InfoRow(context.tr('order.due'), formatDate(context, o.dueDate!), strong: true),
                      ],
                    ),
                  ),
                ],
                SectionTitle(context.tr('tailor.customer')),
                _CustomerCard(order: o, customer: customer),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(height: 360, child: FittingRoomView(controller: _room)),
                ),
                SectionTitle(context.tr('order.cutting'), subtitle: context.tr('order.cuttingHint')),
                CuttingListPanel(measurements: o.measurements, design: o.design, unit: unit),
                SectionTitle(context.tr('order.body')),
                BodySizesPanel(measurements: o.measurements, unit: unit),
                SectionTitle(context.tr('order.design')),
                DesignPanel(design: o.design, unit: unit, currency: o.currency),
                if ((o.customerNotes ?? '').isNotEmpty) ...[
                  SectionTitle(context.tr('order.customerNotes')),
                  Panel(child: Text(o.customerNotes!, style: const TextStyle(height: 1.5))),
                ],
                SectionTitle(context.tr('order.history')),
                OrderTimeline(events: events, customerId: o.customerId),
                if (needsTailor(o.status)) ...[
                  const SizedBox(height: 20),
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: Palette.henna),
                    onPressed: _busy ? null : () => _decline(o),
                    icon: const Icon(Icons.block_rounded, size: 18),
                    label: Text(context.tr('tailor.decline')),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (actions.isNotEmpty) BottomActions(children: actions),
      ],
    );
  }
}

/// The customer's full profile as the tailor sees it. The live profile is
/// used when available; the address frozen on the order is what to deliver to.
class _CustomerCard extends StatelessWidget {
  const _CustomerCard({required this.order, required this.customer});

  final Order order;
  final Profile? customer;

  @override
  Widget build(BuildContext context) {
    final d = order.delivery;
    final name = customer?.fullName ?? d.name;
    final phone = customer?.phone ?? d.phone;
    final whatsapp = customer?.whatsapp ?? d.whatsapp;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: Palette.goldSoft,
                child: Text(
                  name.trim().isEmpty ? '?' : name.trim().characters.first,
                  style: displayStyle(18, color: Palette.goldInk),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    if (customer?.createdAt != null)
                      Text(
                        context.tr('tailor.memberSince', {'date': formatDate(context, customer!.createdAt!)}),
                        style: const TextStyle(color: Palette.muted, fontSize: 12.5),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(),
          InfoRow(context.tr('profile.phone'), phone, mono: true),
          if ((whatsapp ?? '').isNotEmpty) InfoRow(context.tr('profile.whatsapp'), whatsapp!, mono: true),
          InfoRow(context.tr('tailor.deliverTo'), placeLine(context, d.city, d.neighbourhood)),
          if ((d.addressDetails ?? '').isNotEmpty) InfoRow(context.tr('profile.addressDetails'), d.addressDetails!),
          InfoRow(context.tr('tailor.wearer'), order.wearerLabel),
          const SizedBox(height: 10),
          ContactButtons(
            phone: phone,
            whatsapp: whatsapp,
            message: context.tr('tailor.waToCustomer', {'name': name, 'id': order.shortId}),
          ),
        ],
      ),
    );
  }
}

class _ConfirmResult {
  const _ConfirmResult(this.price, this.due, this.note);

  final double price;
  final DateTime due;
  final String? note;
}

class _ConfirmSheet extends StatefulWidget {
  const _ConfirmSheet({
    required this.suggestedPrice,
    required this.estimate,
    required this.leadDays,
    required this.suggestedDue,
    required this.currency,
  });

  final double suggestedPrice;
  /// What the customer was quoted; null on orders from before quotes were kept.
  final double? estimate;
  final int leadDays;
  final DateTime suggestedDue;
  final String currency;

  @override
  State<_ConfirmSheet> createState() => _ConfirmSheetState();
}

class _ConfirmSheetState extends State<_ConfirmSheet> {
  late final TextEditingController _price;
  final _note = TextEditingController();
  late DateTime _due;
  String? _error;

  @override
  void initState() {
    super.initState();
    _price = TextEditingController(
      text: widget.suggestedPrice > 0 ? trimNumber(widget.suggestedPrice, decimals: 0) : '',
    );
    _due = widget.suggestedDue;
    _price.addListener(() => setState(() {}));
  }

  /// Whether this price and date go to the customer as an offer first.
  bool get _isOffer {
    final price = parseLooseNumber(_price.text);
    if (price == null || price <= 0) return false;
    return offerNeedsApproval(
      estimate: widget.estimate,
      price: price,
      due: _due,
      leadDays: widget.leadDays,
    );
  }

  @override
  void dispose() {
    _price.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _due,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _due = picked);
  }

  void _submit() {
    final price = parseLooseNumber(_price.text);
    if (price == null || price <= 0) {
      setState(() => _error = context.tr('form.price'));
      return;
    }
    final note = _note.text.trim();
    Navigator.of(context).pop(_ConfirmResult(price, _due, note.isEmpty ? null : note));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.tr('tailor.confirmTitle'), style: displayStyle(20)),
          const SizedBox(height: 4),
          Text(context.tr('tailor.confirmBody'), style: const TextStyle(color: Palette.muted)),
          const SizedBox(height: 18),
          TextField(
            controller: _price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: monoStyle(18),
            decoration: field(
              labelText: context.tr('order.price'),
              suffixText: context.tr('money.sdg'),
              errorText: _error,
            ),
          ),
          const SizedBox(height: 14),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _pickDate,
            child: InputDecorator(
              decoration: field(
                labelText: context.tr('order.due'),
                suffixIcon: const Icon(Icons.event_outlined),
              ),
              child: Text(formatDate(context, _due)),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _note,
            minLines: 1,
            maxLines: 3,
            decoration: field(labelText: context.tr('tailor.noteOptional')),
          ),
          if (_isOffer) ...[
            const SizedBox(height: 14),
            NoticeBanner(
              tone: BannerTone.gold,
              text: context.tr('tailor.offerHint', {
                'price': widget.estimate == null ? '—' : formatMoney(context, widget.estimate!, widget.currency),
                'days': '${widget.leadDays}',
              }),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _submit,
            child: Text(context.tr(_isOffer ? 'tailor.sendOffer' : 'tailor.confirm')),
          ),
        ],
      ),
    );
  }
}
