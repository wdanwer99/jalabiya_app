import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'l10n/strings.dart';
import 'screens/auth/blocked_screen.dart';
import 'screens/auth/welcome_screen.dart';
import 'screens/customer/customer_home.dart';
import 'screens/profile/profile_setup_screen.dart';
import 'screens/tailor/tailor_home.dart';
import 'state/session.dart';
import 'theme/theme.dart';
import 'widgets/common.dart';
import 'widgets/splash.dart';

/// Lets code outside the widget tree (a tapped notification) open a screen.
final appNavigatorKey = GlobalKey<NavigatorState>();

class JalabiyaApp extends StatelessWidget {
  const JalabiyaApp({super.key});

  @override
  Widget build(BuildContext context) {
    final locale = context.select<Session, Locale>((s) => s.locale);
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: 'Jalabiya',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      locale: locale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const AppGate(),
    );
  }
}

/// Decides the first screen: sign in → finish your profile → your home.
///
/// On launch the splash plays its short opening once, even if the session is
/// ready sooner, then cross-fades into whichever screen applies.
class AppGate extends StatefulWidget {
  const AppGate({super.key});

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> {
  static const _splashKey = ValueKey('splash');
  bool _introDone = false;

  Widget _screen(BuildContext context, Session s) {
    final splash = SplashView(
      key: _splashKey,
      onIntroDone: () {
        if (mounted) setState(() => _introDone = true);
      },
    );
    if (!_introDone || !s.started) return splash;
    if (!s.signedIn) return const WelcomeScreen();
    if (s.profile == null) {
      if (s.loadError != null && !s.loadingProfile) {
        return Scaffold(
          body: ErrorView(
            error: s.loadError!,
            onRetry: s.reload,
            onSecondary: s.signOut,
            secondaryLabel: context.tr('action.signOut'),
          ),
        );
      }
      return splash;
    }
    if (s.blocked) return const BlockedScreen();
    if (!s.profileComplete) return const ProfileSetupScreen(asGate: true);
    return s.profile!.isTailor ? const TailorHome() : const CustomerHome();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    final next = _screen(context, s);
    // Gate changes (splash → sign in → profile → home) cross-fade.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
      child: KeyedSubtree(key: next.key ?? ValueKey(next.runtimeType), child: next),
    );
  }
}

/// Shown when the app was built without Supabase keys, instead of crashing.
class MissingConfigApp extends StatelessWidget {
  const MissingConfigApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Supabase keys missing', style: displayStyle(24)),
                const SizedBox(height: 12),
                const Text(
                  'Run the app with:\n\n'
                  'flutter run --dart-define-from-file=env.json\n\n'
                  'See README.md for the contents of env.json.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
