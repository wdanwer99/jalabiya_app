import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/repository.dart';
import '../../l10n/strings.dart';
import '../../models/profile.dart';
import '../../theme/theme.dart';
import '../../widgets/common.dart';
import 'auth_widgets.dart';
import 'sign_in_screen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _shell = GlobalKey<AuthShellState>();
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  UserRole _role = UserRole.customer;
  bool _busy = false;
  bool _hide = true;
  bool _tried = false;

  static bool _nameOk(String v) => v.trim().length >= 3;
  static bool _emailOk(String v) {
    final s = v.trim();
    return s.contains('@') && s.contains('.');
  }

  static bool _passwordOk(String v) => v.length >= 8;

  double _progress() {
    final done = [
      _nameOk(_name.text),
      isValidPhone(_phone.text),
      _emailOk(_email.text),
      _passwordOk(_password.text),
    ].where((ok) => ok).length;
    return done / 4;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _create() async {
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
      final needsConfirm = await context.read<Repository>().signUp(
            email: _email.text,
            password: _password.text,
            role: _role,
            fullName: _name.text,
            phone: _phone.text,
          );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      if (needsConfirm) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Palette.paper,
            icon: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutBack,
              builder: (context, v, child) => Transform.scale(scale: v, child: child),
              child: const Icon(Icons.mark_email_read_rounded, color: Palette.nile, size: 44),
            ),
            title: Text(ctx.tr('auth.checkEmailTitle'), style: displayStyle(19)),
            content: Text(ctx.tr('auth.checkEmailBody', {'email': _email.text.trim()})),
            actions: [
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(ctx.tr('action.done')),
              ),
            ],
          ),
        );
      }
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) {
        _shell.currentState?.shake();
        showError(context, e, onRetry: _create);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // AutofillGroup lets the phone offer to save the new login.
    return AutofillGroup(
      child: Form(
        key: _form,
        autovalidateMode: _tried ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
        child: AuthShell(
          key: _shell,
          title: context.tr('auth.signUpTitle'),
          subtitle: context.tr('auth.signUpBody'),
          children: [
            FormProgress(
              listenable: Listenable.merge([_name, _phone, _email, _password]),
              progress: _progress,
            ),
            const SizedBox(height: 22),
            Text(context.tr('auth.iAm'), style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _RoleCard(
                    selected: _role == UserRole.customer,
                    icon: Icons.person_outline_rounded,
                    title: context.tr('role.customer'),
                    body: context.tr('role.customerBody'),
                    onTap: () => setState(() => _role = UserRole.customer),
                  ),
                  const SizedBox(width: 10),
                  _RoleCard(
                    selected: _role == UserRole.tailor,
                    icon: Icons.content_cut_rounded,
                    title: context.tr('role.tailor'),
                    body: context.tr('role.tailorBody'),
                    onTap: () => setState(() => _role = UserRole.tailor),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            TextFormField(
              scrollPadding: authFieldScrollPadding,
              controller: _name,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.name],
              decoration: field(
                labelText: context.tr('profile.fullName'),
                prefixIcon: const Icon(Icons.badge_outlined),
                suffixIcon: ValidMark(controller: _name, isValid: _nameOk),
              ),
              validator: (v) => _nameOk(v ?? '') ? null : context.tr('form.name'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              scrollPadding: authFieldScrollPadding,
              controller: _phone,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.telephoneNumber],
              textDirection: TextDirection.ltr,
              decoration: field(
                labelText: context.tr('profile.phone'),
                hintText: '0912345678',
                prefixIcon: const Icon(Icons.phone_outlined),
                suffixIcon: ValidMark(controller: _phone, isValid: isValidPhone),
              ),
              validator: (v) => isValidPhone(v) ? null : context.tr('form.phone'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              scrollPadding: authFieldScrollPadding,
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              textDirection: TextDirection.ltr,
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
              obscureText: _hide,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _create(),
              autofillHints: const [AutofillHints.newPassword],
              textDirection: TextDirection.ltr,
              decoration: field(
                labelText: context.tr('auth.password'),
                helperText: context.tr('auth.passwordHelp'),
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: PeekButton(hidden: _hide, onToggle: () => setState(() => _hide = !_hide)),
              ),
              validator: (v) => _passwordOk(v ?? '') ? null : context.tr('auth.passwordHelp'),
            ),
            PasswordStrength(controller: _password),
            const SizedBox(height: 26),
            PressScale(
              child: BusyButton(
                label: context.tr('welcome.create'),
                icon: Icons.person_add_alt_1_rounded,
                busy: _busy,
                onPressed: _create,
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(context.tr('auth.haveAccount'), style: const TextStyle(color: Palette.muted)),
                TextButton(
                  onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute<void>(builder: (_) => const SignInScreen()),
                  ),
                  child: Text(context.tr('welcome.signIn')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Customer / tailor choice. The selected card tints, lifts slightly and
/// pops a check badge; the icon bounces when picked.
class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        child: AnimatedScale(
          scale: selected ? 1 : 0.97,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: selected ? Palette.nileSoft : Palette.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: selected ? Palette.nile : Palette.line, width: selected ? 1.6 : 1),
              boxShadow: [
                if (selected)
                  BoxShadow(color: Palette.nile.withValues(alpha: 0.18), blurRadius: 18, offset: const Offset(0, 6)),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  if (!selected) HapticFeedback.selectionClick();
                  onTap();
                },
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: selected ? Palette.nile : Palette.paper,
                            ),
                            child: Icon(icon, size: 20, color: selected ? Colors.white : Palette.muted),
                          ),
                          const Spacer(),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 260),
                            transitionBuilder: (child, a) => ScaleTransition(
                              scale: a.drive(CurveTween(curve: Curves.easeOutBack)),
                              child: child,
                            ),
                            child: selected
                                ? const Icon(Icons.check_circle_rounded,
                                    key: ValueKey('on'), size: 22, color: Palette.nile)
                                : const Icon(Icons.radio_button_off,
                                    key: ValueKey('off'), size: 20, color: Palette.chalk),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(body, style: const TextStyle(color: Palette.muted, fontSize: 12.5, height: 1.4)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
