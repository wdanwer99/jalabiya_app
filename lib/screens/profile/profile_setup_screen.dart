import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/strings.dart';
import '../../models/places.dart';
import '../../models/profile.dart';
import '../../models/tailor_shop.dart';
import '../../state/session.dart';
import '../../theme/theme.dart';
import '../../util/format.dart';
import '../../widgets/common.dart';
import '../../widgets/motion.dart';

/// The full-profile gate. A customer cannot order, and a tailor cannot be
/// listed, until every field here is filled, because the other side relies
/// on it: the tailor to call and deliver, the customer to find the shop.
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key, this.asGate = false});

  final bool asGate;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _whatsapp;
  late final TextEditingController _neighbourhood;
  late final TextEditingController _address;
  late final TextEditingController _shopName;
  late final TextEditingController _bio;
  late final TextEditingController _price;
  late final TextEditingController _lead;
  String? _city;
  bool _waSame = true;
  bool _accepts = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<Session>();
    final p = s.profile!;
    final shop = s.shop;
    _name = TextEditingController(text: p.fullName)..addListener(_refresh);
    _phone = TextEditingController(text: p.phone)..addListener(_refresh);
    _whatsapp = TextEditingController(text: p.whatsapp ?? '');
    _waSame = (p.whatsapp ?? '').isEmpty || p.whatsapp == p.phone;
    _city = p.city ?? shop?.city;
    _neighbourhood = TextEditingController(text: p.neighbourhood ?? shop?.neighbourhood ?? '')..addListener(_refresh);
    _address = TextEditingController(text: p.addressDetails ?? shop?.addressDetails ?? '')..addListener(_refresh);
    _shopName = TextEditingController(text: shop?.shopName ?? '')..addListener(_refresh);
    _bio = TextEditingController(text: shop?.bio ?? '');
    _price = TextEditingController(text: shop == null ? '' : trimNumber(shop.basePrice, decimals: 0))
      ..addListener(_refresh);
    _lead = TextEditingController(text: shop == null ? '7' : '${shop.leadTimeDays}')..addListener(_refresh);
    _accepts = shop?.acceptsOrders ?? true;
    _initial = _snapshot();
  }

  late final String _initial;

  /// Everything editable, as one string, to tell whether anything changed.
  String _snapshot() => [
        _name.text,
        _phone.text,
        _whatsapp.text,
        _waSame,
        _city,
        _neighbourhood.text,
        _address.text,
        _shopName.text,
        _bio.text,
        _price.text,
        _lead.text,
        _accepts,
      ].join('\u0001');

  bool get _dirty => _snapshot() != _initial;

  Future<void> _leave() async {
    if (!_dirty || await confirmDiscard(context)) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    for (final c in [_name, _phone, _whatsapp, _neighbourhood, _address, _shopName, _bio, _price, _lead]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isTailor => context.read<Session>().profile!.isTailor;

  Profile _draftProfile() {
    final p = context.read<Session>().profile!;
    return p.copyWith(
      fullName: _name.text,
      phone: _phone.text,
      whatsapp: _waSame ? '' : _whatsapp.text,
      city: _city ?? '',
      neighbourhood: _neighbourhood.text,
      addressDetails: _address.text,
    );
  }

  /// Every required field with whether it is filled, for the checklist.
  List<MapEntry<String, bool>> _checks() {
    final checks = [..._draftProfile().checklist];
    if (_isTailor) {
      final lead = int.tryParse(digitsOnly(_lead.text));
      checks.addAll([
        MapEntry('shopName', _shopName.text.trim().length >= 2),
        MapEntry('price', parseLooseNumber(_price.text) != null),
        MapEntry('lead', lead != null && lead >= 1 && lead <= 120),
      ]);
    }
    return checks;
  }

  double _progress() {
    final checks = _checks();
    return checks.where((c) => c.value).length / checks.length;
  }

  Future<void> _pickCity() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Palette.paper,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _CityPicker(current: _city),
    );
    if (picked != null) {
      Haptics.select();
      setState(() => _city = picked);
    }
  }

  Future<void> _save() async {
    final ok = _form.currentState!.validate();
    if ((_city ?? '').trim().isEmpty) {
      showSnack(context, context.tr('form.city'), error: true);
      return;
    }
    if (!ok) {
      showSnack(context, context.tr('profile.fixFields'), error: true);
      return;
    }
    final session = context.read<Session>();
    final profile = _draftProfile();
    final saved = session.shop;
    final shop = profile.isTailor
        ? TailorShop(
            tailorId: profile.id,
            shopName: _shopName.text,
            bio: _bio.text,
            city: _city!,
            neighbourhood: _neighbourhood.text,
            addressDetails: _address.text,
            basePrice: parseLooseNumber(_price.text) ?? 0,
            leadTimeDays: int.parse(digitsOnly(_lead.text)),
            acceptsOrders: _accepts,
            // edited on their own screen; keep what is saved
            clothOptions: saved?.clothOptions ?? const [],
            threadOptions: saved?.threadOptions ?? const [],
          )
        : null;
    final forReview = saved != null && shop != null && saved.saveSendsForReview(shop);
    // a listed shop is about to disappear from customers: say so first
    if (forReview && saved.review == ShopReview.approved) {
      final go = await confirmAction(
        context,
        title: context.tr('shop.reReviewTitle'),
        body: context.tr('shop.reReviewBody'),
        confirmLabel: context.tr('shop.reReviewConfirm'),
      );
      if (!go || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      if (!await requireOnline(context) || !mounted) return;
      await session.saveProfile(profile);
      if (shop != null) await session.saveShop(shop);
      if (!mounted) return;
      final message = context.tr(forReview ? 'shop.resubmitted' : 'profile.saved');
      if (widget.asGate) {
        showSnack(context, message);
      } else {
        await showSuccess(context, message);
        if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) showError(context, e, onRetry: _save);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTailor = _isTailor;
    final progress = _progress();
    return PopScope(
      canPop: widget.asGate || !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr(widget.asGate ? 'profile.gateTitle' : 'profile.editTitle')),
          actions: [
            if (widget.asGate)
              TextButton(
                onPressed: () => context.read<Session>().signOut(),
                child: Text(context.tr('action.signOut')),
              ),
          ],
        ),
        bottomNavigationBar: BottomActions(children: [
          BusyButton(
            label: context.tr(widget.asGate ? 'profile.saveContinue' : 'action.save'),
            icon: Icons.check_rounded,
            busy: _busy,
            onPressed: _save,
          ),
        ]),
        body: Form(
          key: _form,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            children: [
              if (widget.asGate)
                Text(
                  context.tr(isTailor ? 'profile.gateBodyTailor' : 'profile.gateBodyCustomer'),
                  style: const TextStyle(color: Palette.muted, height: 1.55),
                ),
              const SizedBox(height: 14),
              _Checklist(progress: progress, checks: _checks()),
              SectionTitle(context.tr('profile.you')),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: field(
                    labelText: context.tr('profile.fullName'), prefixIcon: const Icon(Icons.person_outline_rounded)),
                validator: (v) => (v ?? '').trim().length >= 3 ? null : context.tr('form.name'),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                decoration: field(
                  labelText: context.tr('profile.phone'),
                  hintText: '0912345678',
                  prefixIcon: const Icon(Icons.call_outlined),
                ),
                validator: (v) => isValidPhone(v) ? null : context.tr('form.phone'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _waSame,
                onChanged: (v) {
                  Haptics.select();
                  setState(() => _waSame = v);
                },
                title: Text(context.tr('profile.waSame')),
              ),
              if (!_waSame)
                TextFormField(
                  controller: _whatsapp,
                  keyboardType: TextInputType.phone,
                  textDirection: TextDirection.ltr,
                  decoration: field(
                    labelText: context.tr('profile.whatsapp'),
                    hintText: '+249912345678',
                    prefixIcon: const Icon(Icons.chat_outlined),
                  ),
                  validator: (v) => isValidPhone(v) ? null : context.tr('form.phone'),
                ),
              SectionTitle(
                context.tr(isTailor ? 'profile.shopPlace' : 'profile.address'),
                subtitle: context.tr(isTailor ? 'profile.shopPlaceHint' : 'profile.addressHint'),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: _pickCity,
                child: InputDecorator(
                  decoration: field(
                    labelText: context.tr('profile.city'),
                    prefixIcon: const Icon(Icons.location_city_outlined),
                    suffixIcon: const Icon(Icons.expand_more_rounded),
                  ),
                  isEmpty: (_city ?? '').isEmpty,
                  child: Text((_city ?? '').isEmpty ? '' : cityLabel(context, _city)),
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _neighbourhood,
                decoration:
                    field(labelText: context.tr('profile.neighbourhood'), prefixIcon: const Icon(Icons.place_outlined)),
                validator: (v) => (v ?? '').trim().isEmpty ? context.tr('form.required') : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _address,
                minLines: 2,
                maxLines: 4,
                decoration: field(
                  labelText: context.tr('profile.addressDetails'),
                  hintText: context.tr('profile.addressDetailsHint'),
                  prefixIcon: const Icon(Icons.signpost_outlined),
                  alignLabelWithHint: true,
                ),
                validator: (v) => (v ?? '').trim().length >= 5 ? null : context.tr('form.address'),
              ),
              if (isTailor) ...[
                SectionTitle(context.tr('shop.title'), subtitle: context.tr('shop.subtitle')),
                TextFormField(
                  controller: _shopName,
                  decoration:
                      field(labelText: context.tr('shop.name'), prefixIcon: const Icon(Icons.storefront_outlined)),
                  validator: (v) => (v ?? '').trim().length >= 2 ? null : context.tr('form.required'),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _bio,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 300,
                  decoration: field(
                    labelText: context.tr('shop.bio'),
                    hintText: context.tr('shop.bioHint'),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _price,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: field(
                          labelText: context.tr('shop.price'),
                          suffixText: context.tr('money.sdg'),
                          prefixIcon: const Icon(Icons.payments_outlined),
                        ),
                        validator: (v) {
                          final n = parseLooseNumber(v ?? '');
                          return n != null && n >= 0 ? null : context.tr('form.number');
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _lead,
                        keyboardType: TextInputType.number,
                        decoration: field(
                          labelText: context.tr('shop.lead'),
                          suffixText: context.tr('unit.days'),
                          prefixIcon: const Icon(Icons.schedule_rounded),
                        ),
                        validator: (v) {
                          final n = int.tryParse(digitsOnly(v ?? ''));
                          return n != null && n >= 1 && n <= 120 ? null : context.tr('form.leadDays');
                        },
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _accepts,
                  onChanged: (v) {
                    Haptics.select();
                    setState(() => _accepts = v);
                  },
                  title: Text(context.tr('shop.accepts')),
                  subtitle: Text(context.tr('shop.acceptsHint')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// How far the profile is: the tailor's tape filling up, and a chip per
/// required field that ticks itself as the field is filled.
class _Checklist extends StatelessWidget {
  const _Checklist({required this.progress, required this.checks});

  final double progress;
  final List<MapEntry<String, bool>> checks;

  @override
  Widget build(BuildContext context) {
    final done = progress >= 1;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.tr(done ? 'profile.allDone' : 'profile.progress'),
                  style: displayStyle(16, color: done ? Palette.nile : Palette.ink),
                ),
              ),
              TweenAnimationBuilder<double>(
                tween: Tween(end: progress),
                duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 400),
                builder: (context, v, _) => Text(
                  '${(v * 100).round()}%',
                  style: monoStyle(14, color: done ? Palette.nile : Palette.goldInk),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TapeRule(progress: progress, height: 12),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in checks)
                AnimatedContainer(
                  duration: Motion.quick,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: c.value ? Palette.nileSoft : Palette.paper,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: c.value ? Palette.nileSoft : Palette.line),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedSwitcher(
                        duration: Motion.quick,
                        transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
                        child: Icon(
                          c.value ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                          key: ValueKey(c.value),
                          size: 15,
                          color: c.value ? Palette.nile : Palette.chalk,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        context.tr('profile.check.${c.key}'),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: c.value ? Palette.nile : Palette.muted,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CityPicker extends StatefulWidget {
  const _CityPicker({this.current});

  final String? current;

  @override
  State<_CityPicker> createState() => _CityPickerState();
}

class _CityPickerState extends State<_CityPicker> {
  final _other = TextEditingController();

  @override
  void initState() {
    super.initState();
    final c = widget.current;
    if (c != null && c.isNotEmpty && !sudanCities.contains(c)) _other.text = c;
  }

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Text(context.tr('profile.city'), style: displayStyle(19)),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final c in sudanCities)
                      ListTile(
                        title: Text(context.tr('city.$c')),
                        trailing: c == widget.current ? const Icon(Icons.check_rounded, color: Palette.nile) : null,
                        onTap: () => Navigator.of(context).pop(c),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _other,
                        decoration: field(hintText: context.tr('profile.otherCity')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size(64, 50)),
                      onPressed: () {
                        final v = _other.text.trim();
                        if (v.isNotEmpty) Navigator.of(context).pop(v);
                      },
                      child: Text(context.tr('action.done')),
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
