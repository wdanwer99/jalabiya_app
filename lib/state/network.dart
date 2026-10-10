import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

/// Where the phone stands with the internet, from the app's point of view.
enum NetStatus {
  /// Not checked yet. Treated like [online] so nothing is blocked on launch.
  checking,

  /// The server answered.
  online,

  /// Wi-Fi and mobile data are both off (or airplane mode is on).
  offline,

  /// On a network, but the server can't be reached: no data balance, a
  /// Wi-Fi without internet, a very weak signal.
  noInternet,

  /// The server answered with an error of its own: the problem is on our
  /// side, not the phone's.
  serverDown,
}

/// Knows whether the app can talk to its server, and says so the moment it
/// changes.
///
/// It listens to the phone's network switches (connectivity_plus) for an
/// instant answer when Wi-Fi or data go off, and confirms the internet
/// really works by asking the Supabase server itself, which also catches
/// "connected but nothing loads". While not online it checks again every
/// few seconds, and again whenever the app comes back to the screen.
class NetworkMonitor extends ChangeNotifier with WidgetsBindingObserver {
  NetworkMonitor({required this.serverUrl, required this.apiKey, Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final String serverUrl;
  final String apiKey;
  final Connectivity _connectivity;

  NetStatus _status = NetStatus.checking;
  NetStatus get status => _status;

  /// True unless we know the server can't be reached. Unknown counts as
  /// online so a slow first check never blocks anything.
  bool get isOnline => _status == NetStatus.online || _status == NetStatus.checking;

  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _retry;
  Future<NetStatus>? _probing;
  bool _foreground = true;
  int _misses = 0;

  Future<void> start() async {
    WidgetsBinding.instance.addObserver(this);
    try {
      _sub = _connectivity.onConnectivityChanged.listen(_onLinks, onError: (Object _) {});
      _onLinks(await _connectivity.checkConnectivity());
    } catch (_) {
      // no plugin (tests, unsupported platform): fall back to asking the server
      unawaited(check());
    }
  }

  void _onLinks(List<ConnectivityResult> links) {
    final none = links.isEmpty || links.every((l) => l == ConnectivityResult.none);
    if (none) {
      _set(NetStatus.offline);
    } else {
      // a network appeared or changed: find out whether it reaches the server
      unawaited(check());
    }
  }

  /// Asks the server right now; true when it answered. Calls made while a
  /// check is running share it.
  Future<bool> check() async {
    final s = await (_probing ??= _probe().whenComplete(() => _probing = null));
    // with Wi-Fi and data off, a failed check says nothing new: stay "offline"
    _set(_status == NetStatus.offline && s != NetStatus.online ? NetStatus.offline : s);
    return s == NetStatus.online;
  }

  /// A request somewhere in the app failed in a way that looks like the
  /// network: check again soon instead of waiting for the next timer.
  void reportFailure() {
    if (_probing == null) unawaited(check());
  }

  Future<NetStatus> _probe() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final base = serverUrl.endsWith('/') ? serverUrl.substring(0, serverUrl.length - 1) : serverUrl;
      final req = await client.getUrl(Uri.parse('$base/auth/v1/health')).timeout(const Duration(seconds: 7));
      req.headers.set('apikey', apiKey);
      final res = await req.close().timeout(const Duration(seconds: 8));
      await res.drain<void>().timeout(const Duration(seconds: 4), onTimeout: () {});
      // any answer means the internet works; a 5xx means the server is unwell
      return res.statusCode >= 500 ? NetStatus.serverDown : NetStatus.online;
    } catch (_) {
      return NetStatus.noInternet;
    } finally {
      client.close(force: true);
    }
  }

  void _set(NetStatus s) {
    _misses = s == NetStatus.online ? 0 : _misses + 1;
    final changed = s != _status;
    _status = s;
    _schedule();
    if (changed) notifyListeners();
  }

  /// While not online, look again: every 5 s at first, easing off to 30 s.
  void _schedule() {
    _retry?.cancel();
    if (_status == NetStatus.online || _status == NetStatus.checking || !_foreground) return;
    final seconds = (5 * _misses).clamp(5, 30);
    _retry = Timer(Duration(seconds: seconds), () => unawaited(check()));
  }

  /// Sets the state directly, without checking or scheduling: for tests.
  @visibleForTesting
  void debugSetStatus(NetStatus s) {
    if (s == _status) return;
    _status = s;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      // the phone may have changed networks while the app was away
      unawaited(check());
    } else {
      _retry?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _retry?.cancel();
    super.dispose();
  }
}
