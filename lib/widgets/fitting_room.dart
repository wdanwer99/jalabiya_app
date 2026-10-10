import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../l10n/strings.dart';
import '../models/design.dart';
import '../models/garment_spec.dart';
import '../models/measurements.dart';
import '../theme/theme.dart';
import '../util/format.dart';
import 'common.dart';

enum EngineStatus { loading, ready, failed }

/// Talks to the three.js fitting room running inside a WebView.
///
/// Everything sent before the page reports "ready" is remembered and replayed
/// on ready, so callers never need to wait for the page themselves.
class FittingRoomController {
  FittingRoomController() {
    web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Palette.ink)
      ..addJavaScriptChannel('JalabiyaBridge', onMessageReceived: _onMessage)
      ..loadFlutterAsset('assets/engine/fitting_room.html');
  }

  late final WebViewController web;
  final ValueNotifier<EngineStatus> status = ValueNotifier(EngineStatus.loading);

  Map<String, dynamic>? _state;
  Map<String, String>? _labels;
  String _view = 'cloth';
  String? _focus;
  String _unit = 'cm';
  bool _paused = false;
  bool _disposed = false;

  String get view => _view;

  void _onMessage(JavaScriptMessage m) {
    Map<String, dynamic>? msg;
    try {
      final decoded = jsonDecode(m.message);
      if (decoded is Map<String, dynamic>) msg = decoded;
    } catch (_) {}
    if (msg == null || _disposed) return;
    if (msg['type'] == 'ready') {
      status.value = EngineStatus.ready;
      _replay();
    } else if (msg['type'] == 'error') {
      status.value = EngineStatus.failed;
    }
  }

  void _replay() {
    if (_labels != null) _run('window.engine.setLabels(${jsonEncode(_labels)})');
    _run('window.engine.setUnit(${jsonEncode(_unit)})');
    _run('window.engine.setView(${jsonEncode(_view)})');
    if (_state != null) _run('window.engine.apply(${jsonEncode(_state)})');
    _run('window.engine.focus(${jsonEncode(_focus)})');
    _run('window.engine.setPaused(${_paused ? 'true' : 'false'})');
  }

  void _run(String js) {
    if (_disposed || status.value != EngineStatus.ready) return;
    web.runJavaScript(js).catchError((Object _) {});
  }

  void show(Measurements m, JalabiyaDesign d) {
    _state = engineState(m, d);
    _run('window.engine.apply(${jsonEncode(_state)})');
  }

  void setView(String v) {
    _view = v;
    _run('window.engine.setView(${jsonEncode(v)})');
  }

  void focus(String? key) {
    if (_focus == key) return;
    _focus = key;
    _run('window.engine.focus(${jsonEncode(key)})');
  }

  void setUnit(LengthUnit u) {
    _unit = u == LengthUnit.inch ? 'in' : 'cm';
    _run('window.engine.setUnit(${jsonEncode(_unit)})');
  }

  void setLabels(Map<String, String> labels) {
    _labels = labels;
    _run('window.engine.setLabels(${jsonEncode(labels)})');
  }

  /// Stops the render loop while the stage is hidden, to spare the battery.
  void setPaused(bool p) {
    if (_paused == p) return;
    _paused = p;
    _run('window.engine.setPaused(${p ? 'true' : 'false'})');
  }

  void dispose() {
    _disposed = true;
    status.dispose();
  }
}

/// The 3D stage plus its view switch. Drag sideways to turn the figure.
class FittingRoomView extends StatefulWidget {
  const FittingRoomView({super.key, required this.controller, this.showViewSwitch = true});

  final FittingRoomController controller;
  final bool showViewSwitch;

  @override
  State<FittingRoomView> createState() => _FittingRoomViewState();
}

class _FittingRoomViewState extends State<FittingRoomView> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    widget.controller.setLabels({
      'height': context.tr('m.height'),
      'shoulder': context.tr('m.shoulder'),
      'chest': context.tr('m.chest'),
      'waist': context.tr('m.waist'),
      'hip': context.tr('m.hip'),
      'hem': context.tr('d.hem'),
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Container(
      color: Palette.ink,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // The tape is drawn on the left inside the page, so keep the
                // WebView itself left-to-right whatever the app language is.
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: WebViewWidget(
                    controller: c.web,
                    gestureRecognizers: {
                      Factory<HorizontalDragGestureRecognizer>(
                        () => HorizontalDragGestureRecognizer(),
                      ),
                    },
                  ),
                ),
                ValueListenableBuilder<EngineStatus>(
                  valueListenable: c.status,
                  builder: (context, s, _) {
                    if (s == EngineStatus.ready) return const SizedBox.shrink();
                    if (s == EngineStatus.loading) {
                      return Container(
                        color: Palette.ink,
                        alignment: Alignment.center,
                        child: const SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Palette.gold),
                        ),
                      );
                    }
                    return Container(
                      color: Palette.ink,
                      padding: const EdgeInsets.all(24),
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.view_in_ar_outlined, color: Palette.gold, size: 32),
                          const SizedBox(height: 10),
                          Text(context.tr('room.noWebgl'),
                              textAlign: TextAlign.center, style: const TextStyle(color: Palette.damur, height: 1.5)),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          if (widget.showViewSwitch)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              child: Row(
                children: [
                  const Icon(Icons.swipe_rounded, size: 16, color: Palette.chalk),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(context.tr('room.dragHint'),
                        overflow: TextOverflow.ellipsis, style: const TextStyle(color: Palette.chalk, fontSize: 12)),
                  ),
                  SegmentBar(
                    dark: true,
                    values: const ['cloth', 'both', 'body'],
                    selected: c.view,
                    label: (v) => context.tr('room.view.$v'),
                    onSelected: (v) => setState(() => c.setView(v)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
