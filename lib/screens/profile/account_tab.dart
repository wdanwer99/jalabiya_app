import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/errors.dart';
import '../../data/repository.dart';
import '../../l10n/strings.dart';
import '../../models/garment_spec.dart';
import '../../models/measurement_set.dart';
import '../../models/measurements.dart';
import '../../models/profile.dart';
import '../../models/tailor_shop.dart';
import '../../state/session.dart';
import '../../theme/theme.dart';
import '../../util/format.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common.dart';
import '../../widgets/motion.dart';
import '../customer/measurement_editor_screen.dart';
import '../tailor/shop_options_screen.dart';
import 'profile_setup_screen.dart';

/// Who you are, at a glance: a header with your name and role, a few live
/// numbers, your sizes (customers) or shop (tailors), how to reach you, and
/// settings. Details can be copied with a tap.
class AccountTab extends StatefulWidget {
  const AccountTab({super.key});

  @override
  State<AccountTab> createState() => _AccountTabState();
}

class _AccountTabState extends State<AccountTab> {
  /// The customer's saved people and order count, loaded together.
  Future<(List<MeasurementSet>, int)>? _customerData;

  @override
  void initState() {
    super.initState();
    final s = context.read<Session>();
    if (!s.profile!.isTailor) _customerData = _loadCustomer();
  }

  Future<(List<MeasurementSet>, int)> _loadCustomer() async {
    final repo = context.read<Repository>();
    final uid = context.read<Session>().user!.id;
    final results = await Future.wait([repo.listMeasurementSets(uid), repo.countCustomerOrders(uid)]);
    return (results[0] as List<MeasurementSet>, results[1] as int);
  }

  Future<void> _reload() async {
    final s = context.read<Session>();
    if (s.profile!.isTailor) {
      Haptics.tap();
      await s.reload();
      return;
    }
    final next = _loadCustomer();
    setState(() => _customerData = next);
    Haptics.tap();
    try {
      await next;
    } catch (_) {
      // the panels show their own error with a retry
    }
  }

  Future<void> _edit() async {
    Haptics.tap();
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ProfileSetupScreen()));
  }

  Future<void> _openMySizes(MeasurementSet? mine) async {
    Haptics.tap();
    final name = context.read<Session>().profile!.fullName.trim();
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MeasurementEditorScreen(existing: mine, initialLabel: name, initialRelation: 'self'),
      ),
    );
    if (changed == true && mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    final p = s.profile;
    // Signed out: the gate is fading this screen away, so draw nothing.
    if (p == null) return const SizedBox.shrink();
    final shop = s.shop;
    final sections = <Widget>[
      if (p.isTailor) ...[
        if (shop != null) ...[_ShopCard(shop: shop), _ColoursCard(shop: shop)],
      ] else
        FutureBuilder<(List<MeasurementSet>, int)>(
          future: _customerData,
          builder: (context, snap) => _MySizesCard(
            loading: snap.connectionState != ConnectionState.done,
            error: snap.error,
            mine: snap.data?.$1.where((m) => m.relation == 'self').firstOrNull,
            onOpen: _openMySizes,
            onRetry: _reload,
          ),
        ),
      _ContactCard(profile: p, email: s.user?.email, onEdit: _edit),
      _SettingsCard(session: s),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: Palette.henna,
          side: BorderSide(color: Palette.henna.withValues(alpha: 0.4)),
        ),
        onPressed: () async {
          final ok = await confirmAction(
            context,
            title: context.tr('action.signOut'),
            body: context.tr('settings.signOutBody'),
            confirmLabel: context.tr('action.signOut'),
            destructive: true,
          );
          if (ok) await s.signOut();
        },
        icon: const Icon(Icons.logout_rounded),
        label: Text(context.tr('action.signOut')),
      ),
    ];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: RefreshIndicator(
          color: Palette.nile,
          edgeOffset: 200,
          onRefresh: _reload,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: _ProfileHeader(
                  profile: p,
                  shop: shop,
                  customerData: _customerData,
                  onEdit: _edit,
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
                sliver: SliverList.list(
                  children: [
                    for (var i = 0; i < sections.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: EntranceFade(index: i, child: sections[i]),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Navy stage: initial, name, role, member since, and three live numbers.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profile, required this.shop, required this.customerData, required this.onEdit});

  final Profile profile;
  final TailorShop? shop;
  final Future<(List<MeasurementSet>, int)>? customerData;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final name = p.fullName.trim();
    return InkHeader(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 22),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const IconTheme(data: IconThemeData(color: Palette.damur), child: DrawerMenuButton()),
                const Spacer(),
                IconButton(
                  tooltip: context.tr(p.isTailor ? 'profile.editWithShop' : 'profile.editTitle'),
                  onPressed: onEdit,
                  style: IconButton.styleFrom(backgroundColor: const Color(0x1FF2EDE1)),
                  icon: const Icon(Icons.edit_outlined, color: Palette.damur),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: Palette.gold),
                        child: Container(
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Palette.goldSoft, Color(0xFFEBD9AE)],
                            ),
                          ),
                          child: Text(
                            name.isEmpty ? '?' : name.characters.first,
                            style: displayStyle(30, color: Palette.goldInk),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name.isEmpty ? '—' : name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: displayStyle(23, color: Palette.damur),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Palette.gold.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    context.tr(p.isTailor ? 'role.tailor' : 'role.customer'),
                                    style:
                                        const TextStyle(color: Palette.gold, fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                ),
                                if (p.createdAt != null)
                                  Text(
                                    context.tr('account.since', {'date': formatDate(context, p.createdAt!.toLocal())}),
                                    style: const TextStyle(color: Palette.onInkMuted, fontSize: 12.5),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (!p.isTailor) _customerStats(context) else if (shop != null) _tailorStats(context, shop!),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _customerStats(BuildContext context) {
    return FutureBuilder<(List<MeasurementSet>, int)>(
      future: customerData,
      builder: (context, snap) {
        final d = snap.data;
        final mine = d?.$1.where((m) => m.relation == 'self').firstOrNull;
        return Row(
          children: [
            _Stat(icon: Icons.receipt_long_outlined, label: context.tr('account.stat.orders'), count: d?.$2),
            const SizedBox(width: 10),
            _Stat(icon: Icons.people_outline_rounded, label: context.tr('account.stat.people'), count: d?.$1.length),
            const SizedBox(width: 10),
            _Stat(
              icon: Icons.straighten_rounded,
              label: context.tr('account.stat.size'),
              text: d == null ? null : (mine == null ? '—' : GarmentSpec.sizeFor(mine.measurements.chest)),
            ),
          ],
        );
      },
    );
  }

  Widget _tailorStats(BuildContext context, TailorShop shop) {
    final (status, icon) = switch (shop.review) {
      ShopReview.pending => ('shop.statusPending', Icons.hourglass_top_rounded),
      ShopReview.rejected => ('shop.statusRejected', Icons.edit_note_rounded),
      ShopReview.suspended => ('shop.statusSuspended', Icons.block_rounded),
      ShopReview.approved => shop.acceptsOrders
          ? ('shop.statusOpen', Icons.storefront_outlined)
          : ('shop.statusPaused', Icons.pause_circle_outline_rounded),
    };
    return Row(
      children: [
        _Stat(
          icon: icon,
          label: context.tr('shop.status'),
          text: context.tr(status),
          small: true,
        ),
        const SizedBox(width: 10),
        _Stat(
          icon: Icons.payments_outlined,
          label: context.tr('account.stat.from'),
          text: trimNumber(shop.basePrice, decimals: 0),
          small: true,
        ),
        const SizedBox(width: 10),
        _Stat(
            icon: Icons.schedule_rounded,
            label: context.tr('shop.lead'),
            text: context.tr('shop.days', {'days': '${shop.leadTimeDays}'}),
            small: true),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label, this.count, this.text, this.small = false});

  final IconData icon;
  final String label;
  final int? count;
  final String? text;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final style = displayStyle(small ? 16 : 22, color: Palette.damur);
    final Widget value;
    if (count != null) {
      value = AnimatedCount(value: count!, style: style);
    } else if (text != null) {
      value = Text(text!, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    } else {
      value = const Shimmer(child: SkeletonBox(width: 30, height: 22));
    }
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0x14F2EDE1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x26F2EDE1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: Palette.gold),
            const SizedBox(height: 8),
            SizedBox(height: small ? 24 : 30, child: Align(alignment: AlignmentDirectional.centerStart, child: value)),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Palette.onInkMuted, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

/// A card with a title row: icon, title, and an optional action on the end.
class _Card extends StatelessWidget {
  const _Card({required this.icon, required this.title, required this.child, this.action, this.onTap});

  final IconData icon;
  final String title;
  final Widget child;
  final Widget? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Panel(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(color: Palette.nileSoft, shape: BoxShape.circle),
                child: Icon(icon, size: 18, color: Palette.nile),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: displayStyle(17))),
              if (action != null) action!,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
    return onTap == null ? card : Pressable(child: card);
  }
}

/// The customer's own sizes as a grid of small tiles, with the ready-made
/// size up top.
class _MySizesCard extends StatelessWidget {
  const _MySizesCard({
    required this.loading,
    required this.error,
    required this.mine,
    required this.onOpen,
    required this.onRetry,
  });

  final bool loading;
  final Object? error;
  final MeasurementSet? mine;
  final ValueChanged<MeasurementSet?> onOpen;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final unit = context.watch<Session>().unit;
    final Widget body;
    if (loading) {
      body = Shimmer(
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (var i = 0; i < 6; i++) const SkeletonBox(width: 96, height: 52, radius: 12)],
        ),
      );
    } else if (error != null) {
      body = Row(
        children: [
          Expanded(child: Text(friendlyError(context, error!), style: const TextStyle(color: Palette.muted))),
          TextButton(onPressed: onRetry, child: Text(context.tr('action.retry'))),
        ],
      );
    } else if (mine == null) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.tr('myMeasure.empty'), style: const TextStyle(color: Palette.muted, height: 1.5)),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => onOpen(null),
            icon: const Icon(Icons.straighten_rounded),
            label: Text(context.tr('myMeasure.add')),
          ),
        ],
      );
    } else {
      final m = mine!.measurements;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, box) {
              // three tiles a row on phones, more when there is room
              final perRow = (box.maxWidth / 110).floor().clamp(3, 6);
              final w = (box.maxWidth - 8 * (perRow - 1)) / perRow;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in Measurements.specs)
                    Container(
                      width: w,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                      decoration: BoxDecoration(color: Palette.goldSoft, borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.tr('m.${s.key}'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Palette.muted, fontSize: 11.5),
                          ),
                          const SizedBox(height: 2),
                          Text(formatLength(m.valueOf(s.key), unit), style: monoStyle(14, weight: FontWeight.w600)),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => onOpen(mine),
            icon: const Icon(Icons.edit_outlined),
            label: Text(context.tr('myMeasure.edit')),
          ),
        ],
      );
    }
    return _Card(
      icon: Icons.straighten_rounded,
      title: context.tr('myMeasure.title'),
      action: mine == null
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration:
                  BoxDecoration(border: Border.all(color: Palette.gold), borderRadius: BorderRadius.circular(8)),
              child:
                  Text(GarmentSpec.sizeFor(mine!.measurements.chest), style: displayStyle(16, color: Palette.goldInk)),
            ),
      child: AnimatedSwitcher(
          duration: Motion.quick, child: KeyedSubtree(key: ValueKey('$loading$error${mine?.id}'), child: body)),
    );
  }
}

/// How others reach you. Each line copies its value when tapped.
class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.profile, required this.email, required this.onEdit});

  final Profile profile;
  final String? email;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final wa = (p.whatsapp ?? '').trim();
    return _Card(
      icon: Icons.contact_phone_outlined,
      title: context.tr('account.contact'),
      action: TextButton(onPressed: onEdit, child: Text(context.tr('action.edit'))),
      child: Column(
        children: [
          _CopyRow(icon: Icons.call_outlined, label: context.tr('profile.phone'), value: p.phone, mono: true),
          _CopyRow(
            icon: Icons.chat_outlined,
            label: context.tr('profile.whatsapp'),
            value: wa.isEmpty ? p.phone : wa,
            note: wa.isEmpty ? context.tr('account.sameNumber') : null,
            mono: true,
          ),
          if ((email ?? '').isNotEmpty)
            _CopyRow(icon: Icons.alternate_email_rounded, label: context.tr('auth.email'), value: email!),
          _CopyRow(
            icon: Icons.place_outlined,
            label: context.tr(p.isTailor ? 'profile.shopPlace' : 'profile.address'),
            value: placeLine(context, p.city, p.neighbourhood),
          ),
          if ((p.addressDetails ?? '').trim().isNotEmpty)
            _CopyRow(
                icon: Icons.signpost_outlined,
                label: context.tr('profile.addressDetails'),
                value: p.addressDetails!.trim(),
                last: true),
        ],
      ),
    );
  }
}

class _CopyRow extends StatelessWidget {
  const _CopyRow({
    required this.icon,
    required this.label,
    required this.value,
    this.note,
    this.mono = false,
    this.last = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? note;
  final bool mono;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      hint: context.tr('account.tapToCopy'),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: value));
          Haptics.select();
          if (context.mounted) {
            showSnack(context, context.tr('account.copied', {'what': label}), icon: Icons.copy_rounded);
          }
        },
        child: Padding(
          padding: EdgeInsets.only(top: 8, bottom: last ? 0 : 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: Palette.muted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(color: Palette.muted, fontSize: 12)),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      textDirection: mono ? TextDirection.ltr : null,
                      style: mono ? monoStyle(14.5) : const TextStyle(fontSize: 14.5, height: 1.4),
                    ),
                    if (note != null) Text(note!, style: const TextStyle(color: Palette.chalk, fontSize: 11.5)),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Icon(Icons.copy_rounded, size: 16, color: Palette.chalk),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShopCard extends StatelessWidget {
  const _ShopCard({required this.shop});

  final TailorShop shop;

  @override
  Widget build(BuildContext context) {
    return _Card(
      icon: Icons.storefront_outlined,
      title: shop.shopName,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (ShopStatusBanner.applies(shop)) ShopStatusBanner(shop: shop),
          if ((shop.bio ?? '').trim().isNotEmpty) ...[
            if (ShopStatusBanner.applies(shop)) const SizedBox(height: 10),
            Text(shop.bio!.trim(), style: const TextStyle(height: 1.5)),
          ],
          const SizedBox(height: 4),
          InfoRow(context.tr('shop.price'), formatMoney(context, shop.basePrice, shop.currency), strong: true),
          InfoRow(context.tr('profile.place'), placeLine(context, shop.city, shop.neighbourhood)),
        ],
      ),
    );
  }
}

class _ColoursCard extends StatelessWidget {
  const _ColoursCard({required this.shop});

  final TailorShop shop;

  void _open(BuildContext context) {
    Haptics.tap();
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ShopOptionsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      icon: Icons.palette_outlined,
      title: context.tr('options.title'),
      onTap: () => _open(context),
      action: const Icon(Icons.chevron_right_rounded, color: Palette.chalk),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final kind in const ['cloth', 'thread']) ...[
            Text(context.tr('options.$kind'), style: const TextStyle(color: Palette.muted, fontSize: 13)),
            const SizedBox(height: 6),
            SwatchStrip(swatches: kind == 'cloth' ? shop.offeredCloths : shop.offeredThreads, max: 10),
            const SizedBox(height: 12),
          ],
          if (shop.clothOptions.isEmpty || shop.threadOptions.isEmpty)
            Text(
              context.tr('options.usingStandard'),
              style: const TextStyle(color: Palette.goldInk, fontSize: 13, height: 1.45),
            ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final s = session;
    Widget row(IconData icon, String label, Widget control) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(icon, size: 20, color: Palette.muted),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: const TextStyle(fontSize: 14.5))),
              control,
            ],
          ),
        );
    return _Card(
      icon: Icons.tune_rounded,
      title: context.tr('settings.title'),
      child: Column(
        children: [
          row(
            Icons.translate_rounded,
            context.tr('settings.language'),
            SegmentBar(
              values: const ['ar', 'en'],
              selected: s.locale.languageCode,
              label: (v) => v == 'ar' ? 'عربي' : 'English',
              onSelected: (v) {
                Haptics.select();
                s.setLocale(v);
              },
            ),
          ),
          const Divider(),
          row(
            Icons.straighten_rounded,
            context.tr('settings.units'),
            SegmentBar(
              values: const ['cm', 'in'],
              selected: s.unit == LengthUnit.cm ? 'cm' : 'in',
              label: (v) => context.tr('settings.unit.$v'),
              onSelected: (v) {
                Haptics.select();
                s.setUnit(v == 'cm' ? LengthUnit.cm : LengthUnit.inch);
              },
            ),
          ),
        ],
      ),
    );
  }
}
