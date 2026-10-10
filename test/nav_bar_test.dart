import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jalabiya_app/widgets/nav_bar.dart';

void main() {
  Widget host({required int selected, required ValueChanged<int> onSelected, int badge = 0, bool still = false}) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: still),
        child: Scaffold(
          bottomNavigationBar: AnimatedNavBar(
            selectedIndex: selected,
            onSelected: onSelected,
            items: [
              NavItem(
                  icon: Icons.receipt_long_outlined,
                  selectedIcon: Icons.receipt_long_rounded,
                  label: 'Orders',
                  badge: badge),
              const NavItem(icon: Icons.straighten_outlined, selectedIcon: Icons.straighten_rounded, label: 'Sizes'),
              const NavItem(icon: Icons.person_outline_rounded, selectedIcon: Icons.person_rounded, label: 'Account'),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('tapping a tab reports it; tapping the current one does nothing', (tester) async {
    final taps = <int>[];
    await tester.pumpWidget(host(selected: 0, onSelected: taps.add));
    await tester.tap(find.text('Sizes'));
    await tester.tap(find.text('Orders'));
    await tester.pumpAndSettle();
    expect(taps, [1]);
  });

  testWidgets('the selected tab shows its filled icon, and the pill glides to a new one', (tester) async {
    await tester.pumpWidget(host(selected: 0, onSelected: (_) {}));
    expect(find.byIcon(Icons.receipt_long_rounded), findsOneWidget);
    expect(find.byIcon(Icons.straighten_outlined), findsOneWidget);

    await tester.pumpWidget(host(selected: 2, onSelected: (_) {}));
    await tester.pump(const Duration(milliseconds: 100)); // mid-glide: no errors, still animating
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.person_rounded), findsOneWidget);
    expect(find.byIcon(Icons.receipt_long_outlined), findsOneWidget);
  });

  testWidgets('with reduced motion the change is immediate', (tester) async {
    await tester.pumpWidget(host(selected: 0, onSelected: (_) {}, still: true));
    await tester.pumpWidget(host(selected: 1, onSelected: (_) {}, still: true));
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.byIcon(Icons.straighten_rounded), findsOneWidget);
  });

  testWidgets('a badge shows its count, caps at 99+, and is announced', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host(selected: 1, onSelected: (_) {}, badge: 3));
    await tester.pumpAndSettle();
    expect(find.text('3'), findsOneWidget);
    expect(find.bySemanticsLabel('Orders, 3'), findsOneWidget);

    await tester.pumpWidget(host(selected: 1, onSelected: (_) {}, badge: 150));
    await tester.pumpAndSettle();
    expect(find.text('99+'), findsOneWidget);

    await tester.pumpWidget(host(selected: 1, onSelected: (_) {}, badge: 0));
    await tester.pumpAndSettle();
    expect(find.text('99+'), findsNothing);
    expect(find.bySemanticsLabel('Orders'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('screen readers hear which tab is selected', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host(selected: 1, onSelected: (_) {}));
    expect(
      tester.getSemantics(find.bySemanticsLabel('Sizes')),
      matchesSemantics(
        label: 'Sizes',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        isInMutuallyExclusiveGroup: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
      ),
    );
    handle.dispose();
  });
}
