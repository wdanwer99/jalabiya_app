import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/design.dart';
import '../models/measurement_set.dart';
import '../models/measurements.dart';
import '../models/order.dart';
import '../models/profile.dart';
import '../models/tailor_shop.dart';

/// Every call the app makes to Supabase lives here, so screens never build
/// queries themselves and the security rules have one client to match.
class Repository {
  Repository(this.client);

  final SupabaseClient client;

  // The embed hints name the foreign keys from schema.sql, so PostgREST never
  // has to guess which relationship is meant.
  static const _orderSelect = '*, '
      'shop:tailor_shops!orders_tailor_id_fkey(*, '
      'owner:profiles!tailor_shops_tailor_id_fkey(full_name, phone, whatsapp)), '
      'customer:profiles!orders_customer_id_fkey(*)';
  static const _shopSelect =
      '*, owner:profiles!tailor_shops_tailor_id_fkey(full_name, phone, whatsapp)';

  // ---------------------------------------------------------------- auth
  User? get currentUser => client.auth.currentUser;
  Stream<AuthState> get authChanges => client.auth.onAuthStateChange;

  /// Returns true when Supabase wants the email confirmed before sign-in.
  Future<bool> signUp({
    required String email,
    required String password,
    required UserRole role,
    required String fullName,
    required String phone,
  }) async {
    final res = await client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {
        'role': roleToDb(role),
        'full_name': fullName.trim(),
        'phone': phone.trim(),
      },
    );
    return res.session == null;
  }

  Future<void> signIn(String email, String password) async {
    await client.auth.signInWithPassword(email: email.trim(), password: password);
  }

  Future<void> sendPasswordReset(String email) async {
    await client.auth.resetPasswordForEmail(email.trim());
  }

  Future<void> signOut() => client.auth.signOut();

  // ------------------------------------------------------------- profile
  Future<Profile?> fetchProfile(String uid) async {
    final row =
        await client.from('profiles').select().eq('id', uid).maybeSingle();
    return row == null ? null : Profile.fromJson(row);
  }

  /// Fallback for projects where the sign-up trigger was not installed:
  /// creates the row from what the user typed at sign-up.
  Future<Profile> ensureProfile(User user) async {
    final existing = await fetchProfile(user.id);
    if (existing != null) return existing;
    final meta = user.userMetadata ?? const <String, dynamic>{};
    await client.from('profiles').upsert({
      'id': user.id,
      'role': meta['role'] == 'tailor' ? 'tailor' : 'customer',
      'full_name': (meta['full_name'] as String?) ?? '',
      'phone': (meta['phone'] as String?) ?? '',
    });
    return (await fetchProfile(user.id))!;
  }

  /// Why this account is blocked, or null when it isn't (never blocked, or
  /// the block was lifted). A project without supabase/admin.sql has no
  /// blocks table, which also means not blocked.
  Future<AccountBlock?> fetchMyBlock(String uid) async {
    try {
      final row = await client.from('account_blocks').select().eq('user_id', uid).maybeSingle();
      final block = row == null ? null : AccountBlock.fromJson(row);
      return block != null && block.active ? block : null;
    } on PostgrestException catch (e) {
      if (e.code == '42P01' || e.code == 'PGRST205' || e.code == '42501') return null;
      rethrow;
    }
  }

  /// Calls [onChange] the moment an admin blocks or unblocks this account.
  /// Both are an insert or update of the account's own row (an unblock only
  /// sets lifted_at), which Realtime filters by user and checks against RLS.
  RealtimeChannel watchMyBlock(String uid, void Function() onChange) {
    final mine = PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: uid);
    return client
        .channel('my-block-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'account_blocks',
          filter: mine,
          callback: (_) => onChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'account_blocks',
          filter: mine,
          callback: (_) => onChange(),
        )
        .subscribe();
  }

  Future<Profile> saveProfile(Profile p) async {
    final row = await client
        .from('profiles')
        .update(p.toWriteJson())
        .eq('id', p.id)
        .select()
        .single();
    return Profile.fromJson(row);
  }

  // --------------------------------------------------------------- shops
  Future<TailorShop?> fetchMyShop(String uid) async {
    final row = await client
        .from('tailor_shops')
        .select(_shopSelect)
        .eq('tailor_id', uid)
        .maybeSingle();
    return row == null ? null : TailorShop.fromJson(row);
  }

  Future<TailorShop> saveShop(TailorShop s) async {
    final row = await client
        .from('tailor_shops')
        .upsert(s.toWriteJson(), onConflict: 'tailor_id')
        .select(_shopSelect)
        .single();
    return TailorShop.fromJson(row);
  }

  /// Calls [onChange] whenever this tailor's own shop row changes, e.g. an
  /// admin approves, rejects or suspends it.
  RealtimeChannel watchMyShop(String tailorId, void Function() onChange) {
    return client
        .channel('my-shop-$tailorId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'tailor_shops',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'tailor_id', value: tailorId),
          callback: (_) => onChange(),
        )
        .subscribe();
  }

  /// Approved shops that take orders. RLS already hides unapproved ones.
  Future<List<TailorShop>> listOpenShops() async {
    final rows = await client
        .from('tailor_shops')
        .select(_shopSelect)
        .eq('approved', true)
        .eq('accepts_orders', true)
        .order('shop_name');
    return rows.map((r) => TailorShop.fromJson(r)).toList();
  }

  // ---------------------------------------------------- measurement sets
  Future<List<MeasurementSet>> listMeasurementSets(String uid) async {
    final rows = await client
        .from('measurement_sets')
        .select()
        .eq('owner_id', uid)
        .order('created_at');
    return rows.map((r) => MeasurementSet.fromJson(r)).toList();
  }

  Future<MeasurementSet> createMeasurementSet(
      String uid, String label, String relation, Measurements m) async {
    final data = MeasurementSet.columns(label, relation, m);
    data['owner_id'] = uid;
    final row =
        await client.from('measurement_sets').insert(data).select().single();
    return MeasurementSet.fromJson(row);
  }

  Future<MeasurementSet> updateMeasurementSet(
      String id, String label, String relation, Measurements m) async {
    final row = await client
        .from('measurement_sets')
        .update(MeasurementSet.columns(label, relation, m))
        .eq('id', id)
        .select()
        .single();
    return MeasurementSet.fromJson(row);
  }

  Future<void> deleteMeasurementSet(String id) async {
    await client.from('measurement_sets').delete().eq('id', id);
  }

  // -------------------------------------------------------------- orders
  Future<List<Order>> fetchCustomerOrders(String uid) async {
    final rows = await client
        .from('orders')
        .select(_orderSelect)
        .eq('customer_id', uid)
        .order('created_at', ascending: false);
    return rows.map((r) => Order.fromJson(r)).toList();
  }

  Future<List<Order>> fetchTailorOrders(String uid) async {
    final rows = await client
        .from('orders')
        .select(_orderSelect)
        .eq('tailor_id', uid)
        .order('created_at', ascending: false);
    return rows.map((r) => Order.fromJson(r)).toList();
  }

  Future<OrderBundle> fetchOrder(String id) async {
    final row =
        await client.from('orders').select(_orderSelect).eq('id', id).single();
    final events = await client
        .from('order_events')
        .select()
        .eq('order_id', id)
        .order('created_at');
    return OrderBundle(
      Order.fromJson(row),
      events.map((e) => OrderEvent.fromJson(e)).toList(),
    );
  }

  /// The last step in an order's history: who moved it, how, and their note.
  Future<OrderEvent?> latestEvent(String orderId) async {
    final row = await client
        .from('order_events')
        .select()
        .eq('order_id', orderId)
        .order('id', ascending: false)
        .limit(1)
        .maybeSingle();
    return row == null ? null : OrderEvent.fromJson(row);
  }

  /// Emits whenever a matching order row changes (Supabase Realtime), so
  /// lists refresh the moment the other side acts.
  Stream<void> orderChanges({required String column, required String value}) {
    return client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq(column, value)
        .map((_) {});
  }

  /// Calls [onChange] with the new row whenever one of this tailor's orders
  /// is created or changed. RLS still applies: only their own orders arrive.
  RealtimeChannel watchTailorOrders(
    String tailorId,
    void Function(PostgresChangeEvent event, Map<String, dynamic> row) onChange,
  ) =>
      _watchOrders('tailor', 'tailor_id', tailorId, onChange);

  /// The same for a customer: their orders as the tailor answers them.
  RealtimeChannel watchCustomerOrders(
    String customerId,
    void Function(PostgresChangeEvent event, Map<String, dynamic> row) onChange,
  ) =>
      _watchOrders('customer', 'customer_id', customerId, onChange);

  RealtimeChannel _watchOrders(
    String side,
    String column,
    String id,
    void Function(PostgresChangeEvent event, Map<String, dynamic> row) onChange,
  ) {
    return client
        .channel('$side-orders-$id')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: column,
            value: id,
          ),
          callback: (p) => onChange(p.eventType, p.newRecord),
        )
        .subscribe();
  }

  Future<void> unwatch(RealtimeChannel channel) => client.removeChannel(channel);

  /// How many orders this customer has placed, without loading them.
  Future<int> countCustomerOrders(String customerId) async {
    final res = await client.from('orders').select('id').eq('customer_id', customerId).count(CountOption.exact);
    return res.count;
  }

  /// Orders sent to this tailor that still wait for their answer.
  Future<int> countAwaitingTailor(String tailorId) async {
    final res = await client
        .from('orders')
        .select('id')
        .eq('tailor_id', tailorId)
        .eq('status', 'submitted')
        .count(CountOption.exact);
    return res.count;
  }

  Future<String> submitOrder({
    required String tailorId,
    required String? measurementSetId,
    required String wearer,
    required Measurements measurements,
    required JalabiyaDesign design,
    required int quantity,
    String? notes,
  }) async {
    final id = await client.rpc('submit_order', params: {
      'p_tailor': tailorId,
      'p_measurement_set': measurementSetId,
      'p_wearer': wearer,
      'p_measurements': measurements.toJson(),
      'p_design': design.toJson(),
      'p_quantity': quantity,
      'p_notes': notes,
    });
    return id as String;
  }

  Future<void> updateOrder({
    required String orderId,
    required String wearer,
    required Measurements measurements,
    required JalabiyaDesign design,
    required int quantity,
    String? notes,
  }) async {
    await client.rpc('update_order', params: {
      'p_order': orderId,
      'p_wearer': wearer,
      'p_measurements': measurements.toJson(),
      'p_design': design.toJson(),
      'p_quantity': quantity,
      'p_notes': notes,
    });
  }

  Future<void> advanceOrder(
    String orderId,
    OrderStatus to, {
    String? note,
    double? price,
    DateTime? dueDate,
  }) async {
    await client.rpc('advance_order', params: {
      'p_order': orderId,
      'p_to': statusToDb(to),
      'p_note': note,
      'p_price': price,
      'p_due': dueDate == null ? null : _date(dueDate),
    });
  }

  static String _date(DateTime d) {
    String two(int n) => n < 10 ? '0$n' : '$n';
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }
}
