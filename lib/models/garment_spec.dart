import 'design.dart';
import 'measurements.dart';

/// The finished garment the tailor cuts, derived from body + design.
///
/// These constants mirror the 3D engine (assets/engine/fitting_room.html) so
/// the numbers on the cutting list match the robe drawn on screen.
class GarmentSpec {
  const GarmentSpec({
    required this.length,
    required this.chest,
    required this.hem,
    required this.shoulderSeam,
    required this.sleeve,
    required this.cuff,
    required this.neckOpening,
    required this.fabricMetres,
    required this.sizeLabel,
  });

  static const double chestEase = 16;
  static const double neckEase = 6;
  static const double shoulderEase = 3;
  static const double shoulderHeight = 0.818; // fraction of stature
  static const double sleeveFactor = 0.94;
  static const Map<String, double> sweep = {
    'slim': 1.30,
    'regular': 1.62,
    'full': 2.05,
  };
  static const Map<String, double> fabricFactor = {
    'slim': 2.0,
    'regular': 2.25,
    'full': 2.6,
  };

  /// Shoulder to hem.
  final double length;
  /// Finished chest, all round.
  final double chest;
  /// Hem, all round.
  final double hem;
  final double shoulderSeam;
  /// Shoulder seam to cuff.
  final double sleeve;
  final double cuff;
  final double neckOpening;
  /// Cloth to buy, an estimate the tailor can override.
  final double fabricMetres;
  /// Nearest ready-made size from the body chest.
  final String sizeLabel;

  double get fabricYards => fabricMetres / 0.9144;

  static String sizeFor(double bodyChest) {
    if (bodyChest < 88) return 'S';
    if (bodyChest < 96) return 'M';
    if (bodyChest < 104) return 'L';
    if (bodyChest < 112) return 'XL';
    if (bodyChest < 122) return '2XL';
    if (bodyChest < 132) return '3XL';
    return '4XL';
  }

  factory GarmentSpec.compute(Measurements m, JalabiyaDesign d) {
    final chestC = m.chest + chestEase;
    final length = m.height * shoulderHeight + 1.0 - d.hem;
    final sleeve = m.arm * sleeveFactor;
    final factor = fabricFactor[d.cut] ?? 2.25;
    return GarmentSpec(
      length: length,
      chest: chestC,
      hem: chestC * (sweep[d.cut] ?? 1.62),
      shoulderSeam: m.shoulder + shoulderEase,
      sleeve: sleeve,
      cuff: d.cuff,
      neckOpening: m.neck + neckEase,
      fabricMetres: (length + sleeve + 30) / 100 * factor,
      sizeLabel: sizeFor(m.chest),
    );
  }
}

/// What the WebView needs to draw this exact person in this exact robe.
Map<String, dynamic> engineState(Measurements m, JalabiyaDesign d) {
  final state = <String, dynamic>{};
  state.addAll(m.toJson());
  state['cut'] = d.cut;
  state['hem'] = d.hem;
  state['cuff'] = d.cuff;
  state['collar'] = d.collar;
  state['emb'] = d.emb;
  state['clothColor'] = d.cloth.color;
  state['threadColor'] = d.thread.color;
  return state;
}
