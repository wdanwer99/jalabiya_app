import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:jalabiya_app/util/format.dart';
import 'package:jalabiya_app/widgets/measure_field.dart';

/// A chest box (76–150 cm) that remembers what it was given.
class _Host extends StatefulWidget {
  const _Host({required this.log, this.unit = LengthUnit.cm});

  final List<String> log;
  final LengthUnit unit;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  double value = 104;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        MeasureField(
          label: 'Chest',
          valueCm: value,
          minCm: 76,
          maxCm: 150,
          stepCm: 0.5,
          unit: widget.unit,
          onChanged: (v) => setState(() => value = v),
          onValidChanged: (ok) => widget.log.add(ok ? 'valid' : 'invalid'),
        ),
        // somewhere else to tap, to leave the box
        const TextField(key: Key('other')),
      ],
    );
  }
}

Future<_HostState> _pump(WidgetTester tester, List<String> log, {LengthUnit unit = LengthUnit.cm}) async {
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('en'),
    supportedLocales: const [Locale('ar'), Locale('en')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: _Host(log: log, unit: unit)),
  ));
  return tester.state<_HostState>(find.byType(_Host));
}

Finder get _box => find.descendant(of: find.byType(MeasureField), matching: find.byType(TextField));

Future<void> _leaveBox(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('other')));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('letters are flagged at once and never used', (tester) async {
    final log = <String>[];
    final host = await _pump(tester, log);
    await tester.enterText(_box, 'abc');
    await tester.pump();
    expect(find.textContaining('Type a number only'), findsOneWidget);
    expect(host.value, 104);
    expect(log, ['invalid']);
  });

  testWidgets('a too-small number waits while typing, then stays red with the kept value', (tester) async {
    final log = <String>[];
    final host = await _pump(tester, log);
    await tester.tap(_box);
    await tester.enterText(_box, '1');
    await tester.pump();
    expect(find.textContaining('Too small'), findsNothing, reason: '"1" may become "175"');

    await _leaveBox(tester);
    expect(find.textContaining('Too small'), findsOneWidget);
    expect(find.textContaining('Still using 104 cm'), findsOneWidget);
    expect(find.text('1'), findsOneWidget, reason: 'the bad entry stays visible, not silently replaced');
    expect(host.value, 104);
    expect(log, ['invalid']);

    // undo puts back the kept value
    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Too small'), findsNothing);
    expect(find.text('104'), findsOneWidget);
    expect(log, ['invalid', 'valid']);
  });

  testWidgets('a too-small number also counts after a pause in typing', (tester) async {
    final log = <String>[];
    await _pump(tester, log);
    await tester.tap(_box);
    await tester.enterText(_box, '50');
    await tester.pump(const Duration(milliseconds: 1300));
    expect(find.textContaining('Too small'), findsOneWidget);
  });

  testWidgets('a too-large number is flagged at once', (tester) async {
    final log = <String>[];
    final host = await _pump(tester, log);
    await tester.enterText(_box, '300');
    await tester.pump();
    expect(find.textContaining('Too large'), findsOneWidget);
    expect(host.value, 104);
  });

  testWidgets('inches typed in cm mode are spotted and fixed with one tap', (tester) async {
    final log = <String>[];
    final host = await _pump(tester, log);
    await tester.tap(_box);
    await tester.enterText(_box, '40');
    await _leaveBox(tester);
    expect(find.textContaining('Did you type 40 in inches? Use 101.6 cm'), findsOneWidget);

    await tester.tap(find.textContaining('Did you type 40 in inches'));
    await tester.pumpAndSettle();
    expect(host.value, closeTo(101.6, 1e-9));
    expect(find.textContaining('Too small'), findsNothing);
    expect(log, ['invalid', 'valid']);
  });

  testWidgets('a good number is used live and leaves no error', (tester) async {
    final log = <String>[];
    final host = await _pump(tester, log);
    await tester.tap(_box);
    await tester.enterText(_box, '110');
    await _leaveBox(tester);
    expect(host.value, 110);
    expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
    expect(log, isEmpty);
  });
}
