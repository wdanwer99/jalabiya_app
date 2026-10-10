import 'design.dart';
import 'measurements.dart';
import 'profile.dart';
import 'tailor_shop.dart';

enum OrderStatus {
  submitted,
  changesRequested,
  priceOffered, // the tailor's price or date differs: the customer decides
  confirmed,
  cutting,
  sewing,
  ready,
  delivered,
  declined,
  cancelled,
}

const Map<OrderStatus, String> _dbNames = {
  OrderStatus.submitted: 'submitted',
  OrderStatus.changesRequested: 'changes_requested',
  OrderStatus.priceOffered: 'price_offered',
  OrderStatus.confirmed: 'confirmed',
  OrderStatus.cutting: 'cutting',
  OrderStatus.sewing: 'sewing',
  OrderStatus.ready: 'ready',
  OrderStatus.delivered: 'delivered',
  OrderStatus.declined: 'declined',
  OrderStatus.cancelled: 'cancelled',
};

String statusToDb(OrderStatus s) => _dbNames[s]!;

OrderStatus statusFromDb(Object? v) {
  for (final e in _dbNames.entries) {
    if (e.value == v) return e.key;
  }
  return OrderStatus.submitted;
}

/// The happy path, in order. Used for the progress tracker.
const List<OrderStatus> statusPath = [
  OrderStatus.submitted,
  OrderStatus.confirmed,
  OrderStatus.cutting,
  OrderStatus.sewing,
  OrderStatus.ready,
  OrderStatus.delivered,
];

/// Mirrors advance_order() in supabase/schema.sql. The server is the real
/// gatekeeper; this only decides which buttons to show.
OrderStatus? nextTailorStep(OrderStatus s) {
  switch (s) {
    case OrderStatus.confirmed:
      return OrderStatus.cutting;
    case OrderStatus.cutting:
      return OrderStatus.sewing;
    case OrderStatus.sewing:
      return OrderStatus.ready;
    case OrderStatus.ready:
      return OrderStatus.delivered;
    default:
      return null;
  }
}

bool customerCanEdit(OrderStatus s) =>
    s == OrderStatus.submitted || s == OrderStatus.changesRequested;

bool isClosed(OrderStatus s) =>
    s == OrderStatus.delivered ||
    s == OrderStatus.declined ||
    s == OrderStatus.cancelled;

/// Where an order sits on the tailor's tabs: not started yet.
bool needsTailor(OrderStatus s) =>
    s == OrderStatus.submitted || s == OrderStatus.changesRequested || s == OrderStatus.priceOffered;

/// The customer has to act: fix the order, or answer the tailor's offer.
bool needsCustomer(OrderStatus s) =>
    s == OrderStatus.changesRequested || s == OrderStatus.priceOffered;

/// Mirrors advance_order() in supabase/price_offers.sql: confirming at a
/// price other than the [estimate] the customer saw, or later than the
/// shop's [leadDays], sends the customer an offer to accept or reject.
bool offerNeedsApproval({
  required double? estimate,
  required double price,
  required DateTime due,
  required int leadDays,
  DateTime? today,
}) {
  final now = today ?? DateTime.now();
  final latest = DateTime(now.year, now.month, now.day + leadDays);
  final day = DateTime(due.year, due.month, due.day);
  if (estimate == null) return true;
  return (price * 100).round() != (estimate * 100).round() || day.isAfter(latest);
}

class Delivery {
  const Delivery({
    required this.name,
    required this.phone,
    this.whatsapp,
    this.city,
    this.neighbourhood,
    this.addressDetails,
  });

  final String name;
  final String phone;
  final String? whatsapp;
  final String? city;
  final String? neighbourhood;
  final String? addressDetails;

  factory Delivery.fromJson(Map<String, dynamic>? j) {
    final m = j ?? const <String, dynamic>{};
    return Delivery(
      name: (m['name'] as String?) ?? '',
      phone: (m['phone'] as String?) ?? '',
      whatsapp: m['whatsapp'] as String?,
      city: m['city'] as String?,
      neighbourhood: m['neighbourhood'] as String?,
      addressDetails: m['address_details'] as String?,
    );
  }
}

class Order {
  const Order({
    required this.id,
    required this.customerId,
    required this.tailorId,
    required this.wearerLabel,
    required this.measurements,
    required this.design,
    required this.delivery,
    required this.quantity,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.measurementSetId,
    this.customerNotes,
    this.price,
    this.estimate,
    this.currency = 'SDG',
    this.dueDate,
    this.tailorNote,
    this.shop,
    this.customer,
  });

  final String id;
  final String customerId;
  final String tailorId;
  final String? measurementSetId;
  final String wearerLabel;
  final Measurements measurements;
  final JalabiyaDesign design;
  final Delivery delivery;
  final int quantity;
  final String? customerNotes;
  final OrderStatus status;
  final double? price;
  /// What the customer was shown when sending: (base + extras) × quantity.
  final double? estimate;
  final String currency;
  final DateTime? dueDate;
  final String? tailorNote;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Embedded when loaded with joins.
  final TailorShop? shop;
  final Profile? customer;

  String get shortId => id.substring(0, 8).toUpperCase();

  factory Order.fromJson(Map<String, dynamic> j) {
    Map<String, dynamic>? map(Object? v) =>
        v is Map<String, dynamic> ? v : null;
    final shopJson = map(j['shop']);
    final customerJson = map(j['customer']);
    return Order(
      id: j['id'] as String,
      customerId: j['customer_id'] as String,
      tailorId: j['tailor_id'] as String,
      measurementSetId: j['measurement_set_id'] as String?,
      wearerLabel: (j['wearer_label'] as String?) ?? '',
      measurements: Measurements.fromJson(map(j['measurements'])),
      design: JalabiyaDesign.fromJson(map(j['design'])),
      delivery: Delivery.fromJson(map(j['delivery'])),
      quantity: (j['quantity'] as num?)?.toInt() ?? 1,
      customerNotes: j['customer_notes'] as String?,
      status: statusFromDb(j['status']),
      price: parseDouble(j['price']),
      estimate: parseDouble(j['estimate']),
      currency: (j['currency'] as String?) ?? 'SDG',
      dueDate: j['due_date'] == null
          ? null
          : DateTime.tryParse(j['due_date'] as String),
      tailorNote: j['tailor_note'] as String?,
      createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
      updatedAt: DateTime.parse(j['updated_at'] as String).toLocal(),
      shop: shopJson == null ? null : TailorShop.fromJson(shopJson),
      customer: customerJson == null ? null : Profile.fromJson(customerJson),
    );
  }
}

class OrderEvent {
  const OrderEvent({
    required this.toStatus,
    required this.kind,
    required this.createdAt,
    this.fromStatus,
    this.note,
    this.actorId,
  });

  final OrderStatus? fromStatus;
  final OrderStatus toStatus;
  final String kind; // status | edited | accepted | rejected | admin (cancelled by app support)
  final String? note;
  final String? actorId;
  final DateTime createdAt;

  factory OrderEvent.fromJson(Map<String, dynamic> j) => OrderEvent(
        fromStatus: j['from_status'] == null ? null : statusFromDb(j['from_status']),
        toStatus: statusFromDb(j['to_status']),
        kind: (j['kind'] as String?) ?? 'status',
        note: j['note'] as String?,
        actorId: j['actor_id'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
      );
}

/// An order together with its history, as the detail screens show it.
class OrderBundle {
  const OrderBundle(this.order, this.events);

  final Order order;
  final List<OrderEvent> events;
}
