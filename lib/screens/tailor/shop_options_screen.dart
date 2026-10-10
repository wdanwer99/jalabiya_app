import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/strings.dart';
import '../../models/design.dart';
import '../../state/session.dart';
import '../../theme/theme.dart';
import '../../util/format.dart';
import '../../widgets/common.dart';

/// The tailor lists the cloth and embroidery-thread colours they work with,
/// each with an extra price on top of the shop's base price. Customers who
/// pick this shop choose only from these. An empty list keeps the standard
/// palette at no extra.
class ShopOptionsScreen extends StatefulWidget {
  const ShopOptionsScreen({super.key});

  @override
  State<ShopOptionsScreen> createState() => _ShopOptionsScreenState();
}

class _ShopOptionsScreenState extends State<ShopOptionsScreen> {
  late List<Swatch> _cloths;
  late List<Swatch> _threads;
  bool _changed = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final shop = context.read<Session>().shop!;
    _cloths = List.of(shop.clothOptions);
    _threads = List.of(shop.threadOptions);
  }

  List<Swatch> _list(String kind) => kind == 'cloth' ? _cloths : _threads;

  void _update(String kind, List<Swatch> next) {
    setState(() {
      if (kind == 'cloth') {
        _cloths = next;
      } else {
        _threads = next;
      }
      _changed = true;
    });
  }

  /// Copies the standard colours, named in the tailor's language, as a
  /// starting point to edit.
  void _useStandard(String kind) {
    final standard = kind == 'cloth' ? JalabiyaDesign.cloths : JalabiyaDesign.threads;
    _update(kind, [for (final s in standard) s.copyWith(name: swatchName(context, kind, s))]);
  }

  Future<void> _edit(String kind, [Swatch? existing]) async {
    final currency = context.read<Session>().shop!.currency;
    final result = await showModalBottomSheet<Swatch>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Palette.paper,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _OptionSheet(kind: kind, existing: existing, currency: currency),
    );
    if (result == null || !mounted) return;
    final list = List.of(_list(kind));
    final i = list.indexWhere((s) => s.id == result.id);
    if (i >= 0) {
      list[i] = result;
    } else {
      list.add(result);
    }
    _update(kind, list);
  }

  void _remove(String kind, Swatch s) {
    _update(kind, _list(kind).where((e) => e.id != s.id).toList());
  }

  Future<void> _save() async {
    final session = context.read<Session>();
    setState(() => _busy = true);
    try {
      if (!await requireOnline(context) || !mounted) return;
      final next = session.shop!.copyWith(clothOptions: _cloths, threadOptions: _threads);
      final forReview = session.shop!.saveSendsForReview(next);
      await session.saveShop(next);
      if (!mounted) return;
      showSnack(context, context.tr(forReview ? 'shop.resubmitted' : 'options.saved'));
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showError(context, e, onRetry: _save);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    if (!_changed || await confirmDiscard(context)) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final shop = context.watch<Session>().shop!;
    return PopScope(
      canPop: !_changed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(context.tr('options.title'))),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            Text(
              context.tr('options.intro', {'price': formatMoney(context, shop.basePrice, shop.currency)}),
              style: const TextStyle(color: Palette.muted, height: 1.55),
            ),
            for (final kind in const ['cloth', 'thread']) ...[
              SectionTitle(
                context.tr('options.$kind'),
                subtitle: context.tr('options.${kind}Hint'),
              ),
              _section(context, kind, shop.currency),
            ],
          ],
        ),
        bottomNavigationBar: BottomActions(children: [
          OutlinedButton(
            onPressed: _busy ? null : _leave,
            child: Text(context.tr('action.cancel')),
          ),
          BusyButton(
            label: context.tr('action.save'),
            busy: _busy,
            onPressed: _changed ? _save : null,
          ),
        ]),
      ),
    );
  }

  Widget _section(BuildContext context, String kind, String currency) {
    final list = _list(kind);
    final addButton = OutlinedButton.icon(
      onPressed: list.length >= Swatch.maxPerKind ? null : () => _edit(kind),
      icon: const Icon(Icons.add_rounded),
      label: Text(context.tr('options.add.$kind')),
    );
    if (list.isEmpty) {
      return Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.tr('options.empty'), style: const TextStyle(color: Palette.muted, height: 1.5)),
            const SizedBox(height: 10),
            SwatchStrip(swatches: kind == 'cloth' ? JalabiyaDesign.cloths : JalabiyaDesign.threads),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _useStandard(kind),
              icon: const Icon(Icons.palette_outlined),
              label: Text(context.tr('options.useStandard')),
            ),
            const SizedBox(height: 8),
            addButton,
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Column(
            children: [
              for (var i = 0; i < list.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                ListTile(
                  contentPadding: const EdgeInsetsDirectional.only(start: 10, end: 0),
                  onTap: () => _edit(kind, list[i]),
                  leading: _Dot(color: list[i].color, size: 30),
                  title: Text(list[i].name ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    list[i].price > 0
                        ? '+${formatMoney(context, list[i].price, currency)}'
                        : context.tr('options.noExtra'),
                    style: const TextStyle(color: Palette.muted, fontSize: 13),
                  ),
                  trailing: IconButton(
                    tooltip: context.tr('action.delete'),
                    icon: const Icon(Icons.delete_outline_rounded, color: Palette.henna),
                    onPressed: () => _remove(kind, list[i]),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        addButton,
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, this.size = 24});

  final int color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Color(0xFF000000 | color),
        shape: BoxShape.circle,
        border: Border.all(color: Palette.line),
      ),
    );
  }
}

/// Name, colour and extra price for one option.
class _OptionSheet extends StatefulWidget {
  const _OptionSheet({required this.kind, required this.currency, this.existing});

  final String kind;
  final String currency;
  final Swatch? existing;

  @override
  State<_OptionSheet> createState() => _OptionSheetState();
}

/// Colours to start from; any other can be typed as #RRGGBB.
const _clothPresets = [
  0xFFFFFF, 0xF5F1E6, 0xEDDFC2, 0xE8D9B5, 0xDCC6A2, 0xC9B28A, 0xA68A64, 0x7A5C3E,
  0x5A4030, 0xC3C7CB, 0x9A9FA5, 0x6B7178, 0x4A5058, 0x2E3238, 0x111111, 0xB9CDD9,
  0x7FA3BF, 0x3E6A8F, 0x1F2A44, 0xA9BFA3, 0x5E7A5A, 0x2F4A3A, 0x8C2F39, 0x5B2333,
];
const _threadPresets = [
  0xC8A24A, 0xE0C068, 0xB08D57, 0xC0C0C0, 0xF6F3EA, 0x111111, 0x2B3F63, 0x3E6A8F,
  0x9C4A2F, 0x8C2F39, 0x2F4A3A, 0x5E7A5A, 0x6B4C9A, 0xD98E04, 0x7A5C3E, 0x6B7178,
];

class _OptionSheetState extends State<_OptionSheet> {
  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _hex;
  late int _color;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final presets = widget.kind == 'cloth' ? _clothPresets : _threadPresets;
    _color = e?.color ?? presets.first;
    _name = TextEditingController(text: e?.name ?? '');
    _price = TextEditingController(text: e == null || e.price == 0 ? '' : trimNumber(e.price, decimals: 0));
    _hex = TextEditingController(text: _toHex(_color));
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _hex.dispose();
    super.dispose();
  }

  static String _toHex(int c) => '#${c.toRadixString(16).padLeft(6, '0').toUpperCase()}';

  static int? _fromHex(String text) {
    final t = text.trim().replaceFirst('#', '');
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(t)) return null;
    return int.parse(t, radix: 16);
  }

  void _pick(int c) {
    setState(() {
      _color = c;
      _hex.text = _toHex(c);
    });
  }

  void _done() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = context.tr('options.needName'));
      return;
    }
    final priceText = _price.text.trim();
    final price = priceText.isEmpty ? 0.0 : parseLooseNumber(priceText);
    if (price == null || price < 0) {
      setState(() => _error = context.tr('form.number'));
      return;
    }
    final id = widget.existing?.id ??
        '${widget.kind[0]}${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    Navigator.of(context).pop(Swatch(id, _color, name: name, price: price));
  }

  @override
  Widget build(BuildContext context) {
    final presets = widget.kind == 'cloth' ? _clothPresets : _threadPresets;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            children: [
              Row(
                children: [
                  _Dot(color: _color, size: 40),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      context.tr(widget.existing == null ? 'options.add.${widget.kind}' : 'options.edit'),
                      style: displayStyle(19),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _name,
                maxLength: Swatch.maxName,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() => _error = null),
                decoration: field(
                  labelText: context.tr('options.name'),
                  hintText: context.tr('options.nameHint.${widget.kind}'),
                ),
              ),
              Text(context.tr('options.colour'), style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final c in presets)
                    GestureDetector(
                      onTap: () => _pick(c),
                      child: Container(
                        width: 36,
                        height: 36,
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: c == _color ? Palette.gold : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                        child: _Dot(color: c, size: 30),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _hex,
                textDirection: TextDirection.ltr,
                maxLength: 7,
                onChanged: (v) {
                  final c = _fromHex(v);
                  if (c != null) setState(() => _color = c);
                },
                decoration: field(
                  labelText: context.tr('options.hex'),
                  hintText: '#C8A24A',
                ),
              ),
              TextField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() => _error = null),
                decoration: field(
                  labelText: context.tr('options.price'),
                  helperText: context.tr('options.priceHint'),
                  suffixText: widget.currency == 'SDG' ? context.tr('money.sdg') : widget.currency,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: Palette.henna)),
              ],
              const SizedBox(height: 18),
              FilledButton(onPressed: _done, child: Text(context.tr('action.done'))),
            ],
          ),
        ),
      ),
    );
  }
}
