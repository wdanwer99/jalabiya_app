import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/repository.dart';
import '../models/profile.dart';
import '../models/tailor_shop.dart';
import '../util/format.dart';

/// Who is signed in, their profile and shop, and their app preferences.
/// The root of the app rebuilds from this to decide which screen to show.
class Session extends ChangeNotifier {
  Session(this.repo, this._prefs)
      : locale = Locale(_prefs.getString(_kLang) ?? 'ar'),
        unit = _prefs.getString(_kUnit) == 'in' ? LengthUnit.inch : LengthUnit.cm;

  static const _kLang = 'lang';
  static const _kUnit = 'unit';

  final Repository repo;
  final SharedPreferences _prefs;
  StreamSubscription<AuthState>? _authSub;

  Locale locale;
  LengthUnit unit;

  bool started = false;
  User? user;
  Profile? profile;
  TailorShop? shop;
  AccountBlock? block;
  bool loadingProfile = false;
  Object? loadError;

  /// Live updates of the tailor's own shop, so an admin's decision shows at once.
  RealtimeChannel? _shopChannel;
  String? _shopWatching;

  /// Live updates of this account's own block, so the gate switches to (or
  /// away from) the blocked screen the moment an admin acts.
  RealtimeChannel? _blockChannel;
  String? _blockWatching;

  /// Looks again when the app comes back to the front, in case an event was
  /// missed while it was in the background or offline.
  AppLifecycleListener? _lifecycle;

  bool get signedIn => user != null;
  bool get blocked => block != null;

  /// The profile gate: nobody orders or takes orders with missing details.
  bool get profileComplete {
    final p = profile;
    if (p == null || !p.detailsComplete) return false;
    if (p.isTailor) return shop != null;
    return true;
  }

  Future<void> start() async {
    user = repo.currentUser;
    _authSub = repo.authChanges.listen(_onAuth);
    _lifecycle = AppLifecycleListener(onResume: _onResume);
    if (user != null) await reload();
    started = true;
    notifyListeners();
  }

  void _onResume() {
    final uid = user?.id;
    if (uid == null || profile == null) return;
    unawaited(refreshBlock());
    if (profile!.isTailor) unawaited(_refreshShop(uid));
  }

  void _onAuth(AuthState state) {
    final next = state.session?.user;
    final changed = next?.id != user?.id;
    user = next;
    if (next == null) {
      profile = null;
      shop = null;
      block = null;
      loadError = null;
      _syncWatches();
      notifyListeners();
    } else if (changed) {
      reload();
    }
  }

  Future<void> reload() async {
    final u = user;
    if (u == null) return;
    loadingProfile = true;
    loadError = null;
    notifyListeners();
    try {
      profile = await repo.ensureProfile(u);
      shop = profile!.isTailor ? await repo.fetchMyShop(u.id) : null;
      block = await repo.fetchMyBlock(u.id);
    } catch (e) {
      loadError = e;
    } finally {
      loadingProfile = false;
      _syncWatches();
      notifyListeners();
    }
  }

  /// Follows the signed-in account's block (everyone) and shop (tailors).
  void _syncWatches() {
    final uid = profile == null ? null : user?.id;
    if (uid != _blockWatching) {
      _unwatch(_blockChannel);
      _blockChannel = null;
      _blockWatching = uid;
      if (uid != null) _blockChannel = repo.watchMyBlock(uid, () => unawaited(refreshBlock()));
    }
    final tailor = profile?.isTailor == true ? uid : null;
    if (tailor != _shopWatching) {
      _unwatch(_shopChannel);
      _shopChannel = null;
      _shopWatching = tailor;
      if (tailor != null) _shopChannel = repo.watchMyShop(tailor, () => unawaited(_refreshShop(tailor)));
    }
  }

  void _unwatch(RealtimeChannel? c) {
    if (c != null) unawaited(repo.unwatch(c).catchError((Object _) {}));
  }

  /// Looks again whether an admin blocked or unblocked this account. Called
  /// by Realtime, on resume, and when the server refuses an action with
  /// ACCOUNT_BLOCKED; the gate redraws only if something changed.
  Future<void> refreshBlock() async {
    final uid = user?.id;
    if (uid == null) return;
    try {
      final next = await repo.fetchMyBlock(uid);
      if (user?.id != uid) return; // signed out meanwhile
      if (next?.reason == block?.reason && (next == null) == (block == null)) return;
      block = next;
      notifyListeners();
    } catch (_) {
      // offline: Realtime or the next resume brings it
    }
  }

  Future<void> _refreshShop(String uid) async {
    try {
      final next = await repo.fetchMyShop(uid);
      if (user?.id != uid) return; // signed out meanwhile
      shop = next;
      notifyListeners();
    } catch (_) {
      // offline: the next reload brings it
    }
  }

  Future<void> saveProfile(Profile p) async {
    profile = await repo.saveProfile(p);
    notifyListeners();
  }

  Future<void> saveShop(TailorShop s) async {
    shop = await repo.saveShop(s);
    notifyListeners();
  }

  Future<void> signOut() async {
    await repo.signOut();
  }

  Future<void> setLocale(String lang) async {
    locale = Locale(lang);
    await _prefs.setString(_kLang, lang);
    notifyListeners();
  }

  Future<void> setUnit(LengthUnit u) async {
    unit = u;
    await _prefs.setString(_kUnit, u == LengthUnit.inch ? 'in' : 'cm');
    notifyListeners();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _lifecycle?.dispose();
    _unwatch(_shopChannel);
    _unwatch(_blockChannel);
    super.dispose();
  }
}
