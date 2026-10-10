import 'measurements.dart';

/// A saved person: the customer, a son, a father. Each order picks one.
class MeasurementSet {
  const MeasurementSet({
    required this.id,
    required this.label,
    required this.relation,
    required this.measurements,
    this.updatedAt,
  });

  final String id;
  final String label;
  final String relation; // self | son | father | brother | other
  final Measurements measurements;
  final DateTime? updatedAt;

  static const relations = ['self', 'son', 'father', 'brother', 'other'];

  factory MeasurementSet.fromJson(Map<String, dynamic> j) => MeasurementSet(
        id: j['id'] as String,
        label: (j['label'] as String?) ?? '',
        relation: (j['relation'] as String?) ?? 'self',
        measurements: Measurements.fromJson(j),
        updatedAt: j['updated_at'] == null
            ? null
            : DateTime.tryParse(j['updated_at'] as String),
      );

  /// Columns for insert/update. The owner is added by the repository.
  static Map<String, dynamic> columns(
      String label, String relation, Measurements m) {
    final row = <String, dynamic>{
      'label': label.trim(),
      'relation': relation,
    };
    row.addAll(m.toJson());
    return row;
  }
}
