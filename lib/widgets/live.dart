import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/errors.dart';
import '../l10n/strings.dart';
import '../state/network.dart';
import '../theme/theme.dart';
import 'common.dart';
import 'motion.dart';

/// Loads data, then reloads it every time [changes] fires (Supabase Realtime),
/// so the customer sees "confirmed" the moment the tailor taps it.
///
/// While loading the first time it shows placeholder cards. If a later
/// refresh fails (offline), it keeps the last data on screen and says what
/// went wrong, with a retry, instead of silently showing something out of
/// date. When the connection comes back it reloads by itself and listens
/// for changes again, so nothing missed while offline stays missed.
class LiveData<T> extends StatefulWidget {
  const LiveData({
    super.key,
    required this.load,
    required this.changes,
    required this.builder,
    this.skeleton,
    this.frame,
  });

  final Future<T> Function() load;
  final Stream<void> Function() changes;
  final Widget Function(BuildContext context, T data, Future<void> Function() refresh) builder;

  /// Shown during the first load, shaped like the real content.
  final Widget? skeleton;

  /// Wraps the first-load error view, e.g. to give a header-less screen its
  /// back button.
  final Widget Function(Widget child)? frame;

  @override
  State<LiveData<T>> createState() => _LiveDataState<T>();
}

class _LiveDataState<T> extends State<LiveData<T>> {
  T? _data;
  bool _has = false;
  Object? _error; // the first load failed
  Object? _staleError; // showing old data because the last refresh failed
  StreamSubscription<void>? _sub;
  bool _loading = false;
  bool _again = false;
  NetworkMonitor? _net;
  NetStatus? _lastNet;

  @override
  void initState() {
    super.initState();
    _load();
    _listen();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    NetworkMonitor? net;
    try {
      net = Provider.of<NetworkMonitor?>(context, listen: false);
    } catch (_) {
      net = null; // tests run without one
    }
    if (net != _net) {
      _net?.removeListener(_onNet);
      _net = net?..addListener(_onNet);
      _lastNet = net?.status;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _net?.removeListener(_onNet);
    super.dispose();
  }

  void _listen() {
    _sub?.cancel();
    _sub = widget.changes().listen((_) => _load(), onError: (Object _) {});
  }

  /// Back online: catch up on anything missed and listen again.
  void _onNet() {
    final now = _net!.status;
    final cameBack = now == NetStatus.online && _lastNet != NetStatus.online && _lastNet != NetStatus.checking;
    _lastNet = now;
    if (!cameBack || !mounted) return;
    _listen();
    _load();
  }

  /// Coalesces bursts of change events into at most one extra load.
  Future<void> _load() async {
    if (_loading) {
      _again = true;
      return;
    }
    _loading = true;
    try {
      final d = await widget.load();
      if (mounted) {
        setState(() {
          _data = d;
          _has = true;
          _error = null;
          _staleError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (_has) {
            _staleError = e;
          } else {
            _error = e;
          }
        });
      }
    } finally {
      _loading = false;
      if (_again && mounted) {
        _again = false;
        _load();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_has) {
      if (_error != null) {
        final view = ErrorView(
          error: _error!,
          onRetry: () {
            setState(() => _error = null);
            _load();
          },
        );
        return widget.frame?.call(view) ?? view;
      }
      return widget.skeleton ?? const SkeletonList();
    }
    return Column(
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: _staleError != null
              ? _StaleBar(error: _staleError!, onRetry: _load)
              : const SizedBox(width: double.infinity),
        ),
        Expanded(child: widget.builder(context, _data as T, _load)),
      ],
    );
  }
}

/// A thin bar over data that could not be refreshed: what went wrong, that
/// what is shown may be out of date, and a retry.
class _StaleBar extends StatelessWidget {
  const _StaleBar({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final info = describeError(context, error);
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        color: Palette.hennaSoft,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 6, 8, 6),
            child: Row(
              children: [
                Icon(info.icon, size: 18, color: Palette.henna),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    info.isNetwork
                        ? '${info.title}. ${context.tr('live.staleNet')}'
                        : '${info.title}. ${context.tr('live.stale')}',
                    style: const TextStyle(color: Palette.henna, fontSize: 13, height: 1.35),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: Palette.henna),
                  onPressed: onRetry,
                  child: Text(context.tr('action.retry')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Placeholder cards with a light sweeping across them while the first load
/// runs, so the screen keeps its shape instead of flashing a spinner.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 3, this.padding = const EdgeInsets.all(16)});

  final int count;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: context.tr('splash.loading'),
      child: Shimmer(
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: padding,
          children: [
            for (var i = 0; i < count; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Panel(
                  child: Row(
                    children: [
                      const SkeletonBox(width: 50, height: 62, radius: 12),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            FractionallySizedBox(widthFactor: 0.6, child: SkeletonBox(height: 15)),
                            SizedBox(height: 10),
                            FractionallySizedBox(widthFactor: 0.85, child: SkeletonBox(height: 11)),
                            SizedBox(height: 10),
                            FractionallySizedBox(widthFactor: 0.4, child: SkeletonBox(height: 20, radius: 10)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
