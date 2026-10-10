import 'design.dart';

double? _toDouble(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

/// Where a shop is in the admin's review (tailor_shops.review_status in
/// supabase/admin.sql). Customers see a shop only when [TailorShop.approved],
/// which the server keeps true for approved shops whose owner isn't blocked.
enum ShopReview { pending, approved, rejected, suspended }

/// Databases without admin.sql have no review column: `approved` decides.
ShopReview reviewFromDb(Object? v, {bool approved = false}) => switch (v) {
      'pending' => ShopReview.pending,
      'approved' => ShopReview.approved,
      'rejected' => ShopReview.rejected,
      'suspended' => ShopReview.suspended,
      _ => approved ? ShopReview.approved : ShopReview.pending,
    };

class TailorShop {
  const TailorShop({
    required this.tailorId,
    required this.shopName,
    required this.city,
    required this.neighbourhood,
    required this.addressDetails,
    required this.basePrice,
    required this.leadTimeDays,
    this.bio,
    this.currency = 'SDG',
    this.acceptsOrders = true,
    this.approved = false,
    this.review = ShopReview.pending,
    this.reviewNote,
    this.clothOptions = const [],
    this.threadOptions = const [],
    this.ownerName,
    this.ownerPhone,
    this.ownerWhatsapp,
  });

  final String tailorId;
  final String shopName;
  final String? bio;
  final String city;
  final String neighbourhood;
  final String addressDetails;
  final double basePrice;
  final String currency;
  final int leadTimeDays;
  final bool acceptsOrders;

  /// Customers can see the shop.
  final bool approved;
  final ShopReview review;

  /// The reviewer's reason, shown to the tailor when rejected or suspended.
  final String? reviewNote;

  /// The cloth and thread colours this tailor works with. Empty means they
  /// have not set any, and customers get the standard palette at no extra.
  final List<Swatch> clothOptions;
  final List<Swatch> threadOptions;

  /// Filled when loaded with the owner's profile embedded.
  final String? ownerName;
  final String? ownerPhone;
  final String? ownerWhatsapp;

  /// What a customer can choose from at this shop. Mirrors shop_option() in
  /// supabase/shop_options.sql.
  List<Swatch> get offeredCloths => clothOptions.isEmpty ? JalabiyaDesign.cloths : clothOptions;
  List<Swatch> get offeredThreads => threadOptions.isEmpty ? JalabiyaDesign.threads : threadOptions;

  /// Mirrors protect_shop() in supabase/admin.sql: saving [next] sends this
  /// shop back for review (hidden until approved again) when it was rejected,
  /// or when it was approved and its name or place changes.
  bool saveSendsForReview(TailorShop next) {
    if (review == ShopReview.rejected) return true;
    if (review != ShopReview.approved) return false;
    bool differs(String a, String b) => a.trim() != b.trim();
    return differs(shopName, next.shopName) ||
        differs(city, next.city) ||
        differs(neighbourhood, next.neighbourhood) ||
        differs(addressDetails, next.addressDetails);
  }

  factory TailorShop.fromJson(Map<String, dynamic> j) {
    final owner = j['owner'] is Map<String, dynamic>
        ? j['owner'] as Map<String, dynamic>
        : null;
    final approved = (j['approved'] as bool?) ?? false;
    return TailorShop(
      tailorId: j['tailor_id'] as String,
      shopName: (j['shop_name'] as String?) ?? '',
      bio: j['bio'] as String?,
      city: (j['city'] as String?) ?? '',
      neighbourhood: (j['neighbourhood'] as String?) ?? '',
      addressDetails: (j['address_details'] as String?) ?? '',
      basePrice: _toDouble(j['base_price']) ?? 0,
      currency: (j['currency'] as String?) ?? 'SDG',
      leadTimeDays: (j['lead_time_days'] as num?)?.toInt() ?? 7,
      acceptsOrders: (j['accepts_orders'] as bool?) ?? true,
      approved: approved,
      review: reviewFromDb(j['review_status'], approved: approved),
      reviewNote: j['review_note'] as String?,
      clothOptions: Swatch.listFromJson(j['cloth_options']),
      threadOptions: Swatch.listFromJson(j['thread_options']),
      ownerName: owner == null ? null : owner['full_name'] as String?,
      ownerPhone: owner == null ? null : owner['phone'] as String?,
      ownerWhatsapp: owner == null ? null : owner['whatsapp'] as String?,
    );
  }

  TailorShop copyWith({List<Swatch>? clothOptions, List<Swatch>? threadOptions}) {
    return TailorShop(
      tailorId: tailorId,
      shopName: shopName,
      bio: bio,
      city: city,
      neighbourhood: neighbourhood,
      addressDetails: addressDetails,
      basePrice: basePrice,
      leadTimeDays: leadTimeDays,
      currency: currency,
      acceptsOrders: acceptsOrders,
      approved: approved,
      review: review,
      reviewNote: reviewNote,
      clothOptions: clothOptions ?? this.clothOptions,
      threadOptions: threadOptions ?? this.threadOptions,
      ownerName: ownerName,
      ownerPhone: ownerPhone,
      ownerWhatsapp: ownerWhatsapp,
    );
  }

  /// `approved` and the review are never sent: only the dashboard can change them.
  Map<String, dynamic> toWriteJson() => {
        'tailor_id': tailorId,
        'shop_name': shopName.trim(),
        'bio': (bio ?? '').trim().isEmpty ? null : bio!.trim(),
        'city': city.trim(),
        'neighbourhood': neighbourhood.trim(),
        'address_details': addressDetails.trim(),
        'base_price': basePrice,
        'currency': currency,
        'lead_time_days': leadTimeDays,
        'accepts_orders': acceptsOrders,
        'cloth_options': [for (final s in clothOptions) s.toJson()],
        'thread_options': [for (final s in threadOptions) s.toJson()],
      };
}

double? parseDouble(Object? v) => _toDouble(v);
