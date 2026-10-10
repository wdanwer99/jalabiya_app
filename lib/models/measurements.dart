/// Body measurements in centimetres. These are the customer's body, not the
/// garment: ease is added later in [GarmentSpec].
class MeasureSpec {
  const MeasureSpec(this.key, this.min, this.max, this.step);

  final String key;
  final double min;
  final double max;
  final double step;

  double clamp(double v) {
    if (v.isNaN) return min;
    if (v < min) return min;
    if (v > max) return max;
    return v;
  }

  /// Snaps to the slider step so 100.30000001 never reaches the database.
  double snap(double v) {
    final snapped = (clamp(v) / step).round() * step;
    return double.parse(clamp(snapped).toStringAsFixed(1));
  }
}

class Measurements {
  const Measurements({
    required this.height,
    required this.chest,
    required this.waist,
    required this.hip,
    required this.shoulder,
    required this.arm,
    required this.neck,
  });

  final double height;
  final double chest;
  final double waist;
  final double hip;
  final double shoulder;
  final double arm;
  final double neck;

  /// Same ranges as the database check constraints and the 3D engine.
  static const List<MeasureSpec> specs = [
    MeasureSpec('height', 145, 205, 1),
    MeasureSpec('chest', 76, 150, 1),
    MeasureSpec('waist', 64, 150, 1),
    MeasureSpec('hip', 76, 150, 1),
    MeasureSpec('shoulder', 36, 58, 0.5),
    MeasureSpec('arm', 48, 74, 0.5),
    MeasureSpec('neck', 32, 50, 0.5),
  ];

  static const Measurements defaults = Measurements(
    height: 175,
    chest: 100,
    waist: 90,
    hip: 100,
    shoulder: 46,
    arm: 60,
    neck: 39,
  );

  static MeasureSpec specFor(String key) =>
      specs.firstWhere((s) => s.key == key);

  double valueOf(String key) {
    switch (key) {
      case 'height':
        return height;
      case 'chest':
        return chest;
      case 'waist':
        return waist;
      case 'hip':
        return hip;
      case 'shoulder':
        return shoulder;
      case 'arm':
        return arm;
      case 'neck':
        return neck;
    }
    throw ArgumentError('Unknown measurement: $key');
  }

  Measurements withValue(String key, double value) {
    final v = specFor(key).snap(value);
    return Measurements(
      height: key == 'height' ? v : height,
      chest: key == 'chest' ? v : chest,
      waist: key == 'waist' ? v : waist,
      hip: key == 'hip' ? v : hip,
      shoulder: key == 'shoulder' ? v : shoulder,
      arm: key == 'arm' ? v : arm,
      neck: key == 'neck' ? v : neck,
    );
  }

  bool get isValid => specs.every((s) {
        final v = valueOf(s.key);
        return v >= s.min && v <= s.max;
      });

  Map<String, dynamic> toJson() => {
        'height': height,
        'chest': chest,
        'waist': waist,
        'hip': hip,
        'shoulder': shoulder,
        'arm': arm,
        'neck': neck,
      };

  /// Accepts numbers or numeric strings (Postgres numeric can arrive as
  /// either). Anything missing falls back to the default, then clamps.
  factory Measurements.fromJson(Map<String, dynamic>? json) {
    double read(String k) {
      final spec = specFor(k);
      final raw = json == null ? null : json[k];
      double? v;
      if (raw is num) v = raw.toDouble();
      if (raw is String) v = double.tryParse(raw);
      return spec.snap(v ?? defaults.valueOf(k));
    }

    return Measurements(
      height: read('height'),
      chest: read('chest'),
      waist: read('waist'),
      hip: read('hip'),
      shoulder: read('shoulder'),
      arm: read('arm'),
      neck: read('neck'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Measurements &&
      specs.every((s) => other.valueOf(s.key) == valueOf(s.key));

  @override
  int get hashCode =>
      Object.hash(height, chest, waist, hip, shoulder, arm, neck);
}
