import 'package:flutter_test/flutter_test.dart';
import 'package:jalabiya_app/l10n/strings.dart';
import 'package:jalabiya_app/models/design.dart';
import 'package:jalabiya_app/models/measurements.dart';
import 'package:jalabiya_app/models/order.dart';
import 'package:jalabiya_app/models/profile.dart';
import 'package:jalabiya_app/models/tailor_shop.dart';
import 'package:jalabiya_app/util/contact.dart';

void main() {
  group('Measurements', () {
    test('reads strings from Postgres numeric and clamps to the allowed range', () {
      final m = Measurements.fromJson({'chest': '104', 'height': 300, 'neck': 10});
      expect(m.chest, 104);
      expect(m.height, 205);
      expect(m.neck, 32);
      expect(m.waist, Measurements.defaults.waist);
    });

    test('snaps to the slider step', () {
      expect(Measurements.defaults.withValue('shoulder', 46.3).shoulder, 46.5);
      expect(Measurements.defaults.withValue('chest', 100.4).chest, 100);
    });

    test('equality by value', () {
      expect(Measurements.fromJson(Measurements.defaults.toJson()), Measurements.defaults);
      expect(Measurements.defaults.withValue('arm', 61) == Measurements.defaults, isFalse);
    });
  });

  group('Design', () {
    test('unknown values fall back to defaults', () {
      final d = JalabiyaDesign.fromJson({'cut': 'tent', 'cloth': 'silk', 'hem': 99, 'cuff': '40'});
      expect(d.cut, 'regular');
      expect(d.cloth.id, 'damuriya');
      expect(d.hem, 30);
      expect(d.cuff, 40);
    });

    test("an order's stored option wins over the standard palette", () {
      final d = JalabiyaDesign.fromJson({
        'emb': 'neck',
        'cloth': 'white-cotton',
        'cloth_option': {'id': 'white-cotton', 'name': 'Egyptian cotton', 'color': 0xFAFAF5, 'price': '5000'},
        'thread': 'gold',
      });
      expect(d.cloth.name, 'Egyptian cotton');
      expect(d.cloth.color, 0xFAFAF5);
      expect(d.cloth.price, 5000);
      expect(d.thread.color, 0xC8A24A);
      expect(d.extrasPrice, 5000);
      expect(d.toJson()['cloth'], 'white-cotton');
    });

    test('thread costs extra only with embroidery', () {
      final d = JalabiyaDesign.defaults.copyWith(
          cloth: const Swatch('c1', 0x111111, name: 'Black', price: 1000),
          thread: const Swatch('t1', 0xC0C0C0, name: 'Silver', price: 500));
      expect(d.extrasPrice, 1500);
      expect(d.copyWith(emb: 'none').extrasPrice, 1000);
    });
  });

  group('TailorShop', () {
    const base = {
      'tailor_id': 't1', 'shop_name': 'A', 'city': 'x', 'neighbourhood': 'y',
      'address_details': 'z', 'base_price': 100, 'lead_time_days': 7,
    };

    test('a shop without its own colours offers the standard palette', () {
      final s = TailorShop.fromJson(base);
      expect(s.offeredCloths, JalabiyaDesign.cloths);
      expect(s.offeredThreads, JalabiyaDesign.threads);
    });

    test("a shop's own colours replace the standard ones and round-trip", () {
      final s = TailorShop.fromJson({
        ...base,
        'cloth_options': [
          {'id': 'navy', 'name': 'Navy', 'color': 0x1F2A44, 'price': 0},
          {'id': 'broken'},
        ],
      });
      expect(s.offeredCloths.map((e) => e.id), ['navy']);
      expect(s.offeredThreads, JalabiyaDesign.threads);
      expect(s.toWriteJson()['cloth_options'], [
        {'id': 'navy', 'name': 'Navy', 'color': 0x1F2A44, 'price': 0.0},
      ]);
    });

    test('reads the review, and falls back to approved on databases without admin.sql', () {
      final rejected = TailorShop.fromJson({...base, 'review_status': 'rejected', 'review_note': 'Add your street'});
      expect(rejected.review, ShopReview.rejected);
      expect(rejected.reviewNote, 'Add your street');
      expect(rejected.copyWith().review, ShopReview.rejected);
      expect(TailorShop.fromJson({...base, 'approved': true}).review, ShopReview.approved);
      expect(TailorShop.fromJson(base).review, ShopReview.pending);
      expect(rejected.toWriteJson().containsKey('review_status'), isFalse);
    });

    test('saving sends a shop back for review like protect_shop() in admin.sql', () {
      TailorShop shop(String review, {String name = 'A', String city = 'x', String note = 'z'}) =>
          TailorShop.fromJson({...base, 'shop_name': name, 'city': city, 'address_details': note, 'review_status': review});
      final approved = shop('approved');
      expect(approved.saveSendsForReview(shop('approved', name: 'B')), isTrue);
      expect(approved.saveSendsForReview(shop('approved', city: 'khartoum')), isTrue);
      expect(approved.saveSendsForReview(shop('approved', note: 'Row 4')), isTrue);
      expect(approved.saveSendsForReview(shop('approved', name: ' A ')), isFalse, reason: 'the app trims');
      expect(approved.saveSendsForReview(approved.copyWith(clothOptions: JalabiyaDesign.cloths)), isFalse);
      expect(shop('rejected').saveSendsForReview(shop('rejected')), isTrue, reason: 'any save resubmits');
      expect(shop('pending').saveSendsForReview(shop('pending', name: 'B')), isFalse);
      expect(shop('suspended').saveSendsForReview(shop('suspended', name: 'B')), isFalse);
    });
  });

  group('Profile', () {
    test('completeness matches the server gate', () {
      const p = Profile(id: 'x', role: UserRole.customer, fullName: 'Osman Ali', phone: '0912345678');
      expect(p.detailsComplete, isFalse);
      final full = p.copyWith(city: 'khartoum', neighbourhood: 'Riyadh', addressDetails: 'Street 15');
      expect(full.detailsComplete, isTrue);
      expect(full.copyWith(phone: '12').detailsComplete, isFalse);
    });

    test('a block applies until an admin lifts it (the row stays for Realtime)', () {
      final b = AccountBlock.fromJson({'reason': 'Fake orders', 'created_at': '2026-10-09T10:00:00Z'});
      expect(b.active, isTrue);
      expect(b.since, isNotNull);
      final lifted = AccountBlock.fromJson({'reason': 'Fake orders', 'lifted_at': '2026-10-10T10:00:00Z'});
      expect(lifted.active, isFalse);
    });

    test('phones typed with Arabic digits count', () {
      expect(isValidPhone('٠٩١٢٣٤٥٦٧٨'), isTrue);
      expect(digitsOnly('+249 91-234'), '24991234');
    });
  });

  group('Contact links', () {
    test('local Sudanese numbers gain the country code', () {
      expect(internationalNumber('0912345678'), '249912345678');
      expect(internationalNumber('+249 91 234 5678'), '249912345678');
      expect(internationalNumber('00201001234567'), '201001234567');
    });
  });

  group('Order', () {
    test('parses a row with embedded shop and customer', () {
      final o = Order.fromJson({
        'id': '5b1f0d1e-0000-4000-8000-000000000001',
        'customer_id': 'c1',
        'tailor_id': 't1',
        'measurement_set_id': null,
        'wearer_label': 'Ahmed',
        'measurements': {'height': 160, 'chest': 84, 'waist': 72, 'hip': 88, 'shoulder': 41, 'arm': 55, 'neck': 35},
        'design': {'cut': 'full', 'hem': 3, 'cuff': 36, 'collar': 'shirt', 'emb': 'none', 'cloth': 'cream', 'thread': 'gold'},
        'delivery': {'name': 'Osman', 'phone': '0912345678', 'city': 'omdurman', 'neighbourhood': 'Souq', 'address_details': 'Row 3'},
        'quantity': 2,
        'status': 'changes_requested',
        'price': '30000.00',
        'currency': 'SDG',
        'due_date': '2026-11-01',
        'tailor_note': 'Re-measure arm',
        'created_at': '2026-10-08T13:48:34.057+00:00',
        'updated_at': '2026-10-08T14:00:00+00:00',
        'shop': {
          'tailor_id': 't1', 'shop_name': 'Abdelrahim', 'city': 'omdurman', 'neighbourhood': 'Souq',
          'address_details': 'Row 3', 'base_price': 25000, 'lead_time_days': 7, 'approved': true,
          'owner': {'full_name': 'Abdelrahim', 'phone': '0911111111', 'whatsapp': null},
        },
        'customer': {'id': 'c1', 'role': 'customer', 'full_name': 'Osman', 'phone': '0912345678'},
      });
      expect(o.status, OrderStatus.changesRequested);
      expect(o.price, 30000);
      expect(o.dueDate, DateTime(2026, 11, 1));
      expect(o.design.cut, 'full');
      expect(o.shop!.ownerPhone, '0911111111');
      expect(o.customer!.fullName, 'Osman');
      expect(o.shortId, '5B1F0D1E');
    });

    test('an offer needs the customer when price or date differ, like advance_order()', () {
      final today = DateTime(2026, 10, 9);
      bool needs(double price, DateTime due, {double? estimate = 71000}) =>
          offerNeedsApproval(estimate: estimate, price: price, due: due, leadDays: 7, today: today);
      expect(needs(71000, DateTime(2026, 10, 16)), isFalse);
      expect(needs(71000, DateTime(2026, 10, 12)), isFalse);
      expect(needs(71000.004, DateTime(2026, 10, 16)), isFalse);
      expect(needs(80000, DateTime(2026, 10, 16)), isTrue);
      expect(needs(60000, DateTime(2026, 10, 16)), isTrue);
      expect(needs(71000, DateTime(2026, 10, 17)), isTrue);
      expect(needs(71000, DateTime(2026, 10, 16), estimate: null), isTrue);
      expect(statusFromDb('price_offered'), OrderStatus.priceOffered);
      expect(needsCustomer(OrderStatus.priceOffered), isTrue);
      expect(customerCanEdit(OrderStatus.priceOffered), isFalse);
      expect(nextTailorStep(OrderStatus.priceOffered), isNull);
    });

    test('status helpers mirror advance_order()', () {
      expect(statusFromDb(statusToDb(OrderStatus.changesRequested)), OrderStatus.changesRequested);
      expect(nextTailorStep(OrderStatus.confirmed), OrderStatus.cutting);
      expect(nextTailorStep(OrderStatus.ready), OrderStatus.delivered);
      expect(nextTailorStep(OrderStatus.submitted), isNull);
      expect(customerCanEdit(OrderStatus.changesRequested), isTrue);
      expect(customerCanEdit(OrderStatus.confirmed), isFalse);
    });
  });

  group('Translations', () {
    test('Arabic and English define the same keys', () {
      expect(L10n.keysFor('ar'), L10n.keysFor('en'));
    });

    test('placeholders are filled', () {
      expect(L10n.lookup('en', 'orders.for', {'name': 'Ahmed'}), "Ahmed's jalabiya");
      expect(L10n.lookup('ar', 'shop.days', {'days': '7'}), '7 يوم');
    });
  });
}
