import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/strings.dart';
import '../../theme/theme.dart';

/// The app icon, small. Shared by the welcome and auth screens through a
/// Hero, so it glides between them.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: 'brand-mark',
      child: ExcludeSemantics(
        child: Image.asset(
          'assets/icon/logo_app.png',
          width: size,
          height: size,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}

/// Scroll padding for auth fields: when Flutter scrolls the caret into view
/// as the keyboard slides up, it also brings the helper / error text and the
/// strength bar below the field along, in the same motion.
const authFieldScrollPadding = EdgeInsets.fromLTRB(20, 20, 20, 96);

/// Gives a button a subtle press-in when touched.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child});

  final Widget child;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Layout shared by sign in and sign up: a dark header with the brand mark
/// and title, and a paper sheet that slides up holding the form. Children of
/// the sheet fade in one after another. Call [AuthShellState.shake] when the
/// form is rejected.
class AuthShell extends StatefulWidget {
  const AuthShell({super.key, required this.title, required this.subtitle, required this.children});

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  State<AuthShell> createState() => AuthShellState();
}

class AuthShellState extends State<AuthShell> with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _intro =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final AnimationController _shake =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  final _scroll = ScrollController();
  Timer? _focusTimer;

  @override
  void initState() {
    super.initState();
    _intro.forward();
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_scheduleShowFocused);
  }

  /// Keyboard opening or closing changes the window metrics.
  @override
  void didChangeMetrics() => _scheduleShowFocused();

  /// Waits for the keyboard and the folding header to settle, then makes sure
  /// the focused field is in view. Flutter only scrolls the caret into view on
  /// its own, which can leave the label, helper or error text under the keyboard.
  void _scheduleShowFocused() {
    _focusTimer?.cancel();
    _focusTimer = Timer(const Duration(milliseconds: 120), _showFocused);
  }

  void _showFocused() {
    if (!mounted || !_scroll.hasClients) return;
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null || !focused.mounted) return;
    final scrollable = Scrollable.maybeOf(focused);
    if (scrollable == null || scrollable.position != _scroll.position) return;

    // the whole form field (label, input, helper / error), not just the text line
    final target = focused.findAncestorStateOfType<FormFieldState<dynamic>>()?.context ?? focused;
    final box = target.findRenderObject() as RenderBox?;
    final viewport = scrollable.context.findRenderObject() as RenderBox?;
    if (box == null || viewport == null || !box.attached) return;

    const margin = 32.0; // room for the password-strength bar under the field
    final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
    final bottom = top + box.size.height;
    if (top >= margin / 2 && bottom <= viewport.size.height - margin) return;

    Scrollable.ensureVisible(
      target,
      alignment: 0.15,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _intro.value = 1;
  }

  @override
  void dispose() {
    _focusTimer?.cancel();
    FocusManager.instance.removeListener(_scheduleShowFocused);
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    _intro.dispose();
    _shake.dispose();
    super.dispose();
  }

  /// Wiggles the form sideways and buzzes, to say "something here needs fixing".
  void shake() {
    HapticFeedback.mediumImpact();
    if (MediaQuery.disableAnimationsOf(context)) return;
    _shake.forward(from: 0);
  }

  Widget _reveal(int order, Widget child) {
    final start = (0.25 + order * 0.06).clamp(0.0, 0.7);
    final anim = _intro.drive(CurveTween(curve: Interval(start, math.min(1, start + 0.35), curve: Curves.easeOutCubic)));
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: anim.drive(Tween(begin: const Offset(0, 0.25), end: Offset.zero)),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Only narrow MediaQuery lookups here: the keyboard changes viewInsets on
    // every frame while it slides, and a plain MediaQuery.of would rebuild the
    // whole form each of those frames.
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final sheetIn = _intro.drive(CurveTween(curve: const Interval(0, 0.6, curve: Curves.easeOutCubic)));

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      // The glow sits outside the Scaffold so it keeps the full screen size and
      // is painted once, instead of repainting each frame the keyboard resizes the body.
      child: DecoratedBox(
        decoration: const BoxDecoration(color: Palette.ink),
        child: Stack(
          children: [
            const Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: _GlowPainter()))),
            Scaffold(
              backgroundColor: Colors.transparent,
              body: SafeArea(
                bottom: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 24, 0),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                            style: IconButton.styleFrom(
                              backgroundColor: Palette.ink2,
                              foregroundColor: Palette.damur,
                              side: const BorderSide(color: Palette.ink3),
                            ),
                            onPressed: () => Navigator.of(context).maybePop(),
                            icon: const BackButtonIcon(),
                          ),
                          const Spacer(),
                          const BrandMark(),
                        ],
                      ),
                    ),
                    _AuthHeader(title: widget.title, subtitle: widget.subtitle),
                    Expanded(
                      child: SlideTransition(
                        position: sheetIn.drive(Tween(begin: const Offset(0, 0.12), end: Offset.zero)),
                        child: FadeTransition(
                          opacity: sheetIn,
                          child: DecoratedBox(
                            decoration: const BoxDecoration(
                              color: Palette.paper,
                              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                            ),
                            child: ClipRRect(
                              clipBehavior: Clip.hardEdge, // cheaper than anti-aliased clipping
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                              child: AnimatedBuilder(
                                animation: _shake,
                                builder: (context, child) {
                                  final t = _shake.value;
                                  final dx = math.sin(t * math.pi * 5) * 10 * (1 - t);
                                  return Transform.translate(offset: Offset(dx, 0), child: child);
                                },
                                child: ListView(
                                  controller: _scroll,
                                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                                  padding: EdgeInsets.fromLTRB(24, 28, 24, 24 + bottomPad),
                                  children: [
                                    for (var i = 0; i < widget.children.length; i++)
                                      _reveal(i, widget.children[i]),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
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
  }
}

/// Title and subtitle on the dark header. The subtitle folds away while the
/// keyboard is up so the form has room. Kept as its own widget so the
/// per-frame keyboard updates only rebuild these two lines.
class _AuthHeader extends StatelessWidget {
  const _AuthHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      alignment: AlignmentDirectional.topStart,
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, keyboardOpen ? 8 : 24, 24, keyboardOpen ? 16 : 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: displayStyle(28, color: Palette.damur)),
            if (!keyboardOpen) ...[
              const SizedBox(height: 6),
              Text(subtitle, style: const TextStyle(color: Palette.onInkMuted, fontSize: 15.5, height: 1.5)),
            ],
          ],
        ),
      ),
    );
  }
}

class _GlowPainter extends CustomPainter {
  const _GlowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    void glow(Offset c, double r, Color color) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)])
              .createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    glow(Offset(size.width * 0.9, size.height * 0.05), size.width * 0.7, Palette.gold.withValues(alpha: 0.16));
    glow(Offset(size.width * 0.05, size.height * 0.25), size.width * 0.6, Palette.nile.withValues(alpha: 0.22));
  }

  @override
  bool shouldRepaint(_GlowPainter old) => false;
}

/// A small check that pops in at the end of a field once its value looks right.
class ValidMark extends StatelessWidget {
  const ValidMark({super.key, required this.controller, required this.isValid});

  final TextEditingController controller;
  final bool Function(String) isValid;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, v, _) {
        final ok = isValid(v.text);
        return AnimatedScale(
          scale: ok ? 1 : 0,
          duration: const Duration(milliseconds: 260),
          curve: ok ? Curves.easeOutBack : Curves.easeIn,
          child: const Icon(Icons.check_circle_rounded, color: Palette.nile, size: 22),
        );
      },
    );
  }
}

/// Four segments that fill and change colour as the password gets stronger.
class PasswordStrength extends StatelessWidget {
  const PasswordStrength({super.key, required this.controller});

  final TextEditingController controller;

  static int score(String p) {
    if (p.isEmpty) return 0;
    if (p.length < 8) return 1; // below the minimum the form accepts
    var s = 2;
    if (RegExp(r'[0-9]').hasMatch(p) && RegExp(r'[A-Za-z؀-ۿ]').hasMatch(p)) s++;
    if (p.length >= 12 || RegExp(r'[^A-Za-z0-9؀-ۿ]').hasMatch(p)) s++;
    return s;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, v, _) {
        final s = score(v.text);
        final color = switch (s) { 1 => Palette.henna, 2 => Palette.goldInk, 3 => Palette.nile, _ => Palette.nile };
        final label = switch (s) {
          1 => context.tr('auth.pw.weak'),
          2 => context.tr('auth.pw.fair'),
          3 => context.tr('auth.pw.good'),
          4 => context.tr('auth.pw.strong'),
          _ => '',
        };
        return AnimatedOpacity(
          opacity: s == 0 ? 0 : 1,
          duration: const Duration(milliseconds: 200),
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                for (var i = 0; i < 4; i++) ...[
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOut,
                      height: 5,
                      decoration: BoxDecoration(
                        color: i < s ? color : Palette.line,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  if (i < 3) const SizedBox(width: 6),
                ],
                const SizedBox(width: 12),
                SizedBox(
                  width: 64,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Text(label,
                        key: ValueKey(label),
                        style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w600)),
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

/// A tape-measure bar showing how much of the form is filled in correctly.
class FormProgress extends StatelessWidget {
  const FormProgress({super.key, required this.listenable, required this.progress});

  final Listenable listenable;
  final double Function() progress;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) {
        final p = progress();
        return Row(
          children: [
            Expanded(
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: p),
                duration: const Duration(milliseconds: 380),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: v,
                    minHeight: 6,
                    backgroundColor: Palette.line,
                    color: p >= 1 ? Palette.nile : Palette.gold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text('${(p * 100).round()}%', style: monoStyle(12, color: p >= 1 ? Palette.nile : Palette.goldInk)),
          ],
        );
      },
    );
  }
}

/// Eye toggle for password fields; the icon flips with a quick rotation.
class PeekButton extends StatelessWidget {
  const PeekButton({super.key, required this.hidden, required this.onToggle});

  final bool hidden;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: context.tr(hidden ? 'auth.showPassword' : 'auth.hidePassword'),
      onPressed: () {
        HapticFeedback.selectionClick();
        onToggle();
      },
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, a) => RotationTransition(
          turns: a.drive(Tween(begin: 0.75, end: 1)),
          child: FadeTransition(opacity: a, child: child),
        ),
        child: Icon(
          hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          key: ValueKey(hidden),
        ),
      ),
    );
  }
}
