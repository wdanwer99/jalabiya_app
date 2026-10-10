import 'package:url_launcher/url_launcher.dart';

import '../models/profile.dart';

/// Local Sudanese numbers (0912345678) become international (249912345678)
/// because WhatsApp links need the country code. Numbers that already carry
/// one are left alone.
String internationalNumber(String raw) {
  final d = digitsOnly(raw);
  if (d.startsWith('00')) return d.substring(2);
  if (d.length == 10 && d.startsWith('0')) return '249${d.substring(1)}';
  if (d.length == 9 && (d.startsWith('9') || d.startsWith('1'))) return '249$d';
  return d;
}

Future<bool> callNumber(String raw) {
  return launchUrl(Uri(scheme: 'tel', path: '+${internationalNumber(raw)}'));
}

Future<bool> openWhatsApp(String raw, {String? text}) {
  final uri = Uri.https(
    'wa.me',
    '/${internationalNumber(raw)}',
    text == null ? null : {'text': text},
  );
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
