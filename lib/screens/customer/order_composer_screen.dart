import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repository.dart';
import '../../l10n/strings.dart';
import '../../models/design.dart';
import '../../models/measurement_set.dart';
import '../../models/measurements.dart';
import '../../models/order.dart';
import '../../models/tailor_shop.dart';
import '../../state/session.dart';
import '../../theme/theme.dart';
import '../../util/format.dart';
import '../../widgets/common.dart';
import '../../widgets/fitting_room.dart';
import '../../widgets/measure_field.dart';
import '../../widgets/motion.dart';
import '../../widgets/order_parts.dart';
import '../profile/profile_setup_screen.dart';
import 'order_detail_screen.dart';

/// The ordering flow, one screen with the 3D figure kept on top:
///   who it is for → their body → the tailor → the jalabiya → review & send.
///
/// The tailor comes before the jalabiya because each shop lists its own
/// cloth and thread colours, and the customer chooses from those.
///
/// The same screen edits an order the tailor has not confirmed yet
/// ([editing]), starts a new order from an old one ([reorderFrom]), and
/// starts one with a tailor already picked from the tailors list ([tailor]),
/// in which case the tailor step is skipped.
class OrderComposerScreen extends StatefulWidget {
  const OrderComposerScreen({super.key, this.editing, this.reorderFrom, this.tailor});

  final Order? editing;
  final Order? reorderFrom;
  final TailorShop? tailor;

  @override
  State<OrderComposerScreen> createState() => _OrderComposerScreenState();
}

const _kNewPerson = '__new__';

class _OrderComposerScreenState extends State<OrderComposerScreen> {
  final _room = FittingRoomController();
  final _notes = TextEditingController();
  final _newLabel = TextEditingController();
  bool _forward = true; // which way the last step change went, for the slide

  /// Size boxes on this step holding a number that was not accepted.
  final _badSizes = <String>{};

  late List<String> _steps;
  int _step = 0;
  bool _tailorGone = false; // the tailor picked beforehand stopped taking orders

  List<MeasurementSet>? _sets;
  String? _personId; // a saved set id, _kNewPerson, or null
  String _newRelation = 'son';
  String _wearer = '';
  Measurements _m = Measurements.defaults;
  Measurements? _savedM; // what the chosen person has on file, to spot edits
  bool _touched = false; // sizes moved by hand in this session
  bool _saveToPerson = true;
  bool _skippedBody = false; // went person → the step after body, using saved sizes
  bool _changed = false; // anything edited that leaving would lose

  JalabiyaDesign _d = JalabiyaDesign.defaults;
  bool _colourReplaced = false; // the earlier order's colour isn't offered now

  List<TailorShop>? _shops;
  TailorShop? _shop;

  int _quantity = 1;
  bool _busy = false;
  Object? _loadError;

  bool get _isEdit => widget.editing != null;

  @override
  void initState() {
    super.initState();
    _steps = _isEdit
        ? const ['body', 'design', 'review']
        : widget.tailor != null
            ? const ['person', 'body', 'design', 'review']
            : const ['person', 'body', 'tailor', 'design', 'review'];
    if (widget.tailor != null) _shop = widget.tailor;
    final from = widget.editing ?? widget.reorderFrom;
    if (from != null) {
      _m = from.measurements;
      _d = from.design;
      _wearer = from.wearerLabel;
      _quantity = from.quantity;
      _notes.text = from.customerNotes ?? '';
      _personId = from.measurementSetId;
      _shop = from.shop;
      _fitDesignToShop(fromEarlierOrder: true);
    }
    _room.setUnit(context.read<Session>().unit);
    _room.setView(_isEdit ? 'body' : 'cloth');
    _room.show(_m, _d);
    _loadData();
  }

  Future<void> _loadData() async {
    final repo = context.read<Repository>();
    final uid = context.read<Session>().user!.id;
    try {
      final sets = await repo.listMeasurementSets(uid);
      final shops = _isEdit ? <TailorShop>[] : await repo.listOpenShops();
      if (!mounted) return;
      setState(() {
        _sets = sets;
        _shops = shops;
        _loadError = null;
        _touched = false;
        // keep the reorder's person only if it still exists
        final match = sets.where((s) => s.id == _personId).toList();
        if (match.isNotEmpty) {
          _savedM = match.first.measurements;
          // a reorder uses the person's current sizes: children grow
          if (widget.reorderFrom != null) _m = _savedM!;
        } else if (widget.reorderFrom != null) {
          // the person was deleted since: offer to save them again
          _personId = _kNewPerson;
          _newLabel.text = _wearer;
        } else if (!_isEdit) {
          _personId = sets.isEmpty ? _kNewPerson : null;
        }
        // a reorder (or a tailor picked from the list) keeps its tailor only
        // if they still take orders
        if (!_isEdit && _shop != null) {
          final open = shops.where((s) => s.tailorId == _shop!.tailorId).toList();
          _shop = open.isEmpty ? null : open.first;
          // the freshly loaded shop has its current colours and prices
          _fitDesignToShop(fromEarlierOrder: widget.reorderFrom != null);
        }
        // the tailor picked beforehand closed meanwhile: bring the step back
        if (widget.tailor != null && _shop == null && !_steps.contains('tailor')) {
          _steps = [..._steps]..insert(_steps.indexOf('design'), 'tailor');
          _tailorGone = true;
        }
      });
      _room.show(_m, _d);
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  @override
  void dispose() {
    _room.dispose();
    _notes.dispose();
    _newLabel.dispose();
    super.dispose();
  }

  String get _stepName => _steps[_step];

  /// Where a saved person goes straight to, their sizes being on file.
  int get _afterBody => _steps.indexOf('body') + 1;

  // ------------------------------------------------------------ choices
  void _choosePerson(MeasurementSet s) {
    Haptics.select();
    setState(() {
      _personId = s.id;
      _wearer = s.label;
      _m = s.measurements;
      _savedM = s.measurements;
      _touched = false;
    });
    _room.show(_m, _d);
    // saved sizes are already known: skip the body step
    _next();
  }

  void _chooseNewPerson() {
    Haptics.select();
    setState(() {
      _personId = _kNewPerson;
      _savedM = null;
    });
  }

  void _setMeasure(String key, double v) {
    setState(() {
      _m = _m.withValue(key, v);
      _touched = true;
      _changed = true;
    });
    _room.show(_m, _d);
  }

  void _setDesign(JalabiyaDesign d) {
    setState(() {
      _d = d;
      _changed = true;
    });
    _room.show(_m, _d);
  }

  /// Keeps the cloth and thread to what [_shop] offers, with its current
  /// name and price. A colour the shop no longer offers becomes its first
  /// one; [fromEarlierOrder] says the customer had chosen it, so we tell them.
  void _fitDesignToShop({bool fromEarlierOrder = false}) {
    final shop = _shop;
    if (shop == null) return;
    Swatch fit(Swatch current, List<Swatch> offered) {
      final same = offered.where((s) => s.id == current.id).firstOrNull;
      if (same == null && fromEarlierOrder) _colourReplaced = true;
      return same ?? offered.first;
    }

    _d = _d.copyWith(
      cloth: fit(_d.cloth, shop.offeredCloths),
      thread: fit(_d.thread, shop.offeredThreads),
    );
  }

  void _chooseShop(TailorShop s) {
    if (_shop?.tailorId != s.tailorId) Haptics.select();
    setState(() {
      _shop = s;
      _fitDesignToShop();
    });
    _room.show(_m, _d);
  }

  void _markSize(String key, bool ok) {
    setState(() => ok ? _badSizes.remove(key) : _badSizes.add(key));
  }

  /// Only offer to overwrite saved sizes when the customer changed them here.
  bool get _sizesChanged => _touched && _savedM != null && _savedM != _m;

  // ------------------------------------------------------------ stepping
  String? _blocker() {
    switch (_stepName) {
      case 'person':
        if (_personId == null) return context.tr('compose.pickPerson');
        if (_personId == _kNewPerson && _newLabel.text.trim().isEmpty) {
          return context.tr('compose.nameNewPerson');
        }
        return null;
      case 'tailor':
        return _shop == null ? context.tr('compose.pickTailor') : null;
      case 'body':
      case 'design':
        return _badSizes.isEmpty ? null : context.tr('measure.fixFirst');
    }
    return null;
  }

  void _goTo(int i) {
    final name = _steps[i];
    setState(() {
      _forward = i > _step;
      _step = i;
      _badSizes.clear(); // a new step builds its boxes afresh
      if (name == 'body' || name == 'person') _skippedBody = false;
    });
    _room.setView(name == 'body' ? 'body' : 'cloth');
    _room.focus(null);
    _room.setPaused(name == 'tailor' || name == 'review');
  }

  void _next() {
    final b = _blocker();
    if (b != null) {
      showSnack(context, b, error: true);
      return;
    }
    Haptics.tap();
    if (_stepName == 'person' && _personId == _kNewPerson) {
      _wearer = _newLabel.text.trim();
    }
    if (_stepName == 'person' && _personId != _kNewPerson) {
      // a saved person: their sizes are on file, skip the body step
      _goTo(_afterBody);
      setState(() => _skippedBody = true);
      return;
    }
    if (_step < _steps.length - 1) _goTo(_step + 1);
  }

  void _back() {
    Haptics.select();
    if (_step == _afterBody && _skippedBody) {
      _goTo(_steps.indexOf('person'));
    } else if (_step > 0) {
      _goTo(_step - 1);
    } else {
      _leave();
    }
  }

  /// Leaving from the first step: ask first if sizes, design, notes or
  /// quantity were changed, so a stray back gesture never loses the work.
  Future<void> _leave() async {
    if (!_changed || await confirmDiscard(context)) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  // ------------------------------------------------------------ submit
  Future<void> _submit() async {
    final session = context.read<Session>();
    if (!session.profileComplete) {
      showSnack(context, context.tr('err.PROFILE_INCOMPLETE'), error: true);
      return;
    }
    setState(() => _busy = true);
    final repo = context.read<Repository>();
    final uid = session.user!.id;
    try {
      if (!await requireOnline(context) || !mounted) return;
      // 1. keep the person's saved sizes in step, if they asked us to
      String? setId = _personId == _kNewPerson ? null : _personId;
      if (_personId == _kNewPerson && _saveToPerson) {
        final created = await repo.createMeasurementSet(uid, _wearer, _newRelation, _m);
        setId = created.id;
        _personId = created.id;
        _savedM = _m;
      } else if (setId != null && _sizesChanged && _saveToPerson) {
        final saved = (_sets ?? []).where((s) => s.id == setId).toList();
        if (saved.isNotEmpty) {
          await repo.updateMeasurementSet(setId, saved.first.label, saved.first.relation, _m);
          _savedM = _m;
        }
      }

      // 2. the order itself
      final notes = _notes.text.trim().isEmpty ? null : _notes.text.trim();
      if (_isEdit) {
        await repo.updateOrder(
          orderId: widget.editing!.id,
          wearer: _wearer,
          measurements: _m,
          design: _d,
          quantity: _quantity,
          notes: notes,
        );
        if (!mounted) return;
        showSnack(context, context.tr('compose.updated'));
        Navigator.of(context).pop();
      } else {
        final id = await repo.submitOrder(
          tailorId: _shop!.tailorId,
          measurementSetId: setId,
          wearer: _wearer,
          measurements: _m,
          design: _d,
          quantity: _quantity,
          notes: notes,
        );
        if (!mounted) return;
        Haptics.success();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => OrderDetailScreen(orderId: id, justSent: true)),
        );
      }
    } catch (e) {
      if (mounted) showError(context, e, onRetry: _submit);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ------------------------------------------------------------ build
  @override
  Widget build(BuildContext context) {
    final unit = context.watch<Session>().unit;
    final h = MediaQuery.of(context).size.height;
    final showStage = _stepName == 'person' || _stepName == 'body' || _stepName == 'design';
    final stageHeight = showStage ? (h * 0.38).clamp(230.0, 420.0).toDouble() : 0.0;
    final last = _step == _steps.length - 1;

    return PopScope(
      canPop: _step == 0 && !_changed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr(_isEdit ? 'compose.editTitle' : 'compose.title')),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(40),
            child: _StepStrip(
              labels: [for (final s in _steps) context.tr('compose.step.$s')],
              current: _step,
              onTap: (i) {
                if (i < _step) _goTo(i);
              },
            ),
          ),
        ),
        body: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              height: stageHeight,
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topCenter,
                  minHeight: 230,
                  maxHeight: (h * 0.38).clamp(230.0, 420.0).toDouble(),
                  child: FittingRoomView(controller: _room),
                ),
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 300),
                switchInCurve: Motion.curve,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, a) {
                  // new steps come in from the side we are heading to
                  final incoming = child.key == ValueKey(_step);
                  final dir =
                      (_forward == incoming ? 1.0 : -1.0) * (Directionality.of(context) == TextDirection.rtl ? -1 : 1);
                  return FadeTransition(
                    opacity: a,
                    child: SlideTransition(
                      position: Tween(begin: Offset(0.08 * dir, 0), end: Offset.zero).animate(a),
                      child: child,
                    ),
                  );
                },
                child: KeyedSubtree(key: ValueKey(_step), child: _stepBody(context, unit)),
              ),
            ),
          ],
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_shop != null && (_stepName == 'design' || _stepName == 'review'))
              _EstimateBar(shop: _shop!, design: _d, quantity: _quantity),
            _actions(last),
          ],
        ),
      ),
    );
  }

  Widget _actions(bool last) {
    return BottomActions(children: [
      OutlinedButton(
        onPressed: _busy ? null : _back,
        child: Text(context.tr(_step == 0 ? 'action.cancel' : 'action.back')),
      ),
      last
          ? BusyButton(
              label: context.tr(_isEdit ? 'compose.sendChanges' : 'compose.send'),
              icon: Icons.send_rounded,
              busy: _busy,
              onPressed: _submit,
            )
          : FilledButton(
              onPressed: _next,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(context.tr('action.next')),
                  const SizedBox(width: 6),
                  const Icon(Icons.arrow_forward_rounded, size: 18),
                ],
              ),
            ),
    ]);
  }

  Widget _stepBody(BuildContext context, LengthUnit unit) {
    if (_sets == null) {
      if (_loadError != null) {
        return ErrorView(error: _loadError!, onRetry: _loadData);
      }
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: Palette.nile));
    }
    final Widget content;
    switch (_stepName) {
      case 'person':
        content = _personStep(context, unit);
        break;
      case 'body':
        content = _bodyStep(context, unit);
        break;
      case 'design':
        content = _designStep(context, unit);
        break;
      case 'tailor':
        content = _tailorStep(context);
        break;
      default:
        content = _reviewStep(context, unit);
    }
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
      children: [
        if (_skippedBody && _step == _afterBody) _usingSavedBanner(context),
        content,
      ],
    );
  }

  Widget _usingSavedBanner(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Panel(
        color: Palette.nileSoft,
        borderColor: Palette.nileSoft,
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline_rounded, color: Palette.nile, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.tr('compose.usingSaved', {'name': _wearer}),
                style: const TextStyle(fontSize: 13.5),
              ),
            ),
            TextButton(
              onPressed: () => _goTo(_steps.indexOf('body')),
              child: Text(context.tr('compose.adjustSizes')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _personStep(BuildContext context, LengthUnit unit) {
    final sets = _sets!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_tailorGone)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: NoticeBanner(tone: BannerTone.warn, text: context.tr('compose.tailorGone')),
          )
        else if (widget.tailor != null && _shop != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Panel(
              color: Palette.goldSoft,
              borderColor: Palette.goldSoft,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.content_cut_rounded, size: 20, color: Palette.goldInk),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.tr('compose.tailorChosen', {'name': _shop!.shopName}),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        SectionTitle(context.tr('compose.whoTitle'), subtitle: context.tr('compose.whoBody')),
        for (final s in sets)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _SelectCard(
              selected: _personId == s.id,
              onTap: () => _choosePerson(s),
              title: s.label,
              subtitle: '${context.tr('relation.${s.relation}')} · '
                  '${context.tr('m.chest')} ${formatLength(s.measurements.chest, unit)} · '
                  '${context.tr('m.height')} ${formatLength(s.measurements.height, unit)}',
              leading: Icons.person_outline_rounded,
            ),
          ),
        _SelectCard(
          selected: _personId == _kNewPerson,
          onTap: _chooseNewPerson,
          title: context.tr('compose.someoneNew'),
          subtitle: context.tr('compose.someoneNewBody'),
          leading: Icons.person_add_alt_1_outlined,
        ),
        if (_personId == _kNewPerson) ...[
          const SizedBox(height: 14),
          TextField(
            controller: _newLabel,
            maxLength: 60,
            onChanged: (_) => setState(() {}),
            decoration: field(
              labelText: context.tr('family.label'),
              hintText: context.tr('family.labelHint'),
            ),
          ),
          ChoiceRow(
            values: MeasurementSet.relations,
            selected: _newRelation,
            label: (v) => context.tr('relation.$v'),
            onSelected: (v) => setState(() => _newRelation = v),
          ),
        ],
      ],
    );
  }

  Widget _bodyStep(BuildContext context, LengthUnit unit) {
    final canSave = _personId == _kNewPerson || _sizesChanged;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          context.tr('compose.bodyTitle', {'name': _wearer}),
          subtitle: context.tr('measure.subtitle'),
        ),
        for (final s in Measurements.specs)
          MeasureField(
            label: context.tr('m.${s.key}'),
            tip: context.tr('tip.${s.key}'),
            valueCm: _m.valueOf(s.key),
            minCm: s.min,
            maxCm: s.max,
            stepCm: s.step,
            unit: unit,
            onChanged: (v) => _setMeasure(s.key, v),
            onFocus: (on) => _room.focus(on ? s.key : null),
            onValidChanged: (ok) => _markSize(s.key, ok),
          ),
        if (canSave && (_personId != null))
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _saveToPerson,
            onChanged: (v) => setState(() => _saveToPerson = v ?? true),
            title: Text(context.tr('compose.saveSizes', {'name': _wearer})),
          ),
      ],
    );
  }

  Widget _designStep(BuildContext context, LengthUnit unit) {
    Widget label(String key) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(context.tr(key), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        );
    final shop = _shop;
    final currency = shop?.currency ?? 'SDG';
    String? extra(Swatch s) => s.price > 0 ? '+${formatMoney(context, s.price, currency)}' : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_colourReplaced)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: NoticeBanner(tone: BannerTone.warn, text: context.tr('compose.colourReplaced')),
          ),
        SectionTitle(
          context.tr('compose.designTitle'),
          subtitle: shop == null
              ? context.tr('compose.designBody')
              : context.tr('compose.designBodyShop', {'name': shop.shopName}),
        ),
        label('d.cloth'),
        SwatchRow(
          swatches: shop?.offeredCloths ?? JalabiyaDesign.cloths,
          selected: _d.cloth.id,
          label: (s) => swatchName(context, 'cloth', s),
          note: extra,
          onSelected: (s) => _setDesign(_d.copyWith(cloth: s)),
        ),
        label('d.cut'),
        ChoiceRow(
          values: JalabiyaDesign.cuts,
          selected: _d.cut,
          label: (v) => context.tr('cut.$v'),
          onSelected: (v) => _setDesign(_d.copyWith(cut: v)),
        ),
        label('d.collar'),
        ChoiceRow(
          values: JalabiyaDesign.collars,
          selected: _d.collar,
          label: (v) => context.tr('collar.$v'),
          onSelected: (v) => _setDesign(_d.copyWith(collar: v)),
        ),
        label('d.emb'),
        ChoiceRow(
          values: JalabiyaDesign.embroideries,
          selected: _d.emb,
          label: (v) => context.tr('emb.$v'),
          onSelected: (v) => _setDesign(_d.copyWith(emb: v)),
        ),
        if (_d.emb != 'none') ...[
          label('d.thread'),
          SwatchRow(
            swatches: shop?.offeredThreads ?? JalabiyaDesign.threads,
            selected: _d.thread.id,
            label: (s) => swatchName(context, 'thread', s),
            note: extra,
            onSelected: (s) => _setDesign(_d.copyWith(thread: s)),
          ),
        ],
        const SizedBox(height: 18),
        MeasureField(
          label: context.tr('d.hem'),
          tip: context.tr('tip.hem'),
          valueCm: _d.hem,
          minCm: JalabiyaDesign.hemMin,
          maxCm: JalabiyaDesign.hemMax,
          stepCm: 1,
          unit: unit,
          onChanged: (v) => _setDesign(_d.copyWith(hem: v.roundToDouble())),
          onFocus: (on) => _room.focus(on ? 'hem' : null),
          onValidChanged: (ok) => _markSize('hem', ok),
        ),
        MeasureField(
          label: context.tr('d.cuff'),
          tip: context.tr('tip.cuff'),
          valueCm: _d.cuff,
          minCm: JalabiyaDesign.cuffMin,
          maxCm: JalabiyaDesign.cuffMax,
          stepCm: 1,
          unit: unit,
          onChanged: (v) => _setDesign(_d.copyWith(cuff: v.roundToDouble())),
          onValidChanged: (ok) => _markSize('cuff', ok),
        ),
      ],
    );
  }

  Widget _tailorStep(BuildContext context) {
    final shops = List<TailorShop>.of(_shops ?? const <TailorShop>[]);
    final myCity = context.read<Session>().profile?.city;
    // same city first, then by name
    shops.sort((a, b) {
      final ac = a.city == myCity ? 0 : 1;
      final bc = b.city == myCity ? 0 : 1;
      if (ac != bc) return ac - bc;
      return a.shopName.compareTo(b.shopName);
    });
    if (shops.isEmpty) {
      return EmptyState(
        icon: Icons.content_cut_rounded,
        title: context.tr('compose.noTailors'),
        body: context.tr('compose.noTailorsBody'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(context.tr('compose.tailorTitle'), subtitle: context.tr('compose.tailorBody')),
        for (final s in shops)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Pressable(
              child: Panel(
                onTap: () => _chooseShop(s),
                flat: false,
                color: _shop?.tailorId == s.tailorId ? Palette.nileSoft : Palette.card,
                borderColor: _shop?.tailorId == s.tailorId ? Palette.nile : Palette.line,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(s.shopName, style: displayStyle(17)),
                        ),
                        Icon(
                          _shop?.tailorId == s.tailorId ? Icons.radio_button_checked : Icons.radio_button_off,
                          color: _shop?.tailorId == s.tailorId ? Palette.nile : Palette.chalk,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(placeLine(context, s.city, s.neighbourhood), style: const TextStyle(color: Palette.muted)),
                    if ((s.bio ?? '').isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(s.bio!, style: const TextStyle(height: 1.5)),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 16,
                      runSpacing: 6,
                      children: [
                        _Fact(Icons.payments_outlined,
                            context.tr('shop.from', {'price': formatMoney(context, s.basePrice, s.currency)})),
                        _Fact(Icons.schedule_rounded, context.tr('shop.ready', {'days': '${s.leadTimeDays}'})),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SwatchStrip(swatches: s.offeredCloths),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _reviewStep(BuildContext context, LengthUnit unit) {
    final profile = context.watch<Session>().profile;
    if (profile == null) return const SizedBox.shrink(); // signed out; the gate closes this screen
    final shop = _shop ?? widget.editing?.shop;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(context.tr('compose.reviewTitle'), subtitle: context.tr('compose.reviewBody')),
        Panel(
          child: Column(
            children: [
              InfoRow(context.tr('compose.for'), _wearer, strong: true),
              if (shop != null) InfoRow(context.tr('compose.tailor'), shop.shopName, strong: true),
              if (shop != null && _d.extrasPrice > 0) ...[
                InfoRow(context.tr('compose.basePrice'), formatMoney(context, shop.basePrice, shop.currency)),
                InfoRow(context.tr('compose.colourExtras'), '+${formatMoney(context, _d.extrasPrice, shop.currency)}'),
              ],
              if (shop != null)
                InfoRow(context.tr('compose.estimate'),
                    formatMoney(context, (shop.basePrice + _d.extrasPrice) * _quantity, shop.currency),
                    strong: _d.extrasPrice > 0),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Expanded(child: Text(context.tr('compose.quantity'), style: const TextStyle(color: Palette.muted))),
                    IconButton(
                      tooltip: context.tr('compose.less'),
                      onPressed: _quantity > 1
                          ? () => setState(() {
                                _quantity--;
                                _changed = true;
                              })
                          : null,
                      icon: const Icon(Icons.remove_circle_outline_rounded),
                    ),
                    Text('$_quantity', style: monoStyle(17)),
                    IconButton(
                      tooltip: context.tr('compose.more'),
                      onPressed: _quantity < 20
                          ? () => setState(() {
                                _quantity++;
                                _changed = true;
                              })
                          : null,
                      icon: const Icon(Icons.add_circle_outline_rounded),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(context.tr('compose.priceNote'), style: const TextStyle(color: Palette.chalk, fontSize: 12.5)),
        SectionTitle(context.tr('order.cutting'), subtitle: context.tr('order.cuttingHint')),
        CuttingListPanel(measurements: _m, design: _d, unit: unit),
        SectionTitle(context.tr('order.design')),
        DesignPanel(design: _d, unit: unit, currency: shop?.currency ?? 'SDG'),
        SectionTitle(context.tr('order.body')),
        BodySizesPanel(measurements: _m, unit: unit),
        SectionTitle(
          context.tr('order.delivery'),
          trailing: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ProfileSetupScreen()),
            ),
            child: Text(context.tr('action.edit')),
          ),
        ),
        DeliveryPanel(
          delivery: Delivery(
            name: profile.fullName,
            phone: profile.phone,
            whatsapp: profile.whatsapp,
            city: profile.city,
            neighbourhood: profile.neighbourhood,
            addressDetails: profile.addressDetails,
          ),
        ),
        SectionTitle(context.tr('order.notes')),
        TextField(
          controller: _notes,
          minLines: 2,
          maxLines: 5,
          maxLength: 500,
          onChanged: (_) => _changed = true,
          decoration: field(hintText: context.tr('compose.notesHint')),
        ),
      ],
    );
  }
}

class _SelectCard extends StatelessWidget {
  const _SelectCard({
    required this.selected,
    required this.onTap,
    required this.title,
    required this.subtitle,
    required this.leading,
  });

  final bool selected;
  final VoidCallback onTap;
  final String title;
  final String subtitle;
  final IconData leading;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      child: Panel(
        onTap: onTap,
        flat: false,
        color: selected ? Palette.nileSoft : Palette.card,
        borderColor: selected ? Palette.nile : Palette.line,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(leading, color: selected ? Palette.nile : Palette.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: Palette.muted, fontSize: 12.5)),
                ],
              ),
            ),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? Palette.nile : Palette.chalk,
            ),
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Palette.goldInk),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      ],
    );
  }
}

/// Numbered steps under the app bar. Earlier steps can be tapped to go back.
class _StepStrip extends StatelessWidget {
  const _StepStrip({required this.labels, required this.current, required this.onTap});

  final List<String> labels;
  final int current;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final fraction = labels.length < 2 ? 1.0 : current / (labels.length - 1);
    return Column(
      children: [
        SizedBox(height: 34, child: _labels(context)),
        // how far along the order is, filling as steps are done
        TweenAnimationBuilder<double>(
          tween: Tween(end: fraction),
          duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 420),
          curve: Motion.curve,
          builder: (context, v, _) => LinearProgressIndicator(
            value: v,
            minHeight: 3,
            color: Palette.gold,
            backgroundColor: Palette.line,
          ),
        ),
      ],
    );
  }

  Widget _labels(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: labels.length,
      separatorBuilder: (_, __) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6),
        child: Center(child: SizedBox(width: 14, child: Divider(color: Palette.line, thickness: 1.2))),
      ),
      itemBuilder: (context, i) {
        final done = i < current;
        final now = i == current;
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => onTap(i),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: Motion.quick,
                  width: now ? 22 : 20,
                  height: now ? 22 : 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done ? Palette.nile : (now ? Palette.gold : Colors.transparent),
                    border: Border.all(color: done || now ? Colors.transparent : Palette.line),
                  ),
                  child: done
                      ? const Icon(Icons.check_rounded, size: 13, color: Colors.white)
                      : Text('${i + 1}', style: monoStyle(11, color: now ? Palette.ink : Palette.muted)),
                ),
                const SizedBox(width: 6),
                Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: now ? FontWeight.w700 : FontWeight.w400,
                    color: now ? Palette.ink : Palette.muted,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The running price under the design and review steps, so each colour
/// choice shows what it costs straight away.
class _EstimateBar extends StatelessWidget {
  const _EstimateBar({required this.shop, required this.design, required this.quantity});

  final TailorShop shop;
  final JalabiyaDesign design;
  final int quantity;

  @override
  Widget build(BuildContext context) {
    final each = shop.basePrice + design.extrasPrice;
    final total = each * quantity;
    return Container(
      color: Palette.goldSoft,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.receipt_long_outlined, size: 20, color: Palette.goldInk),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr('compose.estimate'),
                    style: const TextStyle(color: Palette.goldInk, fontSize: 12, fontWeight: FontWeight.w600)),
                Text(
                  design.extrasPrice > 0
                      ? context.tr('compose.estimateBreakdown', {
                          'base': formatMoney(context, shop.basePrice, shop.currency),
                          'extra': formatMoney(context, design.extrasPrice, shop.currency),
                        })
                      : shop.shopName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Palette.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          AnimatedSwitcher(
            duration: Motion.quick,
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(a),
                child: child,
              ),
            ),
            child: Text(
              formatMoney(context, total, shop.currency),
              key: ValueKey(total),
              style: displayStyle(18),
            ),
          ),
        ],
      ),
    );
  }
}
