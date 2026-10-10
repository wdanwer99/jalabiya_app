import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repository.dart';
import '../../l10n/strings.dart';
import '../../models/design.dart';
import '../../models/measurement_set.dart';
import '../../models/measurements.dart';
import '../../state/session.dart';
import '../../theme/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/fitting_room.dart';
import '../../widgets/measure_field.dart';

/// Create or edit one saved person. Pops `true` when something changed.
class MeasurementEditorScreen extends StatefulWidget {
  const MeasurementEditorScreen({super.key, this.existing, this.initialLabel, this.initialRelation});

  final MeasurementSet? existing;

  /// Prefills used only when creating a new set (e.g. "my sizes" from the profile).
  final String? initialLabel;
  final String? initialRelation;

  @override
  State<MeasurementEditorScreen> createState() => _MeasurementEditorScreenState();
}

class _MeasurementEditorScreenState extends State<MeasurementEditorScreen> {
  final _room = FittingRoomController();
  final _form = GlobalKey<FormState>();
  late final TextEditingController _label;
  late String _relation;
  late Measurements _m;
  bool _busy = false;

  /// Size boxes holding a number that was not accepted.
  final _badSizes = <String>{};

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _label = TextEditingController(text: e?.label ?? widget.initialLabel ?? '');
    _relation = e?.relation ?? widget.initialRelation ?? 'self';
    _m = e?.measurements ?? Measurements.defaults;
    _room.setView('body');
    _room.setUnit(context.read<Session>().unit);
    _room.show(_m, JalabiyaDesign.defaults);
  }

  @override
  void dispose() {
    _label.dispose();
    _room.dispose();
    super.dispose();
  }

  void _set(String key, double v) {
    setState(() => _m = _m.withValue(key, v));
    _room.show(_m, JalabiyaDesign.defaults);
  }

  /// Something differs from what was opened, so leaving would lose it.
  bool get _dirty {
    final e = widget.existing;
    return _label.text.trim() != (e?.label ?? widget.initialLabel ?? '').trim() ||
        _relation != (e?.relation ?? widget.initialRelation ?? 'self') ||
        _m != (e?.measurements ?? Measurements.defaults);
  }

  Future<void> _leave() async {
    if (!_dirty || await confirmDiscard(context)) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _save() async {
    final labelOk = _form.currentState!.validate();
    if (_badSizes.isNotEmpty) {
      showSnack(context, context.tr('measure.fixFirst'), error: true);
      return;
    }
    if (!labelOk) return;
    setState(() => _busy = true);
    final repo = context.read<Repository>();
    final uid = context.read<Session>().user!.id;
    try {
      if (!await requireOnline(context) || !mounted) return;
      if (widget.existing == null) {
        await repo.createMeasurementSet(uid, _label.text, _relation, _m);
      } else {
        await repo.updateMeasurementSet(widget.existing!.id, _label.text, _relation, _m);
      }
      if (!mounted) return;
      showSnack(context, context.tr('family.saved', {'name': _label.text.trim()}));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showError(context, e, onRetry: _save);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmAction(
      context,
      title: context.tr('family.deleteTitle'),
      body: context.tr('family.deleteBody', {'name': widget.existing!.label}),
      confirmLabel: context.tr('action.delete'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      if (!await requireOnline(context) || !mounted) return;
      await context.read<Repository>().deleteMeasurementSet(widget.existing!.id);
      if (!mounted) return;
      showSnack(context, context.tr('family.deleted', {'name': widget.existing!.label}),
          icon: Icons.delete_outline_rounded);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final unit = context.watch<Session>().unit;
    final stageHeight = (MediaQuery.of(context).size.height * 0.36).clamp(240.0, 400.0).toDouble();
    // Saving and deleting pop with Navigator.pop, which skips this guard; only
    // back gestures and the app-bar back arrow come through here.
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr(widget.existing == null ? 'family.newTitle' : 'family.editTitle')),
          actions: [
            if (widget.existing != null)
              IconButton(
                tooltip: context.tr('action.delete'),
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
          ],
        ),
        body: Column(
          children: [
            SizedBox(height: stageHeight, child: FittingRoomView(controller: _room)),
            Expanded(
              child: Form(
                key: _form,
                child: ListView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  children: [
                    TextFormField(
                      controller: _label,
                      maxLength: 60,
                      onChanged: (_) => setState(() {}), // keeps the leave-guard current
                      decoration: field(
                        labelText: context.tr('family.label'),
                        hintText: context.tr('family.labelHint'),
                      ),
                      validator: (v) => (v ?? '').trim().isEmpty ? context.tr('form.required') : null,
                    ),
                    ChoiceRow(
                      values: MeasurementSet.relations,
                      selected: _relation,
                      label: (v) => context.tr('relation.$v'),
                      onSelected: (v) => setState(() => _relation = v),
                    ),
                    SectionTitle(context.tr('measure.title'), subtitle: context.tr('measure.subtitle')),
                    for (final s in Measurements.specs)
                      MeasureField(
                        label: context.tr('m.${s.key}'),
                        tip: context.tr('tip.${s.key}'),
                        valueCm: _m.valueOf(s.key),
                        minCm: s.min,
                        maxCm: s.max,
                        stepCm: s.step,
                        unit: unit,
                        onChanged: (v) => _set(s.key, v),
                        onFocus: (on) => _room.focus(on ? s.key : null),
                        onValidChanged: (ok) => setState(() => ok ? _badSizes.remove(s.key) : _badSizes.add(s.key)),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: BottomActions(children: [
          BusyButton(label: context.tr('action.save'), busy: _busy, onPressed: _save),
        ]),
      ),
    );
  }
}
