import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// The man from the app icon: white 'imma and jalabiya, a shawl with teal
/// Sudanese embroidery and fringe, dark glasses, and a black cane with a gold
/// knob. He arrives in steps, the 'imma wound band by band, the shawl laid on
/// his shoulders, the cane swung into his hand, the glasses slid down, and
/// then stands in a light breeze. Tap him and he taps his cane.
///
/// [entrance] runs 0 → 1 once, [ambient] loops, and [tap] plays 0 → 1 per
/// tap. Pass [still] to draw the finished figure with nothing moving.
/// [mirror] flips him so he can face the text beside him in either direction.
class SudaniMan extends StatelessWidget {
  const SudaniMan({
    super.key,
    required this.entrance,
    required this.ambient,
    required this.tap,
    this.still = false,
    this.mirror = false,
    this.onTap,
  });

  final Animation<double> entrance;
  final Animation<double> ambient;
  final Animation<double> tap;
  final bool still;
  final bool mirror;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Widget art = CustomPaint(
      painter: _ManPainter(entrance: entrance, ambient: ambient, tap: tap, still: still),
      size: Size.infinite,
    );
    if (mirror) art = Transform.flip(flipX: true, child: art);
    return ExcludeSemantics(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: RepaintBoundary(child: art),
      ),
    );
  }
}

/// Everything is drawn on a 100 × 180 grid, scaled to fit.
class _ManPainter extends CustomPainter {
  _ManPainter({required this.entrance, required this.ambient, required this.tap, required this.still})
      : super(repaint: Listenable.merge([entrance, ambient, tap]));

  final Animation<double> entrance;
  final Animation<double> ambient;
  final Animation<double> tap;
  final bool still;

  // skin in three tones, as in the logo: lit, turned away, and in shadow
  static const _skin = Color(0xFFBC7348);
  static const _skinShade = Color(0xFFA0623D);
  static const _skinDeep = Color(0xFF7E4A2C);
  static const _skinLight = Color(0xFFCB8659); // knuckles and the thumb in the light
  static const _nail = Color(0xFFDDA27C);
  static const _hair = Color(0xFF121C24); // the logo's blue-black beard
  static const _lens = Color(0xFF0B0F14);
  static const _robe = Color(0xFFF7F5EF);
  static const _robeLow = Color(0xFFE9E4D8);
  static const _fold = Color(0xFFCFC9BC);
  static const _shawl = Color(0xFFFFFFFF);
  static const _teal = Color(0xFF13756F); // the shawl embroidery in the logo
  static const _cane = Color(0xFF14181E);
  static const _goldLight = Color(0xFFF3DA97);

  /// The hand that holds the cane; the cane turns about it.
  static const _grip = Offset(47.3, 106.2);
  static const _caneTop = Offset(62.6, 84);
  static const _caneTip = Offset(5.5, 167);

  static double _seg(double t, double a, double b, [Curve curve = Curves.linear]) =>
      curve.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

  @override
  void paint(Canvas canvas, Size size) {
    final k = math.min(size.width / 100, size.height / 180);
    canvas.save();
    canvas.translate((size.width - 100 * k) / 2, (size.height - 180 * k) / 2);
    canvas.scale(k);

    final e = still ? 1.0 : entrance.value;
    final amb = still ? 0.0 : ambient.value;
    final t = still ? 0.0 : tap.value;

    // breeze: a slow sway shared by the hem, the shawl and its fringe
    final sway = math.sin(amb * 2 * math.pi * 3);

    final halo = _seg(e, 0.0, 0.6, Curves.easeOut);
    final body = _seg(e, 0.0, 0.4, Curves.easeOutCubic);
    final turban = _seg(e, 0.18, 0.62);
    final shawl = _seg(e, 0.34, 0.72, Curves.easeOutBack);
    final cane = _seg(e, 0.5, 0.86, Curves.easeOutBack);
    final glasses = _seg(e, 0.68, 0.92, Curves.easeOutCubic);

    _paintStage(canvas, halo, amb);
    if (body <= 0) {
      canvas.restore();
      return;
    }

    final fade = body < 1;
    if (fade) {
      canvas.saveLayer(const Rect.fromLTWH(-10, -10, 120, 200), Paint()..color = Color.fromRGBO(0, 0, 0, body));
    }
    canvas.save();
    canvas.translate(0, 10 * (1 - body));

    // swung in from behind, then a breath of sway, and a lift-and-tap on touch;
    // the fist turns with it
    final caneTurn = -1.1 * (1 - cane) +
        0.012 * math.sin(amb * 2 * math.pi * 3 + 1) -
        0.32 * math.sin(math.pi * (t / 0.6).clamp(0.0, 1.0));

    _paintNeck(canvas);
    _paintRobe(canvas, sway);
    _paintShawl(canvas, shawl, sway);
    _paintSleeves(canvas);
    _paintCane(canvas, cane, caneTurn, t, amb);
    _paintFist(canvas, caneTurn);
    _paintRestingHand(canvas);
    _paintHead(canvas);
    _paintGlasses(canvas, glasses, e, amb, t);
    _paintTurban(canvas, turban);

    canvas.restore();
    if (fade) canvas.restore();
    canvas.restore();
  }

  // ------------------------------------------------------------ the stage

  /// A warm glow behind his shoulders, a slowly turning ring of the diamond
  /// motif from Sudanese embroidery and basketry, and his shadow on the ground.
  void _paintStage(Canvas canvas, double v, double amb) {
    if (v <= 0) return;
    const glowC = Offset(54, 58);
    canvas.drawCircle(
      glowC,
      58,
      Paint()
        ..shader = ui.Gradient.radial(
          glowC,
          58,
          [Palette.gold.withValues(alpha: 0.22 * v), Palette.gold.withValues(alpha: 0)],
        ),
    );

    const ringC = Offset(53, 74);
    const count = 22;
    // two diamonds' worth of turn per loop, so the loop joins up seamlessly
    final turn = amb * 2 * math.pi * 2 / count;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7;
    for (var i = 0; i < count; i++) {
      // each diamond lights in turn as the ring forms
      final local = ((v * (count + 6) - i) / 6).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final a = turn + i * 2 * math.pi / count;
      final c = ringC + Offset(math.cos(a) * 47, math.sin(a) * 47);
      stroke.color = Palette.gold.withValues(alpha: 0.32 * local);
      final r = 1.8 * local;
      canvas.drawPath(_diamond(c, r, r * 1.35), stroke);
    }

    canvas.drawOval(
      Rect.fromCenter(center: const Offset(50, 173.5), width: 76 * v, height: 6),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.4 * v)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
  }

  // ------------------------------------------------------------ the body

  void _paintNeck(Canvas canvas) {
    canvas.drawPath(
      Path()
        ..moveTo(48.8, 39)
        ..lineTo(58.4, 42)
        ..lineTo(59, 51)
        ..lineTo(47.6, 51)
        ..quadraticBezierTo(48.2, 45, 48.8, 39)
        ..close(),
      Paint()..color = _skinShade,
    );
    // the beard throws a shadow down the throat
    canvas.drawPath(
      Path()
        ..moveTo(48.8, 42)
        ..lineTo(58.6, 45)
        ..lineTo(58.8, 48.4)
        ..quadraticBezierTo(53, 46.6, 48.4, 47.4)
        ..close(),
      Paint()..color = _skinDeep,
    );
  }

  void _paintRobe(Canvas canvas, double sway) {
    final s = sway * 1.4; // the hem moves, the shoulders stay put
    final robe = Path()
      ..moveTo(47, 48)
      ..quadraticBezierTo(36, 49.5, 31, 53)
      ..quadraticBezierTo(27.5, 56, 27.2, 64)
      ..lineTo(26.8, 104)
      ..quadraticBezierTo(25.4 + s * 0.5, 140, 23 + s, 172)
      ..quadraticBezierTo(52 + s, 176.5, 81 + s, 172)
      ..quadraticBezierTo(78.6 + s * 0.5, 140, 77.2, 104)
      ..lineTo(76.8, 64)
      ..quadraticBezierTo(76.5, 56, 73, 53)
      ..quadraticBezierTo(68, 49.5, 58, 48)
      ..quadraticBezierTo(52.5, 52, 47, 48)
      ..close();
    canvas.drawPath(
      robe,
      Paint()
        ..shader = ui.Gradient.linear(const Offset(0, 48), const Offset(0, 174), const [_robe, _robeLow]),
    );

    // the cloth falls in long soft folds
    final fold = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..strokeCap = StrokeCap.round
      ..color = _fold;
    for (final f in const [
      [50.0, 118.0, 49.0, 172.0],
      [30.5, 116.0, 27.0, 170.0],
      [73.5, 116.0, 77.0, 170.0],
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(f[0], f[1])
          ..quadraticBezierTo((f[0] + f[2]) / 2 + 1 + s * 0.4, (f[1] + f[3]) / 2, f[2] + s, f[3]),
        fold,
      );
    }
  }

  void _paintShawl(Canvas canvas, double v, double sway) {
    if (v <= 0) return;
    canvas.save();
    // laid on from above, landing with a small bounce
    canvas.translate(0, -12 * (1 - v));
    final alpha = (v * 2).clamp(0.0, 1.0);

    final cloth = Paint()..color = _shawl.withValues(alpha: alpha);
    final shade = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = _fold.withValues(alpha: alpha);

    // around the back of the neck
    canvas.drawPath(
      Path()
        ..moveTo(43.5, 49.5)
        ..quadraticBezierTo(52.5, 45.2, 62, 49.5)
        ..lineTo(64.4, 55)
        ..quadraticBezierTo(52.5, 50.6, 40.8, 55)
        ..close(),
      cloth,
    );

    // the two ends hang down the chest and swing from the top
    for (final left in const [true, false]) {
      canvas.save();
      final top = left ? const Offset(44, 52) : const Offset(60, 52);
      canvas.translate(top.dx, top.dy);
      canvas.transform(Matrix4.skewX(sway * 0.014).storage);
      canvas.translate(-top.dx, -top.dy);

      final strip = left
          ? (Path()
            ..moveTo(40.4, 52)
            ..lineTo(48.2, 51.4)
            ..quadraticBezierTo(46.8, 98, 45.2, 146)
            ..lineTo(33.8, 146)
            ..quadraticBezierTo(36.2, 98, 40.4, 52)
            ..close())
          : (Path()
            ..moveTo(56.6, 51.4)
            ..lineTo(64.4, 52)
            ..quadraticBezierTo(68.2, 98, 70.6, 146)
            ..lineTo(59.2, 146)
            ..quadraticBezierTo(57.8, 98, 56.6, 51.4)
            ..close());
      canvas.drawPath(strip, cloth);
      // a crease down the inner edge
      canvas.drawPath(
        left
            ? (Path()
              ..moveTo(46.6, 56)
              ..quadraticBezierTo(45.6, 100, 44, 144))
            : (Path()
              ..moveTo(58.2, 56)
              ..quadraticBezierTo(59, 100, 60.6, 144)),
        shade,
      );

      // the embroidered band: teal with a white zigzag and a row of diamonds
      final x0 = left ? 34.2 : 59.4, x1 = left ? 45.1 : 70.4;
      const y0 = 130.0, y1 = 146.0;
      final band = Rect.fromLTRB(x0, y0, x1, y1);
      canvas.drawRect(band, Paint()..color = _teal.withValues(alpha: alpha));
      final white = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.75
        ..strokeJoin = StrokeJoin.miter
        ..color = _shawl.withValues(alpha: alpha);
      final w = x1 - x0;
      for (final y in const [132.6, 143.4]) {
        final zig = Path()..moveTo(x0, y);
        for (var i = 1; i <= 6; i++) {
          zig.lineTo(x0 + w * i / 6, i.isOdd ? y - 1.4 : y);
        }
        canvas.drawPath(zig, white);
      }
      for (var i = 0; i < 3; i++) {
        final c = Offset(x0 + w * (i + 0.5) / 3, 138);
        canvas.drawPath(_diamond(c, 1.5, 2.6), white);
        canvas.drawCircle(c, 0.45, Paint()..color = _shawl.withValues(alpha: alpha));
      }

      // the fringe trails a beat behind the cloth
      final fringe = Paint()
        ..strokeWidth = 0.5
        ..strokeCap = StrokeCap.round
        ..color = _teal.withValues(alpha: alpha);
      for (var x = x0 + 0.5; x <= x1; x += 1.25) {
        canvas.drawLine(Offset(x, y1), Offset(x + sway * 0.9, y1 + 5.6), fringe);
      }
      canvas.restore();
    }
    canvas.restore();
  }

  void _paintSleeves(Canvas canvas) {
    final cloth = Paint()
      ..shader = ui.Gradient.linear(const Offset(0, 52), const Offset(0, 116), const [_robe, _robeLow]);
    final shade = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..strokeCap = StrokeCap.round
      ..color = _fold;
    // the sleeves lie over the robe, so a fine edge keeps the arms readable
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..strokeJoin = StrokeJoin.round
      ..color = _fold;

    // his right arm, bent across to hold the cane
    final right = Path()
      ..moveTo(31, 53)
      ..quadraticBezierTo(24, 56, 22.6, 70)
      ..lineTo(20.4, 96)
      ..quadraticBezierTo(20.6, 106, 28, 110.6)
      ..lineTo(42.5, 114.6)
      ..quadraticBezierTo(46.4, 112.6, 46, 107)
      ..lineTo(44.8, 104.2)
      ..lineTo(33.6, 99.6)
      ..quadraticBezierTo(32, 95, 32.4, 86)
      ..lineTo(33, 62)
      ..close();
    canvas.drawPath(right, cloth);
    canvas.drawPath(right, edge);
    canvas.drawPath(
        Path()
          ..moveTo(25, 100)
          ..quadraticBezierTo(31, 106, 41, 109.6),
        shade);

    // his left arm, the hand resting at the waist
    final left = Path()
      ..moveTo(73, 53)
      ..quadraticBezierTo(80, 56, 81.4, 70)
      ..lineTo(83.6, 96)
      ..quadraticBezierTo(83.4, 106, 76, 110.6)
      ..lineTo(62.4, 115.4)
      ..quadraticBezierTo(58.4, 113.6, 58.8, 108)
      ..lineTo(60, 105)
      ..lineTo(70.4, 99.6)
      ..quadraticBezierTo(72, 95, 71.6, 86)
      ..lineTo(71, 62)
      ..close();
    canvas.drawPath(left, cloth);
    canvas.drawPath(left, edge);
    canvas.drawPath(
        Path()
          ..moveTo(79, 100)
          ..quadraticBezierTo(73, 106, 63.4, 110.4),
        shade);
  }

  void _paintCane(Canvas canvas, double v, double angle, double tapT, double amb) {
    if (v <= 0) return;
    final alpha = (v * 3).clamp(0.0, 1.0);

    canvas.save();
    canvas.translate(_grip.dx, _grip.dy);
    canvas.rotate(angle);
    canvas.translate(-_grip.dx, -_grip.dy);

    canvas.drawLine(
      _caneTip,
      _caneTop,
      Paint()
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..color = _cane.withValues(alpha: alpha),
    );
    // gold ferrule at the foot
    canvas.drawLine(
      _caneTip,
      Offset.lerp(_caneTip, _caneTop, 0.035)!,
      Paint()
        ..strokeWidth = 1.9
        ..strokeCap = StrokeCap.round
        ..color = Palette.gold.withValues(alpha: alpha),
    );

    // the knob: a gold collar and a polished ball
    final dir = (_caneTop - _caneTip) / (_caneTop - _caneTip).distance;
    final collar = _caneTop - dir * 0.6;
    canvas.drawLine(
      collar - dir * 1.2,
      collar + dir * 0.6,
      Paint()
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.butt
        ..color = const Color(0xFF9C7B2E).withValues(alpha: alpha),
    );
    final ball = _caneTop + dir * 2.0;
    canvas.drawCircle(
      ball,
      2.5,
      Paint()
        ..shader = ui.Gradient.radial(
          ball + const Offset(-0.8, -0.9),
          3.2,
          [_goldLight.withValues(alpha: alpha), Palette.gold.withValues(alpha: alpha), const Color(0xFF8A6A1F).withValues(alpha: alpha)],
          const [0.0, 0.5, 1.0],
        ),
    );
    // a glint on the knob as he settles, and again now and then
    final glint = math.max(_bump(v, 0.75, 1.0), _bump((amb * 2 + 0.5) % 1.0, 0.0, 0.07));
    if (glint > 0) {
      canvas.drawCircle(
        ball + const Offset(-0.7, -0.8),
        2.6 * glint,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.75 * glint)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.4),
      );
    }
    canvas.restore();

    // the tap lands: a ring of dust spreads on the ground
    final ripple = ((tapT - 0.55) / 0.45).clamp(0.0, 1.0);
    if (ripple > 0 && ripple < 1) {
      canvas.drawOval(
        Rect.fromCenter(center: _caneTip + const Offset(0, 1), width: 4 + 16 * ripple, height: 1.4 + 3 * ripple),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = Palette.gold.withValues(alpha: 0.7 * (1 - ripple)),
      );
    }
  }

  /// A crease between fingers: dark where the fingers meet at the edge of
  /// the hand, fading out across the back of it, so the hand reads as one
  /// smooth form rather than a stack of pieces.
  static void _crease(Canvas canvas, Offset from, Offset to, {double width = 0.32, double strength = 0.85}) {
    canvas.drawLine(
      from,
      to,
      Paint()
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..shader = ui.Gradient.linear(
          from,
          to,
          [_skinDeep.withValues(alpha: strength), _skinDeep.withValues(alpha: 0)],
        ),
    );
  }

  /// A soft spot of light, for knuckles and the back of the hand.
  static void _glow(Canvas canvas, Offset c, double r, double alpha) {
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = _skinLight.withValues(alpha: alpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.8),
    );
  }

  /// His right hand closed round the cane: one rounded fist with the four
  /// curled fingers along its front and the thumb laid over the top. Drawn
  /// along the cane so the fist turns with it.
  void _paintFist(Canvas canvas, double turn) {
    final along = (_caneTop - _caneTip).direction;
    canvas.save();
    canvas.translate(_grip.dx, _grip.dy);
    canvas.rotate(along + turn);
    canvas.scale(1.25);
    // x now runs up the cane (index finger at +x), y across it towards his front

    // a soft shadow on the robe beneath
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(-0.2, 1.4), width: 8.4, height: 7.4),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.1),
    );

    // the whole fist in one outline, the fingers' knuckles gently scalloped
    final fist = Path()
      ..moveTo(-3.5, -3.1)
      ..quadraticBezierTo(-0.4, -4.5, 3.0, -3.5)
      ..cubicTo(4.2, -3.0, 4.3, -0.6, 3.5, 2.5)
      ..quadraticBezierTo(2.6, 3.9, 1.6, 3.0)
      ..quadraticBezierTo(0.8, 4.1, -0.05, 3.15)
      ..quadraticBezierTo(-0.85, 4.0, -1.7, 3.0)
      ..quadraticBezierTo(-2.6, 3.5, -3.3, 2.4)
      ..cubicTo(-4.1, 1.2, -4.2, -1.8, -3.5, -3.1)
      ..close();
    canvas.drawPath(
      fist,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(-3.8, -3.6),
          const Offset(3.6, 3.2),
          const [_skinShade, _skin, _skinLight],
          const [0.0, 0.6, 1.0],
        ),
    );

    canvas.save();
    canvas.clipPath(fist);
    // where the fingers fold over: a faint line across the fist, strongest
    // in the middle and gone by either end
    canvas.drawPath(
      Path()
        ..moveTo(-3.6, 0.5)
        ..quadraticBezierTo(0, -0.5, 3.8, 0.2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.35
        ..shader = ui.Gradient.linear(
          const Offset(-3.6, 0),
          const Offset(3.8, 0),
          [
            _skinDeep.withValues(alpha: 0),
            _skinDeep.withValues(alpha: 0.24),
            _skinDeep.withValues(alpha: 0),
          ],
          const [0.0, 0.5, 1.0],
        ),
    );
    // creases between the fingers, from each notch inwards
    _crease(canvas, const Offset(1.6, 3.1), const Offset(1.45, 0.1));
    _crease(canvas, const Offset(-0.05, 3.2), const Offset(-0.1, 0.0));
    _crease(canvas, const Offset(-1.7, 3.1), const Offset(-1.75, 0.3));
    // light on each knuckle, brightest towards the index finger
    _glow(canvas, const Offset(2.5, 2.1), 0.62, 0.75);
    _glow(canvas, const Offset(0.8, 2.3), 0.6, 0.6);
    _glow(canvas, const Offset(-0.85, 2.2), 0.55, 0.45);
    _glow(canvas, const Offset(-2.45, 1.8), 0.5, 0.3);
    canvas.restore();

    // the thumb, laid over the index finger towards the knob, with the soft
    // shadow it casts on the fingers
    canvas.save();
    canvas.clipPath(fist);
    canvas.drawPath(
      Path()
        ..moveTo(-0.8, -1.7)
        ..cubicTo(1.0, -1.2, 2.8, -0.1, 3.9, 0.0),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..strokeCap = StrokeCap.round
        ..color = _skinDeep.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.5),
    );
    canvas.restore();
    final thumb = Path()
      ..moveTo(-0.6, -3.4)
      ..cubicTo(1.0, -4.7, 3.6, -4.0, 4.4, -2.0)
      ..quadraticBezierTo(4.8, -0.8, 3.9, -0.5)
      ..cubicTo(2.8, -0.6, 1.0, -1.7, -0.6, -2.3)
      ..close();
    // its root fades into the hand, so the thumb grows out of it with no seam
    canvas.drawPath(
      thumb,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(-0.6, -2.9),
          const Offset(4.4, -1.4),
          [_skin.withValues(alpha: 0), _skin, _skinLight],
          const [0.0, 0.4, 1.0],
        ),
    );
    _glow(canvas, const Offset(2.2, -3.0), 0.7, 0.55); // light along its top
    // its underside, where it rests on the finger
    canvas.drawPath(
      Path()
        ..moveTo(-0.8, -2.2)
        ..cubicTo(1.0, -1.7, 2.8, -0.6, 3.9, -0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.34
        ..strokeCap = StrokeCap.round
        ..shader = ui.Gradient.linear(
          const Offset(-0.8, -2.2),
          const Offset(3.9, -0.5),
          [_skinDeep.withValues(alpha: 0.15), _skinDeep.withValues(alpha: 0.8)],
        ),
    );
    canvas.save();
    canvas.translate(3.75, -1.35);
    canvas.rotate(0.45);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 1.4, height: 0.95), Paint()..color = _nail);
    canvas.restore();

    canvas.restore();
  }

  /// His left hand, loosely closed at the waist: the back of it towards us,
  /// the fingers curled under along its front edge, and the sleeve's hem
  /// falling over the wrist.
  void _paintRestingHand(Canvas canvas) {
    canvas.save();
    // drawn at the size of the logo's hands, grown about the wrist
    const wrist = Offset(60.4, 110.6);
    canvas.translate(wrist.dx, wrist.dy);
    canvas.scale(1.2); // keep in step with the hem shadow below
    canvas.translate(-wrist.dx, -wrist.dy);

    // a soft shadow on the robe beneath
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(59, 113.4), width: 9, height: 8),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.14)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.1),
    );

    // the thumb lies along the top, just behind the first finger
    canvas.drawPath(
      Path()
        ..moveTo(60.2, 105.2)
        ..cubicTo(58.2, 105.0, 56, 105.8, 55.2, 107.2)
        ..quadraticBezierTo(55.3, 108.3, 56.6, 108)
        ..cubicTo(57.8, 107.3, 59.2, 106.9, 60.4, 106.9)
        ..close(),
      Paint()..color = _skinShade,
    );

    // the hand in one outline: back of the hand, then the four curled
    // fingers rounding off its front edge
    final hand = Path()
      ..moveTo(62.4, 105.2)
      ..cubicTo(60.2, 104.6, 57.6, 105.4, 55.8, 107.6)
      ..quadraticBezierTo(54.0, 108.4, 55.3, 109.45)
      ..quadraticBezierTo(53.7, 110.3, 55.1, 111.15)
      ..quadraticBezierTo(53.9, 112.0, 55.4, 112.8)
      ..quadraticBezierTo(54.6, 113.9, 56.6, 114.6)
      ..quadraticBezierTo(57.6, 116.0, 59.8, 115.8)
      ..quadraticBezierTo(62.2, 115.6, 63.2, 114)
      ..close();
    canvas.drawPath(
      hand,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(54.6, 108),
          const Offset(63, 113),
          const [_skinLight, _skin, _skinShade],
          const [0.0, 0.45, 1.0],
        ),
    );

    canvas.save();
    canvas.clipPath(hand);
    // where the fingers curl under the knuckles
    canvas.drawPath(
      Path()
        ..moveTo(57.4, 107.4)
        ..quadraticBezierTo(58.2, 111, 57.6, 114.6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.35
        ..color = _skinDeep.withValues(alpha: 0.3),
    );
    // creases between the fingers
    _crease(canvas, const Offset(55.2, 109.45), const Offset(58, 109));
    _crease(canvas, const Offset(55.0, 111.15), const Offset(58.2, 110.9));
    _crease(canvas, const Offset(55.3, 112.8), const Offset(58.2, 112.8));
    // light on the knuckles and across the back of the hand
    _glow(canvas, const Offset(55.4, 108.5), 0.6, 0.7);
    _glow(canvas, const Offset(55.1, 110.3), 0.6, 0.6);
    _glow(canvas, const Offset(55.3, 112.0), 0.55, 0.5);
    _glow(canvas, const Offset(58.8, 108.4), 1.5, 0.35);
    canvas.restore();
    canvas.restore();

    // the hem of the sleeve falls over the wrist, kept inside the sleeve's
    // own outline, with a soft shadow on the hand beneath it
    final edge = Path()
      ..moveTo(61.2, 104.9)
      ..quadraticBezierTo(60.4, 110.4, 62.6, 116);
    const s = 1.2;
    final grown = hand.transform(Float64List.fromList(
        [s, 0, 0, 0, 0, s, 0, 0, 0, 0, 1, 0, wrist.dx * (1 - s), wrist.dy * (1 - s), 0, 1]));
    canvas.save();
    canvas.clipPath(grown);
    canvas.drawPath(
      edge.shift(const Offset(-0.5, 0)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = _skinDeep.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.6),
    );
    canvas.restore();
    canvas.drawPath(
      Path()
        ..addPath(edge, Offset.zero)
        ..lineTo(64.6, 115.2)
        ..quadraticBezierTo(62.6, 110, 63.6, 103.7)
        ..close(),
      Paint()
        ..shader = ui.Gradient.linear(const Offset(0, 104), const Offset(0, 116), const [_robe, _robeLow]),
    );
    canvas.drawPath(
      edge,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.55
        ..strokeCap = StrokeCap.round
        ..color = _fold,
    );
  }

  void _paintHead(Canvas canvas) {
    // hair at the nape, behind the ear
    final hair = Paint()..color = _hair;
    canvas.drawPath(
      Path()
        ..moveTo(45.2, 28.6)
        ..lineTo(48.4, 28.6)
        ..lineTo(48.2, 38.6)
        ..quadraticBezierTo(46.6, 40.8, 45.6, 38.8)
        ..quadraticBezierTo(44.6, 33.6, 45.2, 28.6)
        ..close(),
      hair,
    );

    // the face in three-quarter view, looking off to his left: brow, the
    // dip at the bridge, a strong nose, lips, chin
    final face = Path()
      ..moveTo(47.6, 26.5)
      ..lineTo(61.6, 26.5)
      ..lineTo(61.9, 30.4)
      ..quadraticBezierTo(61.5, 31.3, 61.9, 32.2)
      ..lineTo(64.5, 35.4)
      ..quadraticBezierTo(64.3, 36.5, 62.8, 36.4)
      ..lineTo(62.7, 37.3)
      ..quadraticBezierTo(63.1, 38.6, 62.4, 39.2)
      ..quadraticBezierTo(62.8, 40, 62.7, 41.2)
      ..quadraticBezierTo(62.4, 44.2, 59.6, 45.2)
      ..lineTo(52, 44.6)
      ..quadraticBezierTo(49.2, 42.6, 48.6, 38.4)
      ..lineTo(47.6, 37.6)
      ..close();
    canvas.drawPath(face, Paint()..color = _skin);

    canvas.save();
    canvas.clipPath(face);
    // the side of the face, turned from the light, and the band of shadow
    // the 'imma throws over the brow
    canvas.drawPath(
      Path()
        ..moveTo(47, 26)
        ..lineTo(54.6, 26)
        ..quadraticBezierTo(53.4, 33.6, 53, 36.8)
        ..quadraticBezierTo(51.8, 40.4, 49.6, 42.6)
        ..lineTo(47, 40)
        ..close(),
      Paint()..color = _skinShade,
    );
    canvas.drawPath(
      Path()
        ..moveTo(47, 26)
        ..lineTo(63, 26)
        ..lineTo(63, 30)
        ..quadraticBezierTo(55, 29.6, 47, 31)
        ..close(),
      Paint()..color = _skinDeep.withValues(alpha: 0.55),
    );
    // light down the ridge of the nose
    canvas.drawLine(
      const Offset(62.2, 32.4),
      const Offset(63.8, 34.8),
      Paint()
        ..strokeWidth = 0.6
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFD08A5C),
    );
    canvas.restore();

    // nostril wing
    canvas.drawPath(
      Path()
        ..moveTo(61.4, 34.2)
        ..quadraticBezierTo(60.6, 35.6, 61.8, 36.3)
        ..quadraticBezierTo(62.6, 36.5, 63.2, 36.2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5
        ..strokeCap = StrokeCap.round
        ..color = _skinDeep,
    );

    // brow and eye, seen until the glasses come down over them
    canvas.drawLine(
      const Offset(54.6, 30.4),
      const Offset(58.8, 30.2),
      Paint()
        ..strokeWidth = 0.9
        ..strokeCap = StrokeCap.round
        ..color = _hair,
    );
    canvas.drawOval(Rect.fromCenter(center: const Offset(57, 32), width: 2.2, height: 1.1), hair);

    // ear, with the fold inside it
    canvas.drawPath(
      Path()
        ..moveTo(47.6, 30.6)
        ..quadraticBezierTo(45.8, 30.6, 46, 33.4)
        ..quadraticBezierTo(46.2, 36.4, 48.4, 37)
        ..quadraticBezierTo(49.8, 37.2, 49.8, 35.2)
        ..lineTo(49.8, 31.6)
        ..quadraticBezierTo(48.8, 30.5, 47.6, 30.6)
        ..close(),
      Paint()..color = _skinShade,
    );
    canvas.drawPath(
      Path()
        ..moveTo(48.4, 31.8)
        ..quadraticBezierTo(47.1, 32.4, 47.4, 34)
        ..quadraticBezierTo(47.6, 35.4, 48.6, 35.8),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.55
        ..strokeCap = StrokeCap.round
        ..color = _skinDeep,
    );

    // the beard, trimmed close: a sideburn down from the ear, along the jaw
    // below a bare cheek, up to join the moustache at the corner of the
    // mouth, and full under the chin, leaving the lower lip bare
    canvas.drawPath(
      Path()
        ..moveTo(49.6, 31.2)
        ..lineTo(51.2, 31.2)
        ..quadraticBezierTo(51.2, 36.6, 52.8, 39.6)
        ..quadraticBezierTo(55.6, 41.6, 58.6, 40.4)
        ..lineTo(58.8, 38.6)
        ..quadraticBezierTo(60.4, 36.2, 62.8, 36.8)
        ..quadraticBezierTo(63.5, 37.6, 62.6, 38.3)
        ..quadraticBezierTo(61.5, 38.6, 60.4, 38.7)
        ..lineTo(60.6, 39.5)
        ..quadraticBezierTo(61.6, 39.3, 62.5, 39.7)
        ..quadraticBezierTo(63, 42.6, 61.8, 44.4)
        ..quadraticBezierTo(59.4, 46.8, 55.4, 46.2)
        ..quadraticBezierTo(51.4, 45.4, 49.6, 42.4)
        ..quadraticBezierTo(48.8, 39.6, 49.6, 37)
        ..close(),
      hair,
    );
  }

  /// Black wayfarers: the near lens full, the far one narrowed by the turn of
  /// his head, and the arm running back to the ear.
  void _paintGlasses(Canvas canvas, double v, double e, double amb, double tapT) {
    if (v <= 0) return;
    canvas.save();
    // slid down from his forehead onto his eyes
    canvas.translate(0, -5 * (1 - v));
    final alpha = v;
    final near = Path()
      ..moveTo(52.2, 29.3)
      ..lineTo(59, 29.3)
      ..quadraticBezierTo(59.2, 31.8, 58.3, 33.1)
      ..quadraticBezierTo(57.6, 33.9, 55.6, 33.9)
      ..quadraticBezierTo(53.3, 33.9, 52.7, 32.4)
      ..quadraticBezierTo(52.1, 31, 52.2, 29.3)
      ..close();
    final far = Path()
      ..moveTo(60, 29.3)
      ..lineTo(63.9, 29.3)
      ..quadraticBezierTo(64, 31.3, 63.3, 32.5)
      ..quadraticBezierTo(62.8, 33.2, 61.6, 33.2)
      ..quadraticBezierTo(60.3, 33.2, 60.1, 31.8)
      ..close();
    final lens = Paint()..color = _lens.withValues(alpha: alpha);
    canvas.drawPath(near, lens);
    canvas.drawPath(far, lens);
    final bar = Paint()
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round
      ..color = _lens.withValues(alpha: alpha);
    canvas.drawLine(const Offset(58.8, 30), const Offset(60.2, 30), bar); // bridge
    canvas.drawLine(const Offset(52.4, 29.9), const Offset(48.6, 31.4), bar); // arm
    // the heavy top rim catches a little light
    canvas.drawLine(
      const Offset(52.8, 29.7),
      const Offset(58.4, 29.7),
      Paint()
        ..strokeWidth = 0.35
        ..color = const Color(0xFF3A4654).withValues(alpha: alpha),
    );

    // a sweep of light across the lenses as they land, then every so often
    final sweep = _seg(e, 0.86, 1.0);
    final later = (amb * 2) % 1.0;
    final p = sweep > 0 && sweep < 1
        ? sweep
        : (later < 0.06 ? later / 0.06 : (tapT > 0 && tapT < 0.5 ? tapT / 0.5 : -1.0));
    canvas.save();
    canvas.clipPath(Path()
      ..addPath(near, Offset.zero)
      ..addPath(far, Offset.zero));
    // a faint standing reflection, so they read as glass and not as holes
    canvas.drawLine(
      const Offset(53.8, 33),
      const Offset(55.6, 30.2),
      Paint()
        ..strokeWidth = 0.6
        ..color = Colors.white.withValues(alpha: 0.16 * alpha),
    );
    if (p >= 0 && p <= 1) {
      final x = 50 + 16 * p;
      canvas.drawPath(
        Path()
          ..moveTo(x, 28.6)
          ..lineTo(x + 1.8, 28.6)
          ..lineTo(x - 0.4, 34.4)
          ..lineTo(x - 2.2, 34.4)
          ..close(),
        Paint()..color = Colors.white.withValues(alpha: 0.7 * alpha),
      );
    }
    canvas.restore();
    canvas.restore();
  }

  /// The 'imma: the dome fades in, then each band is wound round in turn.
  void _paintTurban(Canvas canvas, double v) {
    if (v <= 0) return;
    // its lower edge sits low on the brow, just above the glasses
    final dome = Path()
      ..moveTo(44.8, 30.4)
      ..quadraticBezierTo(42.8, 21, 47, 17)
      ..quadraticBezierTo(52, 12.5, 58.5, 14)
      ..quadraticBezierTo(65, 16, 64.4, 25.6)
      ..quadraticBezierTo(64, 28.4, 62.6, 29.4)
      ..quadraticBezierTo(53.4, 27.6, 44.8, 30.4)
      ..close();
    final domeAlpha = (v * 3).clamp(0.0, 1.0);
    canvas.drawPath(
      dome,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(46, 14),
          const Offset(62, 30),
          [Colors.white.withValues(alpha: domeAlpha), const Color(0xFFE8E4DA).withValues(alpha: domeAlpha)],
        ),
    );

    // the wraps cross one another, as the cloth is wound alternately up
    // and down round the head
    const bands = [
      [45.2, 28.4, 54.0, 25.6, 63.8, 27.4],
      [44.2, 25.4, 50.6, 19.4, 60.6, 15.8],
      [47.8, 17.6, 56.6, 18.0, 64.4, 23.4],
      [45.0, 21.8, 54.0, 21.6, 63.2, 18.8],
    ];
    final band = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.75
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFD0CBC0);
    for (var i = 0; i < bands.length; i++) {
      final local = (v * (bands.length + 1) - i - 0.6).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final b = bands[i];
      final path = Path()
        ..moveTo(b[0], b[1])
        ..quadraticBezierTo(b[2], b[3], b[4], b[5]);
      for (final m in path.computeMetrics()) {
        canvas.drawPath(m.extractPath(0, m.length * local), band);
      }
    }
  }

  /// 0 → 1 → 0 across [a, b].
  static double _bump(double t, double a, double b) {
    if (t <= a || t >= b) return 0;
    return math.sin(math.pi * (t - a) / (b - a));
  }

  @override
  bool shouldRepaint(_ManPainter old) => old.still != still;
}

Path _diamond(Offset c, double hw, double hh) => Path()
  ..moveTo(c.dx, c.dy - hh)
  ..lineTo(c.dx + hw, c.dy)
  ..lineTo(c.dx, c.dy + hh)
  ..lineTo(c.dx - hw, c.dy)
  ..close();
