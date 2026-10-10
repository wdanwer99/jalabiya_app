import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'motion.dart';

/// One tab in [AnimatedNavBar].
class NavItem {
  const NavItem({required this.icon, required this.selectedIcon, required this.label, this.badge = 0});

  final IconData icon;
  final IconData selectedIcon;
  final String label;

  /// A count to flag on the icon (e.g. new orders); hidden when 0.
  final int badge;
}

/// The bottom navigation of both homes.
///
/// A Nile pill glides to the chosen tab, stretching a little on the way. The
/// icon fills in with a small spring, the label darkens, and a badge pops each
/// time its count changes. Buttons sink under the finger. With reduced motion
/// everything shows its end state at once.
///
/// Haptics are left to [onSelected], since tabs also change from the menu.
class AnimatedNavBar extends StatefulWidget {
  const AnimatedNavBar({super.key, required this.items, required this.selectedIndex, required this.onSelected});

  final List<NavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const height = 68.0;

  @override
  State<AnimatedNavBar> createState() => _AnimatedNavBarState();
}

class _AnimatedNavBarState extends State<AnimatedNavBar> with SingleTickerProviderStateMixin {
  late final AnimationController _glide =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 420), value: 1);

  /// Where the pill set off from, in tab units.
  late double _from = widget.selectedIndex.toDouble();

  double _pillAt(double t, int target) => lerpDouble(_from, target.toDouble(), Curves.easeOutCubic.transform(t))!;

  @override
  void didUpdateWidget(AnimatedNavBar old) {
    super.didUpdateWidget(old);
    if (old.selectedIndex == widget.selectedIndex) return;
    // leave from wherever the pill is now, even if it is still gliding
    _from = _pillAt(_glide.value, old.selectedIndex);
    if (reduceMotion(context)) {
      _glide.value = 1;
    } else {
      _glide.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _glide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.items.length;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Palette.card,
        border: Border(top: BorderSide(color: Palette.line)),
        boxShadow: [BoxShadow(color: Color(0x12101A2B), blurRadius: 18, offset: Offset(0, -4))],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: AnimatedNavBar.height,
            child: LayoutBuilder(
              builder: (context, box) {
                final slot = box.maxWidth / n;
                final pillW = math.min(slot - 16, 64.0);
                return Stack(
                  children: [
                    AnimatedBuilder(
                      animation: _glide,
                      builder: (context, _) {
                        final t = _glide.value;
                        final at = _pillAt(t, widget.selectedIndex);
                        // stretch mid-flight, more for longer jumps
                        final jump = (widget.selectedIndex - _from).abs().clamp(0.0, 2.0);
                        final stretch = math.sin(math.pi * Curves.easeOutCubic.transform(t)) * 0.35 * jump;
                        final w = pillW * (1 + stretch);
                        return PositionedDirectional(
                          start: (at + 0.5) * slot - w / 2,
                          top: 9,
                          width: w,
                          height: 32,
                          child: const DecoratedBox(
                            decoration: BoxDecoration(
                              color: Palette.nileSoft,
                              borderRadius: BorderRadius.all(Radius.circular(16)),
                            ),
                          ),
                        );
                      },
                    ),
                    Row(
                      children: [
                        for (var i = 0; i < n; i++)
                          Expanded(
                            child: _NavButton(
                              item: widget.items[i],
                              selected: i == widget.selectedIndex,
                              onTap: () {
                                if (i != widget.selectedIndex) widget.onSelected(i);
                              },
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.item, required this.selected, required this.onTap});

  final NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final still = reduceMotion(context);
    final quick = still ? Duration.zero : Motion.quick;
    final color = selected ? Palette.nile : Palette.muted;
    final labelStyle = (Theme.of(context).textTheme.labelMedium ?? const TextStyle()).copyWith(
      fontSize: 12,
      height: 1.2,
      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      color: selected ? Palette.ink : Palette.muted,
    );
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: item.badge > 0 ? '${item.label}, ${item.badge}' : item.label,
      // Only the visuals are hidden from screen readers; the InkResponse stays
      // visible to them so the tab keeps its tap and focus actions.
      child: Pressable(
        scale: 0.92,
        child: InkResponse(
          onTap: onTap,
          radius: 34,
          splashColor: Palette.nile.withValues(alpha: 0.12),
          highlightColor: Colors.transparent,
          child: ExcludeSemantics(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 32,
                  child: Center(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // outline swaps to filled with a small spring
                        AnimatedSwitcher(
                          duration: still ? Duration.zero : const Duration(milliseconds: 280),
                          switchInCurve: Curves.easeOutBack,
                          switchOutCurve: Curves.easeIn,
                          transitionBuilder: (child, a) => FadeTransition(
                            opacity: a,
                            child: ScaleTransition(scale: Tween(begin: 0.6, end: 1.0).animate(a), child: child),
                          ),
                          child: Icon(
                            selected ? item.selectedIcon : item.icon,
                            key: ValueKey(selected),
                            color: color,
                            size: 24,
                          ),
                        ),
                        PositionedDirectional(
                          top: -5,
                          end: -11,
                          child: _Badge(count: item.badge, still: still),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                AnimatedDefaultTextStyle(
                  duration: quick,
                  curve: Motion.curve,
                  style: labelStyle,
                  child: Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A henna count that pops each time it changes and shrinks away at 0.
class _Badge extends StatelessWidget {
  const _Badge({required this.count, required this.still});

  final int count;
  final bool still;

  @override
  Widget build(BuildContext context) {
    final text = count > 99 ? '99+' : '$count';
    return AnimatedScale(
      scale: count > 0 ? 1 : 0,
      duration: still ? Duration.zero : Motion.quick,
      curve: count > 0 ? Curves.easeOutBack : Curves.easeIn,
      child: TweenAnimationBuilder<double>(
        // a new key restarts the pop whenever the number changes
        key: ValueKey(count),
        tween: Tween(begin: still ? 1 : 1.4, end: 1),
        duration: still ? Duration.zero : const Duration(milliseconds: 520),
        curve: Curves.elasticOut,
        builder: (context, s, child) => Transform.scale(scale: s, child: child),
        child: Container(
          constraints: const BoxConstraints(minWidth: 18),
          height: 18,
          padding: const EdgeInsets.symmetric(horizontal: 5),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Palette.henna,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: Palette.card, width: 1.5),
          ),
          child: Text(
            count > 0 ? text : '',
            style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700, height: 1),
          ),
        ),
      ),
    );
  }
}
