import 'package:flutter_test/flutter_test.dart';
import 'package:jalabiya_app/models/design.dart';
import 'package:jalabiya_app/models/garment_spec.dart';
import 'package:jalabiya_app/models/measurements.dart';
import 'package:jalabiya_app/util/format.dart';

void main() {
  group('GarmentSpec', () {
    // Same numbers the web prototype's cutting list printed for its defaults.
    final g = GarmentSpec.compute(Measurements.defaults, JalabiyaDesign.defaults);

    test('shoulder to hem follows stature and hem height', () {
      expect(g.length, closeTo(140.15, 1e-9));
      expect(formatLength(g.length, LengthUnit.cm), '140.1 cm');
    });

    test('ease is added at chest, neck and shoulder', () {
      expect(g.chest, 116);
      expect(g.neckOpening, 45);
      expect(g.shoulderSeam, 49);
    });

    test('hem sweep scales with the chosen cut', () {
      expect(g.hem, closeTo(116 * 1.62, 1e-9));
      final full = GarmentSpec.compute(
          Measurements.defaults, JalabiyaDesign.defaults.copyWith(cut: 'full'));
      expect(full.hem, closeTo(116 * 2.05, 1e-9));
    });

    test('sleeve and cloth estimate', () {
      expect(g.sleeve, closeTo(56.4, 1e-9));
      expect(g.fabricMetres, closeTo((140.15 + 56.4 + 30) / 100 * 2.25, 1e-9));
      expect(g.fabricYards, closeTo(g.fabricMetres / 0.9144, 1e-9));
    });

    test('nearest ready size boundaries', () {
      expect(GarmentSpec.sizeFor(87.9), 'S');
      expect(GarmentSpec.sizeFor(88), 'M');
      expect(GarmentSpec.sizeFor(100), 'L');
      expect(GarmentSpec.sizeFor(104), 'XL');
      expect(GarmentSpec.sizeFor(121.9), '2XL');
      expect(GarmentSpec.sizeFor(131), '3XL');
      expect(GarmentSpec.sizeFor(150), '4XL');
      expect(g.sizeLabel, 'L');
    });

    test('engine state carries sizes, choices and colours', () {
      final s = engineState(
          Measurements.defaults,
          JalabiyaDesign.defaults.copyWith(
              cloth: JalabiyaDesign.clothSwatch('nile'), thread: JalabiyaDesign.threadSwatch('henna')));
      expect(s['chest'], 100);
      expect(s['cut'], 'regular');
      expect(s['clothColor'], 0xB9CDD9);
      expect(s['threadColor'], 0x9C4A2F);
      expect(s.containsKey('cloth'), isFalse);
    });
  });

  group('formatting', () {
    test('lengths in cm and inches', () {
      expect(formatLength(100, LengthUnit.cm), '100 cm');
      expect(formatLength(46.5, LengthUnit.cm), '46.5 cm');
      expect(formatLength(100, LengthUnit.inch), '39.4″');
    });

    test('Arabic digits and comma decimals are understood', () {
      expect(parseLooseNumber('١٠٤٫٥'), 104.5);
      expect(parseLooseNumber('104,5'), 104.5);
      expect(parseLooseNumber(' 98 '), 98);
      expect(parseLooseNumber('abc'), isNull);
    });

    test('unit round trip', () {
      expect(fromUnit(toUnit(100, LengthUnit.inch), LengthUnit.inch), closeTo(100, 1e-9));
    });
  });
}
