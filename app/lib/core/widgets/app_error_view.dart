import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../network/api_failure.dart';
import '../theme/mode_theme.dart';
import '../theme/tokens.dart';

/// What to say about a failure, as (title, help).
///
/// Lives outside the widget because the cached-answer banner says the same
/// thing in a smaller space: the reason the app fell back to storage is the
/// same reason it would otherwise have shown this screen, and two copies of
/// that mapping would drift.
(String, String) failureCopy(AppLocalizations l, ApiFailure failure) =>
    switch (failure.kind) {
      FailureKind.offline => (l.errorOffline, l.errorOfflineHelp),
      // Separate from offline on purpose. A timeout on a phone showing four
      // bars, reported as "no internet connection", sends the user looking
      // for a fault on their side that is not there.
      FailureKind.timedOut => (l.errorTimedOut, l.errorTimedOutHelp),
      FailureKind.serverDown => (l.errorServerDown, l.errorServerDownHelp),
      FailureKind.badRequest => (l.errorUnexpected, failure.detail ?? ''),
      FailureKind.unexpected => (l.errorUnexpected, failure.detail ?? ''),
    };

/// A failure, explained in terms of what the user can do about it.
///
/// The three a passenger actually meets are the three that lead to different
/// advice: the phone has no connection, the connection was too slow to
/// finish, or the service itself is down. "Something went wrong" with a retry
/// button is not an explanation, and a server outage is not the user's fault
/// — saying so is the difference between an app that feels broken and one
/// that feels honest.
class AppErrorView extends StatelessWidget {
  const AppErrorView({super.key, required this.failure, this.onRetry});

  final ApiFailure failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final p = context.colors;

    final (title, help) = failureCopy(l, failure);

    return Center(
      child: Padding(
        padding: EdgeInsetsDirectional.all(Insets.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              switch (failure.kind) {
                FailureKind.offline => Icons.wifi_off_rounded,
                FailureKind.timedOut => Icons.hourglass_disabled_rounded,
                _ => Icons.cloud_off_rounded,
              },
              size: 34,
              color: p.ink3,
            ),
            SizedBox(height: Insets.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (help.isNotEmpty) ...[
              SizedBox(height: Insets.sm),
              Text(
                help,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (onRetry != null) ...[
              SizedBox(height: Insets.xl),
              TextButton(onPressed: onRetry, child: Text(l.tryAgain)),
            ],
          ],
        ),
      ),
    );
  }
}
