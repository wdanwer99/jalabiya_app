import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/theme.dart';

/// The opening screen. A gold thread sews the outline of a jalabiya, the
/// damuriya cloth fills in, the neck embroidery is worked, then the name
/// rises. While the app is still loading after that, a running stitch moves
/// under the name.
///
/// Respects the system's reduce-motion setting: the finished picture shows at
/// once and nothing loops.
class SplashView extends StatefulWidget {
  const SplashView({super.key, this.onIntroDone});

  /// Called once the opening has played (or straight away with reduced motion).
  final VoidCallback? onIntroDone;

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView> with TickerProviderStateMixin {
  late final AnimationController _intro =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2300));
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));

  late final Animation<double> _backdrop = _phase(0.0, 0.55, Curves.easeOut);
  late final Animation<double> _stitch = _phase(0.0, 0.56, Curves.easeInOutCubic);
  late final Animation<double> _cloth = _phase(0.36, 0.72, Curves.easeOut);
  late final Animation<double> _embroidery = _phase(0.56, 0.86, Curves.easeOut);
  late final Animation<double> _word = _phase(0.62, 0.92, Curves.easeOutCubic);
  late final Animation<double> _tagline = _phase(0.74, 1.0, Curves.easeOut);

  bool _started = false;
  bool _still = false;

  Animation<double> _phase(double a, double b, Curve c) =>
      CurvedAnimation(parent: _intro, curve: Interval(a, b, curve: c));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _still = MediaQuery.of(context).disableAnimations;
    if (_still) {
      _intro.value = 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onIntroDone?.call();
      });
    } else {
      _intro.forward().whenComplete(() {
        if (!mounted) return;
        _loop.repeat();
        widget.onIntroDone?.call();
      });
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shortest = MediaQuery.sizeOf(context).shortestSide;
    final figureW = (shortest * 0.38).clamp(120.0, 190.0);
    return Scaffold(
      backgroundColor: Palette.ink,
      body: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(child: CustomPaint(painter: _BackdropPainter(_backdrop))),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: RepaintBoundary(
                    child: SizedBox(
                      width: figureW,
                      height: figureW * 1.4,
                      child: CustomPaint(
                        painter: _JalabiyaPainter(
                          stitch: _stitch,
                          cloth: _cloth,
                          embroidery: _embroidery,
                          repaint: _intro,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                AnimatedBuilder(
                  animation: _intro,
                  builder: (context, _) => Column(
                    children: [
                      _Rise(
                        t: _word.value,
                        child: Text('جلابية', style: displayStyle(46, color: Palette.damur)),
                      ),
                      const SizedBox(height: 2),
                      _Rise(
                        t: _tagline.value,
                        child: Column(
                          children: [
                            ExcludeSemantics(
                              child: Text(
                                'JALABIYA',
                                style: monoStyle(11, color: Palette.gold, weight: FontWeight.w500)
                                    .copyWith(letterSpacing: 7),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              context.tr('splash.tagline'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Palette.onInkMuted, fontSize: 15, height: 1.5),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                Semantics(
                  label: context.tr('splash.loading'),
                  child: SizedBox(
                    width: 140,
                    height: 8,
                    child: CustomPaint(
                      painter: _RunningStitchPainter(loop: _loop, appear: _tagline, still: _still),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Fades in while sliding up a little.
class _Rise extends StatelessWidget {
  const _Rise({required this.t, required this.child});

  final double t;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: t.clamp(0.0, 1.0),
      child: Transform.translate(offset: Offset(0, 14 * (1 - t)), child: child),
    );
  }
}

// ---------------------------------------------------------------- backdrop

/// The night-blue stage of the fitting room, with a faint lattice of
/// diamonds, the motif of Sudanese embroidery and basketry, glowing from the
/// centre.
class _BackdropPainter extends CustomPainter {
  _BackdropPainter(this.t) : super(repaint: t);

  final Animation<double> t;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(size.width / 2, size.height * 0.36),
          size.longestSide * 0.62,
          const [Palette.ink3, Palette.ink],
          const [0.0, 1.0],
        ),
    );

    final v = t.value;
    if (v <= 0) return;
    const cell = 34.0;
    final centre = Offset(size.width / 2, size.height * 0.4);
    final reach = size.longestSide * 0.55;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var y = -cell; y < size.height + cell; y += cell) {
      final shift = ((y / cell).round().isOdd) ? cell / 2 : 0.0;
      for (var x = -cell + shift; x < size.width + cell; x += cell) {
        final c = Offset(x, y);
        final fade = 1 - ((c - centre).distance / reach).clamp(0.0, 1.0);
        if (fade <= 0) continue;
        paint.color = Palette.gold.withValues(alpha: 0.075 * fade * v);
        final r = 6.0 * (0.6 + 0.4 * v);
        canvas.drawPath(_diamond(c, r, r * 1.25), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_BackdropPainter old) => false;
}

Path _diamond(Offset c, double hw, double hh) => Path()
  ..moveTo(c.dx, c.dy - hh)
  ..lineTo(c.dx + hw, c.dy)
  ..lineTo(c.dx, c.dy + hh)
  ..lineTo(c.dx - hw, c.dy)
  ..close();

// ---------------------------------------------------------------- the robe

/// Drawn on a 100 × 140 grid, scaled to fit.
class _JalabiyaPainter extends CustomPainter {
  _JalabiyaPainter({
    required this.stitch,
    required this.cloth,
    required this.embroidery,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final Animation<double> stitch;
  final Animation<double> cloth;
  final Animation<double> embroidery;

  static const _clothTop = Color(0xFFF5F1E6); // damuriya
  static const _clothBottom = Color(0xFFE2D8C3);

  static final Path _outline = Path()
    ..moveTo(43, 12)
    ..quadraticBezierTo(33, 13.5, 24, 18) // shoulder
    ..quadraticBezierTo(17, 40, 13, 66) // sleeve, outside
    ..lineTo(25, 69) // cuff
    ..quadraticBezierTo(27, 50, 31, 34) // sleeve, inside, up to the armpit
    ..cubicTo(30, 70, 25, 105, 21, 133) // side seam, easing out to the hem
    ..quadraticBezierTo(35, 135.5, 50, 134) // hem
    ..quadraticBezierTo(65, 135.5, 79, 133)
    ..cubicTo(75, 105, 70, 70, 69, 34)
    ..quadraticBezierTo(73, 50, 75, 69)
    ..lineTo(87, 66)
    ..quadraticBezierTo(83, 40, 76, 18)
    ..quadraticBezierTo(67, 13.5, 57, 12)
    ..quadraticBezierTo(50, 17, 43, 12) // front neckline
    ..close();

  static final RRect _collar = RRect.fromLTRBR(43.6, 7.4, 56.4, 13, const Radius.circular(1.6));

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 100;
    canvas.save();
    canvas.translate((size.width - 100 * k) / 2, (size.height - 140 * k) / 2);
    canvas.scale(k);

    _paintCloth(canvas);
    _paintStitch(canvas);
    _paintEmbroidery(canvas);

    canvas.restore();
  }

  void _paintCloth(Canvas canvas) {
    final c = cloth.value;
    if (c <= 0) return;
    // a soft shadow pooled under the hem keeps the robe standing, not floating
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(50, 136), width: 64 * c, height: 5),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35 * c)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    final fill = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 8),
        const Offset(0, 134),
        [_clothTop.withValues(alpha: c), _clothBottom.withValues(alpha: c)],
      );
    canvas.drawPath(_outline, fill);
    canvas.drawRRect(_collar, fill);

    // the cloth falls in a few soft folds below the hip
    final fold = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFB9AC92).withValues(alpha: 0.55 * c);
    for (final f in const [
      [38.0, 74.0, 33.0, 130.0],
      [50.0, 80.0, 50.0, 131.0],
      [62.0, 74.0, 67.0, 130.0],
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(f[0], f[1])
          ..quadraticBezierTo((f[0] + f[2]) / 2 + 1.5, (f[1] + f[3]) / 2, f[2], f[3]),
        fold,
      );
    }
    // sleeve inner shade where it lies against the body
    final shade = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0xFFB9AC92).withValues(alpha: 0.6 * c);
    canvas.drawPath(
        Path()
          ..moveTo(31, 34)
          ..quadraticBezierTo(29, 52, 27.5, 66),
        shade);
    canvas.drawPath(
        Path()
          ..moveTo(69, 34)
          ..quadraticBezierTo(71, 52, 72.5, 66),
        shade);
  }

  /// The outline, sewn in a running stitch, with a glowing needle at its head.
  void _paintStitch(Canvas canvas) {
    final s = stitch.value;
    if (s <= 0) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..color = Palette.gold;
    const dash = 2.4, gap = 1.6;
    for (final m in _outline.computeMetrics()) {
      final drawn = m.length * s;
      for (var d = 0.0; d < drawn; d += dash + gap) {
        canvas.drawPath(m.extractPath(d, math.min(d + dash, drawn)), paint);
      }
      if (s < 1) {
        final tip = m.getTangentForOffset(drawn)?.position;
        if (tip != null) {
          canvas.drawCircle(
            tip,
            3.2,
            Paint()
              ..color = Palette.gold.withValues(alpha: 0.55)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.6),
          );
          canvas.drawCircle(tip, 1.1, Paint()..color = Palette.damur);
        }
      }
    }
    // the collar band is sewn in the same thread once the body is done
    final collarT = ((s - 0.85) / 0.15).clamp(0.0, 1.0);
    if (collarT > 0) {
      final cm = (Path()..addRRect(_collar)).computeMetrics().first;
      final drawn = cm.length * collarT;
      for (var d = 0.0; d < drawn; d += dash + gap) {
        canvas.drawPath(cm.extractPath(d, math.min(d + dash, drawn)), paint);
      }
    }
  }

  /// Placket, buttons, and a chain of small diamonds down both sides and
  /// round the neckline, each one appearing in turn as if being worked.
  void _paintEmbroidery(Canvas canvas) {
    final e = embroidery.value;
    if (e <= 0) return;
    final gold = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..color = Palette.gold;
    final goldFill = Paint()..color = Palette.gold;

    // placket seam
    canvas.drawLine(const Offset(50, 15.6), Offset(50, 15.6 + 28 * e), gold);

    final spots = <Offset>[
      for (var i = 0; i < 6; i++) Offset(46.6, 18.5 + i * 4.4),
      for (var i = 0; i < 6; i++) Offset(53.4, 18.5 + i * 4.4),
      // round the front of the neck, just under the collar
      const Offset(41.2, 15.0), const Offset(37.6, 15.9),
      const Offset(58.8, 15.0), const Offset(62.4, 15.9),
    ];
    for (var i = 0; i < spots.length; i++) {
      final local = ((e * (spots.length + 4) - i) / 4).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final r = 1.25 * Curves.easeOutBack.transform(local);
      canvas.drawPath(_diamond(spots[i], r, r * 1.3), gold);
      canvas.drawCircle(spots[i], 0.35 * local, goldFill);
    }

    // three buttons down the placket
    final button = Paint()..color = const Color(0xFFCFC3A8).withValues(alpha: e);
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(Offset(50, 21 + i * 8.0), 0.95, button);
    }
    // embroidered top edge of the collar
    canvas.drawLine(
      const Offset(44.4, 8.6),
      Offset(44.4 + 11.2 * e, 8.6),
      gold..strokeWidth = 0.8,
    );
  }

  @override
  bool shouldRepaint(_JalabiyaPainter old) => false;
}

// ---------------------------------------------------------------- loading

/// A running stitch drawn along a line and pulled steadily through, fading at
/// both ends. The one thing that loops, and only while the app is loading.
class _RunningStitchPainter extends CustomPainter {
  _RunningStitchPainter({required this.loop, required this.appear, required this.still})
      : super(repaint: Listenable.merge([loop, appear]));

  final Animation<double> loop;
  final Animation<double> appear;
  final bool still;

  @override
  void paint(Canvas canvas, Size size) {
    final a = appear.value;
    if (a <= 0) return;
    const dash = 9.0, gap = 7.0, period = dash + gap;
    final y = size.height / 2;
    final offset = still ? 0.0 : loop.value * period;
    final paint = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var x = -period + offset; x < size.width; x += period) {
      final x0 = x.clamp(0.0, size.width), x1 = (x + dash).clamp(0.0, size.width);
      if (x1 - x0 < 0.5) continue;
      final mid = (x0 + x1) / 2 / size.width;
      final edge = math.sin(math.pi * mid).clamp(0.0, 1.0);
      paint.color = Palette.gold.withValues(alpha: 0.9 * edge * a);
      canvas.drawLine(Offset(x0, y), Offset(x1, y), paint);
    }
  }

  @override
  bool shouldRepaint(_RunningStitchPainter old) => old.still != still;
}
