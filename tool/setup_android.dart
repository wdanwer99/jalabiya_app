// Run once after `flutter create`:
//
//   dart run tool/setup_android.dart
//
// Adds what the generated Android project is missing for this app:
//   * INTERNET permission (release builds have none by default, so Supabase
//     would fail only in the build you ship)
//   * <queries> so "Call" and "WhatsApp" buttons can open other apps on
//     Android 11+
//   * the app name shown under the icon
import 'dart:io';

void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml');
  if (!manifest.existsSync()) {
    stderr.writeln('android/ not found. First run:\n'
        '  flutter create --org sd.jalabiya --project-name jalabiya_app --platforms android .');
    exit(1);
  }
  var xml = manifest.readAsStringSync();
  final before = xml;

  const internet = '<uses-permission android:name="android.permission.INTERNET"/>';
  if (!xml.contains('android.permission.INTERNET')) {
    xml = xml.replaceFirst('<application', '$internet\n    <application');
  }

  const intents = '''
        <intent>
            <action android:name="android.intent.action.DIAL"/>
            <data android:scheme="tel"/>
        </intent>
        <intent>
            <action android:name="android.intent.action.VIEW"/>
            <data android:scheme="https"/>
        </intent>''';
  if (!xml.contains('android:scheme="tel"')) {
    if (xml.contains('<queries>')) {
      xml = xml.replaceFirst('<queries>', '<queries>$intents');
    } else {
      xml = xml.replaceFirst('</manifest>', '    <queries>$intents\n    </queries>\n</manifest>');
    }
  }

  xml = xml.replaceFirst(RegExp(r'android:label="[^"]*"'), 'android:label="جلابية"');

  if (xml == before) {
    stdout.writeln('AndroidManifest.xml already set up.');
  } else {
    manifest.writeAsStringSync(xml);
    stdout.writeln('AndroidManifest.xml updated: internet, call/WhatsApp links, app name.');
  }
}
