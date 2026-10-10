import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../data/repository.dart';
import '../l10n/strings.dart';
import '../models/order.dart';
import '../models/tailor_shop.dart';
import '../screens/customer/order_detail_screen.dart';
import '../screens/tailor/tailor_order_screen.dart';
import '../theme/theme.dart';
import 'session.dart';

/// Tells a tailor the moment an order arrives or a customer answers, and a
/// customer the moment a tailor offers them a different price or date.
///
/// While someone is signed in, it listens to their orders over Supabase
/// Realtime. For a tailor with a shop, a phone notification comes when an
/// order arrives, a customer edits one (it comes back for review), cancels
/// one, or accepts or rejects a price offer. For a customer, an offer they
/// must accept or reject does. Both sides hear when app support cancels one
/// of their orders, and a tailor when an admin approves, rejects or suspends
/// their shop. Tapping an order's notification opens the order. It also keeps [awaiting], the number of orders waiting for the
/// tailor's answer, for the badges on the Orders tab and in the menu.
///
/// This works while the app is open or in the background. Notifications when
/// the app has been fully closed need push (Firebase), which is not set up.
class OrderAlerts extends ChangeNotifier {
  OrderAlerts(this.repo, this.session, this.navigatorKey) {
    session.addListener(_sync);
    _sync();
  }

  final Repository repo;
  final Session session;
  final GlobalKey<NavigatorState> navigatorKey;

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  RealtimeChannel? _channel;
  String? _watching;
  bool _asTailor = false;
  String? _pendingOpen;

  /// The tailor's shop review as last seen, to notice an admin's decision.
  ShopReview? _review;

  /// Orders sent to this tailor that still wait for their answer.
  int awaiting = 0;

  static const _tailorChannel = 'new_orders';
  static const _tailorUpdatesChannel = 'order_updates';
  static const _customerChannel = 'price_offers';
  static const _supportChannel = 'support';

  String _t(String key, [Map<String, String>? args]) => L10n.lookup(session.locale.languageCode, key, args);

  void _sync() {
    _noticeReview();
    final p = session.profile;
    final asTailor = p != null && p.isTailor;
    // a tailor is watched once their shop exists; a customer straight away
    final uid = p == null || (asTailor && session.shop == null) ? null : session.user?.id;
    if (uid == _watching && asTailor == _asTailor) return;
    _stop();
    if (uid != null) unawaited(_start(uid, asTailor));
  }

  Future<void> _start(String uid, bool asTailor) async {
    _watching = uid;
    _asTailor = asTailor;
    try {
      await _init();
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (_) {
      // No notification support here (e.g. tests): the badge still works.
    }
    if (_watching != uid) return; // signed out while we were starting
    _channel = asTailor ? repo.watchTailorOrders(uid, _onChange) : repo.watchCustomerOrders(uid, _onCustomerChange);
    await _refreshCount();
    _flushOpen();
  }

  void _stop() {
    final c = _channel;
    if (c != null) unawaited(repo.unwatch(c).catchError((Object _) {}));
    _channel = null;
    _watching = null;
    if (awaiting != 0) {
      awaiting = 0;
      notifyListeners();
    }
  }

  Future<void> _init() async {
    if (_ready) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher_monochrome'),
      ),
      onDidReceiveNotificationResponse: (r) => _open(r.payload),
    );
    _ready = true;
    // The app was opened by tapping one of our notifications.
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      _pendingOpen = launch!.notificationResponse?.payload;
    }
  }

  Future<void> _refreshCount() async {
    final uid = _watching;
    if (uid == null || !_asTailor) return;
    try {
      final n = await repo.countAwaitingTailor(uid);
      if (_watching == uid && n != awaiting) {
        awaiting = n;
        notifyListeners();
      }
    } catch (_) {
      // offline: keep the last count
    }
  }

  void _onChange(PostgresChangeEvent event, Map<String, dynamic> row) {
    unawaited(_refreshCount());
    final id = row['id'] as String?;
    if (id == null) return;
    final status = row['status'];
    if (event == PostgresChangeEvent.update && (status == 'cancelled' || status == 'confirmed')) {
      unawaited(_onCustomerAnswer(id, row));
      return;
    }
    if (status != 'submitted') return;
    // Orders only become 'submitted' again when the customer edits them.
    final edited = event == PostgresChangeEvent.update;
    if (!edited && event != PostgresChangeEvent.insert) return;

    final delivery = row['delivery'];
    final name = (delivery is Map ? delivery['name'] as String? : null)?.trim();
    final who = (name == null || name.isEmpty) ? _t('notif.someone') : name;
    final wearer = (row['wearer_label'] as String?) ?? '';
    final qty = '${row['quantity'] ?? 1}';
    unawaited(_notify(
      id,
      edited ? _t('notif.editedTitle', {'name': who}) : _t('notif.newTitle', {'name': who}),
      edited ? _t('notif.editedBody', {'wearer': wearer}) : _t('notif.newBody', {'wearer': wearer, 'qty': qty}),
    ));
  }

  /// An order the tailor sees became cancelled or confirmed. Only the
  /// customer's own steps are news to the tailor (a cancel, or an answer to a
  /// price offer), so the order's last history entry decides: who did it,
  /// what kind of step it was, and the reason they gave.
  Future<void> _onCustomerAnswer(String id, Map<String, dynamic> row) async {
    final OrderEvent? e;
    try {
      e = await repo.latestEvent(id);
    } catch (_) {
      return; // offline: the order list still shows the new status
    }
    if (cancelledBySupport(e, row)) {
      await _notifySupportCancel(id, row, e!);
      return;
    }
    final answer = customerAnswer(e, row);
    if (answer == null || e == null) return;

    final delivery = row['delivery'];
    final name = (delivery is Map ? delivery['name'] as String? : null)?.trim();
    final who = (name == null || name.isEmpty) ? _t('notif.someone') : name;
    final wearer = (row['wearer_label'] as String?) ?? '';
    final reason = (e.note ?? '').trim();

    final String title;
    final String body;
    if (answer == CustomerAnswer.accepted) {
      final price = parseDouble(row['price']);
      final currency = (row['currency'] as String?) ?? 'SDG';
      final money = price == null
          ? '—'
          : '${NumberFormat.decimalPattern('en').format(price)} ${currency == 'SDG' ? _t('money.sdg') : currency}';
      title = _t('notif.acceptTitle', {'name': who});
      body = _t('notif.acceptBody', {'price': money, 'wearer': wearer});
    } else {
      final rejected = answer == CustomerAnswer.rejected;
      title = _t(rejected ? 'notif.rejectTitle' : 'notif.cancelTitle', {'name': who});
      body = reason.isEmpty
          ? _t(rejected ? 'notif.rejectBody' : 'notif.cancelBody', {'wearer': wearer})
          : _t(rejected ? 'notif.rejectBodyReason' : 'notif.cancelBodyReason', {'wearer': wearer, 'reason': reason});
    }
    await _notify(id, title, body, channel: _tailorUpdatesChannel);
  }

  /// A customer's order became an offer: the tailor's price or date differs
  /// from what they were quoted, and they need to accept or reject it.
  void _onCustomerChange(PostgresChangeEvent event, Map<String, dynamic> row) {
    final id = row['id'] as String?;
    if (id == null || event != PostgresChangeEvent.update) return;
    if (row['status'] == 'cancelled') {
      unawaited(_onCancelled(id, row));
      return;
    }
    if (row['status'] != 'price_offered') return;
    final lang = session.locale.languageCode;
    final wearer = (row['wearer_label'] as String?) ?? '';
    final price = parseDouble(row['price']);
    final currency = (row['currency'] as String?) ?? 'SDG';
    final due = row['due_date'] is String ? DateTime.tryParse(row['due_date'] as String) : null;
    final money = price == null
        ? '—'
        : '${NumberFormat.decimalPattern('en').format(price)} ${currency == 'SDG' ? _t('money.sdg') : currency}';
    unawaited(_notify(
      id,
      _t('notif.offerTitle', {'wearer': wearer}),
      _t('notif.offerBody', {
        'price': money,
        'date': due == null ? '—' : DateFormat.yMMMd(lang).format(due),
      }),
      channel: _customerChannel,
    ));
  }

  /// A customer's order was cancelled: news only when app support did it.
  Future<void> _onCancelled(String id, Map<String, dynamic> row) async {
    final OrderEvent? e;
    try {
      e = await repo.latestEvent(id);
    } catch (_) {
      return;
    }
    if (cancelledBySupport(e, row)) await _notifySupportCancel(id, row, e!);
  }

  Future<void> _notifySupportCancel(String id, Map<String, dynamic> row, OrderEvent e) {
    final wearer = (row['wearer_label'] as String?) ?? '';
    return _notify(
      id,
      _t('notif.supportCancelTitle', {'wearer': wearer}),
      _t('notif.supportCancelBody', {'reason': (e.note ?? '').trim()}),
      channel: _supportChannel,
    );
  }

  /// An admin approved, rejected or suspended this tailor's shop while the
  /// app was running (Session follows the shop row live).
  void _noticeReview() {
    final shop = session.profile?.isTailor == true ? session.shop : null;
    final before = _review;
    _review = shop?.review;
    if (shop == null || before == null || before == shop.review) return;
    final reason = (shop.reviewNote ?? '').trim();
    String withReason(String key) => reason.isEmpty ? _t('${key}Plain') : _t(key, {'reason': reason});
    final String title;
    final String body;
    switch (shop.review) {
      case ShopReview.approved:
        title = _t('notif.shopApprovedTitle');
        body = _t('notif.shopApprovedBody', {'shop': shop.shopName});
      case ShopReview.rejected:
        title = _t('notif.shopRejectedTitle');
        body = withReason('shop.rejectedBody');
      case ShopReview.suspended:
        title = _t('notif.shopSuspendedTitle');
        body = withReason('shop.suspendedBody');
      case ShopReview.pending:
        return; // the tailor's own save sent it back; nothing to tell them
    }
    unawaited(_notify('shop-${shop.tailorId}', title, body, channel: _supportChannel, opensOrder: false));
  }

  /// One notification per [key] (an order id, or the shop); tapping it opens
  /// that order when [opensOrder].
  Future<void> _notify(String key, String title, String body,
      {String channel = _tailorChannel, bool opensOrder = true}) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        id: key.hashCode & 0x7fffffff,
        title: title,
        body: body,
        payload: opensOrder ? key : null,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channel,
            _t(switch (channel) {
              _tailorChannel => 'notif.channel',
              _tailorUpdatesChannel => 'notif.updatesChannel',
              _supportChannel => 'notif.supportChannel',
              _ => 'notif.offerChannel',
            }),
            channelDescription: _t(switch (channel) {
              _tailorChannel => 'notif.channelBody',
              _tailorUpdatesChannel => 'notif.updatesChannelBody',
              _supportChannel => 'notif.supportChannelBody',
              _ => 'notif.offerChannelBody',
            }),
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.message,
            color: Palette.gold,
            ticker: title,
            styleInformation: BigTextStyleInformation(body),
          ),
        ),
      );
    } catch (_) {
      // permission refused or channel blocked: the badge still shows it
    }
  }

  void _open(String? orderId) {
    if (orderId == null || orderId.isEmpty) return;
    _pendingOpen = orderId;
    _flushOpen();
  }

  /// Opens the order once the home screen is up (it may still be loading
  /// when the app was started from the notification).
  void _flushOpen() {
    final id = _pendingOpen;
    final nav = navigatorKey.currentState;
    if (id == null || nav == null || _watching == null) return;
    _pendingOpen = null;
    nav.push(MaterialPageRoute<void>(
      builder: (_) => _asTailor ? TailorOrderScreen(orderId: id) : OrderDetailScreen(orderId: id),
    ));
  }

  @override
  void dispose() {
    session.removeListener(_sync);
    _stop();
    super.dispose();
  }
}

/// A step a customer took that their tailor should hear about.
enum CustomerAnswer { cancelled, rejected, accepted }

/// Given the last history entry [e] of an order that just became cancelled or
/// confirmed ([row] is the order as Realtime sent it), what the customer did,
/// or null when it isn't news for the tailor: the tailor did it themselves,
/// something newer already happened, or the entry is old (a replayed event).
CustomerAnswer? customerAnswer(OrderEvent? e, Map<String, dynamic> row, {DateTime? now}) {
  if (e == null || e.actorId == null || e.actorId != row['customer_id']) return null;
  if (statusToDb(e.toStatus) != row['status']) return null;
  if ((now ?? DateTime.now()).difference(e.createdAt).inMinutes.abs() > 10) return null;
  if (e.toStatus == OrderStatus.confirmed) return e.kind == 'accepted' ? CustomerAnswer.accepted : null;
  if (e.toStatus == OrderStatus.cancelled) {
    return e.kind == 'rejected' ? CustomerAnswer.rejected : CustomerAnswer.cancelled;
  }
  return null;
}

/// Whether [e], the last history entry of an order that just became
/// cancelled ([row] as Realtime sent it), is app support cancelling it
/// (admin_cancel_order in supabase/admin.sql), and recent enough to be news.
bool cancelledBySupport(OrderEvent? e, Map<String, dynamic> row, {DateTime? now}) {
  if (e == null || e.kind != 'admin' || e.toStatus != OrderStatus.cancelled) return false;
  if (row['status'] != 'cancelled') return false;
  return (now ?? DateTime.now()).difference(e.createdAt).inMinutes.abs() <= 10;
}
