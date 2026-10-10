import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../l10n/strings.dart';
import '../../state/session.dart';
import '../../theme/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/sudani_man.dart';
import 'auth_widgets.dart';
import 'sign_in_screen.dart';
import 'sign_up_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> with TickerProviderStateMixin {
  static const _stepCount = 3;
  static const _autoAdvance = Duration(seconds: 4);

  /// Staggered entrance of the whole screen.
  late final AnimationController _intro =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  /// Slow loop driving the background glow and the gold shimmer on the name.
  late final AnimationController _ambient =
      AnimationController(vsync: this, duration: const Duration(seconds: 14));

  /// The man from the icon arriving: 'imma, shawl, cane, glasses.
  late final AnimationController _figure =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));

  /// One lift-and-tap of his cane when he is touched.
  late final AnimationController _caneTap =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  final _pages = PageController(viewportFraction: 0.92);
  Timer? _timer;
  int _step = 0;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _intro.forward();
    _figure.forward();
    _ambient.repeat();
    _restartTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _intro.value = 1;
      _figure.value = 1;
      _ambient.stop();
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pages.dispose();
    _intro.dispose();
    _ambient.dispose();
    _figure.dispose();
    _caneTap.dispose();
    super.dispose();
  }

  void _tapMan() {
    HapticFeedback.lightImpact();
    if (_reduceMotion || _caneTap.isAnimating) return;
    _caneTap.forward(from: 0);
    // a firmer tick as the cane meets the ground
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) HapticFeedback.mediumImpact();
    });
  }

  void _restartTimer() {
    _timer?.cancel();
    if (_reduceMotion) return;
    _timer = Timer.periodic(_autoAdvance, (_) {
      // skip while sign in / sign up is on top: this screen stays alive underneath
      if (!_pages.hasClients || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
      _goTo((_step + 1) % _stepCount);
    });
  }

  void _goTo(int index) {
    _pages.animateToPage(index, duration: const Duration(milliseconds: 520), curve: Curves.easeOutCubic);
  }

  /// Fades and lifts [child] into place; [order] staggers it after earlier items.
  Widget _reveal(int order, Widget child) {
    final start = (order * 0.09).clamp(0.0, 0.6);
    final anim = _intro.drive(CurveTween(curve: Interval(start, start + 0.4, curve: Curves.easeOutCubic)));
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: anim.drive(Tween(begin: const Offset(0, 0.18), end: Offset.zero)),
        child: child,
      ),
    );
  }

  /// The man from the icon stands at the end side, turned towards the name
  /// beside him in either reading direction; he takes whatever height the
  /// screen can spare.
  Widget _hero({required double heroHeight}) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return SizedBox(
      height: heroHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          PositionedDirectional(
            end: -12,
            top: 0,
            bottom: 0,
            width: heroHeight * 0.62,
            child: SudaniMan(
              entrance: _figure,
              ambient: _ambient,
              tap: _caneTap,
              still: _reduceMotion,
              mirror: !rtl,
              onTap: _tapMan,
            ),
          ),
          PositionedDirectional(
            start: 0,
            bottom: 0,
            child: _reveal(1, _ShimmerName(animation: _ambient, still: _reduceMotion)),
          ),
        ],
      ),
    );
  }

  void _push(Widget screen) {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final lang = session.locale.languageCode;
    final steps = [
      (Icons.straighten_rounded, context.tr('welcome.s1')),
      (Icons.checkroom_rounded, context.tr('welcome.s2')),
      (Icons.content_cut_rounded, context.tr('welcome.s3')),
    ];

    return Scaffold(
      backgroundColor: Palette.ink,
      body: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(painter: _AmbientPainter(_ambient)),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: box.maxHeight),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _reveal(
                            0,
                            Row(
                              children: [
                                const BrandMark(),
                                const Spacer(),
                                SegmentBar(
                                  dark: true,
                                  values: const ['ar', 'en'],
                                  selected: lang,
                                  label: (v) => v == 'ar' ? 'عربي' : 'English',
                                  onSelected: (v) {
                                    HapticFeedback.selectionClick();
                                    session.setLocale(v);
                                  },
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          _hero(heroHeight: (box.maxHeight - 580).clamp(150.0, 280.0)),
                          const SizedBox(height: 6),
                          _reveal(
                            2,
                            Text(context.tr('welcome.title'),
                                style: displayStyle(24, color: Palette.gold, weight: FontWeight.w400)),
                          ),
                          const SizedBox(height: 14),
                          _reveal(
                            3,
                            Text(
                              context.tr('welcome.body'),
                              style: const TextStyle(color: Palette.onInkMuted, fontSize: 16, height: 1.65),
                            ),
                          ),
                          const SizedBox(height: 28),
                          _reveal(
                            4,
                            _TapeRuler(
                              controller: _pages,
                              count: _stepCount,
                              current: _step,
                              onSelect: (i) {
                                HapticFeedback.selectionClick();
                                _goTo(i);
                                _restartTimer();
                              },
                            ),
                          ),
                          const SizedBox(height: 14),
                          _reveal(
                            5,
                            SizedBox(
                              height: 132,
                              child: NotificationListener<ScrollStartNotification>(
                                // a finger on the carousel pauses auto-advance until it settles
                                onNotification: (n) {
                                  if (n.dragDetails != null) _restartTimer();
                                  return false;
                                },
                                child: PageView.builder(
                                  controller: _pages,
                                  padEnds: false,
                                  itemCount: steps.length,
                                  onPageChanged: (i) => setState(() => _step = i),
                                  itemBuilder: (context, i) => _StepCard(
                                    controller: _pages,
                                    index: i,
                                    total: steps.length,
                                    icon: steps[i].$1,
                                    text: steps[i].$2,
                                    onTap: () {
                                      HapticFeedback.selectionClick();
                                      _goTo(i);
                                      _restartTimer();
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const Spacer(flex: 3),
                          const SizedBox(height: 24),
                          _reveal(
                            6,
                            PressScale(
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: Palette.gold,
                                  foregroundColor: Palette.ink,
                                  minimumSize: const Size.fromHeight(56),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  elevation: 0,
                                ),
                                onPressed: () => _push(const SignUpScreen()),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(context.tr('welcome.create')),
                                    const SizedBox(width: 10),
                                    const Icon(Icons.arrow_forward_rounded, size: 20),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _reveal(
                            7,
                            PressScale(
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Palette.damur,
                                  minimumSize: const Size.fromHeight(56),
                                  backgroundColor: Palette.ink2.withValues(alpha: 0.6),
                                  side: const BorderSide(color: Palette.ink3, width: 1.2),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                                onPressed: () => _push(const SignInScreen()),
                                child: Text(context.tr('welcome.signIn')),
                              ),
                            ),
                          ),
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
    );
  }
}

/// The app name with a gold light sweeping across it now and then.
class _ShimmerName extends StatelessWidget {
  const _ShimmerName({required this.animation, required this.still});

  final Animation<double> animation;
  final bool still;

  @override
  Widget build(BuildContext context) {
    final text = Text('جلابية', style: displayStyle(60, color: Colors.white));
    if (still) return Text('جلابية', style: displayStyle(60, color: Palette.damur));
    return AnimatedBuilder(
      animation: animation,
      child: text,
      builder: (context, child) {
        // sweep during the first part of each cycle, then rest
        final p = (animation.value * 3) % 1.0;
        final x = p < 0.45 ? -1.0 + (p / 0.45) * 3.0 : 2.0;
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment(x - 1, -0.3),
            end: Alignment(x + 1, 0.3),
            colors: const [Palette.damur, Color(0xFFF3DA97), Palette.damur],
            stops: const [0.3, 0.5, 0.7],
          ).createShader(rect),
          child: child,
        );
      },
    );
  }
}

/// A measuring tape: tick marks with a gold fill that follows the carousel.
/// Tap a section to jump to that step.
class _TapeRuler extends StatelessWidget {
  const _TapeRuler({required this.controller, required this.count, required this.current, required this.onSelect});

  final PageController controller;
  final int count;
  final int current;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Semantics(
      label: '${current + 1} / $count',
      // fixed height outside the LayoutBuilder keeps the parent's IntrinsicHeight happy
      child: SizedBox(
        height: 44, // full touch target, painted tape sits inside
        child: LayoutBuilder(
          builder: (context, box) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) {
              var f = d.localPosition.dx / box.maxWidth;
              if (rtl) f = 1 - f;
              onSelect((f * count).floor().clamp(0, count - 1));
            },
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                final page = controller.hasClients && controller.position.haveDimensions
                    ? controller.page ?? current.toDouble()
                    : current.toDouble();
                return CustomPaint(
                  painter: _TapePainter(progress: (page + 1) / count, count: count, rtl: rtl),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _TapePainter extends CustomPainter {
  _TapePainter({required this.progress, required this.count, required this.rtl});

  final double progress;
  final int count;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    final top = size.height / 2 - 9;
    final tape = RRect.fromLTRBR(0, top, size.width, top + 18, const Radius.circular(5));
    canvas.drawRRect(tape, Paint()..color = Palette.ink2);

    final fillW = size.width * progress.clamp(0.0, 1.0);
    final fillRect = rtl
        ? Rect.fromLTRB(size.width - fillW, top, size.width, top + 18)
        : Rect.fromLTRB(0, top, fillW, top + 18);
    canvas.save();
    canvas.clipRRect(tape);
    canvas.drawRect(
      fillRect,
      Paint()
        ..shader = LinearGradient(
          colors: [Palette.gold.withValues(alpha: 0.55), Palette.gold],
          begin: rtl ? Alignment.centerRight : Alignment.centerLeft,
          end: rtl ? Alignment.centerLeft : Alignment.centerRight,
        ).createShader(fillRect),
    );
    canvas.restore();

    // centimetre ticks, longer every fifth
    const gap = 7.0;
    final ticks = (size.width / gap).floor();
    for (var i = 1; i < ticks; i++) {
      final x = i * gap;
      final filled = rtl ? x >= size.width - fillW : x <= fillW;
      final long = i % 5 == 0;
      canvas.drawLine(
        Offset(x, top),
        Offset(x, top + (long ? 10 : 5)),
        Paint()
          ..color = filled ? Palette.ink.withValues(alpha: 0.55) : Palette.chalk.withValues(alpha: 0.45)
          ..strokeWidth = 1,
      );
    }

    // section dividers between steps
    for (var s = 1; s < count; s++) {
      final x = size.width * s / count;
      canvas.drawLine(Offset(x, top - 4), Offset(x, top + 22), Paint()..color = Palette.gold.withValues(alpha: 0.5));
    }

    // the chalk marker at the leading edge of the fill
    final edge = rtl ? size.width - fillW : fillW;
    final marker = Path()
      ..moveTo(edge - 6, top - 7)
      ..lineTo(edge + 6, top - 7)
      ..lineTo(edge, top + 1)
      ..close();
    canvas.drawPath(marker, Paint()..color = Palette.damur);
  }

  @override
  bool shouldRepaint(_TapePainter old) => old.progress != progress || old.rtl != rtl;
}

/// One step of the journey as a card; neighbours shrink and dim while swiping.
class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.controller,
    required this.index,
    required this.total,
    required this.icon,
    required this.text,
    required this.onTap,
  });

  final PageController controller;
  final int index;
  final int total;
  final IconData icon;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final card = Padding(
      padding: const EdgeInsetsDirectional.only(end: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Palette.ink3),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Palette.ink2, Palette.ink2.withValues(alpha: 0.55)],
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Palette.gold.withValues(alpha: 0.12),
                    border: Border.all(color: Palette.gold.withValues(alpha: 0.6)),
                  ),
                  child: Icon(icon, color: Palette.gold, size: 26),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('0${index + 1} / 0$total', style: monoStyle(12, color: Palette.gold)),
                      const SizedBox(height: 6),
                      Text(
                        text,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Palette.damur, fontSize: 15.5, height: 1.45),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return AnimatedBuilder(
      animation: controller,
      child: card,
      builder: (context, child) {
        var delta = 0.0;
        if (controller.hasClients && controller.position.haveDimensions) {
          delta = ((controller.page ?? 0) - index).abs().clamp(0.0, 1.0);
        } else if (index != 0) {
          delta = 1;
        }
        return Opacity(
          opacity: 1 - delta * 0.55,
          child: Transform.scale(scale: 1 - delta * 0.06, child: child),
        );
      },
    );
  }
}

/// Two soft glows (gold and Nile green) drifting slowly behind the content,
/// plus a faint stitched seam curving across the screen.
class _AmbientPainter extends CustomPainter {
  _AmbientPainter(this.t) : super(repaint: t);

  final Animation<double> t;
  Size? _seamSize;
  PathMetric? _seam;

  @override
  void paint(Canvas canvas, Size size) {
    final a = t.value * 2 * math.pi;

    void glow(Offset c, double r, Color color) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)])
              .createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    glow(
      Offset(size.width * (0.85 + 0.08 * math.sin(a)), size.height * (0.18 + 0.05 * math.cos(a))),
      size.width * 0.75,
      Palette.gold.withValues(alpha: 0.16),
    );
    glow(
      Offset(size.width * (0.1 + 0.08 * math.cos(a)), size.height * (0.62 + 0.06 * math.sin(a))),
      size.width * 0.85,
      Palette.nile.withValues(alpha: 0.22),
    );

    // dashed seam; the curve is measured once per screen size, and all the
    // dashes go out in a single draw call
    if (_seamSize != size) {
      _seamSize = size;
      _seam = (Path()
            ..moveTo(-20, size.height * 0.36)
            ..cubicTo(size.width * 0.3, size.height * 0.28, size.width * 0.7, size.height * 0.48,
                size.width + 20, size.height * 0.40))
          .computeMetrics()
          .first;
    }
    final seam = _seam!;
    final shift = t.value * 120; // the stitches crawl slowly along the seam
    final dashes = Path();
    for (var d = shift % 12; d < seam.length; d += 12) {
      dashes.addPath(seam.extractPath(d, d + 6), Offset.zero);
    }
    canvas.drawPath(
      dashes,
      Paint()
        ..color = Palette.gold.withValues(alpha: 0.10)
        ..strokeWidth = 1.4
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_AmbientPainter old) => false;
}
