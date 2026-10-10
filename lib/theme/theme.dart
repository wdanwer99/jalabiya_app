import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Colours from the web fitting room: night-blue stage, damuriya cloth,
/// Nile green for actions, tailor's-chalk gold for measurements.
class Palette {
  static const ink = Color(0xFF101A2B);
  static const ink2 = Color(0xFF182740);
  static const ink3 = Color(0xFF22344F);
  static const damur = Color(0xFFF2EDE1);
  static const paper = Color(0xFFFAF7F0);
  static const card = Color(0xFFFFFFFF);
  static const line = Color(0xFFE4DCCB);
  static const nile = Color(0xFF2E6E6B);
  static const nileSoft = Color(0xFFE3EEEC);
  static const gold = Color(0xFFC8A24A);
  static const goldInk = Color(0xFF8A6A1F); // gold that passes contrast on paper
  static const goldSoft = Color(0xFFF6EDD6);
  static const chalk = Color(0xFF8B93A5);
  static const muted = Color(0xFF5B6476);
  static const henna = Color(0xFF9C4A2F);
  static const hennaSoft = Color(0xFFF6E4DD);
  static const onInkMuted = Color(0xB3F2EDE1); // damur at 70%
}

TextStyle displayStyle(double size, {FontWeight weight = FontWeight.w600, Color? color}) {
  return GoogleFonts.reemKufi(
    fontSize: size,
    fontWeight: weight,
    color: color ?? Palette.ink,
    height: 1.25,
  );
}

TextStyle monoStyle(double size, {Color? color, FontWeight weight = FontWeight.w500}) {
  return GoogleFonts.ibmPlexMono(fontSize: size, color: color ?? Palette.ink, fontWeight: weight);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Palette.nile,
    brightness: Brightness.light,
  ).copyWith(
    primary: Palette.nile,
    onPrimary: Colors.white,
    secondary: Palette.gold,
    onSecondary: Palette.ink,
    error: Palette.henna,
    surface: Palette.paper,
    onSurface: Palette.ink,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final body = GoogleFonts.ibmPlexSansArabicTextTheme(base.textTheme)
      .apply(bodyColor: Palette.ink, displayColor: Palette.ink);

  return base.copyWith(
    scaffoldBackgroundColor: Palette.paper,
    // one calm, modern transition for every screen change
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    textTheme: body.copyWith(
      headlineMedium: displayStyle(26),
      headlineSmall: displayStyle(22),
      titleLarge: displayStyle(19),
      titleMedium: GoogleFonts.ibmPlexSansArabic(
          textStyle: body.titleMedium, fontWeight: FontWeight.w600),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Palette.nile,
        foregroundColor: Colors.white,
        minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.ibmPlexSansArabic(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Palette.ink,
        minimumSize: const Size(64, 52),
        side: const BorderSide(color: Palette.line, width: 1.2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.ibmPlexSansArabic(fontSize: 15, fontWeight: FontWeight.w500),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: Palette.nile),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: Palette.nile,
      inactiveTrackColor: Palette.line,
      thumbColor: Palette.nile,
      overlayColor: Color(0x1F2E6E6B),
      trackHeight: 3,
    ),
    dividerTheme: const DividerThemeData(color: Palette.line, space: 1, thickness: 1),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Palette.card,
      indicatorColor: Palette.nileSoft,
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStatePropertyAll(
          GoogleFonts.ibmPlexSansArabic(fontSize: 12, fontWeight: FontWeight.w500)),
    ),
  );
}

/// Text field look, applied per field rather than through ThemeData:
/// ThemeData's appBarTheme / inputDecorationTheme parameters changed type
/// across Flutter releases, and this keeps the app compiling on all of them.
InputDecoration field({
  String? labelText,
  String? hintText,
  String? helperText,
  String? errorText,
  String? suffixText,
  Widget? suffixIcon,
  Widget? prefixIcon,
  bool? alignLabelWithHint,
}) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: const BorderSide(color: Palette.line),
  );
  return InputDecoration(
    labelText: labelText,
    hintText: hintText,
    helperText: helperText,
    errorText: errorText,
    suffixText: suffixText,
    suffixIcon: suffixIcon,
    prefixIcon: prefixIcon,
    // the leading icon lights up with the field it belongs to
    prefixIconColor: WidgetStateColor.resolveWith((s) => s.contains(WidgetState.error)
        ? Palette.henna
        : s.contains(WidgetState.focused)
            ? Palette.nile
            : Palette.chalk),
    alignLabelWithHint: alignLabelWithHint,
    filled: true,
    fillColor: Palette.card,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: border,
    enabledBorder: border,
    focusedBorder: border.copyWith(borderSide: const BorderSide(color: Palette.nile, width: 1.6)),
    errorBorder: border.copyWith(borderSide: const BorderSide(color: Palette.henna)),
    focusedErrorBorder: border.copyWith(borderSide: const BorderSide(color: Palette.henna, width: 1.6)),
    labelStyle: const TextStyle(color: Palette.muted),
    hintStyle: const TextStyle(color: Palette.chalk),
  );
}
