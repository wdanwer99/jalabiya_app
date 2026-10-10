import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../l10n/strings.dart';
import '../models/places.dart';

enum LengthUnit { cm, inch }

const double cmPerInch = 2.54;

String trimNumber(double v, {int decimals = 1}) {
  final s = v.toStringAsFixed(decimals);
  if (!s.contains('.')) return s;
  return s.replaceFirst(RegExp(r'\.?0+$'), '');
}

/// 140.15 → "140.1 cm" or "55.2″". Rounds like the web prototype.
String formatLength(double cm, LengthUnit unit) {
  if (unit == LengthUnit.cm) {
    return '${trimNumber((cm * 10).round() / 10)} cm';
  }
  final inches = cm / cmPerInch;
  return '${trimNumber((inches * 10).round() / 10)}″';
}

double toUnit(double cm, LengthUnit unit) =>
    unit == LengthUnit.cm ? cm : cm / cmPerInch;

double fromUnit(double v, LengthUnit unit) =>
    unit == LengthUnit.cm ? v : v * cmPerInch;

/// Accepts Arabic-Indic digits and a comma decimal, which Arabic keyboards send.
double? parseLooseNumber(String input) {
  const arabicIndic = '٠١٢٣٤٥٦٧٨٩';
  const easternArabic = '۰۱۲۳۴۵۶۷۸۹';
  final b = StringBuffer();
  for (final ch in input.trim().split('')) {
    final a = arabicIndic.indexOf(ch);
    final e = easternArabic.indexOf(ch);
    if (a >= 0) {
      b.write(a);
    } else if (e >= 0) {
      b.write(e);
    } else if (ch == ',' || ch == '٫' || ch == '،') {
      b.write('.');
    } else {
      b.write(ch);
    }
  }
  return double.tryParse(b.toString().replaceAll(' ', ''));
}

String formatMoney(BuildContext context, double amount, String currency) {
  final n = NumberFormat.decimalPattern('en').format(amount);
  final unit = currency == 'SDG' ? context.tr('money.sdg') : currency;
  return '$n $unit';
}

String formatDate(BuildContext context, DateTime d) {
  final lang = Localizations.localeOf(context).languageCode;
  return DateFormat.yMMMd(lang).format(d);
}

String formatDateTime(BuildContext context, DateTime d) {
  final lang = Localizations.localeOf(context).languageCode;
  return '${DateFormat.yMMMd(lang).format(d)} · ${DateFormat.Hm(lang).format(d)}';
}

/// City keys become their local name; anything typed by hand shows as typed.
String cityLabel(BuildContext context, String? city) {
  if (city == null || city.trim().isEmpty) return '—';
  if (sudanCities.contains(city)) return context.tr('city.$city');
  return city;
}

String placeLine(BuildContext context, String? city, String? neighbourhood) {
  final parts = <String>[];
  if ((neighbourhood ?? '').trim().isNotEmpty) parts.add(neighbourhood!.trim());
  if ((city ?? '').trim().isNotEmpty) parts.add(cityLabel(context, city));
  return parts.isEmpty ? '—' : parts.join('، ');
}
