import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/strings.dart';
import '../../state/session.dart';
import '../../theme/theme.dart';
import '../../widgets/common.dart';

/// Shown instead of the home screen while an admin has blocked this account
/// (supabase/admin.sql). The server refuses its order and shop changes
/// anyway; this says why, and checks again once the person has been in touch.
class BlockedScreen extends StatelessWidget {
  const BlockedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final reason = (session.block?.reason ?? '').trim();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(color: Palette.hennaSoft, shape: BoxShape.circle),
                    child: const Icon(Icons.block_rounded, color: Palette.henna, size: 34),
                  ),
                ),
                const SizedBox(height: 20),
                Text(context.tr('blocked.title'), style: displayStyle(22), textAlign: TextAlign.center),
                const SizedBox(height: 10),
                Text(
                  context.tr('blocked.body'),
                  style: const TextStyle(color: Palette.muted, height: 1.55),
                  textAlign: TextAlign.center,
                ),
                if (reason.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  NoticeBanner(tone: BannerTone.warn, text: context.tr('blocked.reason', {'reason': reason})),
                ],
                const SizedBox(height: 24),
                BusyButton(
                  label: context.tr('blocked.check'),
                  icon: Icons.refresh_rounded,
                  busy: session.loadingProfile,
                  onPressed: session.reload,
                ),
                const SizedBox(height: 10),
                OutlinedButton(onPressed: session.signOut, child: Text(context.tr('action.signOut'))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
