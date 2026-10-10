import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:jalabiya_app/data/errors.dart';
import 'package:jalabiya_app/models/order.dart';
import 'package:jalabiya_app/state/network.dart';
import 'package:jalabiya_app/state/order_alerts.dart';
import 'package:jalabiya_app/widgets/common.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

NetworkMonitor _monitor(NetStatus s) =>
    NetworkMonitor(serverUrl: 'https://example.supabase.co', apiKey: 'key')..debugSetStatus(s);

Widget _host(NetworkMonitor net, Widget child) => ChangeNotifierProvider<NetworkMonitor>.value(
      value: net,
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: child),
      ),
    );

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('errorKindOf', () {
    test('a dropped connection reads as offline, no internet or server, by what the monitor saw', () {
      const e = SocketException('Failed host lookup');
      expect(errorKindOf(e, net: NetStatus.offline), ErrorKind.offline);
      expect(errorKindOf(e, net: NetStatus.noInternet), ErrorKind.noInternet);
      expect(errorKindOf(e, net: NetStatus.online), ErrorKind.noInternet);
      expect(errorKindOf(e, net: NetStatus.serverDown), ErrorKind.server);
      expect(errorKindOf(Exception('ClientException: Connection closed'), net: NetStatus.offline), ErrorKind.offline);
      expect(errorKindOf(AuthRetryableFetchException(), net: NetStatus.offline), ErrorKind.offline);
    });

    test('slow, server and session problems', () {
      expect(errorKindOf(TimeoutException('x')), ErrorKind.timeout);
      expect(errorKindOf(const PostgrestException(message: '<html>Bad gateway</html>', code: '502')), ErrorKind.server);
      expect(errorKindOf(AuthRetryableFetchException(statusCode: '503')), ErrorKind.server);
      expect(errorKindOf(const PostgrestException(message: 'JWT expired', code: 'PGRST301')), ErrorKind.session);
      expect(errorKindOf(AuthSessionMissingException()), ErrorKind.session);
    });

    test('server rules map to what the person can do about them', () {
      PostgrestException raised(String code) => PostgrestException(message: code, code: 'P0001');
      expect(errorKindOf(raised('TRANSITION_NOT_ALLOWED')), ErrorKind.conflict);
      expect(errorKindOf(raised('OPTION_UNAVAILABLE')), ErrorKind.conflict);
      expect(errorKindOf(raised('ORDER_NOT_FOUND')), ErrorKind.notFound);
      expect(errorKindOf(raised('INVALID_DESIGN')), ErrorKind.invalid);
      expect(errorKindOf(raised('TOO_MANY_ORDERS')), ErrorKind.tooMany);
      expect(errorKindOf(raised('NOT_A_CUSTOMER')), ErrorKind.forbidden);
      expect(errorKindOf(raised('ACCOUNT_BLOCKED')), ErrorKind.forbidden);
      expect(errorKindOf(const PostgrestException(message: 'row-level security', code: '42501')), ErrorKind.forbidden);
      expect(errorKindOf(const AuthException('Invalid login credentials', statusCode: '400')), ErrorKind.invalid);
      expect(errorKindOf(StateError('?')), ErrorKind.unknown);
    });
  });

  group('customerAnswer', () {
    final now = DateTime(2026, 10, 9, 12);
    const row = {'id': 'o1', 'customer_id': 'c1', 'status': 'cancelled'};
    OrderEvent event(OrderStatus to, String kind, {String actor = 'c1', int minutesAgo = 0, String? note}) =>
        OrderEvent(
          toStatus: to,
          kind: kind,
          actorId: actor,
          note: note,
          createdAt: now.subtract(Duration(minutes: minutesAgo)),
        );

    test('a customer cancelling or rejecting is news for the tailor', () {
      expect(customerAnswer(event(OrderStatus.cancelled, 'status'), row, now: now), CustomerAnswer.cancelled);
      expect(customerAnswer(event(OrderStatus.cancelled, 'rejected'), row, now: now), CustomerAnswer.rejected);
      expect(
        customerAnswer(event(OrderStatus.confirmed, 'accepted'), {...row, 'status': 'confirmed'}, now: now),
        CustomerAnswer.accepted,
      );
    });

    test("the tailor's own steps, stale entries and old events are not", () {
      expect(
        customerAnswer(event(OrderStatus.confirmed, 'status', actor: 't1'), {...row, 'status': 'confirmed'}, now: now),
        isNull,
        reason: 'the tailor confirmed it themselves',
      );
      expect(customerAnswer(event(OrderStatus.cancelled, 'status'), {...row, 'status': 'confirmed'}, now: now), isNull);
      expect(customerAnswer(event(OrderStatus.cancelled, 'status', minutesAgo: 30), row, now: now), isNull);
      expect(customerAnswer(null, row, now: now), isNull);
    });

    test('app support cancelling is news for both sides, and not a customer answer', () {
      final support = event(OrderStatus.cancelled, 'admin', actor: 'a1', note: 'Shop closed');
      expect(cancelledBySupport(support, row, now: now), isTrue);
      expect(customerAnswer(support, row, now: now), isNull);
      expect(cancelledBySupport(event(OrderStatus.cancelled, 'status'), row, now: now), isFalse);
      expect(cancelledBySupport(event(OrderStatus.cancelled, 'admin', minutesAgo: 30), row, now: now), isFalse);
      expect(cancelledBySupport(support, {...row, 'status': 'confirmed'}, now: now), isFalse);
    });
  });

  group('screens', () {
    testWidgets('an offline error says so, shows the connection, and retries by itself when it returns',
        (tester) async {
      final net = _monitor(NetStatus.offline);
      var retries = 0;
      await tester.pumpWidget(_host(net, ErrorView(error: const SocketException('down'), onRetry: () => retries++)));
      expect(find.text("You're offline"), findsOneWidget);
      expect(find.textContaining('Wi-Fi and mobile data are off'), findsOneWidget);
      expect(find.text('Waiting for a connection…'), findsOneWidget);

      net.debugSetStatus(NetStatus.online);
      await tester.pump();
      expect(retries, 1);
      expect(find.text('Back online'), findsOneWidget);
    });

    testWidgets('a session error offers to sign in again instead of retrying', (tester) async {
      final net = _monitor(NetStatus.online);
      await tester.pumpWidget(_host(net, ErrorView(error: AuthSessionMissingException(), onRetry: () {})));
      expect(find.text('Your session ended'), findsOneWidget);
      expect(find.text('Sign in again'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('an action is stopped before it starts while offline, and says nothing was sent', (tester) async {
      final net = _monitor(NetStatus.offline);
      bool? allowed;
      await tester.pumpWidget(_host(
        net,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => allowed = await requireOnline(context),
            child: const Text('Send'),
          ),
        ),
      ));
      await tester.tap(find.text('Send'));
      await tester.pump();
      expect(allowed, isFalse);
      expect(find.textContaining('Nothing was sent'), findsOneWidget);

      net.debugSetStatus(NetStatus.online);
      await tester.tap(find.text('Send'));
      await tester.pump();
      expect(allowed, isTrue);
    });
  });
}
