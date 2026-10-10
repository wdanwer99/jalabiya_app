import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';
import '../theme/theme.dart';
import '../util/format.dart';

/// One measurement: the label, a box to type the exact number, fine −/+
/// buttons for half-centimetre corrections, and a slider for big moves.
///
/// A number that can't be used is never taken silently: the box turns red,
/// says what is wrong and which value is still kept, and offers a way out.
class MeasureField extends StatefulWidget {
  const MeasureField({
    super.key,
    required this.label,
    required this.valueCm,
    required this.minCm,
    required this.maxCm,
    required this.stepCm,
    required this.unit,
    required this.onChanged,
    this.tip,
    this.onFocus,
    this.onValidChanged,
  });

  final String label;
  final double valueCm;
  final double minCm;
  final double maxCm;
  final double stepCm;
  final LengthUnit unit;
  final ValueChanged<double> onChanged;
  final String? tip;

  /// true while the customer is adjusting this value (to light it up in 3D).
  final ValueChanged<bool>? onFocus;

  /// false while the box holds something that was not accepted, so the
  /// screen can stop the customer from moving on with it.
  final ValueChanged<bool>? onValidChanged;

  @override
  State<MeasureField> createState() => _MeasureFieldState();
}

/// What is wrong with the typed text.
enum _Problem { notNumber, tooSmall, tooLarge }

class _MeasureFieldState extends State<MeasureField> with SingleTickerProviderStateMixin {
  late final TextEditingController _ctrl;
  final _focus = FocusNode();
  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  Timer? _wait;
  _Problem? _problem;

  /// When the number fits once read in the other unit (inches typed in cm
  /// mode, or the reverse), that value in cm.
  double? _otherUnitCm;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _display());
    _focus.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(MeasureField old) {
    super.didUpdateWidget(old);
    // Slider and −/+ moves show up in the box; while typing, leave it alone so
    // snapping never rewrites what the customer is in the middle of entering.
    if (!_focus.hasFocus && (old.valueCm != widget.valueCm || old.unit != widget.unit)) {
      _ctrl.text = _display();
      // a good value was set another way: whatever was wrong is gone. This
      // runs during a build, so the screen hears about it after the frame.
      if (_problem != null) {
        _problem = null;
        _otherUnitCm = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onValidChanged?.call(true);
        });
      }
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _ctrl.dispose();
    _shake.dispose();
    _wait?.cancel();
    super.dispose();
  }

  String get _unitLabel => widget.unit == LengthUnit.cm ? 'cm' : 'in';

  String _display() => trimNumber(toUnit(widget.valueCm, widget.unit));

  double _clamp(double v) => v < widget.minCm ? widget.minCm : (v > widget.maxCm ? widget.maxCm : v);

  void _onFocusChange() {
    if (!mounted) return;
    widget.onFocus?.call(_focus.hasFocus);
    if (!_focus.hasFocus) _settle();
  }

  /// What is wrong with [text]. A too-small number only counts once [done]
  /// (the box was left, or typing paused): "1" on the way to "175" is not a
  /// mistake yet. A too-large one or letters count straight away.
  _Problem? _check(String text, {required bool done}) {
    if (text.trim().isEmpty) return done ? _Problem.notNumber : null;
    final v = parseLooseNumber(text);
    if (v == null) return _Problem.notNumber;
    if (v > toUnit(widget.maxCm, widget.unit) + 0.001) return _Problem.tooLarge;
    if (v < toUnit(widget.minCm, widget.unit) - 0.001) return done ? _Problem.tooSmall : null;
    return null;
  }

  /// The value in cm if the typed number fits when read in the other unit.
  double? _otherUnit(_Problem? p) {
    if (p != _Problem.tooSmall && p != _Problem.tooLarge) return null;
    final v = parseLooseNumber(_ctrl.text);
    if (v == null) return null;
    final cm = widget.unit == LengthUnit.cm ? v * cmPerInch : v;
    return cm >= widget.minCm && cm <= widget.maxCm ? cm : null;
  }

  void _setProblem(_Problem? p) {
    final other = _otherUnit(p);
    if (p == _problem && other == _otherUnitCm) return;
    final wasValid = _problem == null;
    setState(() {
      _problem = p;
      _otherUnitCm = other;
    });
    if (wasValid != (p == null)) widget.onValidChanged?.call(p == null);
  }

  /// Live update while typing, for numbers in range only.
  void _onTyped(String text) {
    _wait?.cancel();
    final v = parseLooseNumber(text);
    if (v != null && _check(text, done: true) == null) {
      widget.onChanged(_clamp(fromUnit(v, widget.unit)));
    }
    final p = _check(text, done: false);
    _setProblem(p);
    // a pause in typing makes a too-small number count
    if (p == null && text.trim().isNotEmpty) {
      _wait = Timer(const Duration(milliseconds: 1200), () {
        if (mounted && _focus.hasFocus) _setProblem(_check(_ctrl.text, done: true));
      });
    }
  }

  /// On leaving the box: a good entry snaps to the kept value; a bad one
  /// stays in the box, in red, so the customer sees it was not taken.
  void _settle() {
    _wait?.cancel();
    final p = _check(_ctrl.text, done: true);
    if (p == null) {
      _setProblem(null);
      setState(() => _ctrl.text = _display());
      return;
    }
    _setProblem(p);
    HapticFeedback.heavyImpact();
    if (!(MediaQuery.maybeDisableAnimationsOf(context) ?? false)) _shake.forward(from: 0);
  }

  /// Puts back the last accepted value.
  void _undo() {
    _ctrl.text = _display();
    _setProblem(null);
  }

  /// Takes the number as the unit it was probably meant in.
  void _useOtherUnit() {
    final cm = _otherUnitCm;
    if (cm == null) return;
    widget.onChanged(_clamp(cm));
    _ctrl.text = trimNumber(toUnit(_clamp(cm), widget.unit));
    _setProblem(null);
  }

  void _nudge(double delta) {
    _focus.unfocus();
    widget.onFocus?.call(true);
    widget.onChanged(_clamp(widget.valueCm + delta));
  }

  void _showTip(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Palette.paper,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.label, style: displayStyle(19)),
            const SizedBox(height: 10),
            Text(widget.tip!, style: const TextStyle(height: 1.6, fontSize: 15)),
          ],
        ),
      ),
    );
  }

  String _message(BuildContext context) {
    final lo = '${trimNumber(toUnit(widget.minCm, widget.unit))} $_unitLabel';
    final hi = '${trimNumber(toUnit(widget.maxCm, widget.unit))} $_unitLabel';
    final what = switch (_problem!) {
      _Problem.notNumber => context.tr('measure.err.notNumber'),
      _Problem.tooSmall => context.tr('measure.err.tooSmall', {'min': lo, 'max': hi}),
      _Problem.tooLarge => context.tr('measure.err.tooLarge', {'min': lo, 'max': hi}),
    };
    if (_focus.hasFocus) return what;
    return '$what ${context.tr('measure.err.kept', {'value': '${_display()} $_unitLabel'})}';
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final divisions = ((w.maxCm - w.minCm) / w.stepCm).round();
    final hasError = _problem != null;
    return AnimatedBuilder(
      animation: _shake,
      builder: (context, child) => Transform.translate(
        // a short side-to-side shake that fades out
        offset: Offset(math.sin(_shake.value * math.pi * 6) * 8 * (1 - _shake.value), 0),
        child: child,
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    w.label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: hasError ? Palette.henna : Palette.ink,
                    ),
                  ),
                ),
                if (w.tip != null)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: context.tr('measure.howTo'),
                    icon: const Icon(Icons.help_outline_rounded, size: 19, color: Palette.chalk),
                    onPressed: () => _showTip(context),
                  ),
                const Spacer(),
                SizedBox(
                  width: 112,
                  child: TextField(
                    controller: _ctrl,
                    focusNode: _focus,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.done,
                    textAlign: TextAlign.center,
                    style: monoStyle(15, color: hasError ? Palette.henna : Palette.goldInk, weight: FontWeight.w600),
                    onChanged: _onTyped,
                    onSubmitted: (_) => _focus.unfocus(),
                    onTapOutside: (_) => _focus.unfocus(),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: hasError ? Palette.hennaSoft : Palette.goldSoft,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                      suffixText: _unitLabel,
                      suffixStyle: TextStyle(color: hasError ? Palette.henna : Palette.goldInk, fontSize: 12.5),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: hasError ? Palette.henna : Palette.gold, width: 1.5),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: hasError ? const BorderSide(color: Palette.henna, width: 1.5) : BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              alignment: Alignment.topCenter,
              child: hasError ? _errorBox(context) : const SizedBox(width: double.infinity),
            ),
            Row(
              children: [
                _StepButton(icon: Icons.remove_rounded, onTap: w.valueCm > w.minCm ? () => _nudge(-w.stepCm) : null),
                Expanded(
                  child: Slider(
                    value: _clamp(w.valueCm),
                    min: w.minCm,
                    max: w.maxCm,
                    divisions: divisions > 0 ? divisions : null,
                    onChangeStart: (_) {
                      _focus.unfocus();
                      w.onFocus?.call(true);
                    },
                    onChangeEnd: (_) => w.onFocus?.call(false),
                    onChanged: w.onChanged,
                  ),
                ),
                _StepButton(icon: Icons.add_rounded, onTap: w.valueCm < w.maxCm ? () => _nudge(w.stepCm) : null),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The red note under the box: what is wrong, what is kept, and a one-tap
  /// way out (undo, or read the number in the unit it was probably meant in).
  Widget _errorBox(BuildContext context) {
    final other = _otherUnitCm;
    final String? otherText;
    if (other == null) {
      otherText = null;
    } else if (widget.unit == LengthUnit.cm) {
      otherText = context.tr('measure.err.wasInches', {
        'typed': _ctrl.text.trim(),
        'value': '${trimNumber(other)} cm',
      });
    } else {
      otherText = context.tr('measure.err.wasCm', {
        'typed': _ctrl.text.trim(),
        'value': '${trimNumber(toUnit(other, LengthUnit.inch))} in',
      });
    }
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 4, 8),
        decoration: BoxDecoration(color: Palette.hennaSoft, borderRadius: BorderRadius.circular(10)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(Icons.error_outline_rounded, size: 18, color: Palette.henna),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_message(context), style: const TextStyle(color: Palette.henna, fontSize: 12.5, height: 1.4)),
                  if (otherText != null)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: Palette.nile,
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: _useOtherUnit,
                      icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                      label: Text(otherText),
                    ),
                ],
              ),
            ),
            if (!_focus.hasFocus)
              IconButton(
                tooltip: context.tr('measure.err.undo'),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.undo_rounded, size: 18, color: Palette.henna),
                onPressed: _undo,
              ),
          ],
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(40, 40), shape: const CircleBorder()),
        onPressed: onTap,
        child: Icon(icon, size: 20),
      ),
    );
  }
}
