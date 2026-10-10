import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/theme.dart';

/// Shared motion, feedback and loading pieces for the customer screens.
///
/// Every animation here checks [reduceMotion] and shows the end state
/// straight away when the phone asks for less motion.

bool reduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// The two durations the app uses: small state changes, and things arriving.
class Motion {
  static const quick = Duration(milliseconds: 180);
  static const enter = Duration(milliseconds: 380);
  static const curve = Curves.easeOutCubic;
}

/// Light taps for choices, a firmer one for things that matter.
class Haptics {
  static void select() => HapticFeedback.selectionClick();
  static void tap() => HapticFeedback.lightImpact();
  static void success() => HapticFeedback.mediumImpact();
}

/// Fades and lifts its child in once, [index] steps after the list starts,
/// so a list of cards arrives one after another instead of all at once.
class EntranceFade extends StatefulWidget {
  const EntranceFade({super.key, required this.child, this.index = 0, this.offset = 18});

  final Widget child;
  final int index;
  final double offset;

  @override
  State<EntranceFade> createState() => _EntranceFadeState();
}

class _EntranceFadeState extends State<EntranceFade> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Motion.enter);
  Timer? _delay;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (reduceMotion(context)) {
      _c.value = 1;
      return;
    }
    // cap the stagger so long lists don't keep the last cards waiting
    final wait = Duration(milliseconds: 45 * math.min(widget.index, 8));
    _delay = Timer(wait, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _delay?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = CurvedAnimation(parent: _c, curve: Motion.curve);
    return AnimatedBuilder(
      animation: t,
      builder: (context, child) => Opacity(
        opacity: t.value,
        child: Transform.translate(offset: Offset(0, (1 - t.value) * widget.offset), child: child),
      ),
      child: widget.child,
    );
  }
}

/// Sinks slightly while a finger is on it. It only listens to the pointer,
/// so the child keeps its own tap handling, ripple and semantics.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.scale = 0.975});

  final Widget child;
  final double scale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
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
        scale: _down && !reduceMotion(context) ? widget.scale : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// A light band that sweeps across its child: the loading look for every
/// skeleton. Holds still with reduced motion.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});

  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _c.stop();
      _c.value = 0.5;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final x = _c.value * 3 - 1.5; // band travels from off one side to off the other
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment(x - 0.6, -0.2),
            end: Alignment(x + 0.6, 0.2),
            colors: const [Color(0x00FFFFFF), Color(0x99FFFFFF), Color(0x00FFFFFF)],
          ).createShader(rect),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// One grey block inside a skeleton.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, required this.height, this.radius = 8, this.circle = false});

  final double? width;
  final double height;
  final double radius;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: circle ? height : width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFEDE6D8),
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(radius),
      ),
    );
  }
}

/// The navy stage the app opens on, with the faint embroidery lattice,
/// used as the header of the customer screens.
class InkHeader extends StatelessWidget {
  const InkHeader({super.key, required this.child, this.padding, this.radius = 28});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(radius)),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
            colors: [Palette.ink3, Palette.ink],
          ),
        ),
        child: CustomPaint(
          painter: const DiamondsPainter(),
          child: Padding(padding: padding ?? const EdgeInsets.fromLTRB(20, 8, 20, 24), child: child),
        ),
      ),
    );
  }
}

/// A faint lattice of gold diamonds, the embroidery motif, strongest in the
/// top corner and fading toward the text.
class DiamondsPainter extends CustomPainter {
  const DiamondsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const cell = 22.0;
    for (var row = 0; row * cell < size.height + cell; row++) {
      final shift = row.isOdd ? cell / 2 : 0.0;
      for (var col = 0; col * cell < size.width + cell; col++) {
        final x = col * cell + shift, y = row * cell;
        final fade = ((x / size.width) * (1 - y / size.height)).clamp(0.0, 1.0);
        if (fade < 0.05) continue;
        paint.color = Palette.gold.withValues(alpha: 0.16 * fade);
        canvas.drawPath(
          Path()
            ..moveTo(x, y - 5)
            ..lineTo(x + 4, y)
            ..lineTo(x, y + 5)
            ..lineTo(x - 4, y)
            ..close(),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(DiamondsPainter oldDelegate) => false;
}

/// Counts up to [value] when it first shows or changes.
class AnimatedCount extends StatelessWidget {
  const AnimatedCount({super.key, required this.value, required this.style});

  final int value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return Text('$value', style: style);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.toDouble()),
      duration: const Duration(milliseconds: 650),
      curve: Motion.curve,
      builder: (context, v, _) => Text('${v.round()}', style: style),
    );
  }
}

/// A check that draws itself inside a growing circle: the moment something
/// worked (an order sent, an offer accepted).
class SuccessCheck extends StatefulWidget {
  const SuccessCheck({super.key, this.size = 64, this.color = Palette.nile});

  final double size;
  final Color color;

  @override
  State<SuccessCheck> createState() => _SuccessCheckState();
}

class _SuccessCheckState extends State<SuccessCheck> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _c.value = 1;
    } else if (_c.value == 0 && !_c.isAnimating) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final grow = CurvedAnimation(parent: _c, curve: const Interval(0, 0.55, curve: Curves.easeOutBack));
    final draw = CurvedAnimation(parent: _c, curve: const Interval(0.4, 1, curve: Curves.easeOut));
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Transform.scale(
        scale: grow.value,
        child: SizedBox.square(
          dimension: widget.size,
          child: CustomPaint(painter: _CheckPainter(draw.value, widget.color)),
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter(this.t, this.color);

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas.drawCircle(c, size.width / 2, Paint()..color = color);
    final s = size.width;
    final path = Path()
      ..moveTo(s * 0.28, s * 0.52)
      ..lineTo(s * 0.44, s * 0.67)
      ..lineTo(s * 0.73, s * 0.37);
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * t),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.08
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.t != t || old.color != color;
}

/// Shows a check with a line of text over the screen for a moment, then
/// goes away by itself.
Future<void> showSuccess(BuildContext context, String message) {
  Haptics.success();
  final nav = Navigator.of(context);
  var open = true;
  Timer(const Duration(milliseconds: 1500), () {
    if (open && nav.mounted) nav.pop();
  });
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: message,
    barrierColor: const Color(0x66101A2B),
    transitionDuration: reduceMotion(context) ? Duration.zero : Motion.quick,
    pageBuilder: (ctx, _, __) => Center(
      child: Material(
        color: Palette.card,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 22),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SuccessCheck(size: 72),
                const SizedBox(height: 16),
                Text(message, textAlign: TextAlign.center, style: displayStyle(17)),
              ],
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (ctx, a, _, child) => FadeTransition(
      opacity: a,
      child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(a), child: child),
    ),
  ).whenComplete(() => open = false);
}
