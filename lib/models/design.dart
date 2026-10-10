double? _toDouble(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

/// One colour the customer can pick: a cloth or an embroidery thread.
/// [color] is 0xRRGGBB, the same value the 3D engine receives.
///
/// The standard palette has no [name] (it is translated from [id]); a
/// colour a tailor added carries the name they typed and their [price],
/// the amount added on top of the shop's base price.
class Swatch {
  const Swatch(this.id, this.color, {this.name, this.price = 0});

  final String id;
  final int color;
  final String? name;
  final double price;

  static const maxName = 40;
  static const maxPerKind = 30;

  /// Null when [j] is not a usable option.
  static Swatch? tryParse(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    final color = j['color'];
    if (id is! String || id.isEmpty || color is! num) return null;
    final name = j['name'];
    final price = _toDouble(j['price']) ?? 0;
    return Swatch(
      id,
      color.toInt() & 0xFFFFFF,
      name: name is String && name.trim().isNotEmpty ? name.trim() : null,
      price: price < 0 ? 0 : price,
    );
  }

  static List<Swatch> listFromJson(Object? j) {
    if (j is! List) return const [];
    return j.map(tryParse).whereType<Swatch>().toList();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'color': color,
        'price': price,
      };

  Swatch copyWith({String? name, int? color, double? price}) =>
      Swatch(id, color ?? this.color, name: name ?? this.name, price: price ?? this.price);
}

class JalabiyaDesign {
  const JalabiyaDesign({
    required this.cut,
    required this.hem,
    required this.cuff,
    required this.collar,
    required this.emb,
    required this.cloth,
    required this.thread,
  });

  /// Sweep: how full the robe is at the hem.
  final String cut; // slim | regular | full
  /// Centimetres between hem and floor.
  final double hem;
  /// Sleeve opening, all round, in centimetres.
  final double cuff;
  final String collar; // round | band | shirt
  final String emb; // none | neck | full
  /// The cloth and thread as the tailor offered them when chosen, so an order
  /// keeps its colour and price after the shop changes its list.
  final Swatch cloth;
  final Swatch thread;

  static const cuts = ['slim', 'regular', 'full'];
  static const collars = ['round', 'band', 'shirt'];
  static const embroideries = ['none', 'neck', 'full'];

  /// The standard palette, offered by shops that have not set their own.
  static const cloths = [
    Swatch('damuriya', 0xF5F1E6),
    Swatch('cream', 0xEDDFC2),
    Swatch('nile', 0xB9CDD9),
    Swatch('sand', 0xDCC6A2),
    Swatch('ash', 0xC3C7CB),
    Swatch('charcoal', 0x4A5058),
  ];
  static const threads = [
    Swatch('gold', 0xC8A24A),
    Swatch('white', 0xF6F3EA),
    Swatch('indigo', 0x2B3F63),
    Swatch('henna', 0x9C4A2F),
  ];

  static const hemMin = 0.0, hemMax = 30.0;
  static const cuffMin = 22.0, cuffMax = 60.0;

  static const JalabiyaDesign defaults = JalabiyaDesign(
    cut: 'regular',
    hem: 4,
    cuff: 34,
    collar: 'band',
    emb: 'neck',
    cloth: Swatch('damuriya', 0xF5F1E6),
    thread: Swatch('gold', 0xC8A24A),
  );

  static Swatch clothSwatch(String id) =>
      cloths.firstWhere((s) => s.id == id, orElse: () => cloths.first);
  static Swatch threadSwatch(String id) =>
      threads.firstWhere((s) => s.id == id, orElse: () => threads.first);

  /// What the cloth and thread add to the shop's base price, per piece.
  /// Thread only counts when there is embroidery to sew with it.
  double get extrasPrice => cloth.price + (emb == 'none' ? 0 : thread.price);

  JalabiyaDesign copyWith({
    String? cut,
    double? hem,
    double? cuff,
    String? collar,
    String? emb,
    Swatch? cloth,
    Swatch? thread,
  }) {
    return JalabiyaDesign(
      cut: cut ?? this.cut,
      hem: hem ?? this.hem,
      cuff: cuff ?? this.cuff,
      collar: collar ?? this.collar,
      emb: emb ?? this.emb,
      cloth: cloth ?? this.cloth,
      thread: thread ?? this.thread,
    );
  }

  /// The server looks the cloth and thread up in the shop's list by id and
  /// stores its own copy, so only the ids matter here.
  Map<String, dynamic> toJson() => {
        'cut': cut,
        'hem': hem,
        'cuff': cuff,
        'collar': collar,
        'emb': emb,
        'cloth': cloth.id,
        'thread': thread.id,
      };

  factory JalabiyaDesign.fromJson(Map<String, dynamic>? json) {
    final j = json ?? const <String, dynamic>{};
    String pick(String k, List<String> allowed, String fallback) {
      final v = j[k];
      return (v is String && allowed.contains(v)) ? v : fallback;
    }

    double num_(String k, double lo, double hi, double fallback) {
      final raw = j[k];
      double? v;
      if (raw is num) v = raw.toDouble();
      if (raw is String) v = double.tryParse(raw);
      v ??= fallback;
      if (v < lo) return lo;
      if (v > hi) return hi;
      return v.roundToDouble();
    }

    // Orders store the option the shop offered; older orders only the id of
    // a standard colour.
    Swatch option(String k, String fallbackId, Swatch Function(String) standard) {
      final stored = Swatch.tryParse(j['${k}_option']);
      if (stored != null) return stored;
      final id = j[k];
      return standard(id is String ? id : fallbackId);
    }

    return JalabiyaDesign(
      cut: pick('cut', cuts, defaults.cut),
      hem: num_('hem', hemMin, hemMax, defaults.hem),
      cuff: num_('cuff', cuffMin, cuffMax, defaults.cuff),
      collar: pick('collar', collars, defaults.collar),
      emb: pick('emb', embroideries, defaults.emb),
      cloth: option('cloth', defaults.cloth.id, clothSwatch),
      thread: option('thread', defaults.thread.id, threadSwatch),
    );
  }
}
