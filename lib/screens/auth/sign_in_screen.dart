import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/repository.dart';
import '../../l10n/strings.dart';
import '../../theme/theme.dart';
import '../../widgets/common.dart';
import 'auth_widgets.dart';
import 'sign_up_screen.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _shell = GlobalKey<AuthShellState>();
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _busy = false;
  bool _hide = true;
  bool _tried = false;

  static bool _emailOk(String v) => v.trim().contains('@');

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_form.currentState!.validate()) {
      // from now on errors clear as soon as the field is fixed
      setState(() => _tried = true);
      _shell.currentState?.shake();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      if (!await requireOnline(context) || !mounted) return;
      await context.read<Repository>().signIn(_email.text, _password.text);
      HapticFeedback.mediumImpact();
      // The gate at the root takes over once the session changes.
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) {
        _shell.currentState?.shake();
        showError(context, e, onRetry: _signIn);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot() async {
    final email = _email.text.trim();
    if (!_emailOk(email)) {
      showSnack(context, context.tr('auth.enterEmailFirst'), icon: Icons.info_outline_rounded);
      return;
    }
    try {
      if (!await requireOnline(context) || !mounted) return;
      await context.read<Repository>().sendPasswordReset(email);
      if (mounted) showSnack(context, context.tr('auth.resetSent'));
    } catch (e) {
      if (mounted) showError(context, e, onRetry: _forgot);
    }
  }

  @override
  Widget build(BuildContext context) {
    // AutofillGroup lets the phone's password manager fill and save the login.
    return AutofillGroup(
      child: Form(
        key: _form,
        autovalidateMode: _tried ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
        child: AuthShell(
          key: _shell,
          title: context.tr('auth.signInTitle'),
          subtitle: context.tr('auth.signInBody'),
          children: [
            TextFormField(
              scrollPadding: authFieldScrollPadding,
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              textDirection: TextDirection.ltr,
              onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
              decoration: field(
                labelText: context.tr('auth.email'),
                prefixIcon: const Icon(Icons.alternate_email_rounded),
                suffixIcon: ValidMark(controller: _email, isValid: _emailOk),
              ),
              validator: (v) => _emailOk(v ?? '') ? null : context.tr('form.email'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              scrollPadding: authFieldScrollPadding,
              controller: _password,
              focusNode: _passwordFocus,
              obscureText: _hide,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              textDirection: TextDirection.ltr,
              onFieldSubmitted: (_) => _signIn(),
              decoration: field(
                labelText: context.tr('auth.password'),
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: PeekButton(hidden: _hide, onToggle: () => setState(() => _hide = !_hide)),
              ),
              validator: (v) => (v ?? '').isEmpty ? context.tr('form.required') : null,
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(onPressed: _forgot, child: Text(context.tr('auth.forgot'))),
            ),
            const SizedBox(height: 12),
            PressScale(
              child: BusyButton(
                label: context.tr('welcome.signIn'),
                icon: Icons.login_rounded,
                busy: _busy,
                onPressed: _signIn,
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(context.tr('auth.noAccount'), style: const TextStyle(color: Palette.muted)),
                TextButton(
                  onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute<void>(builder: (_) => const SignUpScreen()),
                  ),
                  child: Text(context.tr('welcome.create')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
