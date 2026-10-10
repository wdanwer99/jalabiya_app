// Also stops `flutter create .` from generating its default counter test,
// which would not compile against this app.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jalabiya_app/models/order.dart';
import 'package:jalabiya_app/widgets/common.dart';

Widget _host(Locale locale, Widget child) => MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('status chip speaks Arabic by default and right-to-left', (tester) async {
    await tester.pumpWidget(_host(const Locale('ar'), const StatusChip(OrderStatus.changesRequested)));
    expect(find.text('مطلوب تعديل'), findsOneWidget);
    final dir = Directionality.of(tester.element(find.byType(StatusChip)));
    expect(dir, TextDirection.rtl);
  });

  testWidgets('status chip in English', (tester) async {
    await tester.pumpWidget(_host(const Locale('en'), const StatusChip(OrderStatus.sewing)));
    expect(find.text('Sewing'), findsOneWidget);
  });

  testWidgets('tape rule paints as a progress bar', (tester) async {
    await tester.pumpWidget(_host(const Locale('en'), const TapeRule(progress: 0.6)));
    expect(find.byType(TapeRule), findsOneWidget);
  });
}
