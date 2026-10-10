import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/errors.dart';
import '../l10n/strings.dart';
import '../models/design.dart';
import '../models/order.dart';
import '../models/tailor_shop.dart';
import '../state/network.dart';
import '../state/session.dart';
import '../theme/theme.dart';

/// One-line feedback at the bottom of the screen. Errors stay longer and buzz;
/// confirmations get a check. Pass [icon] for neutral hints.
void showSnack(BuildContext context, String message, {bool error = false, IconData? icon}) {
  if (error) {
    HapticFeedback.heavyImpact();
  } else {
    HapticFeedback.lightImpact();
  }
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      backgroundColor: error ? Palette.henna : Palette.ink,
      duration: Duration(seconds: error ? 5 : 3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      content: Row(
        children: [
          Icon(
            icon ?? (error ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded),
            color: error ? Colors.white : Palette.gold,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    ));
}

/// Asks before throwing away edits the user has not saved.
Future<bool> confirmDiscard(BuildContext context) => confirmAction(
      context,
      title: context.tr('discard.title'),
      body: context.tr('discard.body'),
      confirmLabel: context.tr('discard.confirm'),
      destructive: true,
    );

/// A strip of tailor's-tape ticks. The app's one ornament: it sits under
/// section titles and doubles as the profile-completeness bar.
class TapeRule extends StatelessWidget {
  const TapeRule({super.key, this.progress, this.height = 10});

  /// 0..1 to fill the tape like a progress bar; null for a plain rule.
  final double? progress;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _TapePainter(
          progress: progress,
          rtl: Directionality.of(context) == TextDirection.rtl,
        ),
      ),
    );
  }
}

class _TapePainter extends CustomPainter {
  _TapePainter({this.progress, required this.rtl});

  final double? progress;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    final base = Paint()
      ..color = Palette.line
      ..strokeWidth = 1;
    final filled = Paint()
      ..color = Palette.gold
      ..strokeWidth = 1.4;
    final p = progress;
    final edge = p == null ? -1.0 : size.width * p;
    canvas.drawLine(Offset(0, size.height - 0.5), Offset(size.width, size.height - 0.5), base);
    if (p != null) {
      final from = rtl ? size.width - edge : 0.0;
      final to = rtl ? size.width : edge;
      canvas.drawLine(
          Offset(from, size.height - 0.5),
          Offset(to, size.height - 0.5),
          Paint()
            ..color = Palette.gold
            ..strokeWidth = 2.5);
    }
    var i = 0;
    for (double x = 0; x <= size.width; x += 6, i++) {
      final major = i % 5 == 0;
      final h = major ? size.height * 0.9 : size.height * 0.45;
      final pos = rtl ? size.width - x : x;
      final inFill = p != null && x <= edge;
      canvas.drawLine(Offset(pos, size.height), Offset(pos, size.height - h), inFill ? filled : base);
    }
  }

  @override
  bool shouldRepaint(_TapePainter old) => old.progress != progress || old.rtl != rtl;
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing, this.subtitle});

  final String text;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(text, style: displayStyle(17))),
              if (trailing != null) trailing!,
            ],
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(subtitle!, style: const TextStyle(color: Palette.muted, fontSize: 13)),
            ),
          const SizedBox(height: 6),
          const TapeRule(height: 7),
        ],
      ),
    );
  }
}

/// A plain bordered card. Flat on purpose: tailors read these in shop light.
/// A card: white, softly lifted off the paper. Tinted panels ([color]) sit
/// flat, since they are notes inside a page rather than things to tap.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding, this.color, this.borderColor, this.onTap, this.flat});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final Color? borderColor;
  final VoidCallback? onTap;
  final bool? flat;

  static const radius = 16.0;
  static const shadow = [
    BoxShadow(color: Color(0x0F101A2B), blurRadius: 18, offset: Offset(0, 6)),
    BoxShadow(color: Color(0x08101A2B), blurRadius: 3, offset: Offset(0, 1)),
  ];

  @override
  Widget build(BuildContext context) {
    final body = Padding(padding: padding ?? const EdgeInsets.all(16), child: child);
    final lifted = !(flat ?? color != null);
    final card = Material(
      color: color ?? Palette.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: borderColor ?? (lifted ? const Color(0xFFEFE8DA) : Palette.line)),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? body : InkWell(onTap: onTap, child: body),
    );
    if (!lifted) return card;
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(radius), boxShadow: shadow),
      child: card,
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.mono = false, this.strong = false});

  final String label;
  final String value;
  final bool mono;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(label, style: const TextStyle(color: Palette.muted, fontSize: 14)),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: mono
                  ? monoStyle(14, color: strong ? Palette.goldInk : Palette.ink)
                  : TextStyle(
                      fontSize: 14.5,
                      fontWeight: strong ? FontWeight.w600 : FontWeight.w500,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.body, this.action});

  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(color: Palette.goldSoft, shape: BoxShape.circle),
              child: Icon(icon, size: 34, color: Palette.goldInk),
            ),
            const SizedBox(height: 18),
            Text(title, textAlign: TextAlign.center, style: displayStyle(19)),
            if (body != null) ...[
              const SizedBox(height: 8),
              Text(body!, textAlign: TextAlign.center, style: const TextStyle(color: Palette.muted, height: 1.5)),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

NetworkMonitor? _net(BuildContext context, {bool listen = false}) {
  try {
    return Provider.of<NetworkMonitor?>(context, listen: listen);
  } catch (_) {
    return null; // tests and previews run without one
  }
}

/// A whole screen that could not load: an icon for the kind of problem, a
/// title, what happened and what to do, and the right button.
///
/// When the problem is the connection, it shows the connection's state as it
/// changes and runs [onRetry] by itself the moment the server is reachable.
class ErrorView extends StatefulWidget {
  const ErrorView({super.key, required this.error, this.onRetry, this.onSecondary, this.secondaryLabel});

  final Object error;
  final VoidCallback? onRetry;
  final VoidCallback? onSecondary;
  final String? secondaryLabel;

  @override
  State<ErrorView> createState() => _ErrorViewState();
}

class _ErrorViewState extends State<ErrorView> {
  NetworkMonitor? _monitor;
  NetStatus? _last;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final m = _net(context);
    if (m != _monitor) {
      _monitor?.removeListener(_onNet);
      _monitor = m?..addListener(_onNet);
      _last = m?.status;
    }
  }

  @override
  void dispose() {
    _monitor?.removeListener(_onNet);
    super.dispose();
  }

  void _onNet() {
    final now = _monitor!.status;
    final cameBack = now == NetStatus.online && _last != NetStatus.online;
    _last = now;
    if (!mounted) return;
    setState(() {});
    if (cameBack && describeError(context, widget.error).canRetry) widget.onRetry?.call();
  }

  @override
  Widget build(BuildContext context) {
    final info = describeError(context, widget.error);
    final network = info.isNetwork || info.kind == ErrorKind.server;
    final tone = network ? Palette.henna : Palette.goldInk;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(color: network ? Palette.hennaSoft : Palette.goldSoft, shape: BoxShape.circle),
              child: Icon(info.icon, size: 38, color: tone),
            ),
            const SizedBox(height: 18),
            Text(info.title, textAlign: TextAlign.center, style: displayStyle(20)),
            const SizedBox(height: 8),
            Text(
              info.message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Palette.muted, height: 1.55, fontSize: 14.5),
            ),
            if (network && _monitor != null) ...[
              const SizedBox(height: 16),
              NetStatusPill(status: _monitor!.status),
            ],
            const SizedBox(height: 22),
            if (info.kind == ErrorKind.session)
              FilledButton.icon(
                onPressed: () => Provider.of<Session>(context, listen: false).signOut(),
                icon: const Icon(Icons.login_rounded),
                label: Text(context.tr('err.signInAgain')),
              )
            else if (widget.onRetry != null)
              FilledButton.icon(
                onPressed: widget.onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(context.tr('action.retry')),
              ),
            if (widget.onSecondary != null && widget.secondaryLabel != null)
              TextButton(onPressed: widget.onSecondary, child: Text(widget.secondaryLabel!)),
          ],
        ),
      ),
    );
  }
}

/// The connection as it is right now, in a few words, with a spinner while
/// the app keeps checking.
class NetStatusPill extends StatelessWidget {
  const NetStatusPill({super.key, required this.status});

  final NetStatus status;

  @override
  Widget build(BuildContext context) {
    final online = status == NetStatus.online;
    final color = online ? Palette.nile : Palette.henna;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: online ? Palette.nileSoft : Palette.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (online)
            Icon(Icons.check_circle_rounded, size: 16, color: color)
          else
            SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2, color: color)),
          const SizedBox(width: 8),
          Text(
            context.tr('net.${status.name}'),
            style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Shows [error] at the bottom of the screen: its icon, a title and the
/// explanation, with Retry when trying again could help ([onRetry]), or
/// "Sign in again" when the session ended.
void showError(BuildContext context, Object error, {VoidCallback? onRetry}) {
  final info = describeError(context, error);
  if (error.toString().contains('ACCOUNT_BLOCKED')) {
    // the server already knows; bring the blocked screen up now
    try {
      unawaited(Provider.of<Session>(context, listen: false).refreshBlock());
    } catch (_) {
      // tests and previews run without a session
    }
  }
  SnackBarAction? action;
  if (info.kind == ErrorKind.session) {
    final session = Provider.of<Session>(context, listen: false);
    action = SnackBarAction(label: context.tr('err.signInAgain'), textColor: Colors.white, onPressed: session.signOut);
  } else if (onRetry != null && info.canRetry) {
    action = SnackBarAction(label: context.tr('action.retry'), textColor: Colors.white, onPressed: onRetry);
  }
  _showInfo(context, info, action: action);
}

void _showInfo(BuildContext context, ErrorInfo info, {SnackBarAction? action}) {
  HapticFeedback.heavyImpact();
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      backgroundColor: info.isNetwork || info.kind == ErrorKind.server ? Palette.ink : Palette.henna,
      duration: const Duration(seconds: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      action: action,
      content: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(info.icon, color: info.isNetwork ? Palette.gold : Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(info.title, style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
                const SizedBox(height: 2),
                Text(info.message, style: const TextStyle(color: Color(0xE6FFFFFF), height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    ));
}

/// Call before anything that must reach the server. Returns true when it
/// can go ahead; otherwise explains why nothing was sent and returns false,
/// so the person isn't left waiting for a request that can't work.
Future<bool> requireOnline(BuildContext context) async {
  final net = _net(context);
  if (net == null || net.isOnline) return true;
  // With Wi-Fi and data off there is nothing to try. Otherwise the internet
  // may have just come back (data topped up), so look once, briefly.
  if (net.status != NetStatus.offline) {
    final ok = await net.check().timeout(const Duration(seconds: 5), onTimeout: () => false);
    if (ok) return true;
  }
  if (!context.mounted) return false;
  final kind = switch (net.status) {
    NetStatus.offline => ErrorKind.offline,
    NetStatus.serverDown => ErrorKind.server,
    _ => ErrorKind.noInternet,
  };
  _showInfo(context, ErrorInfo(kind, context.tr('err.title.${kind.name}'), context.tr('err.blocked.${kind.name}')));
  return false;
}

/// A row of mutually exclusive options, sized for thumbs.
class ChoiceRow extends StatelessWidget {
  const ChoiceRow(
      {super.key, required this.values, required this.selected, required this.label, required this.onSelected});

  final List<String> values;
  final String selected;
  final String Function(String value) label;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final v in values)
          ChoiceChip(
            label: Text(label(v)),
            selected: v == selected,
            showCheckmark: false,
            onSelected: (_) {
              if (v != selected) HapticFeedback.selectionClick();
              onSelected(v);
            },
            selectedColor: Palette.nile,
            backgroundColor: Palette.card,
            side: BorderSide(color: v == selected ? Palette.nile : Palette.line),
            labelStyle: TextStyle(
              color: v == selected ? Colors.white : Palette.ink,
              fontWeight: FontWeight.w500,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
      ],
    );
  }
}

/// Small segmented switch used under the 3D stage and in settings.
class SegmentBar extends StatelessWidget {
  const SegmentBar(
      {super.key,
      required this.values,
      required this.selected,
      required this.label,
      required this.onSelected,
      this.dark = false});

  final List<String> values;
  final String selected;
  final String Function(String) label;
  final ValueChanged<String> onSelected;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final border = dark ? Palette.ink3 : Palette.line;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final v in values)
            InkWell(
              borderRadius: BorderRadius.circular(9),
              onTap: () => onSelected(v),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: v == selected ? (dark ? Palette.damur : Palette.ink) : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  label(v),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: v == selected
                        ? (dark ? Palette.ink : Colors.white)
                        : (dark ? Palette.onInkMuted : Palette.muted),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A cloth or thread colour's name: the one the tailor typed, or the
/// translation of a standard colour. [kind] is `cloth` or `thread`.
String swatchName(BuildContext context, String kind, Swatch s) => s.name ?? context.tr('$kind.${s.id}');

/// True for a 0xRRGGBB colour dark enough to need light text on top.
bool isDarkColor(int rgb) => Color(0xFF000000 | rgb).computeLuminance() < 0.18;

class SwatchRow extends StatelessWidget {
  const SwatchRow({
    super.key,
    required this.swatches,
    required this.selected,
    required this.label,
    required this.onSelected,
    this.note,
  });

  final List<Swatch> swatches;
  final String selected;
  final String Function(Swatch s) label;
  final ValueChanged<Swatch> onSelected;

  /// Extra text after the selected colour's name, such as its price.
  final String? Function(Swatch s)? note;

  @override
  Widget build(BuildContext context) {
    final current = swatches.where((s) => s.id == selected).firstOrNull;
    final extra = current == null ? null : note?.call(current);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final s in swatches)
              Semantics(
                button: true,
                selected: s.id == selected,
                label: label(s),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (s.id != selected) HapticFeedback.selectionClick();
                    onSelected(s);
                  },
                  child: _SwatchDot(swatch: s, selected: s.id == selected),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (current != null)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Text(
              extra == null ? label(current) : '${label(current)} · $extra',
              key: ValueKey(current.id),
              style: const TextStyle(color: Palette.ink, fontSize: 13.5, fontWeight: FontWeight.w500),
            ),
          ),
      ],
    );
  }
}

/// One colour to pick: a 52 px disc that gains a gold ring and a check.
class _SwatchDot extends StatelessWidget {
  const _SwatchDot({required this.swatch, required this.selected});

  final Swatch swatch;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final dark = isDarkColor(swatch.color);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: 52,
      height: 52,
      padding: EdgeInsets.all(selected ? 4 : 3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: selected ? Palette.gold : Palette.line, width: selected ? 2.5 : 1),
        boxShadow:
            selected ? const [BoxShadow(color: Color(0x33C8A24A), blurRadius: 10, offset: Offset(0, 3))] : const [],
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFF000000 | swatch.color),
          border: Border.all(color: const Color(0x22101A2B)),
        ),
        child: AnimatedScale(
          scale: selected ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutBack,
          child: Icon(Icons.check_rounded, size: 22, color: dark ? Colors.white : Palette.ink),
        ),
      ),
    );
  }
}

/// A shop's colours at a glance: small dots, the rest counted.
class SwatchStrip extends StatelessWidget {
  const SwatchStrip({super.key, required this.swatches, this.max = 8});

  final List<Swatch> swatches;
  final int max;

  @override
  Widget build(BuildContext context) {
    final shown = swatches.take(max).toList();
    return Row(
      children: [
        for (final s in shown)
          Container(
            width: 18,
            height: 18,
            margin: const EdgeInsetsDirectional.only(end: 5),
            decoration: BoxDecoration(
              color: Color(0xFF000000 | s.color),
              shape: BoxShape.circle,
              border: Border.all(color: Palette.line),
            ),
          ),
        if (swatches.length > shown.length)
          Text('+${swatches.length - shown.length}', style: const TextStyle(color: Palette.muted, fontSize: 12)),
      ],
    );
  }
}

Color statusColor(OrderStatus s) {
  switch (s) {
    case OrderStatus.submitted:
      return Palette.goldInk;
    case OrderStatus.changesRequested:
    case OrderStatus.priceOffered:
      return Palette.henna;
    case OrderStatus.declined:
    case OrderStatus.cancelled:
      return Palette.muted;
    case OrderStatus.delivered:
      return Palette.ink;
    default:
      return Palette.nile;
  }
}

Color statusBackground(OrderStatus s) {
  switch (s) {
    case OrderStatus.submitted:
      return Palette.goldSoft;
    case OrderStatus.changesRequested:
    case OrderStatus.priceOffered:
      return Palette.hennaSoft;
    case OrderStatus.declined:
    case OrderStatus.cancelled:
    case OrderStatus.delivered:
      return const Color(0xFFECEDEF);
    default:
      return Palette.nileSoft;
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: statusBackground(status),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        context.tr('status.${statusToDb(status)}'),
        style: TextStyle(color: statusColor(status), fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Primary action pinned to the bottom, with a spinner while it works.
class BottomActions extends StatelessWidget {
  const BottomActions({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Palette.card,
        border: Border(top: BorderSide(color: Palette.line)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: children[i]),
            ],
          ],
        ),
      ),
    );
  }
}

class BusyButton extends StatelessWidget {
  const BusyButton({super.key, required this.label, required this.busy, required this.onPressed, this.icon});

  final String label;
  final bool busy;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
                Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
              ],
            ),
    );
  }
}

class NoticeBanner extends StatelessWidget {
  const NoticeBanner({super.key, required this.text, this.title, this.tone = BannerTone.info, this.action});

  final String? title;
  final String text;
  final BannerTone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final bg = tone == BannerTone.warn
        ? Palette.hennaSoft
        : tone == BannerTone.gold
            ? Palette.goldSoft
            : Palette.nileSoft;
    final fg = tone == BannerTone.warn
        ? Palette.henna
        : tone == BannerTone.gold
            ? Palette.goldInk
            : Palette.nile;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(title!, style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
            ),
          Text(text, style: TextStyle(color: fg, height: 1.45)),
          if (action != null) Padding(padding: const EdgeInsets.only(top: 8), child: action!),
        ],
      ),
    );
  }
}

enum BannerTone { info, warn, gold }

/// What a tailor needs to know about their shop's listing: waiting for
/// review, turned down or suspended (with the reviewer's reason), or paused
/// by themselves. Check [applies] first; a listed shop taking orders has none.
class ShopStatusBanner extends StatelessWidget {
  const ShopStatusBanner({super.key, required this.shop});

  final TailorShop shop;

  static bool applies(TailorShop shop) => shop.review != ShopReview.approved || !shop.acceptsOrders;

  @override
  Widget build(BuildContext context) {
    final reason = (shop.reviewNote ?? '').trim();
    String withReason(String key) =>
        reason.isEmpty ? context.tr('${key}Plain') : context.tr(key, {'reason': reason});
    return switch (shop.review) {
      ShopReview.pending => NoticeBanner(
          tone: BannerTone.gold, title: context.tr('shop.pendingTitle'), text: context.tr('shop.pendingBody')),
      ShopReview.rejected => NoticeBanner(
          tone: BannerTone.warn, title: context.tr('shop.rejectedTitle'), text: withReason('shop.rejectedBody')),
      ShopReview.suspended => NoticeBanner(
          tone: BannerTone.warn, title: context.tr('shop.suspendedTitle'), text: withReason('shop.suspendedBody')),
      ShopReview.approved => shop.acceptsOrders
          ? const SizedBox.shrink()
          : NoticeBanner(tone: BannerTone.warn, text: context.tr('shop.pausedBody')),
    };
  }
}

/// Bottom sheet that asks for one line of text, e.g. a note for the customer.
Future<String?> askForText(
  BuildContext context, {
  required String title,
  required String hint,
  required String confirmLabel,
  bool required = true,
  String initial = '',
}) {
  final ctrl = TextEditingController(text: initial);
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Palette.paper,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) {
      String? error;
      return StatefulBuilder(builder: (ctx, setSheet) {
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: displayStyle(19)),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                autofocus: true,
                minLines: 3,
                maxLines: 6,
                maxLength: 500,
                decoration: field(hintText: hint, errorText: error),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () {
                  final v = ctrl.text.trim();
                  if (required && v.isEmpty) {
                    setSheet(() => error = ctx.tr('form.required'));
                    return;
                  }
                  Navigator.of(ctx).pop(v);
                },
                child: Text(confirmLabel),
              ),
            ],
          ),
        );
      });
    },
  );
}

Future<bool> confirmAction(BuildContext context,
    {required String title, required String body, required String confirmLabel, bool destructive = false}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Palette.paper,
      title: Text(title, style: displayStyle(19)),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(ctx.tr('action.back'))),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: Palette.henna, minimumSize: const Size(64, 44))
              : FilledButton.styleFrom(minimumSize: const Size(64, 44)),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}
