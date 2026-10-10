import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../state/session.dart';
import '../theme/theme.dart';
import '../util/format.dart';
import 'common.dart';

/// One line in the side menu.
class DrawerEntry {
  const DrawerEntry({
    required this.id,
    required this.icon,
    required this.label,
    required this.onTap,
    this.selectedIcon,
    this.highlight = false,
    this.badge = 0,
  });

  final String id;
  final IconData icon;
  final IconData? selectedIcon;
  final String label;
  final VoidCallback onTap;

  /// Drawn as a filled call to action (e.g. "New order").
  final bool highlight;

  /// A count to flag, e.g. new orders waiting; hidden when 0.
  final int badge;
}

/// The side menu shared by the customer and tailor homes: who you are, where
/// you can go, quick settings, and signing out. Opens from the start edge, so
/// from the right in Arabic.
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key, required this.entries, this.selected});

  final List<DrawerEntry> entries;

  /// The [DrawerEntry.id] of the screen currently showing.
  final String? selected;

  void _go(BuildContext context, VoidCallback action) {
    Navigator.of(context).pop(); // close the drawer first, then act
    action();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    final cta = entries.where((e) => e.highlight).toList();
    final nav = entries.where((e) => !e.highlight).toList();
    return Drawer(
      backgroundColor: Palette.paper,
      width: (MediaQuery.sizeOf(context).width * 0.84).clamp(260.0, 340.0),
      child: Column(
        children: [
          _Header(session: s),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
              children: [
                for (final e in cta)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: FilledButton.icon(
                      onPressed: () => _go(context, e.onTap),
                      icon: Icon(e.icon),
                      label: Text(e.label),
                    ),
                  ),
                for (final e in nav)
                  _Item(
                    entry: e,
                    selected: e.id == selected,
                    onTap: () => _go(context, e.onTap),
                  ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  child: Divider(),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: Text(
                    context.tr('settings.title'),
                    style: const TextStyle(color: Palette.muted, fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
                _SettingRow(
                  icon: Icons.translate_rounded,
                  label: context.tr('settings.language'),
                  control: SegmentBar(
                    values: const ['ar', 'en'],
                    selected: s.locale.languageCode,
                    label: (v) => v == 'ar' ? 'عربي' : 'English',
                    onSelected: s.setLocale,
                  ),
                ),
                _SettingRow(
                  icon: Icons.straighten_rounded,
                  label: context.tr('settings.units'),
                  control: SegmentBar(
                    values: const ['cm', 'in'],
                    selected: s.unit == LengthUnit.cm ? 'cm' : 'in',
                    label: (v) => context.tr('settings.unit.$v'),
                    onSelected: (v) => s.setUnit(v == 'cm' ? LengthUnit.cm : LengthUnit.inch),
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: const Icon(Icons.logout_rounded, color: Palette.henna),
                title: Text(context.tr('action.signOut'),
                    style: const TextStyle(color: Palette.henna, fontWeight: FontWeight.w600)),
                onTap: () async {
                  Navigator.of(context).pop();
                  final ok = await confirmAction(
                    context,
                    title: context.tr('action.signOut'),
                    body: context.tr('settings.signOutBody'),
                    confirmLabel: context.tr('action.signOut'),
                    destructive: true,
                  );
                  if (ok) await s.signOut();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final p = session.profile;
    final name = (p?.fullName ?? '').trim();
    final shop = session.shop;
    final subtitle = p == null ? '' : (p.isTailor && shop != null ? shop.shopName : (session.user?.email ?? ''));
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [Palette.ink3, Palette.ink],
        ),
      ),
      child: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: _DiamondsPainter())),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Palette.goldSoft,
                      shape: BoxShape.circle,
                      border: Border.all(color: Palette.gold, width: 2),
                    ),
                    child: Text(
                      name.isEmpty ? '?' : name.characters.first,
                      style: displayStyle(24, color: Palette.goldInk),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    name.isEmpty ? '—' : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: displayStyle(20, color: Palette.damur),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (p != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(
                            color: Palette.gold.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            context.tr(p.isTailor ? 'role.tailor' : 'role.customer'),
                            style: const TextStyle(color: Palette.gold, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Palette.onInkMuted, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A faint lattice of diamonds, the embroidery motif, in the header corner.
class _DiamondsPainter extends CustomPainter {
  const _DiamondsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const cell = 22.0;
    for (var row = 0; row * cell < size.height + cell; row++) {
      final shift = row.isOdd ? cell / 2 : 0.0;
      for (var col = 0; col * cell < size.width + cell; col++) {
        final x = col * cell + shift, y = row * cell;
        // strongest in the far top corner, fading toward the text
        final fade = ((x / size.width) * (1 - y / size.height)).clamp(0.0, 1.0);
        if (fade < 0.05) continue;
        paint.color = Palette.gold.withValues(alpha: 0.16 * fade);
        canvas.drawPath(
          Path()
            ..moveTo(x, y - 5)
            ..lineTo(x + 4, y)
            ..lineTo(x, y + 5)
            ..lineTo(x - 4, y)
            ..close(),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_DiamondsPainter oldDelegate) => false;
}

class _Item extends StatelessWidget {
  const _Item({required this.entry, required this.selected, required this.onTap});

  final DrawerEntry entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        selected: selected,
        selectedTileColor: Palette.nileSoft,
        selectedColor: Palette.nile,
        iconColor: Palette.muted,
        textColor: Palette.ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Icon(selected ? (entry.selectedIcon ?? entry.icon) : entry.icon),
        title: Text(
          entry.label,
          style: TextStyle(fontSize: 15, fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
        ),
        trailing: entry.badge > 0
            ? Container(
                constraints: const BoxConstraints(minWidth: 24),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(color: Palette.henna, borderRadius: BorderRadius.circular(12)),
                child: Text(
                  entry.badge > 99 ? '99+' : '${entry.badge}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              )
            : null,
        onTap: onTap,
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.icon, required this.label, required this.control});

  final IconData icon;
  final String label;
  final Widget control;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Palette.muted),
          const SizedBox(width: 14),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14.5))),
          control,
        ],
      ),
    );
  }
}

/// The menu button for app bars inside a tab. Tabs build their own Scaffold,
/// so the drawer lives on the home Scaffold above them: this finds it.
class DrawerMenuButton extends StatelessWidget {
  const DrawerMenuButton({super.key});

  ScaffoldState? _drawerScaffold(BuildContext context) {
    ScaffoldState? found;
    context.visitAncestorElements((e) {
      if (e is StatefulElement && e.state is ScaffoldState && (e.state as ScaffoldState).hasDrawer) {
        found = e.state as ScaffoldState;
        return false;
      }
      return true;
    });
    return found;
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: context.tr('drawer.menu'),
      icon: const Icon(Icons.menu_rounded),
      onPressed: () => _drawerScaffold(context)?.openDrawer(),
    );
  }
}
