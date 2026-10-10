enum UserRole { customer, tailor }

UserRole roleFromDb(Object? v) =>
    v == 'tailor' ? UserRole.tailor : UserRole.customer;

String roleToDb(UserRole r) => r == UserRole.tailor ? 'tailor' : 'customer';

String digitsOnly(String s) {
  const arabicIndic = '٠١٢٣٤٥٦٧٨٩';
  const easternArabic = '۰۱۲۳۴۵۶۷۸۹';
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final a = arabicIndic.indexOf(ch);
    final e = easternArabic.indexOf(ch);
    if (a >= 0) {
      b.write(a);
    } else if (e >= 0) {
      b.write(e);
    } else if ('0123456789'.contains(ch)) {
      b.write(ch);
    }
  }
  return b.toString();
}

/// Matches profile_is_complete() in supabase/schema.sql.
bool isValidPhone(String? phone) {
  final d = digitsOnly(phone ?? '');
  return d.length >= 9 && d.length <= 15;
}

/// An admin blocked this account (account_blocks in supabase/admin.sql):
/// the server refuses its order and shop changes, and the app says why.
class AccountBlock {
  const AccountBlock({required this.reason, this.since, this.liftedAt});

  final String reason;
  final DateTime? since;

  /// When an admin lifted it. The row stays after an unblock so Realtime can
  /// tell the app; a lifted block no longer applies.
  final DateTime? liftedAt;

  bool get active => liftedAt == null;

  factory AccountBlock.fromJson(Map<String, dynamic> j) {
    DateTime? time(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
    return AccountBlock(
      reason: (j['reason'] as String?) ?? '',
      since: time(j['created_at']),
      liftedAt: time(j['lifted_at']),
    );
  }
}

class Profile {
  const Profile({
    required this.id,
    required this.role,
    required this.fullName,
    required this.phone,
    this.whatsapp,
    this.city,
    this.neighbourhood,
    this.addressDetails,
    this.createdAt,
  });

  final String id;
  final UserRole role;
  final String fullName;
  final String phone;
  final String? whatsapp;
  final String? city;
  final String? neighbourhood;
  final String? addressDetails;
  final DateTime? createdAt;

  bool get isTailor => role == UserRole.tailor;

  /// The fields every account must fill before it can order or take orders.
  /// Each entry is (field key, filled?). Used for the progress bar and the gate.
  List<MapEntry<String, bool>> get checklist => [
        MapEntry('fullName', fullName.trim().length >= 3),
        MapEntry('phone', isValidPhone(phone)),
        MapEntry('city', (city ?? '').trim().isNotEmpty),
        MapEntry('neighbourhood', (neighbourhood ?? '').trim().isNotEmpty),
        MapEntry('addressDetails', (addressDetails ?? '').trim().length >= 5),
      ];

  bool get detailsComplete => checklist.every((e) => e.value);

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: j['id'] as String,
        role: roleFromDb(j['role']),
        fullName: (j['full_name'] as String?) ?? '',
        phone: (j['phone'] as String?) ?? '',
        whatsapp: j['whatsapp'] as String?,
        city: j['city'] as String?,
        neighbourhood: j['neighbourhood'] as String?,
        addressDetails: j['address_details'] as String?,
        createdAt: j['created_at'] == null
            ? null
            : DateTime.tryParse(j['created_at'] as String),
      );

  /// What the app is allowed to write (role and id are guarded server-side).
  Map<String, dynamic> toWriteJson() => {
        'id': id,
        'role': roleToDb(role),
        'full_name': fullName.trim(),
        'phone': phone.trim(),
        'whatsapp': (whatsapp ?? '').trim().isEmpty ? null : whatsapp!.trim(),
        'city': city?.trim(),
        'neighbourhood': neighbourhood?.trim(),
        'address_details': addressDetails?.trim(),
      };

  Profile copyWith({
    String? fullName,
    String? phone,
    String? whatsapp,
    String? city,
    String? neighbourhood,
    String? addressDetails,
  }) {
    return Profile(
      id: id,
      role: role,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      whatsapp: whatsapp ?? this.whatsapp,
      city: city ?? this.city,
      neighbourhood: neighbourhood ?? this.neighbourhood,
      addressDetails: addressDetails ?? this.addressDetails,
      createdAt: createdAt,
    );
  }
}
