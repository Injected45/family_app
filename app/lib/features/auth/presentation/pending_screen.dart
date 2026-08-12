import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/theme.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/app_localizations.dart';
import 'auth_controller.dart';

/// A first-class state, not an error.
///
/// The association is private, so a valid Google account grants nothing by
/// itself. This screen must never crash, never show an empty dashboard, and
/// never retry in a loop — it simply explains the wait and offers a way out.
class PendingScreen extends ConsumerWidget {
  const PendingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);
    final AuthState auth = ref.watch(authControllerProvider);
    final String? email = auth.pendingEmail;

    return CenteredMessage(
      icon: Icons.hourglass_top,
      iconColor: AppColors.warning,
      title: l.pendingTitle,
      body: auth.serverMessage ?? l.pendingBody,
      footnote: email == null ? null : l.pendingSignedInAs(email),
      actions: <Widget>[
        OutlinedButton.icon(
          onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
          icon: const Icon(Icons.logout, size: 18),
          label: Text(l.signOut),
        ),
      ],
    );
  }
}
