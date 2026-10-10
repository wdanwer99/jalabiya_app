import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import 'app.dart';
import 'config.dart';
import 'data/repository.dart';
import 'state/network.dart';
import 'state/order_alerts.dart';
import 'state/session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting();
  final prefs = await SharedPreferences.getInstance();

  if (!AppConfig.isConfigured) {
    runApp(const MissingConfigApp());
    return;
  }

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseAnonKey,
  );
  final repo = Repository(Supabase.instance.client);
  final net = NetworkMonitor(serverUrl: AppConfig.supabaseUrl, apiKey: AppConfig.supabaseAnonKey);
  await net.start();
  final session = Session(repo, prefs);
  final alerts = OrderAlerts(repo, session, appNavigatorKey);

  runApp(
    MultiProvider(
      providers: [
        Provider<Repository>.value(value: repo),
        ChangeNotifierProvider<NetworkMonitor>.value(value: net),
        ChangeNotifierProvider<Session>.value(value: session),
        ChangeNotifierProvider<OrderAlerts>.value(value: alerts),
      ],
      child: const JalabiyaApp(),
    ),
  );
  await session.start();
}
